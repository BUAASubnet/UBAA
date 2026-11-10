const numeric = /^[0-9]+$/;

function order(left, right) {
  return left < right ? -1 : left > right ? 1 : 0;
}

function parts(version) {
  const [release, build = "0"] = version.split("+");
  const suffix = release.indexOf("-");
  return {
    core: (suffix < 0 ? release : release.slice(0, suffix))
      .split(".")
      .map(BigInt),
    prerelease: suffix < 0 ? [] : release.slice(suffix + 1).split("."),
    build: BigInt(build),
  };
}

// 输入先按合同校验。构建号只在 SemVer 优先级相同时比较。
export function compareVersions(left, right) {
  const a = parts(left);
  const b = parts(right);
  for (let i = 0; i < a.core.length; i++) {
    const result = order(a.core[i], b.core[i]);
    if (result !== 0) return result;
  }
  if ((a.prerelease.length === 0) !== (b.prerelease.length === 0)) {
    return a.prerelease.length === 0 ? 1 : -1;
  }
  for (let i = 0; i < Math.min(a.prerelease.length, b.prerelease.length); i++) {
    const x = a.prerelease[i];
    const y = b.prerelease[i];
    const xIsNumeric = numeric.test(x);
    const yIsNumeric = numeric.test(y);
    if (xIsNumeric !== yIsNumeric) return xIsNumeric ? -1 : 1;
    const result = xIsNumeric ? order(BigInt(x), BigInt(y)) : order(x, y);
    if (result !== 0) return result;
  }
  if (a.prerelease.length !== b.prerelease.length) {
    return a.prerelease.length < b.prerelease.length ? -1 : 1;
  }
  return order(a.build, b.build);
}
