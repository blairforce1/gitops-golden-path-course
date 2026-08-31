# 0006. Branch names are `<type>/<issue>/<slug>`; the branch is scaffolding

- **Status:** accepted
- **Date:** 2026-08-27
- **Deciders:** blairforce1, with Claude Code
- **Supersedes:** none

## Context

No standard covers branch names the way Conventional Commits covers subjects, so every repo invents one and most invent nothing. A branch name is shown everywhere GitHub shows a PR: the header, the checks page, the push log. With merge-commit-only and delete-on-merge, nobody looks at a branch after merge; its only job is to make intent confirmable at a glance while the PR is open. The repo already has two vocabularies that carry intent: the commit type and the work item.

## Decision

Branches are named `<type>/<issue>/<slug>`: the commit type the PR will carry, the work item it advances, and a kebab-case slug, as in `feat/3/overlays`, `promote/10/app-prod`, `rotate/22/dev-key`. `pr-open` refuses a name that does not parse, checks the type against the subject and the issue segment against the body's trailer. `pr-revert` emits `revert/<issue>/<sha7>`. The robot's standing `flux-image-updates` branch is the named exception, reused rather than per-change, because the image-automation controller owns it.

## Considered options

- **Free-form names.** Nothing to check; intent has to be read from the diff.
- **`<user>/<slug>`.** Names the author, who is already on the PR, and nothing about the change.
- **Ticket key only (`GGP-142`).** Half the information; the type is the half that says what kind of change is coming.

## Consequences

- Easier: type and work item are visible before the PR is opened, and `pr-open` can cross-check the three surfaces (branch, subject, trailer) for agreement.
- Harder: one more thing for a hand-typed branch to get wrong; `pr-open` is the answer, and it is the only tool that creates branches from stage 04.
- Follow-up: none; the shape reuses vocabularies that already exist ([0004](0004-commit-convention-scope-is-blast-radius.md), [0005](0005-every-change-cites-a-work-item.md)).

## Where it is taught or enforced

Rule 2.4; stages 02 and 03 type it by hand, stage 04 introduces `pr-open`; the exception at stage 14.
