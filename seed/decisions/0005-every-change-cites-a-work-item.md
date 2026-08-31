# 0005. Every change cites an open work item; merge is not verification

- **Status:** accepted
- **Date:** 2026-08-26
- **Deciders:** blairforce1, with Claude Code
- **Supersedes:** none

## Context

"Why now" in a PR body is a claim. A work item is a record with its own history: who asked, when, what was discussed, what else it touched. The control an auditor asks for first is that every production change traces to an approved work item and that no change cites finished work; a closed ticket re-used is the classic gap. GitHub's `Closes:` keyword closes the item on merge, but merging is not the same as verifying the change did what it claimed.

## Decision

Every PR body ends with a `Refs: #<issue>` or `Closes: #<issue>` trailer. The number must be an issue in this repo (not a PR) that is still open. No exception for robots: image automation cites a standing issue created for it and resolved by label at run time; a freeze override cites the incident; a revert inherits what the reverted change cited. `Closes:` is used only where the PR is the whole work item, because it fires on merge and merge is not verification. A stage's or piece of work's item is closed by the person, after the checks, never by the merge.

## Considered options

- **Issue IDs in the commit scope.** Collides with blast radius ([0004](0004-commit-convention-scope-is-blast-radius.md)).
- **One issue per PR.** The honest production grain and a maintenance trap at course scale; the work item is the piece of work, not the PR.
- **Symbolic references resolved by tooling (`Refs: stage-07`).** Hides the shape a team meets in production, where the reference is a ticket key.
- **Auto-close on merge everywhere.** Closes work before its verification ran.

## Consequences

- Easier: `git log --grep='^Refs: #9'` answers "what did this piece of work actually change" long after the PR page is gone, because the body travels into the merge commit ([0003](0003-merge-commit-only.md)).
- Easier: the check is layered: `pr-open` refuses a body with no trailer, `issue-gate` resolves every number (exists, is an issue, is open), the `pr-record` job runs the same gate on every PR event and the ruleset requires it; on a push it runs `--landed`, because the merge may be what closed the item.
- Harder: trailers are only as durable as the forge's numbering, which is why production teams cite a ticket system's keys; the dependency is named rather than hidden.
- Follow-up: the robot needs a standing work item; creating it is part of wiring the robot, not a seed.

## Where it is taught or enforced

Rule 2.5; first typed at stage 02, scripted at stage 04 (`pr-open`), enforced at stage 11 (`pr-record`), the robot's standing item at stage 14, queried at stage 26 (the change record); `scripts/issue-gate`, `scripts/check-repo`. Course consequence: the backlog is the course.
