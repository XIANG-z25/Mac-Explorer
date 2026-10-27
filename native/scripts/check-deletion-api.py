#!/usr/bin/env python3
"""Verify that validation-only deletion seams cannot be called in an ordinary build."""
import pathlib
import platform
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='explorer-deletion-api-') as temporary:
    probe = pathlib.Path(temporary) / 'ProductionAPIProbe.swift'
    probe.write_text('''import Foundation
func forbidden(_ url: URL) throws {
  _ = try PreparedDeletion.fixtures([url], root: url, classification: { _ in nil })
  let plan = try NetworkDeletion(url)
  plan.auditHook = nil
  _ = try NetworkDeletion(url, network: { _ in true })
}
''')
    result = subprocess.run([
        'xcrun', 'swiftc', '-typecheck', '-parse-as-library', '-swift-version', '5',
        '-target', platform.machine() + '-apple-macos13.0',
        *map(str, sorted((root / 'Sources/ExplorerCore').glob('*.swift'))), str(probe),
    ], capture_output=True, text=True)
    expected = ["has no member 'fixtures'", "has no member 'auditHook'", "extra argument 'network'"]
    if result.returncode == 0 or not all(message in result.stderr for message in expected):
        raise RuntimeError('Production deletion API boundary failed:\n' + result.stderr)
print('Deletion production API boundary: 3 prohibited validation entry points are absent.')
