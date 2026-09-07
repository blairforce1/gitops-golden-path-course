# What the rules buy

[Walkthrough index](../README.md) · [The GitOps rules](../rules.md) · [The git policy](git-policy.md) · [The compliance evidence map](compliance-map.md)

[The rules page](../rules.md) says what the platform obeys and why, one rule at a time. [The decision records](../seed/decisions/README.md) say what each rule rejected. This page reads the same material the other way round: the things the platform can do, and the rules that build each one. Every entry is something you can point at, a script, a check, a drill or a query, and the rules under it say what part each plays. The second half lists what the rules get for free from git, GitHub and the tools underneath, because most of the machinery is borrowed, not built. The last section is the order the rules pay off in.

## The features, and the rules that build them

### Measurement

**The four DORA numbers** (`dora`, [stage 10](../act-3/stage-10.md)). Deployment frequency, lead time, change failure rate and time to restore, from the hub.

- 5.8: the numbers come from metric samples and commit timestamps, never a clock.
- 5.7 and [stage 09](../act-3/stage-09.md): the hub with `gotk_resource_info` and `kube_deployment_metadata_generation`; before it the script says SKIP.
- 5.5: the unit is the change, so one commit reaching fifty tenants is one deployment.
- 3.6: stamps named `app-<env>` and namespaces `<tenant>-<env>`, which is how a workload is booked against its stamp.

**Where the lead time goes** (`dora --stages`, [stage 10](../act-3/stage-10.md)). The headline starts at the promotion; this traces it back to the dev pin and the PR.

- 2.1: the version token in `pin(app-dev): app <V>` and `promote(app-prod): app <V>` is the join key.
- 1.2: the production revision is a merge commit, so its sha finds the PR and the PR's opened, merged and review timestamps.
- 2.4: every promotion went through a PR, so every change has a review interval to read.

**Lead time per rung** (`rung-time`, [Act II checkpoint](../act-2/act-checkpoint.md)). From the commit that asked to the status that says the rung converged.

- 5.1: a commit status per stamp per cluster, each with a creation time.
- 5.8: the answer is the difference of two recorded timestamps, and the script waits for the cluster to report the revision applied before it reads the status.
- 1.2: `commit-by-subject` walks first-parent history, so a subject resolves to the merge that wears the statuses.
- 3.6: the status context `kustomization/<stamp>/<cluster>` is selected by name.
- 2.1, optional: a subject can name the commit; a sha works too.

**Detection time** (`detect-time`, [Act III checkpoint](../act-3/act-checkpoint.md), [stage 22](../act-6/stage-22.md)). From the break to the hub knowing.

- 5.8: the state timeline is metric samples of the stamp's Ready condition.
- 5.7 and [stage 09](../act-3/stage-09.md): the hub.
- 3.6: the stamp name selects the series.
- 2.1, optional: `break(<stamp>): ` is the default argument, so a drill needs no sha; an incident passes the sha from the stamp's `status.history`.

### Record and audit

**Per-cluster release notes and the promotion gap** (`release-notes`, [stage 26](../act-6/stage-26.md)). What a cluster is running since the last note, and what dev has that prod does not.

- 2.3 and Flux's `lastAppliedRevision`: the range is the cluster's own statement, so there is no tag ceremony and no changelog to keep honest.
- 1.2: `--first-parent` gives the per-PR view, and the merge subject is the note.
- 2.1: git-cliff groups by type, so "Promoted to this rung" and "Deliberate breaks" are sections rather than a reading exercise.
- 1.1 and 3.2: the input set is the stamp's path plus `apps/base` and `apps/components`, so a base edit shows in every cluster's notes.
- 5.5: "N of M commits touch this cluster's inputs" is the reconcile-is-not-change line.
- 4.2: git-cliff runs as a pinned container.

**Audit by query** ([stage 26](../act-6/stage-26.md) step 5, [the compliance evidence map](compliance-map.md), the `audit-evidence` skill). Every policy change this quarter, every access change to prod, what issue N changed, every freeze crossing.

- 2.1: the type is the first token of the subject, so `--grep='^policy'` is the whole query.
- 2.5 and 2.2: `Refs:` in the body, so `--grep='^Refs: #9'` answers "what did this work change".
- 1.2: `PR_BODY` carries the trailer into the merge commit, where `git log` can see it after the PR page is gone.
- 3.2: `-- '*/secrets/*'` scopes `^rotate` to the register.
- 1.3: every one of those commits is a merged PR, which is the first control an auditor asks about.

**The evidence dossier for one commit** (`evidence`, [Act II](../act-2/act-checkpoint.md) and [Act III](../act-3/act-checkpoint.md) checkpoints). Who changed what, what the fleet said in order, what each cluster applied, and the blast radius, from artifacts.

- 5.1: the status sequence on the merge commit is the fleet's own account.
- 3.6: a red context splits into stamp and cluster, so the blast radius needs no lookup table.
- 1.2: "who touched this path afterwards" walks first-parent history, the merges that landed rather than the branch commits under them.
- 5.5: the paths the commit touched decide who was affected.
- 5.8: what the cluster applied is read from the cluster, and a green is never taken for either.

**Work-item traceability** (`issue-gate`, `pr-record`, [stage 04](../act-1/stage-04.md) and [stage 11](../act-4/stage-11.md)). No change without an open work item, robots included.

- 2.5: the `Refs:`/`Closes:` trailer, and the rule that it names an open issue, not a PR.
- 2.2: the body is where the trailer lives, and the template puts it in front of every author.
- 2.4: `pr-open` cross-checks the branch's issue segment against the trailer.
- 1.3: `pr-record` is a required check, so a change citing nothing, or citing finished work, is a refused merge.
- 1.2: the trailer reaches `main` in the merge commit.

**Day-zero readback** (`check-repo`, [stage 00](../act-1/stage-00.md)). Is the repository still configured the way day zero said.

- 1.2: the merge policy, read back from the API.
- 1.3: both rulesets, their rules and their bypass list.
- 1.4 and 2.2: the seeded files.
- 2.5: the backlog, with issue 1 being stage 00.

### Control

**The promotion ladder with two signatures** ([stage 07](../act-2/stage-07.md), [stage 09](../act-3/stage-09.md), `slo-gate`, the `promote` skill). A version climbs platform, dev, prod on evidence.

- 5.4: the ladder is folders and PRs; `pin` enters and `promote` climbs; a base change rides as patches and absorbs on an empty rendered diff.
- 1.1: environment equals folder, so promotion is a diff.
- 5.7: convergence is one signature, a clean SLO window on the rung below is the other, and no traffic is a FAIL.
- 3.6: `slo-gate <cluster>` finds the stamp by name.
- 4.3: Kubernetes versions and chart bumps climb the same rungs.
- 2.1: the promotion is a `promote(app-prod):` commit the queries can find.

**Robots that obey the same rules** ([stage 13](../act-4/stage-13.md) and [stage 14](../act-4/stage-14.md)). Renovate at the platform rung, Flux image automation at dev, both by PR.

- 1.3: no bypass actor; `allow_auto_merge` lets the robot merge on the same required check a human waits for.
- 5.4 and [record 0017](../seed/decisions/0017-automation-writes-only-at-the-entry-rung.md): automation writes only at its ladder's entry rung.
- 2.1: the robot's title is typed through configuration (Renovate's `:semanticCommitTypeAll(pin)`, the image automation's `--commit-template`).
- 2.5: a standing `automation` work item, cited from `prBodyNotes` or the workflow's body.
- 2.4: the robot's standing branch is the named exception, reused rather than made per change.

**Rendered blast radius on every PR** ([stage 12](../act-4/stage-12.md)). A sticky comment showing what each cluster will receive.

- 1.1: the roots are every `path:` a Flux Kustomization under `clusters/` points at, so the set follows the fleet.
- 4.1: CI installs kustomize from the same pin, so the diff is what the controller will do.
- 2.4: the PR is where the comment lands, and the merge is the gate.
- 5.4: a base change shows in every root at once, which is the point.
- 5.10: sops files render as ciphertext, present in the blast radius and unreadable in the log.

**Owners and protected paths** ([stage 21](../act-5/stage-21.md), `path-gate`, `CODEOWNERS`). Off-rung paths need their owners.

- 1.1 and 3.2: the rows are folders, so the layout is the map.
- 5.4: `base/`, `clusters/`, `infrastructure/`, the access lists and the gates are the paths the ladder cannot gate.
- 1.3: `ruleset require-owners` turns a review request into a requirement.
- 5.5: a path touched is the blast radius, and the rendered diff pairs with it ([record 0024](../seed/decisions/0024-codeowners-by-effective-blast-radius.md)).
- 5.4, third corollary: `base-gate` refuses a base change unless every consumed root renders byte-identical and the title says `refactor`; base is sacred as a required check.

**Change freeze as a merge-time control** ([stage 27](../act-6/stage-27.md), `freeze-gate`). A calendar in git, enforced where merges are decided.

- 5.9: a gate over the working tree, so a paste block, CI and the hook agree.
- 1.3: a required check, so the freeze refuses the merge rather than the reconcile.
- 2.2: `Freeze-override:` is a trailer in the body, deliberately possible and deliberately loud.

**Policy applied in git and validated at gates** ([stage 08](../act-3/stage-08.md), `policy-gate`). The workload baseline as a component, judged on rendered output.

- 5.6: applied in git, validated at every gate, never mutated at admission.
- 5.9: `policy-gate` is a pure function over the tree.
- 4.1 and 4.2: kustomize from the pin renders, conftest from a pinned image judges.
- 1.3: the rendered-policy job is a required check.

### Recovery

**Revert by PR, safe for secrets** (`pr-revert`, [stage 04](../act-1/stage-04.md); `revert-gate`, [stage 20](../act-5/stage-20.md)). Undo a merged PR as a reviewed change, and be refused when a revert would not restore.

- 1.2: a merge commit has two parents, so `git revert -m 1` undoes the whole PR.
- 2.1, through the commit convention's rules 6 and 9: git's `Revert "<subject>"` is kept, and `!` with `Roll-forward:` says a revert will not save you.
- 2.5: the revert inherits the reverted change's work item.
- 3.2 and 5.10: secret material is found by `*/secrets/*`, and for secrets the answer is roll forward.
- 2.4: the revert is a PR on a `revert/<n>/<sha>` branch that never merges itself.

**Rebuild from nothing** (`act-N-drill`, every act checkpoint). The state at the end of an act, from git and a handful of root keys.

- 5.2: the cluster is derivable from git, and each act defines its "nothing".
- 5.3: the IOUs are the honest residue, and an era-aware checkpoint reports which is outstanding.
- 1.1: nothing but platform config in the repo, so the rebuild has nothing to skip.
- 1.3: tags are immutable, so the baseline a drill rebuilds cannot move.
- 5.8: the rebuild time is read from artifacts, and history is not manufactured.

**Alert to file with no lookup table** ([stage 09](../act-3/stage-09.md), the `fleet-triage` skill). From a notification to the file to open.

- 3.6: one identifier in seven homes, the alert payload included.
- 3.1: the resource's name is its filename.
- 3.2: the folder says what kind of thing it is.
- 5.1: the alert carries the identifier because the loop posts it.

**Secrets with a ladder** ([stage 06](../act-2/stage-06.md), Act V). Encrypted in git with class keys, rotated by revoking, referenced when they cannot die.

- 5.10: the taxonomy, the ladder, roll forward, assume the clone leaks.
- 3.2: `secrets/` is the countable debt register.
- 2.1: `rotate` is the value and `access` is the set, so both are queryable.
- 4.1: the sops and age the CLI encrypts with are what the controller decrypts with.

### Hygiene and parity

**Style and layout enforced on the laptop** ([stage 11](../act-4/stage-11.md), `layout-gate`, `style-gate`, the hooks). A red CI run on a mechanical check is a process failure.

- 3.1 and 3.2: `layout-gate`, one resource per file in a typed folder under its own name.
- 3.4: kustofmt is the format authority and yamllint the backstop.
- 3.5: the tool wrote most of the files, so most of the tree was already clean.
- 4.1: kustofmt is pinned to the kustomize pin's kyaml.
- 4.2: yamllint runs from a pinned image.
- 5.9: gates first, hooks second, CI as the backstop that never fires.

**Render parity, laptop to CI to controller** (`check` and the parity gates, [stage 00](../act-1/stage-00.md), [stage 05](../act-2/stage-05.md), [stage 06](../act-2/stage-06.md), [stage 11](../act-4/stage-11.md)). What you render is what the cluster renders.

- 4.1: one authority per tool, and kubectl never renders.
- 4.3: pins follow their authority at Kubernetes' pace, and drift is checked on a schedule.
- 4.2: filters from images, operators installed from the pin.
- 3.5: the tool writes the file, so the file is in the style the renderer emits.

## What the rules get for free

Each rule is small because something underneath already does most of the work. The pattern is the same every time: adopt the platform's own convention on day zero, and every later control is a query or a setting rather than a tool.

### From git

| Machinery | Rule | What it opens up |
|---|---|---|
| A merge commit has two parents | 1.2, 2.3 | `git log --first-parent` is the per-PR view and the full log the per-commit view ([stage 26](../act-6/stage-26.md)); `git revert -m 1` undoes a whole PR (`pr-revert`); `commit-by-subject` walks first parents, so a subject resolves to the merge that wears the statuses and never the branch commit that shares its title |
| The subject is a searchable field (`--grep`, `--basic-regexp`) | 2.1 | every grammar query in the stages and the audit (`^promote(app-prod):`, `^policy`, `^access`); git-cliff already speaks Conventional Commits, so the grouped release notes are a short `cliff.toml`, not a parser |
| Trailers (`Key: value` lines at the end of a body, git's own convention) | 2.2, 2.5, 5.10, stage 27 | one carrier for every gate: `Refs:` and `Closes:` (`issue-gate`), `Roll-forward:` (`revert-gate`), `Freeze-override:` (`freeze-gate`); `git log --grep='^Refs: #9'` answers "what did this work change" |
| `git revert` composes `Revert "<subject>"` | 2.1 | a durable link from the undo to the change with no tooling; `revert-gate` finds the original by that quoted subject and reads its `!` |
| Commit timestamps and `--since` | 5.8 | the start of every lead time (`rung-time`, `dora`) and the window of every measurement, with no clock of the author's |
| Path-scoped history (`git log -- <paths>`, `git diff-tree --name-only`) | 3.2, 5.5 | `release-notes`' "N of M commits touch this cluster's inputs", `evidence`'s blast-radius paths, `git log -- '*/secrets/*'`, `revert-gate`'s secrets scan: the folder convention is the query |
| `git merge-base --is-ancestor` | 5.8 | "the cluster already moved past it" in `rung-time`; "this commit is in what the cluster runs" in `evidence`, true after a revert too |
| Tags as save points | 1.3, 5.2 | `stage-NN` and `act-N` are the ranges every drill, DORA window and change record reads; the tag ruleset makes them immutable |
| Per-clone config (`commit.template`, `pull.rebase false`, `core.hooksPath`) | 1.2, 5.9 | the vocabulary in the editor, no accidental rebase, hooks in twenty lines of bash with no framework ([record 0020](../seed/decisions/0020-gates-not-checks-ci-is-a-backstop.md)) |
| `.gitattributes` with `eol=lf` | 1.4 | hygiene the repo enforces instead of a README asking for it |
| `git ls-files` | 5.9 | every gate judges what is tracked, so a scratch file cannot make a gate lie |

### From GitHub

| Machinery | Rule | What it opens up |
|---|---|---|
| `merge_commit_title=PR_TITLE`, `merge_commit_message=PR_BODY` | 1.2, 2.2, 2.5 | the PR title and body become the commit, so the grammar and the trailers reach `main` with no bot, and `pr-record`'s lint of a title is a lint of the future commit |
| `delete_branch_on_merge` | 2.4 | the branch is scaffolding by setting, not by discipline; the commits stay reachable through the merge's second parent |
| `allow_auto_merge` | 1.3, stage 14 | the robot merges on the same required check a human waits for; no bypass actor, and the merge is attributed to the robot |
| Rulesets (pull request required, force-push and deletion blocked, required checks, required owners, no bypass actors) | 1.3, 5.9, stages 08, 11, 21, 27 | every gate becomes mandatory by one `ruleset require-check`; `ruleset show` reads the policy back; the second ruleset, on tags, blocks update and deletion while leaving creation open |
| The commit status API (`/statuses`) | 5.1, 3.6, 5.8 | Flux posts one status per stamp per cluster on the merge commit, so the commit wears the result; the status's creation time is `rung-time`'s end; the context string carries the stamp and the cluster, so `evidence` derives the blast radius from a red with no table; `/statuses` keeps the sequence where `/status` keeps only the latest, which is how a green whose description is not "reconciliation succeeded" is caught |
| `pull_request` events, `edited` included; the workflow taken from the merge ref | 2.2, stage 12 | `pr-record` re-judges a title or body edit; the rendered-diff workflow runs on its own PR, so the first comment is that PR's |
| `GITHUB_TOKEN` issued per run, with `permissions:` | stages 11, 14 | the repository opens the robot's PRs itself, once `can_approve_pull_request_reviews` is on (GitHub ships it off); nothing in the cluster holds a credential that can; `pr-record` reads issues with a scoped token. A merge by that token raises no workflow on `main` and no automatic branch deletion, so the robot's evidence is the branch head's checks and the fleet's statuses |
| Issues and milestones | 2.5 | the backlog is an issue per stage and a milestone per act, seeded before the first PR; `issue-gate` resolves every number through the API (exists, is an issue, is open); auto-close is used only where the PR is the whole item ([record 0005](../seed/decisions/0005-every-change-cites-a-work-item.md)) |
| `.github/pull_request_template.md` | 2.2 | the record's headings in front of every browser author, for the cost of a short file |
| `CODEOWNERS` | 5.4, stage 21 | review requested by path for free, and required through the ruleset; last match wins, so the specific rules follow the catch-all |
| PR comments with a marker line | stage 12 | one sticky rendered-diff comment, found by its marker and edited on every push |
| `gh pr list --json createdAt,mergedAt,mergeCommit,reviews` | 5.8 | review time to the second, joined to the production change by the merge commit sha (`dora --stages`) |
| Renovate's semantic-commit presets; the image automation's `--commit-template`; `prBodyNotes` | 2.1, 2.5, stages 13, 14 | the robots speak the grammar and cite the standing work item through configuration, so `pr-record` judges them like a human |
| `gh api` with `--jq` | 1.2, 1.3 | `check-repo` reads day zero back; `ruleset` amends the policy; `evidence` reads the status sequence; no SDK anywhere |

### The same pattern in the tools underneath

Beyond git and GitHub, the Part 3 and Part 4 rules and the measurement scripts lean on tool behaviour the same way.

| Machinery | Rule | What it opens up |
|---|---|---|
| kustomize's emitter: alphabetical, indentless sequences, block style | 3.3, 3.4, 3.5 | ordering and style are free for every tool-written file; `kustomize build` was always a formatter for resources, and kustofmt is the same emitter for every other file |
| `flux create <kind> --export` | 3.5 | stamps, Alerts, Providers and sources authored by the tool, and the flags are the day-2 vocabulary |
| `lastAppliedRevision` (`main@sha1:<sha>`) | 2.3, stage 26 | the release-notes range is the cluster's own statement, so there is no tag ceremony and no changelog to keep honest; `app-dev@<context>` as the "since" is the promotion gap |
| `commitStatusExpr` (a CEL expression on the Provider) | 3.6 | the status suffix is declared per cluster instead of the Provider's UID, so the status thread survives a Provider recreation |
| `gotk_resource_info{revision,ready}` and `kube_deployment_metadata_generation` on the hub | 5.7, 5.8 | the four DORA numbers and `detect-time` are metric samples, and the two series together separate a reconcile from a change |
| sops encrypts values only (`encrypted_regex`) | 3.1, 5.10, stage 12 | `kind` and `metadata.name` stay readable, so `layout-gate` judges an encrypted file and `kustomize build` renders ciphertext, which puts a secret change in the blast radius with no key near a runner |
| `dependsOn` and `wait: true` on a stamp | 5.1 | a green means converged, not applied, so the status is a verdict rather than a receipt |

## The order they pay off in

Three sets of rules only work together.

- **The record: 1.2 with 2.1 with 2.2.** The title is the commit, the merge keeps it, the body carries the trailers. Alone, 1.2 still buys the per-PR view, the PR pointer and reachable revisions, so it is worth having by itself. Alone, 2.1 is rewritten at the first squash merge. Alone, 2.2 is a prose body.
- **The control: 1.3 with 2.4 with 2.5, enforced from stage 11.** The PR is mandatory, the record is complete, the work item is open. Alone, 1.3 makes the PR mandatory and nothing else. Alone, 2.5 is a convention nobody checks.
- **The chain: 3.6 with 3.2 with 5.1.** An alert names a stamp, the stamp names a folder, the folder holds the file. Alone, 3.6 is a naming preference.

And the tiers, cumulative, in the order the course adopts them. Each tier names what it buys, which is the list above read as a ladder.

| Tier | Rules | Buys |
|---|---|---|
| Flux runs | 1.1, 1.4, 4.1 for kustomize and flux | a cluster derivable from git; renders that agree with the controller |
| The record | 1.2, 1.3, 2.4 as PR-only | the per-PR view, revert by PR, "reviewed and merged", and the four DORA numbers once the hub exists |
| The grammar | 2.1, 2.2, 2.5 | where the lead time goes, grouped release notes, the audit queries, robots constrained |
| The fleet | 3.6, 3.1 and 3.2 with `layout-gate`, 5.7, 5.8, 5.9 with the hooks | the evidence dossier, the second signature, `revert-gate`, mechanical failures caught on the laptop |
| The polish | 3.3, 3.4, 3.5, 4.2, 4.3's ladder, 2.4's branch shape, the tag ruleset | clean diffs, a version ladder, immutable baselines |
