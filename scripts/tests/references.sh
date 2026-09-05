#!/usr/bin/env bash
# 冻结引用 bootstrap/纯校验合同；只操作临时本地 Git 仓库，不访问网络。
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
check_script=$repo_root/scripts/check/references.sh
bootstrap_script=$repo_root/scripts/bootstrap/references.sh

if [[ ! -f "$check_script" || ! -f "$bootstrap_script" ]]; then
  printf '%s\n' 'RED: refs 的 bootstrap/纯校验入口尚未建立' >&2
  exit 1
fi

# shellcheck source=../check/references.sh
source "$check_script"
# shellcheck source=../bootstrap/references.sh
source "$bootstrap_script"

test_root=$(mktemp -d "${TMPDIR:-/tmp}/ubaa-references-test.XXXXXX")
trap 'rm -rf -- "$test_root"' EXIT

origin_work=$test_root/origin-work
remote=$test_root/reference.git
sandbox=$test_root/sandbox
mkdir -p "$origin_work" "$sandbox"
git -C "$origin_work" init -q
printf '%s\n' 'reference fixture' >"$origin_work/reference.txt"
git -C "$origin_work" add reference.txt
git -C "$origin_work" -c user.name=UBAA -c user.email=ubaa@example.invalid commit -q -m fixture
locked_commit=$(git -C "$origin_work" rev-parse HEAD)
git clone -q --bare "$origin_work" "$remote"

# 缺失引用只能失败和提示显式 bootstrap，不得创建任何路径。
missing=$sandbox/missing
if check_reference "$sandbox" "$missing" "$remote" "$locked_commit" \
  >"$test_root/missing.out" 2>"$test_root/missing.err"; then
  printf '%s\n' '缺失引用被纯校验错误接受' >&2
  exit 1
fi
[[ ! -e "$missing" ]]
grep -F 'just refs-bootstrap' "$test_root/missing.err" >/dev/null

# 已存在的正确引用在禁止联网 Git 子命令的 PATH 下仍应通过。
reference=$sandbox/reference
git clone -q "$remote" "$reference"
git -C "$reference" checkout -q --detach "$locked_commit"
real_git=$(command -v git)
mkdir -p "$test_root/fake-bin"
cat >"$test_root/fake-bin/git" <<'FAKE_GIT'
#!/usr/bin/env bash
set -euo pipefail
arguments=("$@")
index=0
while [[ ${arguments[$index]:-} == -C || ${arguments[$index]:-} == -c ]]; do
  index=$((index + 2))
done
command=${arguments[$index]:-}
case "$command" in
  clone|fetch|pull|checkout|switch|reset|clean|add|commit)
    printf '纯校验禁止写入 Git 子命令：%s\n' "$command" >&2
    exit 97
    ;;
esac
exec "$REAL_GIT" "$@"
FAKE_GIT
chmod +x "$test_root/fake-bin/git"
PATH="$test_root/fake-bin:$PATH" REAL_GIT="$real_git" \
  check_reference "$sandbox" "$reference" "$remote" "$locked_commit" \
  >"$test_root/correct.out"
grep -F "reference @ $locked_commit" "$test_root/correct.out" >/dev/null

# remote、HEAD 与工作树任一不符都必须失败，且不得自动规范化。
git -C "$reference" remote set-url origin "$test_root/wrong.git"
if check_reference "$sandbox" "$reference" "$remote" "$locked_commit" \
  >"$test_root/remote.out" 2>"$test_root/remote.err"; then
  printf '%s\n' '错误 remote 被纯校验接受' >&2
  exit 1
fi
grep -F '远端不匹配' "$test_root/remote.err" >/dev/null
[[ $(git -C "$reference" remote get-url origin) == "$test_root/wrong.git" ]]
git -C "$reference" remote set-url origin "$remote"

git -C "$reference" -c user.name=UBAA -c user.email=ubaa@example.invalid \
  commit -q --allow-empty -m wrong-head
wrong_commit=$(git -C "$reference" rev-parse HEAD)
if check_reference "$sandbox" "$reference" "$remote" "$locked_commit" \
  >"$test_root/head.out" 2>"$test_root/head.err"; then
  printf '%s\n' '错误 HEAD 被纯校验接受' >&2
  exit 1
fi
grep -F '提交不匹配' "$test_root/head.err" >/dev/null
[[ $(git -C "$reference" rev-parse HEAD) == "$wrong_commit" ]]
git -C "$reference" checkout -q --detach "$locked_commit"

printf '%s\n' 'dirty' >>"$reference/reference.txt"
if check_reference "$sandbox" "$reference" "$remote" "$locked_commit" \
  >"$test_root/dirty.out" 2>"$test_root/dirty.err"; then
  printf '%s\n' '脏引用被纯校验接受' >&2
  exit 1
fi
grep -F '工作树不干净' "$test_root/dirty.err" >/dev/null

# bootstrap 只创建缺失引用；已有非 Git 路径必须保持原样并失败。
failed=$sandbox/failed
mkdir -p "$test_root/fail-bin"
cat >"$test_root/fail-bin/git" <<'FAIL_GIT'
#!/usr/bin/env bash
set -euo pipefail
if [[ ${1:-} == -C && ${3:-} == fetch ]]; then
  exit 73
fi
exec "$REAL_GIT" "$@"
FAIL_GIT
chmod +x "$test_root/fail-bin/git"
if PATH="$test_root/fail-bin:$PATH" REAL_GIT="$real_git" \
  bootstrap_reference "$sandbox" "$failed" "$remote" "$locked_commit" \
  >"$test_root/failed.out" 2>"$test_root/failed.err"; then
  printf '%s\n' '注入 fetch 失败后 bootstrap 错误成功' >&2
  exit 1
fi
[[ ! -e "$failed" ]]
if find "$sandbox" -maxdepth 1 -name '.ubaa-reference.failed.*' -print -quit | grep -q .; then
  printf '%s\n' 'bootstrap 失败后遗留临时目录' >&2
  exit 1
fi

# bootstrap 在 Git 子进程触发终止信号时也必须清理临时目录和未完成目标。
signaled=$sandbox/signaled
mkdir -p "$test_root/signal-bin"
cat >"$test_root/signal-bin/git" <<'SIGNAL_GIT'
#!/usr/bin/env bash
set -euo pipefail
if [[ ${1:-} == -C && ${3:-} == fetch ]]; then
  kill -TERM "$PPID"
  exit 143
fi
exec "$REAL_GIT" "$@"
SIGNAL_GIT
chmod +x "$test_root/signal-bin/git"
set +e
PATH="$test_root/signal-bin:$PATH" REAL_GIT="$real_git" \
  bootstrap_reference "$sandbox" "$signaled" "$remote" "$locked_commit" \
  >"$test_root/signaled.out" 2>"$test_root/signaled.err"
signal_status=$?
set -e
[[ $signal_status -eq 143 ]]
[[ ! -e "$signaled" ]]
if find "$sandbox" -maxdepth 1 -name '.ubaa-reference.signaled.*' -print -quit | grep -q .; then
  printf '%s\n' 'bootstrap 被信号中断后遗留临时目录' >&2
  exit 1
fi

bootstrapped=$sandbox/bootstrapped
bootstrap_reference "$sandbox" "$bootstrapped" "$remote" "$locked_commit" \
  >"$test_root/bootstrap.out"
check_reference "$sandbox" "$bootstrapped" "$remote" "$locked_commit" >/dev/null

blocked=$sandbox/blocked
mkdir -p "$blocked"
printf '%s\n' 'keep' >"$blocked/marker"
if bootstrap_reference "$sandbox" "$blocked" "$remote" "$locked_commit" \
  >"$test_root/blocked.out" 2>"$test_root/blocked.err"; then
  printf '%s\n' 'bootstrap 覆盖了已有非 Git 路径' >&2
  exit 1
fi
[[ $(<"$blocked/marker") == keep ]]

# recipe、release preflight 与 CI 必须体现副作用边界。
outside=$test_root/outside
mkdir -p "$outside"
dry_run_recipe() {
  local cwd=$1
  local recipe=$2
  if [[ $cwd == "$outside" ]]; then
    (cd "$cwd" && just --justfile "$repo_root/justfile" --dry-run "$recipe")
  else
    (cd "$cwd" && just --dry-run "$recipe")
  fi
}
for cwd in "$repo_root" "$repo_root/apps/ubaa-cli" "$outside"; do
  refs_dry_run=$(dry_run_recipe "$cwd" refs 2>&1)
  bootstrap_dry_run=$(dry_run_recipe "$cwd" refs-bootstrap 2>&1)
  sensitive_dry_run=$(dry_run_recipe "$cwd" check-sensitive 2>&1)
  flutter_dry_run=$(dry_run_recipe "$cwd" flutter-check 2>&1)
  preflight_dry_run=$(dry_run_recipe "$cwd" release-preflight 2>&1)
  if ! [[ $refs_dry_run == *'scripts/check/references.sh'* &&
    $refs_dry_run != *'bootstrap/references.sh'* &&
    $bootstrap_dry_run == *'scripts/bootstrap/references.sh'* &&
    $sensitive_dry_run == *'scripts/check/sensitive.sh'* &&
    $flutter_dry_run == *'scripts/check/flutter-workspace.sh'* &&
    $preflight_dry_run == *'scripts/release/preflight.sh'* ]]; then
    printf 'recipe dry-run 输出未满足副作用边界：%s\n' "$cwd" >&2
    exit 1
  fi
done
grep -F 'scripts/check/references.sh' "$repo_root/scripts/release/preflight.sh" >/dev/null
if grep -F 'bootstrap/references.sh' "$repo_root/scripts/release/preflight.sh" >/dev/null; then
  printf '%s\n' 'release preflight 不得调用引用 bootstrap' >&2
  exit 1
fi

bootstrap_line=$(grep -n 'just refs-bootstrap' "$repo_root/.github/workflows/ci.yml" | head -n 1 | cut -d: -f1)
refs_line=$(grep -n 'just refs$' "$repo_root/.github/workflows/ci.yml" | head -n 1 | cut -d: -f1)
[[ -n "$bootstrap_line" && -n "$refs_line" && $bootstrap_line -lt $refs_line ]]

printf '%s\n' 'references shell contract passed'
