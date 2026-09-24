# Git Identity Guard

Git Identity Guard is a cross-platform plugin for Claude Code and Codex CLI. It ensures that commits, pushes, and pull request creation use the Git and GitHub identity configured for the current repository.

## What it protects

- Stores the expected GitHub login, Git email, and author name in local Git configuration.
- Installs chained `pre-commit` and `pre-push` hooks without discarding existing hooks.
- Checks commit author/committer identity before commits, and before pushes checks every outgoing commit that no remote-tracking ref already contains. Commits merged in from another remote, such as an upstream fork parent, keep their original authors and pass.
- Provides Claude Code and Codex CLI PreToolUse hooks for `git commit`, `git push`, and `gh pr create`.
- Verifies the current GitHub CLI account before pull request creation.

Credentials and tokens are never written into the repository.

## Install

Clone a specific release tag or commit instead of executing an unpinned remote script:

```bash
git clone --depth 1 --branch v0.1.0 https://github.com/hiiamtrong/git-identity-guard.git \
  ~/.local/share/git-identity-guard
```

Install the guard in a repository:

```bash
~/.local/share/git-identity-guard/scripts/git-identity-guard install \
  --user <github-login> \
  --email <verified-git-email> \
  --name "<git-author-name>"
```

For example:

```bash
~/.local/share/git-identity-guard/scripts/git-identity-guard install \
  --user hiiamtrong \
  --email hiiamtrong@gmail.com \
  --name "David"
```

Run the following checks after installation:

```bash
~/.local/share/git-identity-guard/scripts/git-identity-guard verify
~/.local/share/git-identity-guard/scripts/git-identity-guard verify-gh
```

## Plugin usage

The plugin resources live under `.claude-plugin/`, `.codex-plugin/`, `hooks/`, and `skills/`. Add this repository to your Claude Code or Codex CLI plugin marketplace using the mechanism supported by your installed version, then install the `git-identity-guard` plugin.

### Pi

Pi uses package extensions rather than Claude/Codex hook manifests. Install this repository as a Pi package:

```bash
pi install git:github.com/hiiamtrong/git-identity-guard
```

Run `/reload` or restart Pi. The included Pi extension blocks agent-initiated `git commit` and `git push` until Git Identity Guard is installed in the current repository. It does not install a guard automatically.

## Enforcement limits

Git hooks protect commits and pushes from terminals, IDEs, and agents, but Git intentionally allows `--no-verify`. PreToolUse hooks protect the Claude Code and Codex CLI execution paths. For server-side enforcement, also use protected branches and CI policy checks.

## Development

```bash
./tests/test_git_identity_guard.sh
```
