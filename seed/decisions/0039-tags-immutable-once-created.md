# 0039. Tags are immutable once created: a tag ruleset from day zero

- **Status:** accepted
- **Date:** 2026-08-30
- **Deciders:** blairforce1, with Claude Code
- **Supersedes:** none

## Context

The config repo is tagged at every stage and act boundary, and those tags are load-bearing evidence: "your tree should now match `stage-07`" is an assertion only because the tag exists, the act drills rebuild *to* a tag, and the DORA computation and the per-cluster change record read ranges between them. [0002](0002-protection-on-main-from-day-zero.md) protects `main` from day zero - nothing reaches it except a merged PR - but a tag is a ref like any other, and by default the repository owner can move or delete one with a single force-push: no PR, no review, no trace beyond a reflog nobody keeps. A movable save point is a rewritable audit trail: everything ever asserted against `stage-07` silently re-aims with it.

## Decision

A second ruleset, `tags`, targets every tag from the day the repo is created, beside the `main` ruleset and with the same posture: enforcement active, **no bypass actors**. It blocks update, deletion and non-fast-forward pushes and deliberately leaves **creation open**: minting `stage-NN` and `act-N` at every boundary is the walkthrough's own loop. Once pushed, a tag names one commit forever. A mis-tag is repaired by disabling the ruleset, fixing, and re-enabling - a deliberate, visible bypass, never a quiet force-push. The app repo is untouched: its `v*` tags drive CI builds and stay ordinary refs.

## Considered options

- **Leave tags unprotected.** The default, and what the repo had while only `main` was covered. Every claim built on tags is then only as strong as a promise that nobody force-pushed. Rejected for the reason 0002 rejected an unprotected `main`.
- **Protect only `stage-*` and `act-*` patterns.** Makes the rule's scope a thing to remember and lets unprotected tags accumulate beside protected ones; every tag in this repo is a boundary marker, so the pattern buys nothing. Rejected.
- **Require signed tags instead.** A signature proves authorship, not immutability: a signed tag can still be moved by its author. Orthogonal, not a substitute. Rejected.
- **Block creation too and mint tags through a workflow.** The tag is the last line of every stop-and-measure; a detour for the loop the course repeats most, to guard against a mistake the update rule already catches. Rejected.

## Consequences

- Easier: every range built on tags - drills, DORA, the change record - rests on refs that cannot silently change; the evidence story has no writable back door.
- Harder: no scratch tags. With deletion blocked, any pushed tag is permanent, so this control is not proved with a test push the way 0002's is; the first mistyped tag teaches it instead.
- Harder: repairing a genuine mis-tag requires disabling the ruleset in the repo settings, visibly.
- Follow-up: `scripts/ruleset show` prints both rulesets; `scripts/check-repo` reads the tag ruleset back beside the main one and fails if creation is blocked or a bypass actor appears.

## Where it is taught or enforced

Rule 1.3; stage 00 step 1 (created beside the `main` ruleset); tags at every boundary is using-the-course §5; `scripts/ruleset`, `scripts/check-repo`. Related: [0002](0002-protection-on-main-from-day-zero.md) (the branch half), [0022](0022-dora-from-artifacts-no-stopwatch.md) (tags as range markers).
