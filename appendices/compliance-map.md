# The compliance evidence map

[Walkthrough index](../README.md) · [The GitOps rules](../rules.md) · [Take it to production](take-it-to-production.md)

Audit evidence is a query, not a quarterly scramble. The platform already produces the change-management evidence an auditor asks for (authorisation, testing, deployment record, actor, rollback), because every one of those is a by-product of the loop: a PR merged under a ruleset, a required check, a commit status per stamp and cluster, a revision the cluster reports. This page maps each control to its mechanism, where the evidence lives, and the query that retrieves it. Each stage's "audit artifacts produced" section is the incremental view; this is the whole.

The `audit-evidence` skill answers a row on demand and writes the dossier; the exercise at the end is the full evidence trail for one change, in ten minutes.

## The map

| Control | Mechanism | Evidence lives in | Retrieve with | Introduced |
|---|---|---|---|---|
| Every production change is reviewed and merged, never pushed | ruleset on `main`: PR required, no bypass actors; owners on protected paths | the merge commits on `main`; the PR's reviews | `git log --first-parent`; `gh pr view <n> --json reviews,mergedBy`; `scripts/ruleset show` | stages 00, 21 |
| Every change traces to a work item, and no change cites finished work | `Refs:`/`Closes:` trailer; `issue-gate` on open and on merge | the merge commit body; the issue | `git log --basic-regexp --grep='^Refs: #'`; `gh issue view <n>` | stages 02, 04, 11 |
| Changes are tested before they can merge | required checks: rendered policy, style, the PR record | the PR's check rollup; workflow runs | `gh pr view <n> --json statusCheckRollup`; `gh run list --branch main` | stages 08, 11 |
| Deployment record: what ran on which cluster, when | a commit status per stamp per cluster; `lastAppliedRevision` | the forge's status API; the cluster | `gh api repos/{owner}/{repo}/commits/<sha>/statuses`; `kubectl get kustomization <stamp> -o jsonpath='{.status.lastAppliedRevision}'` | stages 04, 07 |
| Blast radius known before merge | the rendered diff comment; `path-gate`; `base-gate` refuses a base change that renders | the PR's comments | `gh pr view <n> --comments` | stages 12, 21 |
| Automation cannot reach production | the robot writes at the entry rung only; setter markers only in the dev overlay; no bypass on the ruleset | the robot's PRs; the ruleset | `gh pr list --search 'author:app/github-actions'`; `scripts/ruleset show` | stage 14 |
| Change freezes are honoured, and crossings are recorded | `freezes.yaml`; `freeze-gate` as a required check; the `Freeze-override:` trailer | git | `scripts/freeze-gate --calendar`; `git log --basic-regexp --grep='^Freeze-override: '` | stage 27 |
| Rollback is a reviewed change | `pr-revert`; merge commits only, so every revision stays reachable | git | `git log --basic-regexp --grep='^Revert '` | stages 04, 20 |
| Secrets are encrypted at rest and rotation revokes | SOPS and age with class-scoped keys; `rotate` commits; `revert-gate` | `.sops.yaml`; `secrets/` history | `git log -- '*/secrets/*'`; `find . -path '*/secrets/*' -name '*.yaml'` | stages 06, 17, 20 |
| Access is reviewed | recipients in `.sops.yaml`; `CODEOWNERS`; RBAC manifests; the forge's collaborator list | files in git; the forge | `git log -- .sops.yaml CODEOWNERS`; `gh api repos/{owner}/{repo}/collaborators` | stages 18, 21, 23 |
| Workload standards are enforced, exceptions expire | the baseline component; `policy-gate`; PSA labels; admission validation with exceptions carrying an expiry | `policy/`; CI; the cluster | `scripts/policy-gate`; `kubectl get policyexceptions -A` (ships with stage 30) | stages 08, 23, 30 |
| Dependencies are patched on a cadence | Renovate PRs that ride the ladder; the parity gates | PRs; `clusters/versions.yaml` history | `gh pr list --search 'author:app/renovate'`; `git log -- clusters/versions.yaml` | stages 13, 16 |
| Availability is measured and gates promotion | the SLO rule on the hub; `slo-gate` as the second signature | the hub's metric store; git | `scripts/slo-gate <cluster>`; `scripts/slo-watch` | stage 09 |
| Incidents are detected and attributed from artifacts | commit statuses; `gotk_resource_info`; `detect-time`; `evidence` | the forge; the metric store | `scripts/detect-time`; `scripts/evidence <sha>` | Act III checkpoint |
| Recovery from nothing is rehearsed | `act-N-drill`; rebuild-region | the checkpoint records | `scripts/act-N-drill` | every act checkpoint |
| Delivery performance is measured, not claimed | `dora` from the hub | the metric store; git | `scripts/dora --window 30d` | stage 10 |
| Supply chain integrity | keyless signing, SBOM attestations, `verifyImages`, `OCIRepository.spec.verify` | the registry; the cluster | admission refusals in events (ships with stage 30) | stage 30 |

Two rows are gaps the course names rather than fills: **actor identity** (git records the author's name and the forge records the merger; a signed-commit requirement on the ruleset and the Kubernetes API audit log are the production additions) and **retention** (statuses live with the forge, metrics with the store; decide what is kept and for how long).

## The exercise: one change, end to end, ten minutes

Pick any commit on `main` that reached prod. Produce, from artifacts alone: who authored and who merged it, the work item it advanced and whether it was open at merge, the checks that gated it and the reviews on it, the rendered blast radius, every status the fleet posted about it in order, what each cluster applied and when, and whether a freeze was in force. Time it from the timestamps, not a clock. The `audit-evidence` skill does this as a dossier; the Act III checkpoint's drill 4 is the worked example.
