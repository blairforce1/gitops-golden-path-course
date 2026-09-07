# Take it to production - what the course leaves you with

[Walkthrough index](../README.md) · [The GitOps rules](../rules.md) · [The compliance evidence map](compliance-map.md)

The config repo you build is not a practice copy of a platform. It is the platform: the gates, the drills, the evidence scripts and the operating skills were seeded into it at stage 00 because a real repo keeps them, and every stage after that is a change you would make on a fleet. This page says which parts are yours to keep, what each one assumes about the course's laptop fleet, and what a production fleet needs that the course does not build.

## What you keep

Everything stage 00 seeds and everything the stages create in the config repo. The "assumes" column names the course-specific assumption to remove; the last column says whether the artefact ships in a template repo built from this course.

| Artefact | Job | Arrives at | Assumes | For a real fleet | Template |
|---|---|---|---|---|---|
| `scripts/pr-open`, `scripts/pr-revert` | branch, commit, push and open a PR from staged changes; revert a merged PR by PR; neither merges | stage 04 | `gh` authenticated to the forge; issue numbers as work items | swap `issue-gate`'s resolver for your ticket system's keys | yes |
| `scripts/ruleset`, `scripts/check-repo` | amend the `main` ruleset (never replace it); read day zero back as PASS/FAIL | stage 00 | GitHub rulesets (a paid plan on a private repo) | set approvals to 1 or more; add your required checks to `check-repo` | yes |
| `scripts/issue-gate`, `scripts/commit-gate` | the work-item trailer resolves to an open issue; the commit grammar as a verdict, four ways | stages 04, 11 | the scope registry in `commit-gate` | extend the scope registry as stamps and clusters are added; drop `--docs` (course-only mode) | yes |
| `scripts/style-gate`, `scripts/style-fix` | kustofmt then yamllint; rewrite in place | stage 11 | the kustofmt pin in `clusters/versions.yaml`, yamllint's pinned image; `.yamllint.yaml` at the root | nothing | yes |
| `scripts/policy-gate` | render every overlay and judge it against `policy/` with pinned conftest | stage 08 | overlays under `apps/overlays/` | add entry points as the tree grows | yes |
| `scripts/path-gate`, `CODEOWNERS` | name what protected paths a change touches and why; owners by blast radius | stage 21 | the course's path list | your paths, your teams (never personal emails) | yes |
| `scripts/revert-gate` | refuse a revert that carries credentials backwards | stage 20 | `secrets/` folders by convention | nothing | yes |
| `scripts/freeze-gate`, `freezes.yaml` | a change freeze as a calendar in git, enforced at merge | stage 27 | none | wire it as a required check | yes |
| `scripts/soak-gate`, `scripts/check-ladder-due`, `soak.yaml` | the soak per ascent as two numbers in git: `min` judged at push and at the PR, `max` reported by `check` with a work item per due ascent | stage 16 | the course's short durations, minutes to days; `check` at stage starts as the schedule | raise `min` (days for an image, a week or more for a chart or a minor) and tighten `max`; run `check-ladder-due --items` on a daily schedule and assign the standing item to the platform owner (stage 27 wires it) | yes |
| `scripts/slo-gate`, `scripts/slo-watch` | the second signature for promotion; SLIs over time | stage 09 | the hub reached by `kubectl port-forward`; the course's SLO rule names | point at your Prometheus; keep the rule names or edit both | yes |
| `scripts/rung-time`, `scripts/detect-time` | lead time per rung and detection time, from artifacts | Act II and III checkpoints | `kind-ggp-` contexts; `break(<stamp>): ` subjects | the context prefix is an environment variable; keep the `break` type for game days | `rung-time` yes; `detect-time` course-leaning |
| `scripts/evidence` | the auditor's dossier for one commit | Act III checkpoint | `EVIDENCE_CLUSTER_PREFIX` (default `kind-ggp-`) | set the prefix | yes |
| `scripts/release-notes` | per-cluster notes from `lastAppliedRevision`, grouped by the commit grammar | stage 26 | pinned git-cliff image | nothing | yes |
| `scripts/dora` | the four numbers, production scope, from the hub | stage 10 | the hub's metric names; retention long enough for the window | point at your Prometheus | yes |
| `scripts/cluster-sync` | the cluster half of bootstrap: install, deploy key, sync | stage 03 | a kube context; a deploy key on the forge | on a managed cluster, the extension replaces it (Act VIII) | yes |
| `scripts/check` and `check-*-parity`, `check-version-ladder` | every tool pinned to its one authority; the Kubernetes ladder | stages 00, 07 | AKS as the flux authority | change the authority if your cloud differs; keep the graph walk | yes |
| `env.sh` | owner, repos and image derived at run time from `gh` and the remote | stage 00 | GitHub | nothing | yes |
| `.gitattributes`, `.gitmessage`, `.github/pull_request_template.md` | LF everywhere; the vocabulary in your editor; the record's headings | stage 00 | none | nothing | yes |
| `hooks/`, `.yamllint.yaml` | pre-commit and pre-push run the gates; the style convention as one file | stage 11 | `git config core.hooksPath hooks/` per clone | nothing | yes |
| `policy/` | conftest policies over rendered output | stage 08 | none | your standards | yes |
| `.claude/skills/audit-evidence` | an audit dossier from artifacts, on demand | stage 00 | the scripts above | nothing | yes |
| `decisions/` | the decision log: why each rule exists, what it rejected | stage 00 | none | supersede what you decide differently, by record | yes |
| `clusters/versions.yaml` | the version ladder, one pin per class | stage 07 | three kind clusters | your clusters; on AKS the pins map to upgrade channels | yes, empty |

## What is deliberately course-only

- `scripts/checkpoint-NN` and `scripts/act-N-drill`: they judge the course's fleet at the course's stages. Keep them as a regression harness if the shape stays close; a real fleet writes its own.
- `scripts/cluster-up`, `scripts/cluster-down`, `scripts/refresh-hub-address`: kind and podman lifecycle, plus the fallback for environments where the hub's container name doesn't resolve and a pinned IP has to chase the node container.
- `tools/` in the course repo (`docs-gate`, `seed-backlog`, `start-quest`): they hold the course's own text honest and seed its backlog. A production team cites a ticket system's keys.
- Azurite and the demo app: props. Their stand-in is your storage and your workloads.
- The seeded backlog: the numbers are literal because every reader's repo is fresh. Your work items come from wherever your work items live, and `issue-gate` is the seam.

## What production needs that the course does not build

- **A break-glass identity** with a post-hoc review issue opened on every use. The drill rehearses the process; the identity, its credential and its audit are yours.
- **The reaper** for ephemeral environments: a scheduled job that removes entries past their TTL or whose PR closed, because the action that creates them will someday fail to fire.
- **Key escrow**: a home for each class's root key that outlives a laptop (a team vault), named before the first rebuild asks for it.
- **Actor identity as evidence**: signed commits required by the ruleset, and the Kubernetes API audit log enabled before anyone needs it. The course records who merged (the forge says) and who authored (git says); an auditor will ask for the signature.
- **Approvals of one or more**, which the course cannot demonstrate with one operator.
- **Alert routing to a person**: the course puts outcomes on commit statuses and a dashboard; production pages someone, with identifiers in the payload.
- **Retention**: commit statuses live with the forge, metrics live as long as the store keeps them, and `dora` warns when a window outruns retention. Decide what is kept and for how long.
- **Multiwindow burn-rate alerts** on the SLO; the course ships one fast-burn rule.

Read [the compliance evidence map](compliance-map.md) for how the controls above are evidenced, and [the GitOps rules](../rules.md) for why each part exists.
