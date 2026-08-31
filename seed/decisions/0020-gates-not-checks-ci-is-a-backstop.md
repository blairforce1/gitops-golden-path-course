# 0020. Gates, not checks; CI is a backstop that never fires

- **Status:** accepted
- **Date:** 2026-08-20
- **Deciders:** blairforce1, with Claude Code
- **Supersedes:** none

## Context

Bare command output at a checkpoint is unreadable: the reader cannot tell pass from fail. A check that lives in three hand-copies (a paste block, a CI workflow, a checkpoint script) drifts, and the contract "CI runs the identical file" quietly breaks. A red CI run on a mechanical check (formatting, lint) is a process failure as well as an annoyance: the check existed and did not run locally. Hook frameworks (pre-commit, husky, lefthook) add a dependency to a repo whose ethos is dependency-free bash.

## Decision

A **gate** turns one class of evidence into one verdict: `PASS`/`FAIL` lines with what each means, non-zero exit, nothing else. Every gate is a pure function over the working tree where it can be, so the same file runs as a paste block, in CI and from a git hook. The `*-gate` family (`policy-gate`, `style-gate`, `commit-gate`, `path-gate`, `revert-gate`, `freeze-gate`, `slo-gate`) each own one verdict. Hooks are a committed `hooks/` directory activated once with `git config core.hooksPath hooks/`: pre-commit is fast and changed-files-only (format auto-fix, yamllint with CI's exact config); pre-push runs exactly CI's jobs. Hooks are opt-in and bypassable (`--no-verify`, fresh clones), so hooks reduce friction while **CI remains the enforcement**, and a red CI on a mechanical check is treated as a process failure.

## Considered options

- **A hook framework.** A dependency and a second config format for a job bash does in twenty lines.
- **CI only.** Every mechanical failure costs a push, a wait and a red run; the fix belongs on the laptop.
- **Hooks only.** Bypassable by construction; enforcement has to sit where bypass is impossible.
- **Checks with human-read output.** Readers miss failures; scripts cannot compose them.

## Consequences

- Easier: one file, three call sites; a drill can manufacture a red CI run deliberately (two bypasses, one backstop) to prove where enforcement lives.
- Harder: gates need to be era-aware when a repo's shape changes over time; the `era` vocabulary exists for that.
- Follow-up: cluster-state checkpoints and toolchain gates are different questions and are deliberately not one umbrella.

## Where it is taught or enforced

Rule 5.9; stage 02 (the first checkpoint), stage 08 (the first gate in CI), stage 11 (hooks, `style-gate`, the record check); `hooks/`, `scripts/*-gate`, `scripts/checkpoint-NN`.
