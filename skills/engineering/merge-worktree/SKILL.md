---
name: merge-worktree
description: Merge the current git worktree's branch into the branch it came from, then remove the worktree and delete the branch. Use when the user is done with work in a worktree and says "merge this into dev", "merge and clean up the worktree", or "merge worktree".
disable-model-invocation: true
---

Merge this worktree's branch into the branch it came from, then clean up.

- If the worktree has uncommitted changes, ask whether to commit them first.
- Target: the branch I name, otherwise the branch this one was created from (check `git reflog show <branch>`). If unsure, ask. Never target `main` unless I say so.
- Merge where the target is checked out (`git worktree list`, then `git -C <path>`). If it isn't checked out anywhere, ask.
- Fast-forward if possible, otherwise a merge commit. No rebase, no squash, no push.
- Resolve conflicts carefully, keeping the intent of both sides. If a conflict needs a product decision, stop and ask me in one short question.
- Stop any servers, containers, or other infrastructure running from this worktree. Only touch what belongs to this worktree.
- Clean up from the target's checkout, never from inside this worktree: `git worktree remove <path>`, then `git branch -d <branch>`. Never force either. If one refuses, stop and tell me why.
- Report briefly: target branch, fast-forward or merge commit, and any conflicts resolved. Explain more only when something unexpected happened.
