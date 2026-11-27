#!/usr/bin/env python3
"""Create separate Native DMG/ZIP assets; never publish or install them."""
import argparse
import hashlib
import pathlib
import plistlib
import re
import shutil
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--app', type=pathlib.Path, default=root / 'output' / 'Mac Explorer.app')
parser.add_argument('--output', type=pathlib.Path)
parser.add_argument('--personal', action='store_true', help='Package the independent Daily bundle')
args = parser.parse_args()
app = args.app.resolve(strict=True)
expected_name = 'Mac Explorer Daily.app' if args.personal else 'Mac Explorer.app'
expected_id = 'local.zx.macexplorer.daily' if args.personal else 'local.macexplorer.native-prototype'
if app.name != expected_name or args.app.is_symlink():
    raise SystemExit('Invalid Native application path.')
with (app / 'Contents/Info.plist').open('rb') as handle:
    info = plistlib.load(handle)
version = info.get('CFBundleShortVersionString', '')
if info.get('CFBundleIdentifier') != expected_id or info.get('CFBundleExecutable') != 'MacExplorerNative' or not re.fullmatch(r'[0-9]{1,6}\.[0-9]{1,6}\.[0-9]{1,6}', version):
    raise SystemExit('Expected the independent Native bundle with a stable version.')
if any(item.is_symlink() for item in app.rglob('*')):
    raise SystemExit('Native update archives must not contain symlinks.')
subprocess.run(['/usr/bin/lipo', str(app / 'Contents/MacOS/MacExplorerNative'), '-verify_arch', 'arm64'], check=True)
subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(app)], check=True)
output = args.output or root / 'output' / 'release' / version
if output.exists():
    raise SystemExit(f'Refusing to overwrite existing artifacts: {output}')
output.mkdir(parents=True)
try:
    with tempfile.TemporaryDirectory(prefix='mac-explorer-native-package-') as temporary:
        folder = pathlib.Path(temporary)
        staged = folder / app.name
        shutil.copytree(app, staged)
        if not args.personal:
            for name in ['install-native.sh', 'update-native.sh']:
                shutil.copy2(root / 'scripts' / name, staged / 'Contents/Resources' / name)
        subprocess.run(['/usr/bin/codesign', '--force', '--sign', '-', str(staged)], check=True)
        subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(staged)], check=True)
        stem = f'Mac-Explorer-Daily-{version}-mac-arm64' if args.personal else f'Mac-Explorer-Native-{version}-mac-arm64'
        archive = output / f'{stem}.zip'
        subprocess.run(['/usr/bin/ditto', '-c', '-k', '--norsrc', '--keepParent', str(staged), str(archive)], check=True)
        (folder / 'Applications').symlink_to('/Applications')
        image = output / f'{stem}.dmg'
        subprocess.run(['/usr/bin/hdiutil', 'create', '-volname', f'Mac Explorer {version}', '-srcfolder', str(folder), '-format', 'UDZO', '-ov', str(image)], check=True)
        subprocess.run(['/usr/bin/codesign', '--force', '--sign', '-', str(image)], check=True)
        subprocess.run(['/usr/bin/hdiutil', 'verify', str(image)], check=True)
        sums = []
        for artifact in [archive, image]:
            digest = hashlib.file_digest(artifact.open('rb'), 'sha256').hexdigest()
            sums.append(f'{digest}  {artifact.name}\n')
        (output / ('SHA256SUMS.txt' if args.personal else 'SHA256SUMS-native.txt')).write_text(''.join(sums))
        if not args.personal:
            shutil.copy2(root / 'scripts' / 'install-native.sh', output / 'install-native.sh')
except BaseException:
    # Partial artifacts were created exclusively by this invocation.
    shutil.rmtree(output)
    raise
print(output)
