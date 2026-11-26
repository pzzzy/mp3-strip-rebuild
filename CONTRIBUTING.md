# Contributing

Open an issue for bugs or proposed changes. Include the macOS version, architecture, reproduction steps, expected behavior, and actual behavior. Avoid posting personal file paths or existing media libraries; the test generates safe fixtures.

1. Fork the repository and make your change on a branch.
2. Run `./build.sh` and `python3 tests/verify_library.py` on macOS. For menu or playback changes, also describe what you manually checked.
3. Open a pull request explaining the change and how you verified it.

Use Apple system frameworks where practical. Do not submit original MP3 Strip binaries, resource forks, icons, manual text, raw decompiler output, or media you do not have permission to redistribute. Contributions are accepted under the repository's MIT license.
