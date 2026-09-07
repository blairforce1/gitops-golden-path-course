# decisions/ - the platform's decision log

[Walkthrough index](https://github.com/blairforce1/gitops-golden-path-course) · [The GitOps rules](https://github.com/blairforce1/gitops-golden-path-course/blob/main/rules.md)

[The GitOps rules](https://github.com/blairforce1/gitops-golden-path-course/blob/main/rules.md) say what the platform obeys. This folder says **why**, and what was rejected: one record per decision, written when the decision was taken, immutable once accepted. Stage 00 seeds it into the config repo beside `scripts/`, because a platform's decision log belongs with the platform, and the reader inherits the log the rules came from rather than a rules page with no history. From then on it is yours: a new decision is a new record, a changed decision is a new record that supersedes the old one, and both land by PR like everything else.

## The format

Nygard's shape with one addition: Context, Decision, **Considered options** (one line each, why it lost), Consequences (easier, harder, follow-up; honest negatives required), and where the decision is taught or enforced (the rule, the stage, the script). A header block carries status, date, deciders and what the record supersedes. At most 120 lines; one decision per file. Copy [`0000-template.md`](0000-template.md), take the next number, and add a row below. No tooling generates this index; keep it by hand.

Status: `accepted` (binding), `proposed` (under discussion), `superseded` (the header names the successor). Only the status line of an accepted record changes.

## The records

| # | Decision | Backs |
|---|---|---|
| [0001](0001-flux-not-argo-cd.md) | Use Flux, not Argo CD | rule 1.1 |
| [0002](0002-protection-on-main-from-day-zero.md) | Protect `main` from day zero and route every change through a PR | rules 1.3, 2.4 |
| [0003](0003-merge-commit-only.md) | Merge commits only; the PR title and body become the commit | rules 1.2, 2.3 |
| [0004](0004-commit-convention-scope-is-blast-radius.md) | Conventional Commits with a domain vocabulary; the scope is the blast radius | rules 2.1, 2.2 |
| [0005](0005-every-change-cites-a-work-item.md) | Every change cites an open work item; merge is not verification | rule 2.5 |
| [0006](0006-branch-names-type-issue-slug.md) | Branch names are `<type>/<issue>/<slug>`; the branch is scaffolding | rule 2.4 |
| [0007](0007-one-resource-per-file-typed-folders.md) | One resource per file, `<name>.<kind>.yaml`, in typed folders | rules 3.1, 3.2, 3.3 |
| [0008](0008-yaml-style-is-the-tools-style.md) | YAML style is the tool's style, and the tool writes the file | rules 3.4, 3.5 |
| [0009](0009-identifier-alignment-one-string-seven-homes.md) | Identifier alignment: one string, seven homes | rule 3.6 |
| [0010](0010-one-authority-per-tool-kubectl-never-renders.md) | One authority per tool, and kubectl never renders | rule 4.1 |
| [0011](0011-filters-from-images-operators-installed.md) | Filters run from pinned images; operators install natively | rule 4.2 |
| [0012](0012-follow-the-authority-at-kubernetes-pace.md) | Follow the authority, at the pace Kubernetes sets | rule 4.3 |
| [0013](0013-clusters-class-cluster-layout-local-is-a-rung.md) | `clusters/<class>/<cluster>/`, and the local cluster is a first-class rung | rule 1.1; the vocabulary |
| [0014](0014-class-is-binary-policy-attaches-to-class.md) | Class is binary, and policy attaches to class, never to name | the vocabulary |
| [0015](0015-bindings-live-in-the-cluster-folder.md) | Bindings live in the cluster folder; folders encode identity, never schedule | the vocabulary |
| [0016](0016-release-channels-as-a-label-ascent-judged-where-members-exist.md) | Release channels are a label on the binding; ascent is judged where members exist | rule 5.13 |
| [0017](0017-automation-writes-only-at-the-entry-rung.md) | Automation writes only at its ladder's entry rung | rule 5.4 |
| [0018](0018-secrets-taxonomy-class-keys-roll-forward.md) | Secrets: encrypted in git with class keys, referenced when they cannot die, rolled forward | rule 5.10 |
| [0019](0019-apply-in-git-validate-at-gates-never-mutate-at-admission.md) | Standards are applied in git and validated at gates; admission never mutates | rule 5.6 |
| [0020](0020-gates-not-checks-ci-is-a-backstop.md) | Gates, not checks; CI is a backstop that never fires | rule 5.9 |
| [0021](0021-slo-gate-is-the-second-signature.md) | Promotion needs two signatures: convergence and a clean SLO window | rule 5.7 |
| [0022](0022-dora-from-artifacts-no-stopwatch.md) | DORA is computed from artifacts, production-scoped, one change is one unit | rule 5.8 |
| [0023](0023-change-freeze-is-a-calendar-in-git.md) | A change freeze is a calendar in git, enforced at merge; the override is a loud trailer | stage 27 |
| [0024](0024-codeowners-by-effective-blast-radius.md) | Code owners follow effective blast radius, paired with the rendered diff | rules 5.4, 5.5 |
| [0025](0025-a-private-repo-is-a-delay-not-a-control.md) | Assume the clone leaks: a private repo is a delay, not a control; tenant naming follows scale | rule 5.10 |
| [0026](0026-push-accelerates-poll-guarantees.md) | Push accelerates, poll guarantees, keep both; the interval is a trust dial | rule 5.1 |
| [0027](0027-the-suspend-audit-dial.md) | The suspend-audit dial: emergency brake or audit-total, chosen by one line | stage 07 |
| [0028](0028-infrastructure-names-operational-role.md) | `infrastructure/` names an operational role; controllers are workloads with lifecycles | rule 5.11 |
| [0029](0029-managed-first-disposable-infrastructure-in-place-patches.md) | Managed-first, disposable infrastructure, in-place for patches and minors | rules 5.11, 5.12 |
| [0030](0030-kubernetes-ladder-three-minors-kubectl-pins-dev.md) | The Kubernetes ladder spans three minors; kubectl pins to the dev class | rule 4.3 |
| [0031](0031-a-tenant-is-a-replica-an-environment-is-a-rung.md) | A tenant is a replica, an environment is a rung, one stamp per tenant | stages 22-24 |
| [0032](0032-ephemeral-pr-environment-is-an-ephemeral-tenant.md) | An ephemeral PR environment is an ephemeral tenant; teardown on close; the reaper is mandatory | stage 25 |
| [0033](0033-break-glass-declare-bypass-narrowly-prove-the-restore.md) | Break-glass: declare, bypass narrowly, prove the restore, reconcile by PR | the break-glass drill |
| [0034](0034-renovate-not-dependabot-for-the-config-repo.md) | Renovate, not Dependabot, for the config repo | rule 5.11 |
| [0035](0035-bicep-owns-the-substrate-aso-owns-application-resources.md) | Bicep owns the substrate; Azure Service Operator owns application-adjacent resources | stages 32-35 |
| [0036](0036-signed-oci-config-artifacts-are-the-release-destination.md) | Signed OCI config artifacts are the release destination | stage 30; the OCI quest |
| [0037](0037-variants-flags-and-migration-overlays-three-lifecycles.md) | Variants, feature flags and migration overlays: three lifecycles, three homes | stage 08 |
| [0038](0038-dr-is-rebuild-not-failover-region-b.md) | DR is rebuild, not failover; the drill is region B | rule 5.2; Act VIII checkpoint |
| [0039](0039-tags-immutable-once-created.md) | Tags are immutable once created: a tag ruleset from day zero | rule 1.3; stage 00 |
| [0040](0040-the-soak-is-declared-in-git-and-judged-from-git-dates.md) | The soak is declared in git and judged from git's dates | rule 5.7; stage 16 |
