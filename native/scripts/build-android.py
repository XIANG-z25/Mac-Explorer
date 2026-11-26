#!/usr/bin/env python3
"""Build pinned, user-space MTP libraries and a read-only helper for macOS 13+."""
import argparse
import hashlib
import os
import pathlib
import shutil
import subprocess
import tarfile

parser = argparse.ArgumentParser()
parser.add_argument('--app', type=pathlib.Path, required=True)
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parents[1]
work = root / 'output/android-deps'
prefix = work / 'install'
work.mkdir(parents=True, exist_ok=True)
packages = [
    ('libusb-1.0.30', 'https://github.com/libusb/libusb/releases/download/v1.0.30/libusb-1.0.30.tar.bz2', 'fea36f34f9156400209595e300840767ab1a385ede1dc7ee893015aea9c6dbaf'),
    ('libmtp-1.1.23', 'https://downloads.sourceforge.net/project/libmtp/libmtp/1.1.23/libmtp-1.1.23.tar.gz', '74a2b6e8cb4a0304e95b995496ea3ac644c29371649b892b856e22f12a0bdeed'),
]
environment = os.environ.copy()
environment.update(MACOSX_DEPLOYMENT_TARGET='13.0', CFLAGS='-O2 -mmacosx-version-min=13.0', LDFLAGS='-mmacosx-version-min=13.0',
                   PKG_CONFIG_PATH=str(prefix / 'lib/pkgconfig'))
environment['PKG_CONFIG'] = shutil.which('pkgconf') or shutil.which('pkg-config') or ''
if not environment['PKG_CONFIG']:
    raise SystemExit('Install pkgconf to build Android support: brew install pkgconf')
marker = work / 'macos13-complete'
expected = '\n'.join(p[2] for p in packages)
if not marker.exists() or marker.read_text() != expected:
    for name, url, sha in packages:
        archive = work / url.rsplit('/', 1)[-1]
        if not archive.exists():
            subprocess.run(['curl', '--fail', '--location', '--retry', '2', '--max-time', '120', url, '-o', str(archive)], check=True)
        if hashlib.sha256(archive.read_bytes()).hexdigest() != sha:
            raise SystemExit('Android dependency checksum mismatch: ' + name)
        source = work / name
        if not source.exists():
            with tarfile.open(archive) as stream:
                stream.extractall(work, filter='data')
        subprocess.run(['./configure', '--prefix=' + str(prefix), '--disable-static'], cwd=source, env=environment, check=True)
        subprocess.run(['make', '-j4'], cwd=source, env=environment, check=True)
        subprocess.run(['make', 'install'], cwd=source, env=environment, check=True)
    marker.write_text(expected)
contents = args.app.resolve() / 'Contents'
frameworks = contents / 'Frameworks'
helpers = contents / 'Helpers'
resources = contents / 'Resources'
for directory in (frameworks, helpers, resources):
    directory.mkdir(parents=True, exist_ok=True)
libraries = ['libmtp.9.dylib', 'libusb-1.0.0.dylib']
for name in libraries:
    shutil.copy2(prefix / 'lib' / name, frameworks / name)
    subprocess.run(['install_name_tool', '-id', '@rpath/' + name, str(frameworks / name)], check=True)
subprocess.run(['install_name_tool', '-change', str(prefix / 'lib/libusb-1.0.0.dylib'), '@loader_path/libusb-1.0.0.dylib', str(frameworks / 'libmtp.9.dylib')], check=True)
helper = helpers / 'android-reader'
subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-O2', '-Wall', '-Wextra', '-mmacosx-version-min=13.0',
                '-I' + str(prefix / 'include'), str(root / 'Helpers/AndroidReader.m'),
                '-L' + str(prefix / 'lib'), '-lmtp', '-framework', 'Foundation',
                '-Wl,-rpath,@executable_path/../Frameworks', '-o', str(helper)], check=True)
subprocess.run(['install_name_tool', '-change', str(prefix / 'lib/libmtp.9.dylib'), '@rpath/libmtp.9.dylib', str(helper)], check=True)
for name in libraries:
    subprocess.run(['codesign', '--force', '--sign', '-', str(frameworks / name)], check=True)
subprocess.run(['codesign', '--force', '--sign', '-', str(helper)], check=True)
for name, _, _ in packages:
    shutil.copy2(work / name / 'COPYING', resources / (name + '-LICENSE.txt'))
(resources / 'ANDROID-SOURCE.txt').write_text(
    'Android USB support uses dynamically linked libmtp and libusb (LGPL-2.1-or-later).\n'
    'Rebuild with native/scripts/build-android.py; replaceable libraries are in Contents/Frameworks.\n'
    + '\n'.join(name + '\n' + url + '\nSHA-256 ' + sha for name, url, sha in packages) + '\n')
print(helper)
