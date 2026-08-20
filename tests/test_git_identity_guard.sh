#!/usr/bin/env bash
set -euo pipefail

plugin_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)"
core="$plugin_root/scripts/git-identity-guard"
pretool="$plugin_root/scripts/pretool-use.sh"
zero_sha='0000000000000000000000000000000000000000'
tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/git-identity-guard-test.XXXXXX")"
trap 'rm -rf "$tmp_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local needle="$1" haystack="$2"
  [[ "$haystack" == *"$needle"* ]] || fail "did not find '$needle' in: $haystack"
}

assert_fails() {
  local output status
  set +e
  output="$("$@" 2>&1)"
  status=$?
  set -e
  [[ "$status" -ne 0 ]] || fail "command should have failed but passed: $*"
  printf '%s' "$output"
}

repo="$tmp_root/repo"
mkdir -p "$repo"
git -C "$repo" init -q
git -C "$repo" config user.name 'Trong Vu'
git -C "$repo" config user.email 'trong.vu@example.com'
mkdir -p "$repo/.git/hooks"
cat >"$repo/.git/hooks/pre-commit" <<'EOF'
#!/bin/sh
printf original >> "$(git rev-parse --git-dir)/original-hook-ran"
EOF
chmod 755 "$repo/.git/hooks/pre-commit"

(
  cd "$repo"
  "$core" install --user trong-vu
)
[[ -x "$repo/.git/hooks/pre-commit" ]] || fail 'pre-commit chưa được cài'
[[ -x "$repo/.git/hooks/pre-push" ]] || fail 'pre-push chưa được cài'
[[ -x "$repo/.git/identity-guard/guard" ]] || fail 'runner chưa được copy'
[[ -f "$repo/.git/hooks/pre-commit.identity-guard-original" ]] || fail 'hook cũ chưa được backup'

printf 'one\n' >"$repo/one.txt"
git -C "$repo" add one.txt
git -C "$repo" commit -q -m 'first commit'
[[ -f "$repo/.git/original-hook-ran" ]] || fail 'hook cũ không được chain'

base_branch="$(git -C "$repo" branch --show-current)"
git -C "$repo" switch -q -c legacy-merge-branch
git -C "$repo" -c user.name='GitHub' -c user.email='noreply@github.com' \
  commit --allow-empty --no-verify -q -m 'legacy branch commit'
git -C "$repo" switch -q "$base_branch"
git -C "$repo" -c user.name='GitHub' -c user.email='noreply@github.com' \
  merge --no-ff --no-verify legacy-merge-branch -m 'legacy GitHub merge'
legacy_merge_sha="$(git -C "$repo" rev-parse HEAD)"
legacy_range_output="$(cd "$repo" && assert_fails "$core" verify --range "$legacy_merge_sha")"
assert_contains 'email mismatch' "$legacy_range_output"
printf 'after merge\n' >"$repo/after-merge.txt"
git -C "$repo" add after-merge.txt
git -C "$repo" commit -q -m 'commit after legacy merge'
incremental_push_sha="$(git -C "$repo" rev-parse HEAD)"
(
  cd "$repo"
  printf 'refs/heads/main %s refs/heads/main %s\n' \
    "$incremental_push_sha" "$legacy_merge_sha" | .git/hooks/pre-push origin test
)
remote="$tmp_root/remote.git"
git init --bare -q "$remote"
git -C "$repo" remote add origin "$remote"
git -C "$repo" push --no-verify -q origin "$legacy_merge_sha:refs/heads/$base_branch"
git -C "$repo" fetch -q origin
git -C "$repo" switch -q -c feature-after-legacy
git -C "$repo" push -q origin HEAD:refs/heads/feature-after-legacy

git -C "$repo" config user.email 'wrong@example.com'
printf 'two\n' >"$repo/two.txt"
git -C "$repo" add two.txt
commit_output="$(assert_fails git -C "$repo" commit -q -m 'wrong identity')"
assert_contains 'email mismatch' "$commit_output"
git -C "$repo" config user.email 'trong.vu@example.com'
git -C "$repo" config user.name 'Other User'
name_output="$(assert_fails git -C "$repo" commit -q -m 'wrong name')"
assert_contains 'name mismatch' "$name_output"
git -C "$repo" config user.name 'Trong Vu'

fake_bin="$tmp_root/bin"
mkdir -p "$fake_bin"
cat >"$fake_bin/gh" <<'EOF'
#!/bin/sh
if [ "$1" = api ]; then
  printf '%s\n' "${FAKE_GH_LOGIN:-trong-vu}"
else
  printf 'gh delegated\n'
fi
EOF
chmod 755 "$fake_bin/gh"

good_path="$fake_bin:$PATH"
(cd "$repo" && PATH="$good_path" "$core" verify-gh)
set +e
wrong_gh_output="$(cd "$repo" && FAKE_GH_LOGIN=other PATH="$good_path" "$core" verify-gh 2>&1)"
wrong_gh_status=$?
set -e
[[ "$wrong_gh_status" -ne 0 ]] || fail 'verify-gh không chặn sai GitHub user'
assert_contains 'GitHub user mismatch' "$wrong_gh_output"

payload='{"cwd":"'$repo'","tool_name":"Bash","tool_input":{"command":"git -C '$repo' commit -m x"}}'
printf '%s' "$payload" | PATH="$good_path" "$pretool"
printf '%s' "$payload" | CLAUDE_PLUGIN_ROOT="$plugin_root" PATH="$good_path" "$pretool"
set +e
bad_payload="$(printf '%s' "$payload" | sed "s#git -C $repo commit -m x#gh --repo owner/repo pr create#" | FAKE_GH_LOGIN=other PATH="$good_path" "$pretool" 2>&1)"
bad_payload_status=$?
set -e
[[ "$bad_payload_status" -eq 2 ]] || fail 'PreToolUse không chặn gh pr create sai user'
assert_contains 'GitHub user mismatch' "$bad_payload"

bin_path="$plugin_root/bin:$fake_bin:$PATH"
gh_output="$(cd "$repo" && PATH="$bin_path" "$plugin_root/bin/gh" pr create --title test)"
assert_contains 'gh delegated' "$gh_output"
set +e
wrong_bin_output="$(cd "$repo" && FAKE_GH_LOGIN=other PATH="$bin_path" "$plugin_root/bin/gh" pr create --title test 2>&1)"
wrong_bin_status=$?
set -e
[[ "$wrong_bin_status" -ne 0 ]] || fail 'gh wrapper không chặn sai user'
assert_contains 'GitHub user mismatch' "$wrong_bin_output"

set +e
malformed_output="$(printf '{' | PATH="$good_path" "$pretool" 2>&1)"
malformed_status=$?
set -e
[[ "$malformed_status" -eq 2 ]] || fail 'PreToolUse không fail-closed với JSON malformed'
assert_contains 'không phân tích được Bash command' "$malformed_output"

git -C "$repo" -c user.name='Other User' -c user.email='other@example.com' commit --allow-empty --no-verify -q -m 'bad commit'
bad_commit_sha="$(git -C "$repo" rev-parse HEAD)"
set +e
push_output="$(cd "$repo" && printf 'refs/heads/main %s refs/heads/main %s\n' "$bad_commit_sha" "$zero_sha" | .git/hooks/pre-push origin test 2>&1)"
push_status=$?
set -e
[[ "$push_status" -ne 0 ]] || fail 'pre-push không chặn commit author sai'
assert_contains 'email mismatch' "$push_output"

(cd "$repo" && "$core" uninstall)
[[ -x "$repo/.git/hooks/pre-commit" ]] || fail 'uninstall không khôi phục hook cũ'
[[ ! -e "$repo/.git/hooks/pre-push" ]] || fail 'uninstall không gỡ pre-push'
[[ ! -e "$repo/.git/identity-guard/guard" ]] || fail 'uninstall không gỡ runner'
[[ -z "$(git -C "$repo" config --local --get identity.guard.runner || true)" ]] || fail 'uninstall không gỡ config'

printf '✓ git-identity-guard tests passed\n'
