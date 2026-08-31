# 0033. Break-glass: declare it, bypass as narrowly as possible, prove the restore, reconcile by PR

- **Status:** accepted
- **Date:** 2026-08-28
- **Deciders:** blairforce1, with Claude Code
- **Supersedes:** none

## Context

The happy path is governed thoroughly; audits and real incidents go straight for the sanctioned ways around it. Sometimes the change machinery itself is the outage: the forge is down, or a required check is stuck red while a production fix must land. A control with no sanctioned bypass gets bypassed by disabling the control, leaving neither the control nor a record. And the temporary hack that became permanent is the classic outcome of an unrecorded bypass.

## Decision

Break-glass is a rehearsed procedure, not an identity with standing power. Declare the bypass on the incident work item before acting. Land the fix by the narrowest bypass that works (a ruleset amendment for one check, a direct apply as the last resort), with every step recorded on the item. Restore the controls to their prior state and prove it: `check-repo` all PASS, `ruleset show` showing no bypass actors. Reconcile the emergency change into a normal PR record afterwards, citing the incident. Where a designated break-glass identity exists in production, every use auto-opens a review item, and drift correction sweeps a manual change at the next reconcile unless it is ratified by PR within a stated window, so the hack cannot calcify. The in-band sibling is the freeze override trailer ([0023](0023-change-freeze-is-a-calendar-in-git.md)); policy exceptions carry an expiry for the same reason.

## Considered options

- **A standing admin bypass on the ruleset.** Every merge is one click from unreviewed, and nothing distinguishes an emergency from a habit.
- **No bypass at all.** The control gets disabled under pressure and the record is lost.
- **Suspend reconciliation during the incident.** Stops drift correction too, and never expires ([0027](0027-the-suspend-audit-dial.md)).

## Consequences

- Easier: an incident leaves a record that reads like a change: declared, bounded, restored, reconciled.
- Harder: the break-glass identity, its credential and its audit are production additions the course does not build.
- Follow-up: the drill runs as a sev0 incident item, and the audit dossier is its deliverable.

## Where it is taught or enforced

The break-glass drill (after Act VI); `scripts/check-repo`, `scripts/ruleset show`; rule 2.5 (the incident is the work item).
