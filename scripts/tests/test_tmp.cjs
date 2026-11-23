const { mkdirSync, mkdtempSync } = require('node:fs');
const { join, resolve } = require('node:path');

function createTestTempDirectory(suite) {
  const root = process.env.UBAA_TEST_TMP || resolve(__dirname, '../../target/test_tmp');
  const parent = resolve(root, suite);
  mkdirSync(parent, { recursive: true, mode: 0o700 });
  return mkdtempSync(join(parent, 'run_'));
}

exports.createTestTempDirectory = createTestTempDirectory;
