#!/usr/bin/env python3
"""分别扫描 Git index 与工作区；未能读取候选时失败且不打印其正文。"""
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
FORBIDDEN = re.compile(r"(^|/)(ubaa_old|examples)(/|$)|(^|/)\.env\.(local|toolchain)$|(^|/)(session\.json|.*\.session\.json)$")
PATTERNS = tuple(re.compile(pattern) for pattern in (
    rb"UBAA_TEST_(USERNAME|PASSWORD)=[\"']?[A-Za-z0-9]",
    rb"-----BEGIN (RSA |OPENSSH |EC |DSA )?PRIVATE KEY-----",
    rb"\b1[3-9][0-9]{9}\b",
    rb"data:image/(png|jpe?g|gif);base64,[A-Za-z0-9+/]{24,}={0,2}",
    rb"gh[pousr]_[A-Za-z0-9]{36,}",
    rb"AKIA[0-9A-Z]{16}",
    # 只接受 <private-evidence>/ 等逻辑占位；不豁免任何用户名或归档目录。
    rb"(?<![A-Za-z0-9_./-])(?:file://)?/(?:Users|home)/[^\s/\\\"'`]+",
    rb"(?i)\b[A-Z]:[\\/]+Users[\\/]+[^\s\\/\"'`]+",
))


def git(*arguments, data=None):
    result = subprocess.run(["git", "-C", str(ROOT), *arguments], input=data,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        raise ValueError(f"Git 读取失败：{arguments[0]}（退出 {result.returncode}）")
    return result.stdout


def check(body, path, snapshot):
    for number, pattern in enumerate(PATTERNS, 1):
        if pattern.search(body):
            raise ValueError(f"可能的敏感材料：{snapshot} {path!r}，规则 {number}；正文不输出")


def main():
    indexed = []
    for record in git("ls-files", "--stage", "-z").split(b"\0"):
        if not record:
            continue
        header, raw_path = record.split(b"\t", 1)
        mode, object_id, stage = header.split()
        path = raw_path.decode("utf-8")
        if stage != b"0" or mode not in {b"100644", b"100755"}:
            raise ValueError(f"无法安全扫描 index 类型或冲突：{path!r}")
        indexed.append((path, object_id))
    untracked = {p.decode("utf-8") for p in
                 git("ls-files", "--others", "--exclude-standard", "-z").split(b"\0") if p}
    candidates = {path for path, _ in indexed} | untracked
    for path in sorted(candidates):
        if FORBIDDEN.search(path):
            raise ValueError(f"禁止提交的敏感路径：{path!r}")

    # 一次批量读取真实暂存 blob；工作区清理或删除不能遮蔽待提交内容。
    objects = git("cat-file", "--batch", data=b"".join(oid + b"\n" for _, oid in indexed))
    offset = 0
    for path, object_id in indexed:
        end = objects.find(b"\n", offset)
        header = objects[offset:end].split()
        if end < 0 or len(header) != 3 or header[:2] != [object_id, b"blob"]:
            raise ValueError(f"无法读取暂存 blob：{path!r}")
        size = int(header[2])
        start, offset = end + 1, end + 2 + size
        if offset > len(objects) or objects[offset - 1:offset] != b"\n":
            raise ValueError(f"暂存 blob 不完整：{path!r}")
        check(objects[start:start + size], path, "index")
    if offset != len(objects):
        raise ValueError("暂存 blob 批量读取包含意外数据")

    for path in sorted(candidates):
        candidate = ROOT / path
        if candidate.is_symlink() or candidate.resolve() != candidate.absolute():
            raise ValueError(f"工作区候选不能是符号链接：{path!r}")
        if not candidate.exists() and path not in untracked:
            continue  # 未暂存删除；index 已单独扫描。
        try:
            check(candidate.read_bytes(), path, "工作区")
        except OSError as error:
            raise ValueError(f"无法读取工作区候选：{path!r}（{type(error).__name__}）") from error
    print(f"敏感扫描通过：{len(indexed)} 个 index blob，{len(candidates)} 个工作区候选；未输出正文")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, UnicodeError) as error:
        raise SystemExit(str(error)) from error
