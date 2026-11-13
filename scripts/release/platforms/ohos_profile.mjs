// 在签名构建期间提供 Flutter OHOS 可读取的签名配置。
import { spawn } from 'node:child_process';
import { chmodSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { constants } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { readLocalSigning } from '../../tools/ohos_hvigor.cjs';

export async function withSigningProfile(file, signing, build) {
  const original = readFileSync(file, 'utf8');
  const mode = statSync(file).mode;
  // 替换仓库固定的签名声明和产品引用，保留 JSON5 注释及其余构建配置。
  const declaration = /"signingConfigs"\s*:\s*\[\s*\]/g;
  if ([...original.matchAll(declaration)].length !== 1) {
    throw new Error('发布签名需要 build-profile.json5 中唯一的空 signingConfigs');
  }
  if (!signing?.material) throw new Error('缺少 Release 签名配置');
  const productSigning = /"signingConfig"\s*:\s*"[^"]*"/g;
  const configured = original.replace(declaration,
    () => `"signingConfigs": ${JSON.stringify([signing])}`)
    .replace(productSigning, () => `"signingConfig": ${JSON.stringify(signing.name)}`);
  try {
    chmodSync(file, 0o600);
    writeFileSync(file, configured);
    return await build();
  } finally {
    writeFileSync(file, original);
    chmodSync(file, mode);
  }
}

function run(command, args) {
  return new Promise((resolveResult, reject) => {
    const child = spawn(command, args, { stdio: 'inherit' });
    const interrupt = () => child.kill('SIGINT');
    const terminate = () => child.kill('SIGTERM');
    process.on('SIGINT', interrupt);
    process.on('SIGTERM', terminate);
    const cleanup = () => {
      process.off('SIGINT', interrupt);
      process.off('SIGTERM', terminate);
    };
    child.once('error', (error) => { cleanup(); reject(error); });
    child.once('exit', (code, signal) => {
      cleanup();
      resolveResult(code ?? 128 + constants.signals[signal]);
    });
  });
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const root = resolve(dirname(fileURLToPath(import.meta.url)), '../../..');
  const [command, ...args] = process.argv.slice(2);
  if (!command) throw new Error('需要签名构建命令');
  const signing = readLocalSigning(root)?.release;
  process.exitCode = await withSigningProfile(
    join(root, 'apps/ubaa_ohos/ohos/build-profile.json5'), signing,
    () => run(command, args));
}
