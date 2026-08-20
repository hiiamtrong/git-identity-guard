#!/usr/bin/env bash
set -euo pipefail

input="$(cat)"
if ! parsed="$(python3 -c '
import json
import shlex
import sys

try:
    payload = json.loads(sys.stdin.read())
except (json.JSONDecodeError, OSError) as exc:
    print(f"ERROR\t{exc}")
    raise SystemExit(0)

tool_input = payload.get("tool_input") or payload.get("toolArgs") or {}
command = tool_input.get("command") if isinstance(tool_input, dict) else None
cwd = payload.get("cwd") if isinstance(payload.get("cwd"), str) else ""
if not isinstance(command, str):
    print("NONE\t" + cwd)
    raise SystemExit(0)

try:
    lexer = shlex.shlex(command, posix=True, punctuation_chars=True)
    tokens = list(lexer)
except ValueError as exc:
    print(f"ERROR\t{exc}")
    raise SystemExit(0)

def subcommand_after(tokens, index, command, options_with_values):
    cursor = index + 1
    while cursor < len(tokens):
        token = tokens[cursor]
        if token == "--":
            return None
        if token in options_with_values:
            cursor += 2
            continue
        if any(token.startswith(option + "=") for option in options_with_values):
            cursor += 1
            continue
        if command == "git" and (token == "-C" or token == "-c" or token.startswith("-C") or token.startswith("-c")):
            cursor += 2 if token in {"-C", "-c"} else 1
            continue
        return token
    return None

actions = []
for index, token in enumerate(tokens):
    if token == "git":
        action = subcommand_after(
            tokens,
            index,
            "git",
            {"--git-dir", "--work-tree", "--config-env", "--exec-path", "--namespace"},
        )
        if action in {"commit", "push"} and action not in actions:
            actions.append(action)
    if token == "gh":
        subcommand = subcommand_after(tokens, index, "gh", {"--repo", "--hostname"})
        if subcommand != "pr":
            continue
        pr_index = tokens.index(subcommand, index + 1)
        action = tokens[pr_index + 1] if pr_index + 1 < len(tokens) else None
        if action == "create" and "pr-create" not in actions:
            actions.append("pr-create")

print(";".join(actions) if actions else "NONE", end="\t")
print(cwd)
' <<<"$input")"; then
  printf 'git-identity-guard: không chạy được parser Bash command; từ chối để tránh bypass.\n' >&2
  exit 2
fi

action_list="${parsed%%$'\t'*}"
event_cwd="${parsed#*$'\t'}"
if [[ "$action_list" == "ERROR"* ]]; then
  printf 'git-identity-guard: không phân tích được Bash command; từ chối để tránh bypass. %s\n' "${action_list#ERROR$'\t'}" >&2
  exit 2
fi
[[ "$action_list" != "NONE" ]] || exit 0

if [[ -n "$event_cwd" ]]; then
  cd -- "$event_cwd" || {
    printf 'git-identity-guard: không vào được thư mục command: %s\n' "$event_cwd" >&2
    exit 2
  }
elif [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
  cd -- "$CLAUDE_PROJECT_DIR" || {
    printf 'git-identity-guard: không vào được project directory.\n' >&2
    exit 2
  }
fi

core="${CLAUDE_PLUGIN_ROOT:-$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)}/scripts/git-identity-guard"
[[ -x "$core" ]] || {
  printf 'git-identity-guard: không tìm thấy core guard: %s\n' "$core" >&2
  exit 2
}

IFS=';' read -r -a actions <<<"$action_list"
for action in "${actions[@]}"; do
  case "$action" in
    commit|push)
      "$core" verify || exit 2
      ;;
    pr-create)
      "$core" verify-gh || exit 2
      ;;
    *)
      printf 'git-identity-guard: action không hỗ trợ: %s\n' "$action" >&2
      exit 2
      ;;
  esac
done
