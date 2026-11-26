# MP3 Strip Rebuild

[![macOS CI](https://github.com/pzzzy/mp3-strip-rebuild/actions/workflows/ci.yml/badge.svg)](https://github.com/pzzzy/mp3-strip-rebuild/actions/workflows/ci.yml)

A small, local MP3 player for the macOS menu bar, inspired by the classic Mac OS MP3 Strip Control Strip module. Built in Swift with AppKit and AVFoundation. No accounts, network access, or runtime packages are required.

- Scan a selected folder recursively for MP3s and browse tracks by album, artist, folder, or filename.
- Play, pause, stop, skip, and go back. Manual next and previous wrap at the ends of the library.
- Enable 10-second Intro mode to sample each track.

## Build and run

Requires macOS 13 or later and the Xcode Command Line Tools (`xcode-select --install` if needed). The build uses the host architecture and no downloads; Apple Silicon is the primary target.

```sh
git clone https://github.com/pzzzy/mp3-strip-rebuild.git
cd mp3-strip-rebuild
./build.sh
open 'dist/MP3 Strip Rebuild.app'
```

Click the music-note icon in the menu bar, then **Choose Music Folder…**. The app does not appear in the Dock. The local build is ad-hoc signed, not Developer ID signed or notarized.

## Verify

With Python 3 and an FFmpeg build with `libmp3lame` on `PATH` (`brew install ffmpeg` on macOS):

```sh
./build.sh
python3 tests/verify_library.py
```

The integration test generates its own audio. It checks recursive scanning, ID3 metadata, all four sort modes, actual PCM decoding, manual navigation wrap, an empty library, and invalid arguments. It checks the configured Intro duration, not real-time playback or physical audio output.

## Scope and provenance

This is an independent recreation informed by static analysis of MP3 Strip 1.5 and its documentation, not the original source or a claim of exact compatibility. The original is not needed to build or run it. Classic alias playlists, cached catalogs, automatic rescans, repeat/shuffle, seeking, and global shortcuts are not implemented. This project is not affiliated with or endorsed by the original authors. See [NOTICE](NOTICE), [CONTRIBUTING.md](CONTRIBUTING.md), and the [MIT license](LICENSE).
