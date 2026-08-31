# 0027. The suspend-audit dial: one line chooses between an emergency brake and an audit-total posture

- **Status:** accepted
- **Date:** 2026-08-08
- **Deciders:** blairforce1, with Claude Code
- **Supersedes:** none

## Context

`flux suspend kustomization` sets `spec.suspend: true` on the CR. The CR records *that* it is suspended, never who or when. Server-side apply field ownership means the parent Kustomization only corrects drift in fields git declares; a stamp manifest that omits `spec.suspend` leaves the CLI's patch owning the field indefinitely, so a suspend persists until an explicit resume. Who and when exist only in the Kubernetes API audit log, which has to be enabled beforehand; `managedFields` shows the manager and the time, not the human.

## Decision

The posture is chosen per stamp by one line, and the choice is stated. Omit `spec.suspend` from git: a CLI suspend is a durable emergency brake, audit-poor, and the lingering-suspend metric alert is the primary safety net. Declare `suspend: false` in git: git owns the field, a CLI suspend is declared-field drift that the parent's force-apply reverts at the next reconcile, so a durable suspend can only happen by PR, audit-total, emergency brake disabled. The default posture is the first, with the alert; a class or tenant that needs the second declares it. `suspend` is two operations wearing one name (`ImageUpdateAutomation` stops new versions arriving; `Kustomization` stops converging), and neither is a freeze ([0023](0023-change-freeze-is-a-calendar-in-git.md)).

## Considered options

- **Always declare `suspend: false`.** No emergency brake at 2am.
- **Never declare it.** Suspends calcify and nobody knows who set them.
- **Wrap the CLI in a script that records the actor.** Records only the callers who used the wrapper.

## Consequences

- Easier: the trade is explicit and reviewable, per stamp; the lingering-suspend alert makes the brake's cost visible.
- Harder: the API audit log has to be on before anyone needs it; on a laptop fleet that is an apiserver flag, on a managed cluster a diagnostic setting.
- Follow-up: suspend-by-label halts a whole release channel's fast tier ([0016](0016-release-channels-as-a-label-ascent-judged-where-members-exist.md)).

## Where it is taught or enforced

Stage 07 (the dial stated as each binding lands), stage 09 (the lingering-suspend alert).
