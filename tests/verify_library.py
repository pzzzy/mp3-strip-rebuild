#!/usr/bin/env python3
"""Exercise the built player against generated, tagged MP3 audio."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / 'dist' / 'MP3 Strip Rebuild.app' / 'Contents' / 'MacOS' / 'MP3StripRebuild'


def verify(folder, mode):
    run = subprocess.run([APP, '--verify-library', folder, '--sort', mode],
                         check=True, capture_output=True, text=True, timeout=30)
    return json.loads(run.stdout)


def main():
    ffmpeg = shutil.which('ffmpeg')
    if not ffmpeg or not APP.is_file():
        raise SystemExit('Build with ./build.sh and put FFmpeg on PATH first.')
    with tempfile.TemporaryDirectory(prefix='mp3-strip-fixtures-') as directory:
        root = Path(directory)
        library, empty = root / 'Music', root / 'Empty'
        library.mkdir()
        empty.mkdir()
        blank = verify(empty, 'album')
        assert blank['tracks'] == [] and blank['decodeSamples'] == 0, blank
        invalid = subprocess.run([APP, '--verify-library', empty, '--sort', 'bad'],
                                 capture_output=True, text=True, timeout=5)
        assert invalid.returncode == 2 and 'Usage:' in invalid.stderr, invalid
        for folder, name, title, album, artist, frequency in [
            ('Folder B', '01.MP3', 'First Song', 'Z Album', 'A Artist', 440),
            ('Folder A', '02.mp3', 'Second Song', 'A Album', 'Z Artist', 660),
        ]:
            (library / folder).mkdir()
            subprocess.run([ffmpeg, '-nostdin', '-hide_banner', '-loglevel', 'error',
                            '-f', 'lavfi', '-i', f'sine=frequency={frequency}:sample_rate=44100',
                            '-t', '2', '-metadata', f'title={title}', '-metadata', f'album={album}',
                            '-metadata', f'artist={artist}', '-codec:a', 'libmp3lame',
                            str(library / folder / name)], check=True, timeout=20)
        (library / 'ignore.txt').write_text('not audio', encoding='utf-8')
        for mode, first in [('album', 'Second Song'), ('artist', 'First Song'),
                            ('folder', 'Second Song'), ('file', 'First Song')]:
            result = verify(library, mode)
            tracks = result['tracks']
            assert len(tracks) == 2 and tracks[0]['title'] == first, (mode, tracks)
            assert {track['title']: (track['album'], track['artist']) for track in tracks} == {
                'First Song': ('Z Album', 'A Artist'), 'Second Song': ('A Album', 'Z Artist'),
            }, tracks
            assert all(1.8 < track['duration'] < 2.3 for track in tracks), tracks
            assert result['decodeSamples'] > 0, result
            assert result['wrappedForward'] and result['wrappedBackward'], result
            assert result['introSeconds'] == 10, result
    print('PASS: MP3 scan, metadata, sort modes, PCM decoding, navigation, empty library and invalid arguments.')


if __name__ == '__main__':
    main()
