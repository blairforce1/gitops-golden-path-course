---
name: break-glass
argument-hint: "[stuck check name | "forge down"] [incident item #N, created if absent]"
description: >-
  Land a production fix when the change machinery itself is the outage (the forge is down, a required check is stuck red), by the narrowest bypass that works, declared on the incident item before acting, with the controls restored and proved afterwards and the change reconciled by PR. Use when asked to bypass a control under incident conditions, or to record a bypass that already happened.
---

# break-glass

The controls exist so that nothing reaches production unreviewed. When the controls themselves are broken, the answer is not to disable them but to bypass one, narrowly, on the record, and put it back.

## 1. Declare, before acting

On the incident work item (create it if absent: labels `incident`, `sev0` or `sev1`), one comment: what is being bypassed, why the normal path cannot work, who is acting, from when. Capture the prior state so the restore can be proved:

```sh
./scripts/ruleset show > /tmp/ruleset-before.txt && cat /tmp/ruleset-before.txt
./scripts/check-repo | tee /tmp/check-repo-before.txt
```

## 2. Bypass, as narrowly as possible, in this order

1. **A stuck check and a working forge:** merge with the check owner's agreement recorded, using the narrowest ruleset change: `./scripts/ruleset require-check` with the stuck check left out of the list, nothing else touched. Every other check still gates.
2. **A working cluster and a dark forge:** apply the fix directly with `kubectl apply -f` from a manifest saved in the incident's own directory, and say in the comment that drift correction will remove it at the next reconcile of a divergent git; the reconcile interval is the deadline for step 4.
3. **Never:** a bypass actor on the ruleset, a force push, disabling the ruleset, `flux suspend` as a way to keep a manual change.

Each command is pasted into the item's comments as it is run.

## 3. Land the fix, then restore and prove

```sh
./scripts/ruleset require-check <the original list>      # exactly the prior state
./scripts/ruleset show > /tmp/ruleset-after.txt && diff /tmp/ruleset-before.txt /tmp/ruleset-after.txt && echo "restored"
./scripts/check-repo                                     # all PASS, pasted into the item
```

`diff` empty and `check-repo` all PASS is the proof. Memory is not.

## 4. Reconcile

The emergency change is not finished until it is a PR: re-land it as a normal change with `./scripts/pr-open`, citing the incident (`Refs: #<incident>`), or open the revert if it must not stay. Confirm the next reconcile converged on `main`. Then write the dossier with `audit-evidence` and attach it to the item. A person closes the item.

## Rules

- Declare first. An undeclared bypass is an incident of its own.
- The narrowest bypass that works; never widen one to save time.
- The ruleset ends in the state it started; `diff` proves it.
- Every step is a comment with its command.
- Where a standing break-glass identity exists, every use opens a review item, and an unratified manual change is swept at the next reconcile.
