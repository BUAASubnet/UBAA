"""生成受 Git 跟踪的输入摘要，并将候选、作业和产物关联。"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess


def digest(path):
    if path.is_symlink():
        return hashlib.sha256(os.readlink(path).encode()).hexdigest()
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def source_lines(root):
    paths = subprocess.check_output([
        "git", "-C", str(root), "ls-files", "-z",
    ]).decode().split("\0")
    lines = []
    for name in sorted(filter(None, paths)):
        if any(char in name for char in "\n\r\\"):
            raise ValueError("构建输入文件名不能安全写入摘要清单")
        lines.append(f"{digest(root / name)}  {name}\n")
    return "".join(lines)


def write_report(root, output, artifact=None, platform=None):
    output.mkdir(parents=True, exist_ok=True)
    manifest = output / "source-manifest.sha256"
    manifest.write_text(source_lines(root), encoding="utf-8", newline="\n")
    record = {
        "schema_version": 1,
        "source_commit": subprocess.check_output(
            ["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip(),
        "tracked_workspace_clean": not subprocess.check_output(
            ["git", "-C", str(root), "status", "--porcelain", "--untracked-files=no"], text=True).strip(),
        "source_manifest_sha256": digest(manifest),
        "scope": "Git 跟踪的工作区输入；外部 SDK、系统库与下载依赖另行登记",
    }
    if os.environ.get("GITHUB_ACTIONS") == "true":
        record["workflow_run"] = (
            f"{os.environ.get('GITHUB_SERVER_URL', 'https://github.com')}/"
            f"{os.environ['GITHUB_REPOSITORY']}/actions/runs/{os.environ['GITHUB_RUN_ID']}")
    if artifact is not None:
        files = [artifact] if artifact.is_file() else sorted(
            path for path in artifact.rglob("*") if path.is_file() or path.is_symlink())
        if not files:
            raise ValueError("产物为空或不存在")
        entries = [{"path": path.name if artifact.is_file() else path.relative_to(artifact).as_posix(),
                    "sha256": digest(path), "symlink": path.is_symlink()} for path in files]
        body = json.dumps(entries, ensure_ascii=False, sort_keys=True, indent=2) + "\n"
        (output / "artifact-files.json").write_text(body, encoding="utf-8", newline="\n")
        record["artifact"] = {"platform": platform, "file_count": len(entries),
                              "manifest_sha256": hashlib.sha256(body.encode()).hexdigest()}
    (output / "build-record.json").write_text(
        json.dumps(record, ensure_ascii=False, sort_keys=True, indent=2) + "\n", encoding="utf-8", newline="\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--artifact", type=Path)
    parser.add_argument("--platform")
    args = parser.parse_args()
    write_report(args.root, args.output, args.artifact, args.platform)


if __name__ == "__main__":
    main()
