"""将候选提交、CI 作业与实际产物的逐文件摘要关联。"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'lib'))
from repo import ROOT



def digest(path):
    if path.is_symlink():
        return hashlib.sha256(os.readlink(path).encode()).hexdigest()
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def write_report(root, output, artifact=None, platform=None):
    output.mkdir(parents=True, exist_ok=True)
    record = {
        "schema_version": 2,
        "source_commit": subprocess.check_output(
            ["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip(),
        "tracked_workspace_clean": not subprocess.check_output(
            ["git", "-C", str(root), "status", "--porcelain", "--untracked-files=no"], text=True).strip(),
        "scope": "源码以提交标识；外部 SDK、系统库与下载依赖另行登记",
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
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--artifact", type=Path)
    parser.add_argument("--platform")
    args = parser.parse_args()
    write_report(args.root, args.output, args.artifact, args.platform)


if __name__ == "__main__":
    main()
