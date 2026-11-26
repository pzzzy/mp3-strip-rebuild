import AppKit
import AVFoundation

@main
struct MP3Strip {
    @MainActor
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.first == "--verify-library" {
            guard args.count == 4, args[2] == "--sort", let mode = SortMode(rawValue: args[3]) else {
                let usage = "Usage: --verify-library FOLDER --sort album|artist|folder|file\n"
                FileHandle.standardError.write(Data(usage.utf8))
                exit(2)
            }
            do {
                try await Verification.run(folder: args[1], mode: mode)
            } catch {
                let message = "Library verification failed. \(error)\n"
                FileHandle.standardError.write(Data(message.utf8))
                exit(1)
            }
            return
        }
        runApp()
    }

    @MainActor
    private static func runApp() {
        let app = NSApplication.shared
        let controller = StripController()
        app.setActivationPolicy(.accessory)
        app.delegate = controller
        withExtendedLifetime(controller) { app.run() }
    }
}

@MainActor
final class StripController: NSObject, NSApplicationDelegate, NSMenuDelegate, AVAudioPlayerDelegate {
    private var status: NSStatusItem!
    private var tracks: [Track] = []
    private var folder: URL?
    private var mode: SortMode = .album
    private var current: Int?
    private var player: AVAudioPlayer?
    private var intro = false
    private var introTimer: Timer?
    private var scanTask: Task<Void, Never>?
    private var scanning = false
    private var message: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        status.menu = menu
        updateStatus()
    }

    private var selected: Track? { current.map { tracks[$0] } }

    private func updateStatus() {
        let title = selected?.title
        let symbol = player?.isPlaying == true ? "waveform" : "music.note"
        status.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "MP3 Strip")
        status.button?.toolTip = title.map { "MP3 Strip — \($0)" } ?? "MP3 Strip"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        info(selected?.title ?? "MP3 Strip", in: menu)
        if let message { info(message, in: menu) }
        if scanning { info("Scanning…", in: menu) }
        if let folder { info(folder.lastPathComponent, in: menu) }
        item("Choose Music Folder…", #selector(chooseFolder), in: menu)
        menu.addItem(.separator())
        item(player?.isPlaying == true ? "Pause" : "Play", #selector(togglePlayback),
             in: menu, enabled: current != nil)
        item("Stop", #selector(stop), in: menu, enabled: player != nil)
        item("Previous Track", #selector(previous), in: menu, enabled: current != nil)
        item("Next Track", #selector(next), in: menu, enabled: current != nil)
        item("10-Second Intro", #selector(toggleIntro), in: menu).state = intro ? .on : .off
        menu.addItem(.separator())

        let sorting = submenu("Sort", in: menu)
        for sort in SortMode.allCases {
            let option = item(sort.label, #selector(changeSort(_:)), in: sorting)
            option.representedObject = sort.rawValue
            option.state = sort == mode ? .on : .off
        }
        if !tracks.isEmpty {
            let catalog = submenu("Tracks", in: menu)
            var group: String?
            var destination = catalog
            for (index, track) in tracks.enumerated() {
                let name = mode.group(for: track)
                if mode != .file, name != group {
                    group = name
                    destination = submenu(name, in: catalog)
                    item("Play from Here", #selector(selectTrack(_:)), in: destination).representedObject = track.url
                    destination.addItem(.separator())
                }
                let entry = item(track.title, #selector(selectTrack(_:)), in: destination)
                entry.representedObject = track.url
                entry.toolTip = track.url.path
                entry.state = index == current ? .on : .off
            }
        }
        menu.addItem(.separator())
        item("Quit MP3 Strip", #selector(quit), in: menu, key: "q")
    }

    private func submenu(_ title: String, in menu: NSMenu) -> NSMenu {
        let child = NSMenu(title: title)
        child.autoenablesItems = false
        item(title, nil, in: menu).submenu = child
        return child
    }

    private func info(_ title: String, in menu: NSMenu) {
        item(title, nil, in: menu, enabled: false)
    }

    @discardableResult
    private func item(_ title: String, _ action: Selector?, in menu: NSMenu,
                      enabled: Bool = true, key: String = "") -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.target = self
        entry.isEnabled = enabled
        menu.addItem(entry)
        return entry
    }

    @objc private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.prompt = "Choose"
        panel.directoryURL = folder
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url?.standardizedFileURL else { return }
        scanTask?.cancel()
        scanning = true
        message = nil
        scanTask = Task {
            do {
                let found = try await Library.scan(url)
                guard !Task.isCancelled else { return }
                stop()
                folder = url
                tracks = mode.sorted(found)
                current = tracks.isEmpty ? nil : 0
                message = tracks.isEmpty ? "No readable MP3 tracks found." : nil
                updateStatus()
            } catch {
                guard !Task.isCancelled else { return }
                message = "Couldn’t read \(url.lastPathComponent)."
            }
            scanning = false
        }
    }

    @objc private func changeSort(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let sort = SortMode(rawValue: raw) else { return }
        let playingURL = selected?.url
        mode = sort
        tracks = mode.sorted(tracks)
        current = tracks.firstIndex { $0.url == playingURL }
        updateStatus()
    }

    @objc private func selectTrack(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL,
              let index = tracks.firstIndex(where: { $0.url == url }) else { return }
        play(index)
    }
    @objc private func previous() { move(-1) }
    @objc private func next() { move(1) }
    @objc private func quit() { NSApp.terminate(nil) }

    private func move(_ step: Int) {
        guard let current, let index = Library.adjacent(to: current, step: step, count: tracks.count) else { return }
        if player?.isPlaying == true {
            play(index)
        } else {
            stop()
            self.current = index
            updateStatus()
        }
    }

    @objc private func togglePlayback() {
        guard let current else { return }
        guard let player else {
            play(current)
            return
        }
        if player.isPlaying {
            player.pause()
        } else if !player.play() {
            playbackFailed()
            return
        }
        scheduleIntro()
        updateStatus()
    }

    @objc private func stop() {
        introTimer?.invalidate()
        introTimer = nil
        player?.stop()
        player = nil
        updateStatus()
    }

    private func play(_ index: Int) {
        stop()
        current = index
        message = nil
        do {
            let audio = try AVAudioPlayer(contentsOf: tracks[index].url)
            audio.delegate = self
            player = audio
            guard audio.play() else {
                playbackFailed()
                return
            }
            scheduleIntro()
            updateStatus()
        } catch {
            playbackFailed()
        }
    }

    private func playbackFailed() {
        stop()
        message = "Couldn’t play the selected track."
    }

    @objc private func toggleIntro() {
        intro.toggle()
        scheduleIntro()
    }

    private func scheduleIntro() {
        introTimer?.invalidate()
        introTimer = nil
        guard intro, let player, player.isPlaying, player.duration > Double(Library.introSeconds) else { return }
        let delay = max(0, Double(Library.introSeconds) - player.currentTime)
        let timer = Timer(timeInterval: delay, target: self, selector: #selector(introEnded(_:)),
                          userInfo: nil, repeats: false)
        introTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    @objc private func introEnded(_ timer: Timer) {
        guard timer === introTimer, player?.isPlaying == true else { return }
        advanceAfterPlayback()
    }

    private func advanceAfterPlayback() {
        guard let current, current + 1 < tracks.count else {
            stop()
            return
        }
        play(current + 1)
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard player === self.player else { return }
            if flag { advanceAfterPlayback() } else { playbackFailed() }
        }
    }
}
