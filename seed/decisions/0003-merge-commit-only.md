# 0003. Merge commits only; the PR title and body become the commit

- **Status:** accepted
- **Date:** 2026-08-24
- **Deciders:** blairforce1, with Claude Code
- **Supersedes:** none

## Context

In a config repo the PR is the unit of review: it carries the approvals, the rendered diff, the status checks and the evidence a promotion was gated on. After merge, the merge strategy decides whether any of that remains reachable from history. Squash rewrites the subject (appending ` (#N)`, concatenating branch messages), so a commit written to the convention becomes a fiction that never reaches `main`. Rebase rewrites SHAs, so the revision a cluster reported an hour ago (`lastAppliedRevision`) can become unreachable exactly when a release-notes range needs it. GitHub's default merge subject is `Merge pull request #N from owner/branch`, which violates any commit convention regardless of how the PR was titled.

## Decision

Merge commit only: squash and rebase disabled, `merge_commit_title=PR_TITLE`, `merge_commit_message=PR_BODY`, head branches deleted on merge, auto-merge allowed for the robot. Set on the day the repo is created, before the first PR. Locally, `pull.rebase false` and `commit.template .gitmessage`. Linear history stays off, because it forbids merge commits.

## Considered options

- **Squash merge.** Clean history at the cost of the record: the PR's typed subject and trailers do not survive, and the branch's commits (which the clusters may have applied on an ephemeral environment) vanish.
- **Rebase merge.** Keeps every commit, loses the pointer to the PR and rewrites SHAs a fleet has already reported.
- **Merge commits with the default title.** Every merge commit fails the commit convention; the fix is two repository settings, so there is no reason to accept it.

## Consequences

- Easier: `git log --first-parent` is the shipped-changes view and the full log the change-level view; both survive. Per-cluster release notes are a `lastAppliedRevision` range grouped by commit type.
- Easier: the trailers (`Refs:`, `Roll-forward:`, `Freeze-override:`) travel into history with the body.
- Harder: the PR title must obey the commit grammar exactly, because it becomes the subject on `main`; that is what the `pr-record` check exists for ([0004](0004-commit-convention-scope-is-blast-radius.md)).
- Harder: undoing a merge is `git revert -m 1`, because a merge commit has two parents; `pr-revert` does it.

## Where it is taught or enforced

Rules 1.2 and 2.3; applied at stage 00 step 1; re-verified at the first PR (stage 07); `appendices/git-policy.md` tabulates the queries this buys; `scripts/check-repo` reads the settings back.
