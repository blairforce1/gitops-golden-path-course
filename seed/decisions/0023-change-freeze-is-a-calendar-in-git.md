# 0023. A change freeze is a calendar in git, enforced at merge; the override is a loud trailer

- **Status:** accepted
- **Date:** 2026-08-25
- **Deciders:** blairforce1, with Claude Code
- **Supersedes:** none

## Context

Customers ask for change freezes: no production change to their tenant over a quarter end, a launch, a holiday. The reflex is `flux suspend kustomization`. The CR's own API wording says suspend stops *subsequent kustomize executions*, which includes drift correction, so the freeze window becomes the only period in which the cluster stops repairing itself. It also never expires, blocks the emergency fix along with everything else, and is an imperative act on a cluster with no record of who or why. The real-world failure is not a freeze somebody violated but a freeze nobody lifted.

## Decision

The freeze lives in git: `freezes.yaml` holds scope (a path prefix), an inclusive UTC window, and a mandatory reason, ticket and contact. `freeze-gate` reads the calendar from `HEAD` at merge time and fails a PR whose changed paths fall inside an active window; it is a required check. Expiry is structural: the window lapses with no action. The override is deliberate: a `Freeze-override:` trailer citing the incident passes loudly and permanently, because a control that cannot be overridden gets bypassed by disabling the check, leaving neither the freeze nor the record. The merge-time gate is complete for production because prod has exactly one write path: automation writes only at the entry rung ([0017](0017-automation-writes-only-at-the-entry-rung.md)), so a check on merges to `main` catches everything that reaches prod.

## Considered options

- **`flux suspend`.** Stops drift correction, never expires, blocks the emergency fix, leaves no record.
- **A freeze label on the binding.** Still reconciled, still cluster-side state; the calendar answers "when" and a label cannot.
- **A check that cannot be overridden.** Bypassed by disabling the check under pressure.

## Consequences

- Easier: "what is frozen right now" is `freeze-gate --calendar`; a freeze is reviewed like any change and lifts itself.
- Harder: the risk relocates to someone weakening the entry-rung invariant to save a PR step; that is a commit under `clusters/` or the workflows, which owners protect ([0024](0024-codeowners-by-effective-blast-radius.md)).
- Follow-up: a customer freeze holds their wave once GA is partitioned ([0016](0016-release-channels-as-a-label-ascent-judged-where-members-exist.md)).

## Where it is taught or enforced

Stage 27; `scripts/freeze-gate`, `freezes.yaml`; the `Freeze-override:` trailer in rule 2.2.
