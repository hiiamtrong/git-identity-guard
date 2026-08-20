---
name: git-identity-guard
description: Install and verify Git Identity Guard so commits, pushes, and gh pr create use the configured GitHub and Git identity.
---

# Git Identity Guard

Install the guard for the current repository:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/git-identity-guard" install \
  --user <github-login> \
  --email <git-email> \
  --name <git-name>
```

`--user` must match the login returned by `gh api user`. The email must be present in both author and committer metadata. The installer stores its configuration in local Git config, copies its runner into `.git/identity-guard/`, and chains existing `pre-commit` and `pre-push` hooks.

Verify the configured identity:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/git-identity-guard" verify
"${CLAUDE_PLUGIN_ROOT}/scripts/git-identity-guard" verify-gh
```

Git hooks can be bypassed deliberately with `--no-verify`; use protected branches and CI for server-side enforcement.
