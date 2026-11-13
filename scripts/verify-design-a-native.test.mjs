import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

// CodeVetter's node adapter executes the actual native suite through the
// required XcodeBuildMCP runner. No saved test result is imported as a pass.
test('native workspace preserves process, alert and lifecycle behavior', { timeout: 115_000 }, () => {
  const packagePath = fileURLToPath(new URL('..', import.meta.url));
  const result = spawnSync('npx', ['--offline', 'xcodebuildmcp', 'swift-package', 'test', '--json', JSON.stringify({
    packagePath,
    configuration: 'debug',
    filter: 'LiveViewModelTests|MenuLifecycleTests|LoadAlertCenterTests|MonitoringSurfaceTests|PerformanceUIResourcesTests|DecodedArtworkTests',
  })], { cwd: packagePath, encoding: 'utf8', timeout: 110_000, maxBuffer: 32 * 1024 * 1024 });
  const output = `${result.stdout ?? ''}\n${result.stderr ?? ''}`;
  process.stdout.write(output);
  assert.equal(result.error, undefined, 'XcodeBuildMCP must finish within the native test budget');
  assert.equal(result.status, 0, 'XcodeBuildMCP must exit successfully');
  const summary = output.match(/(\d+) tests passed, 0 failed, 0 skipped/);
  assert.ok(summary, 'Runner must report executed native tests with no failures or skips');
  assert.ok(Number(summary[1]) >= 60, 'The complete focused native suite must execute');
});
