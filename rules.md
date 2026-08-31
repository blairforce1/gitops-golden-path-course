# The GitOps Golden Rules - read before stage 00

[Walkthrough index](README.md)

There are many defensible ways to run GitOps, and this page does not claim to have found the only one. It is one worked example, and most of its rules were learned the painful way. One of the hardest parts of working with Kubernetes is simply *choosing*: an approach, a tool, a naming scheme, out of a dozen plausible candidates each. Rather than spend hours deciding, adopt these rules as given, feel what they buy you over the course, and then make an educated decision when you do GitOps for real. Several of them exist purely to shrink the option space on purpose: one YAML style, one renderer, one naming shape. A smaller surface is easier to build tooling against, keeps diffs readable, and lets the conventions reinforce themselves by side-stepping tool quirks (an inline patch, for example, can come out flow-styled; a patch file never does).

Everything in this course rests on a small number of disciplines, and most of them have to be adopted **before the first commit**. A commit convention retrofitted at stage 07 is a migration, a merge policy set after the first PR has already rewritten one subject, a file-naming rule adopted at stage 05 leaves stages 02–04 as exceptions forever. So they are collected here, once, each in the same shape: **the rule**, **why** it exists (usually a specific failure it was written against), **how** it is applied and enforced, and **where** the course teaches it. Stages reference this page rather than re-arguing it; when a stage seems to be doing something odd, the reason is almost always here.

Two kinds of thing share this page, and it helps to know which you are reading. **Repository rules** (parts 1–4) are mechanical: naming, layout, configuration, tooling. A linter can check these, and mostly does. **Operating rules** (part 5) are the claims the platform is built to make true: *the cluster is derivable from git*, *converged is not working*, *for secrets, roll forward*, each one taught by a stage that demonstrates it and a drill that measures it. The course has conventions of its own, too: how a stage is shaped, what the text never names, the idioms of its paste blocks. They are not GitOps rules, and live on [their own page](using-the-course.md).

The quick reference at the end lists every rule on one line with what enforces it and the decision record behind it; the records, with the alternatives each rule rejected, are in [decisions/](seed/decisions/README.md), and stage 00 seeds them into your config repo beside the scripts.

---

## Vocabulary

The course coins a few terms where Kubernetes' own names collide or under-describe. This table is the canonical mapping; every page re-states it at a term's first use ([using the course §3](using-the-course.md#3-how-the-text-is-written)).

| Term | The mechanism it names | Why not the mechanism's name |
|---|---|---|
| **stamp** | A Flux `Kustomization` CR (`kustomize.toolkit.fluxcd.io`): "apply this git path to this cluster: prune, health-check, decrypt" | Two unrelated things are officially called "Kustomization", kustomize's `kustomization.yaml` file and Flux's CR. Reserving *stamp* for the CR keeps every sentence unambiguous |
| **binding** | A cluster's `clusters/<class>/<cluster>/resources/` folder: the stamps, Alerts, and Provider that cluster runs | They're ordinary CR files; the word names their *role*, binding a cluster to what it applies. A "binding-move PR" migrates workloads between clusters by moving these files |
| **environment = folder** | A kustomize overlay (`apps/overlays/dev`, …) plus every binding pointing at it | The anti-branch-per-environment stance made load-bearing: environments are folders on one branch, promotion is a diff |
| **ladder / rung** | The promotion order platform → dev → prod, for platform changes, charts, and Kubernetes versions; a rung is a class the change has reached | **No mechanism enforces it.** It's folders, PR discipline, and evidence gates (statuses, `slo-gate`). Naming it keeps it visible as a *practice*: assume it's a controller feature and you stop guarding it |
| **class** | platform / dev / prod as a *kind* of cluster: folder level, sops key scope, version-ladder pin | One word for the three places the same split shows up |
| **release channel** | Which release a stamp follows: engineering → internal → pilot → early access → general availability. Declared as a `release-channel` label on the binding, **orthogonal to class**: how exposed the release is, not where it runs. Distinct from the `release` label, which names the version a stamp currently carries; the channel is the schedule that decides when that version moves | Until stage 28 the app rides the class ladder, one implicit channel. Class answers "what kind of cluster"; the channel answers "how exposed is this release". The names deliberately share no word with a class, and conflating the two is how a dogfood tenant becomes impossible to express |
| **wave** | A named partition of a release channel's membership, advanced one batched PR at a time with soak between | Stage 29. A channel mid-rollout honestly runs two versions; waves make that a plan rather than an accident |
| **variant** | A permanent named alternative (sizing, tier, hub versus agent) a stamp selects; the selection outlives releases | "Component" is kustomize's word for the mechanism; *variant* names the role. The first lifecycle of rule 5.14; stage 09's monitoring hub and agent are the first two built |
| **feature flag** | A config toggle born default-off in the release that introduces it, promoted channel by channel, then removed; its schema rides the release, its setting rides the stamp | The second lifecycle of 5.14. Deployment-shape flags belong in config, not a runtime flag service, and the schema-at-pin-move check is what stops temporary-by-intent becoming permanent-by-accident |
| **migration overlay** | A change-scoped overlay staging a base change: rolled out rung by rung, folded into base, made a null-op, then deleted | Expand/contract for config, the third lifecycle of 5.14: base takes only empty rendered diffs (5.4), so the overlay is how a base change rides the ladder |
| **era** | Which stage-shape the repo is in; tooling detects it from git itself (`.sops.yaml` present ⇒ post-06) | Scripts must behave correctly across the course's own history; *era* names that honestly |
| **IOU** | A thing done the wrong way *on purpose and loudly*, labelled with the stage that pays back the debt | Every stage needs machinery a later stage builds; the label turns a shortcut into a motivation |
| **gate** | A script that turns evidence into a verdict: `PASS`/`FAIL` lines, non-zero exit, and nothing else | "Check" is what a human does with their eyes; a gate is what CI, a hook and a paste block all run identically |

---

## Part 1 - Day zero: the repositories

### 1.1 Two repositories, one job each

**The rule.** The *config repo* says what runs where. The *app repo* says what the app is. Nothing else lands in the config repo: not application source, not a tutorial, not tooling that belongs to anything but the platform.

**Why.** A config repo that carries anything else is a worse config repo: Flux paths grow prefixes that mean nothing in production, path-keyed gates protect folders no fleet has, and a reader cannot see what a real repo looks like because they are standing inside one that is not. Keeping the app's source out is the same rule from the other side: the config repo pins an image, it does not build one. So the two change at different rates for different reasons, and a reviewer of one never has to read the other.

**How.** From its first commit the config repo is Flux's own recommended monorepo shape: `apps/`, `infrastructure/`, `clusters/`, and later `policy/` and `tenants/`. The gates, checkpoints and drills under `scripts/` are platform tooling a real repo keeps; what the course seeds and when is in [using the course §1](using-the-course.md#1-three-repositories-and-what-the-course-seeds).

**Where.** Stage 00 (both repos created), stage 02 (the config repo takes its shape).

### 1.2 Repository configuration: the merge policy is set before the first PR

**The rule.** Merge commit only: squash and rebase disabled; the merge commit's subject is the PR title and its body is the PR body; head branches delete on merge. Set on the day the repo is created, not the day the first PR is opened.

**Why.** In a config repo the PR *is* the unit of review: it carries the approvals, the rendered diff, the status checks and the SLO evidence a promotion was gated on. A merge commit is the only strategy that leaves a durable pointer to it: `git log --first-parent` becomes the shipped-changes view, the full log the change-level view, and both survive. Squash rewrites the subject (appending ` (#N)`, concatenating branch messages) so a commit written to the convention becomes a fiction that never reaches `main`; rebase rewrites shas, so the revision a cluster reported an hour ago (`lastAppliedRevision`) can become unreachable at exactly the moment the release-notes range needs it. And GitHub's *default* merge subject is `Merge pull request #1 from owner/branch`: the PR title lands on line 3, so without `merge_commit_title=PR_TITLE` the merge commit itself violates the convention no matter how carefully the PR was titled.

**How.** Plain repository settings, in one call:

```sh
gh api -X PATCH "repos/{owner}/{repo}" \
  -F allow_merge_commit=true -F allow_squash_merge=false -F allow_rebase_merge=false \
  -f merge_commit_title=PR_TITLE -f merge_commit_message=PR_BODY \
  -F delete_branch_on_merge=true -F allow_auto_merge=true \
  --jq '"merge: \(.allow_merge_commit)  squash: \(.allow_squash_merge)  rebase: \(.allow_rebase_merge)  subject: \(.merge_commit_title)  auto: \(.allow_auto_merge)"'
```

(`allow_auto_merge` is here because it is the same call; what it is *for*, the robot's PR at stage 14, is [1.3](#13-protection-from-day-zero-nothing-reaches-main-except-a-merged-pr)'s subject.) Plus two local settings that keep the policy true on your own machine: `pull.rebase false` (merges here too) and `commit.template .gitmessage` (the vocabulary in your editor; git will not let a repo set this on clone, so it is a per-clone line). Branch protection is the *other* half: whether a merge can be *skipped* at all. It is set in the same breath, on the same day ([1.3](#13-protection-from-day-zero-nothing-reaches-main-except-a-merged-pr)). Linear history must stay **off**: it forbids merge commits, the opposite of this policy.

**Where.** Applied at [stage 00 step 1](act-1/stage-00.md#1-the-config-repo---create-it-and-seed-it-from-the-course); re-verified at the first PR in [stage 07](act-2/stage-07.md); the full argument and the queries it buys are in [the git policy appendix](appendices/git-policy.md).

### 1.3 Protection from day zero: nothing reaches `main` except a merged PR

**The rule.** A ruleset on `main` from the day the config repo is created: *pull request required, force-push and deletion blocked, linear history off*. It has **no bypass actors**: not the repository admin, not the robot. Every change from stage 02 onward reaches `main` as a merged PR, and the ruleset grows one requirement per act: CI as a required check at stage 08, the style and PR-record checks at stage 11, code-owner review and the path gate at stage 21. Approvals are set to **0** in this course and the reason is stated where a team would set 1: GitHub forbids approving your own PR, and there is one of you. The same day creates a second ruleset for **tags**: creation open (`stage-NN` and `act-N` are minted at every boundary, [using the course §5](using-the-course.md#5-tags-at-every-boundary)), update and deletion blocked, no bypass actors. The tags are the save points and range markers every drill, DORA window and change-record query leans on; a movable tag is a rewritable audit trail.

**Why.** Two reasons, one about mistakes and one about learning. The mistake: a direct push that touches `apps/base/` reaches every cluster at once, with no diff read by anyone. A ruleset makes that *impossible* rather than discouraged, and the day it saves you is not the day you expected. The learning: the PR is the spine every later control hangs off. The status contexts land on its merge commit (04), CI becomes a required check on it (08), the rendered diff is a comment on it (12), CODEOWNERS requests review on it (21), the freeze gate fails it (26). Adopt the PR on day one and each of those arrives as *one line added to a thing you already do*; adopt it at stage 07 and stages 02–06 teach a workflow you then unlearn. A little friction for a few stages, muscle memory by stage 04, and every control after that lands as a payoff rather than a cost. It is also the only path a reader under four-eyes controls (SOC 2, ISO 27001) can follow without forking the course.

**What it assumes.** A **paid GitHub plan**, Pro or above, because rulesets on a *private* repository need one, and the config repo is private ([stage 21](act-5/stage-21.md) has the argument). This is stated in the README before stage 00; a free-plan reader's only route is a public config repo, with stage 21's reasons why that is wrong for a real fleet.

**What it costs.** Anything that pushes straight to `main` is out. `flux bootstrap` is one: it commits its manifests to the branch it is told. So stage 03 lands bootstrap's three files by PR and installs from them, which is what bootstrap does internally anyway, and stage 16 never has to carry accumulated bootstrap flags, because git holds the components. Stage 14's robot writes to a branch, its PR is opened by the repository's own token and auto-merges on the same required check a human waits for. The ruleset still has no exceptions, and the merge is attributed to the robot, not to you.

**How.** Two `gh api` calls at [stage 00 step 1](act-1/stage-00.md#1-the-config-repo---create-it-and-seed-it-from-the-course), immediately after the merge policy: the `main` ruleset, then the `tags` ruleset. The branch half is amended (never replaced) by `scripts/ruleset require-check` at stages 08 and 11 and `require-owners` at 21; the tag half is never amended at all. `scripts/ruleset show` prints both: what a merge currently requires, who may bypass it (nobody), and that tags are permanent. A mistyped tag is repaired by disabling the tag ruleset in the repo settings, fixing, and re-enabling - a visible bypass, never a force-push.

**Where.** Set at stage 00; first felt at [stage 02](act-1/stage-02.md) (the first config commit is a PR); verified at [stage 07](act-2/stage-07.md) before the first production change; amended at [stage 08](act-3/stage-08.md), [stage 11](act-4/stage-11.md) and [stage 21](act-5/stage-21.md); the robot's case at [stage 14](act-4/stage-14.md).

### 1.4 Line endings

**The rule.** LF for every text file, on every platform, regardless of local git config: `* text=auto eol=lf` in `.gitattributes`, present from the first commit.

**Why.** Shell scripts break outright under CRLF, and golden-file snapshot tests (the render checkpoints from stage 02 on) require byte-identical renders. Repo-enforced hygiene beats user-config advice: a `core.autocrlf` recommendation in a README is a bug report waiting to be filed by a Windows contributor.

**Where.** Seeded at stage 00; nothing else to do.

---

## Part 2 - The change record

### 2.1 The commit convention: the subject is a field, not a sentence

**The rule.** Every commit follows [Conventional Commits](https://www.conventionalcommits.org/) with a **domain vocabulary**: `pin` `promote` `bind` `rotate` `access` `policy` `break` alongside the standard `feat` `fix` `docs` `ci` `chore` `refactor` `revert`. And **the scope is the blast radius**: the same identifier the alignment rule (3.6) already demands in the stamp name, the namespace, the label and the metric; the subject line is simply its seventh home. Issue IDs go in **trailers** (`Closes: #142`, `Refs: #98, #131`), never in the scope. `!` is redefined: not "breaks the API" (a config repo publishes none) but **"reverting this will not restore the previous state"**, a rung that is rebuilt rather than upgraded, a secret whose old key is retired. It requires a `Roll-forward:` trailer saying what to do instead.

**Why.** Three things a prose subject cannot give: a machine-readable blast radius, per-cluster release notes derived from `lastAppliedRevision` ranges, and an audit you can *query* by type: every `policy:` change in a quarter, every `access:` change to prod. It also removes fragility: the checkpoint drills find commits by subject, and typed subjects turn those prose matches into grammar queries (`--basic-regexp --grep='^promote(app-prod): '` in paste blocks; never `-E`, where `(` becomes grouping and the match silently empties). Adopted at the *first* config commit, because retrofitting one means rewriting every subject already on `main`, or living forever with an era the grammar cannot query.

**How.** Two populations, kept apart: the course repo's own authoring commits take standard types (`docs(convention)`, `fix(checkpoint)`); the domain types belong to the *content* commits a learner types against the config repo, and the scope registry is enforced only for those. Git's own `Revert "…"` subject is never rewritten (machine output, and a durable link to what it undoes); `revert(scope):` is reserved for the hand-composed partial revert of stage 20. Exemptions: stage 00 commits to the **app repo**, which is not the platform, so it takes plain `feat:`; and stage 09's "plausible bad release" keeps its innocent subject on purpose, because the drill's lesson is that a plausible commit message is not evidence. Enforcement is `scripts/commit-gate`, one grammar four ways: `--range` (real commits), `--file` (the `commit-msg` hook, the only hook that fires while you still hold the thing it rejected), `--subject` (the PR title, which `PR_TITLE` turns into a commit; the `pr-record` check from stage 11, required by the ruleset), and `--docs` (every commit string in the walkthrough, so the course cannot teach a convention it has stopped following).

**Where.** Taught at [stage 02 step 7](act-1/stage-02.md), the first config commit. Full vocabulary, the scope registry and the nine deciding rules: [the commit convention appendix](appendices/commit-convention.md). Hooks arrive at stage 11.

### 2.2 The PR convention: the title is the commit, the body is the deployment record

**The rule.** A PR's **title** obeys the commit convention exactly, because with `merge_commit_title=PR_TITLE` it *becomes* the commit subject on `main`. `pr-open` lints it before the PR exists, and from stage 11 the `pr-record` check (`commit-gate --subject` plus `issue-gate`, re-run on every edit) is a required check, so a prose title is a refused merge rather than a courtesy. The same job judges the merge commit on `main` after the fact, and the robot's subject on its push branch, where no PR event exists. A PR's **body** is the deployment record: what is moving, why now, what evidence justified it, what to do if it is wrong. It is never left to `--fill`, which copies the one-line commit subject and leaves the record empty. Trailers live in the body, and one is mandatory: `Refs:` or `Closes:`, the work item ([2.5](#25-every-change-has-a-work-item-the-trailer-is-the-reason)), beside `Roll-forward:` when the title carries `!` and `Freeze-override:` when a freeze is being crossed deliberately.

**Why.** After merge, the PR is the only place the *reasoning* for a production change survives: the rendered diff and the gate outputs are attached to it, the approvals are on it, and `merge_commit_message=PR_BODY` carries its body down into history so the trailers still resolve when the PR page is gone. A body that says "promote" is not a record; a body that says "promote 0.1.4 to prod: dev has been green for 3 days, slo-gate passed at 99.4% over 10m, no open freeze on prod, roll back by reverting this merge" is one, and it costs thirty seconds.

**How.** A **template**, `.github/pull_request_template.md`, seeded at stage 00, puts the headings in front of every author who opens a PR in the browser or an interactive `gh pr create`. Paste blocks in the course pass an explicit `--body` that follows the same headings, because a paste block cannot be interactive. The template is short on purpose: a template nobody fills in is worse than none.

**Where.** First PR at [stage 07 step 4](act-2/stage-07.md#4-promotion-is-a-pr-that-moves-a-pin); the body-matters aside is there. The title check lands at [stage 11 step 4](act-4/stage-11.md#4-ci-gains-two-jobs---the-backstop-half-and-the-title-check). Rendered diffs (stage 12) and path-gate output (stage 21) arrive as automated comments on the same PR.

### 2.3 Git policy: the merge commit is the PR record

Covered in 1.2 from the configuration side. The policy side, in one line each: `git log --first-parent` is the shipped view and the full log the change view; a revision a cluster reported must stay reachable; a PR title is a first-class artifact. The queries this buys are tabulated in [the git policy appendix](appendices/git-policy.md#what-this-buys-concretely): what shipped to prod between two revisions, which were promotions versus pins, every policy change this quarter, what issue #142 actually changed. None of them are possible against prose subjects and squashed history.

### 2.4 Every change is a PR: the branch is scaffolding, the PR is the artifact

**The rule.** No commit reaches `main` except through a merged PR, whether human or robot, platform config or tooling. The branch is short-lived, deleted on merge, and named to one shape, **`<type>/<issue>/<slug>`**: the commit type the PR will carry (2.1), the work item it advances (2.5), and a kebab-case slug for the change, as in `feat/3/overlays`, `promote/10/app-prod`, `rotate/22/dev-key`. No formal standard covers branch names the way Conventional Commits covers subjects; this shape simply reuses the two vocabularies the repo already has, so the type and the work item are already on screen everywhere GitHub shows a branch name: the PR header, the checks page, a push log. Intent is confirmable at a glance. `pr-open` refuses a name that does not parse and cross-checks the issue segment against the body's trailer; the robot's standing `flux-image-updates` branch (stage 14) is the named exception, reused rather than per-change. Nobody will ever look at a merged branch again, because the PR is what survives. The commit subject is the PR title ([2.1](#21-the-commit-convention-the-subject-is-a-field-not-a-sentence), [2.2](#22-the-pr-convention-the-title-is-the-commit-the-body-is-the-deployment-record)); the body is the record. And **the merge is the gate**: read the diff before merging, every time, even when you wrote it five seconds ago. That habit is the whole point of the five stages where the diff is one line. Solo, you merge your own PR on green; that is the *dev* privilege, and stage 14 gives the robot exactly it.

**Why.** [1.3](#13-protection-from-day-zero-nothing-reaches-main-except-a-merged-pr) has the argument; this section has the shape. What each stage adds to the PR you already open: statuses on its merge commit (04), a lead-time number from its own timestamps (10), a required check (08), a rendered diff as a comment (12), a robot author (14), owners and a path gate (21), a freeze (26). None of them are a workflow change, because the workflow was there from the first commit.

**How.** Stages 02 and 03 spell the flow out in full, so it is typed before it is scripted: branch, commit, push, open, read, merge, return. Stage 04 introduces `scripts/pr-open`, which does the first four from the staged changes and stops: **it never merges**. Merging is always your line, always after the diff: `gh pr merge --merge --delete-branch && git switch main && git pull`. Undoing a merged PR is `git revert -m 1 <merge-sha>` on a branch of its own: a merge commit has two parents and git will not guess which one is `main`. `scripts/pr-revert` does exactly that, with git's own subject and a body built from the reverted merge, and again never merges.

**Where.** First at [stage 02 step 7](act-1/stage-02.md); the helper at [stage 04](act-1/stage-04.md); the first PR that carries *evidence* at [stage 07 step 4](act-2/stage-07.md#4-promotion-is-a-pr-that-moves-a-pin); the robot at [stage 14](act-4/stage-14.md).

### 2.5 Every change has a work item: the trailer is the reason

**The rule.** Every PR body ends with a `Refs: #<issue>` (or `Closes: #<issue>`) trailer naming the work item the change advances, and the number must be an issue in this repo, not a PR, that is still open. No exception for robots: the image automation cites a standing issue, a freeze override cites the incident, a revert cites what the reverted change cited. `Closes:` is used only where the PR *is* the whole work item, because it fires on merge, and merge is not verification.

**Why.** "Why now" in prose is a claim; a work item is a record with its own history: who asked, when, what was discussed, what else it touched. The trailer travels into the merge commit (`merge_commit_message=PR_BODY`), so `git log --grep='^Refs: #9'` (`#9` is stage 07's work item) answers "what did this piece of work actually change" long after the PR page is gone. It is also the control an auditor asks for first: every production change traceable to an approved work item, and no change citing finished work. A closed ticket re-used is the classic gap. In this course the work items are the course itself: stage 00 seeds a milestone per act and an issue per stage and checkpoint, before the first PR, so the numbers are identical for every reader, which is honest about what they are, since the stage *is* the work you were asked to do. The production version is a ticket key; the mechanism is the same.

**How.** Stages 02–03 type the trailer by hand. From stage 04 `pr-open` refuses a body without one, and `scripts/issue-gate` resolves every number: exists, is an issue, is open. From stage 11 the `pr-record` job runs the same gate on every PR event, body edits included, and the ruleset requires it: a change citing nothing, or citing finished work, is a refused merge. On a push it runs `--landed`, because the merge may be what closed the item. `pr-revert` inherits the reverted merge's trailer. A stage's issue closes at the tag step, after the stop-and-measure, never at the merge. `scripts/check-repo` reports the backlog with the rest of day zero.

**Where.** Seeded at [stage 00 step 1](act-1/stage-00.md#1-the-config-repo---create-it-and-seed-it-from-the-course); first typed at [stage 02 step 7](act-1/stage-02.md); scripted at [stage 04](act-1/stage-04.md); enforced at [stage 11 step 4](act-4/stage-11.md#4-ci-gains-two-jobs---the-backstop-half-and-the-title-check); the robot's standing item at [stage 14](act-4/stage-14.md); queried at [stage 26](act-6/stage-26.md).

---

## Part 3 - Files and folders

### 3.1 File naming: `<metadata.name>.<kind>.yaml`

**The rule.** Every YAML resource file is `<metadata.name>.<kind>.yaml`, all lowercase, dots in the name replaced by dashes (`foo.bar` → `foo-bar.<kind>.yaml`): `ggp.namespace.yaml`, `app.deployment.yaml`, `app-dev.kustomization.yaml`. Patch files: `<target-name>.<kind>.patch.yaml`; replacements: `<target-name>.<kind>.replacement.yaml`. Exemptions: `kustomization.yaml` (tool-mandated) and other tool-generated files (Flux's bootstrap manifests).

**Why.** It forces **one resource per file** (a multi-doc file has no single name/kind), which is the point: the filename is the resource's identity (greppable, diffable, CODEOWNERS-addressable), and blast-radius reports read as resource lists. It is also an *observability* control (3.6): an alert names a resource, the resource name is the filename, so alert→file is a grep with no lookup table. A patch cannot be mistaken for the resource it patches.

**Where.** Stated at stage 01 (the plain manifests already follow it); enforced by `checkpoint-02`'s naming checks from stage 02 on.

### 3.2 Folder convention: everything has a place

**The rule.** Each "thing" (an app base, an overlay, a cluster binding, a component) segregates its YAML into typed folders: `resources/`, `patches/`, `replacements/`, `secrets/`, `config/`, and `components/` (reserved for kustomize `Component` units: optional, selectable features; always-on sub-parts just live in `resources/`). Folders appear when first populated: no empty scaffolding. **`config/` and `secrets/` are self-contained kustomizations**: each carries its own `kustomization.yaml` holding the configMap/secret *generators*, with their file-based inputs co-located, and the parent includes the folder as one `resources:` entry. **Patches and replacements are always files in their folders, never inline** in a kustomization.

**Why.** Findability is structural: one place to look when wiring `env`/`envFrom`, one place for extra protections (CODEOWNERS, scanning) to attach, and per-type churn is one `git log -- '*/patches/*'` away. And `secrets/` is deliberately a **debt register**: secrets are a liability to be eliminated, so the folder exists to be *emptied*: `find . -path '*/secrets/*' -name '*.yaml'` is the countable debt, stage 06 moves the stage-04 IOU into it, Act V operates it, and the workload-identity stages drain it. Its true endgame is *conversion*, not emptiness: nothing left that contains `stringData:` or sops metadata, every remaining file a pointer with a vault home, an owner and a rotation story.

**How.** Exemptions: stage 01's flat `deploy/` (deliberately pre-convention; naive is its point) and tool-managed trees (Flux's `flux-system/`). `checkpoint-02` judges the taxonomy.

**Where.** Stage 02 (the restructure), stage 06 (`secrets/` as a register), stage 08 (`components/`).

### 3.3 Array ordering: alphabetical wherever order doesn't matter

**The rule.** Lists are alphabetical wherever order doesn't matter: kustomization `resources`, label pairs, RBAC rule lists. Where order is genuinely semantic, that's fine for the inherently positional cases (command `args`) and **comment-worthy everywhere else** (`env` entries using dependent `$(VAR)` expansion, say so next to the list).

**Why.** Insertions then diff as one line in a predictable place instead of appearing wherever the author's cursor was. A list that *needs* non-alphabetical order is usually a code smell, and the comment requirement makes you say why.

**How.** `kustomize edit` emits alphabetically, so the rule is free for tool-written files (3.5); hand-written lists are the only place it costs anything.

### 3.4 YAML style: adopt the tool's style, everywhere

**The rule.** All YAML follows kustomize's own emitted style: two-space maps, **sequence items not indented** relative to their key, block style throughout. **Flow style (`{a: b}` / `[x, y]`) is banned in authored YAML** with exactly two exceptions: genuinely empty collections (`emptyDir: {}` has no block form; the standing exemption, no callout needed), and places where flow is the *tool's* syntax rather than file content (yq expressions, JSON), each called out where it occurs. Inline comments get a single space (`key: value # note`); aligned comment columns are collapsed by the formatter, so don't build them.

**Why.** Half your YAML will be written or rewritten by kustomize, so adopting its style is the only choice that keeps every diff clean: fighting it means reformatting noise forever. An unexplained `{a: b}` is a convention violation, not a shortcut.

**How.** `kustomize cfg fmt` was removed in kustomize v5 but the library survives: [kustofmt](https://github.com/blairforce1/kustofmt) wraps it as a formatter (pinned container; `scripts/style-gate` checks, `scripts/style-fix` rewrites), so the house style is a byte comparison against what kyaml emits rather than a description. yamllint is the backstop for what formatting can't express. Editor settings can't express sequence indentation; don't try.

**Where.** Stated at stage 02; the gate and the hooks arrive at [stage 11](act-4/stage-11.md).

### 3.5 The tool writes the file

**The rule.** `kustomize create --autodetect` scaffolds inventory kustomizations (`--recursive` when resources sit in typed subfolders), `kustomize edit add …` grows them, `kustomize create --resources <list>` expresses explicit-selection roots, never a hand-typed resource list. `flux create <kind> --export` authors stamps, Alerts, Providers and sources. Whole-file writes are reserved for content the CLI can't express, and each states its reason where it occurs: comments that are the point, `Component` files, generators needing options the CLI lacks, `.sops.yaml`, Namespaces (kubectl's `--dry-run` output carries empty `status:`/`spec:` noise).

**Why.** Generated files come out alphabetical and in the tool's emitted style, 3.3 and 3.4 enforced for free, and the flags are the day-2 vocabulary: a reader who learns `flux create kustomization --health-check-timeout` has learned the thing they will type at 3am. Two traps the rule was written against: on `flux create kustomization`, `--health-check-timeout` writes the CR's `spec.timeout` while the bare `--timeout` is the CLI's operation timeout; and `kustomize create` refuses to overwrite (`kustomization file already exists`, no `--force`), so re-running a scaffold block means deleting the file first.

**How.** **yq is quarantined:** its edits preserve scalars, maps, comments, quoting and the leading `---`, but its emitter re-indents *every sequence in the file* to yq's house style, silently violating 3.4 in files kustomize and flux wrote indentless. So yq is for scalar/map edits on sequence-free files; any change to a file carrying a list re-authors the whole file through its owning tool: regeneration, not patching, and the diff shows exactly the intended change. Flux's exports open with `---`: keep it (tool's style, diff-stable), but don't add one by hand to files other tools author.

**Where.** Stage 02 (kustomize), stage 03–04 (flux create), stated as a convention at stage 05.

### 3.6 Identifier alignment: one string, seven homes

**The rule.** The identifier for a thing is the same string everywhere it appears: git folder (`clusters/prod/prod-01/`) → kube context (`kind-ggp-prod-01`) → stamp (`app-prod`) → commit status context (`kustomization/app-prod/prod-01`) → metric labels (`gotk_resource_info{name,cluster}`) → resource filename (`app-prod.kustomization.yaml`) → commit scope (`promote(app-prod):`). **Alert payloads carry identifiers, not just symptoms**, and if you anonymise, anonymise the whole chain or none of it.

**Why.** The naming decision is only half the operational cost; the other half is whether the identifier survives the trip from an *alert* back to the *config*. Half-anonymised is the worst option available: you pay the translation cost while the name survives in metric labels, certificates or alert text. The test: from the notification alone, can you name the file to open? The `evidence` script is the proof. Handed a red status context, it splits the stamp and cluster straight out of the string and opens the right file with no lookup table.

**Where.** Stage 03 (first stamp), stage 07 (per-cluster contexts), stage 09 (labels); the full argument is in [assume the clone leaks](appendices/repo-leak-posture.md).

---

## Part 4 - Tools

### 4.1 The render rule: one master per tool, and kubectl never renders

**The rule.** Every tool in the chain is pinned to exactly one authority, so no pairwise compatibility matrix exists: **flux → the AKS `microsoft.flux` release**; **kustomize → kustomize-controller's *effective* library**, go.mod `replace` directives included; **helm → helm-controller's embedded library**; **sops and age → kustomize-controller's embedded decryption libraries**; **kubectl → the dev rung of the version ladder**. `kubectl apply -k` / `kubectl kustomize` are **banned as renderers**: kubectl is the API client, nothing more. `kustomize build` is the canonical overlay renderer; `flux build --dry-run` is the stamp renderer, used only where binding-level transforms matter and trusted conditionally.

**Why.** What the CLI encrypts the controller must decrypt; what the CLI renders the controller must render identically; and kubectl's embedded kustomize answers to the wrong master (the Kubernetes ladder) and would silently change render output on every client bump. The pin to AKS's Flux is what makes Act VIII's "the cloud absorbs what you built" an honest claim rather than a version skew.

**How.** `./scripts/check` runs every `check-*` gate at once; pins live in `clusters/versions.yaml`. When the parity script notes the flux CLI's embedded kustomize has diverged from the controller's, the controller is the truth and `flux build` is advisory.

**Where.** Stage 00 (the toolchain gate), stage 03 (the flux pin), stage 05 (helm), stage 06 (sops/age), stage 07 (the version ladder), stage 16 (climbing it).

### 4.2 Tool provisioning: filters from images, operators installed

**The rule.** A tool that is a pure function over files/stdin with no credentials, cluster access or local state (kubeconform, conftest, trivy, yamllint, kustofmt) runs as a **container with a pinned tag**. A tool that holds credentials (gh), talks to the cluster (kubectl, flux), manages local machine state (kind, podman), writes files constantly (kustomize) or is an SDK (dotnet) installs natively. Borderline constant-use filters (yq) go native for ergonomics.

**Why.** The pin lives in the command and CI runs the identical image, so "works locally, fails in CI" is structurally impossible for that check: environment parity is a property, not an aspiration.

**Where.** Stage 00; every gate from stage 02 on follows it.

### 4.3 The version policy: follow the master, at the pace Kubernetes sets

**The rule.** Versions are *followed*, never chased: every pin (4.1) tracks its master's current release, and the fleet's Kubernetes version climbs a **ladder**: platform first, then dev, then prod, each class at most one minor behind the next. The ladder is recorded in `clusters/versions.yaml` and climbed one rung per change. The local Flux mirrors the release bundled in AKS's `microsoft.flux` extension; OSS Flux typically runs a minor ahead of it, so the reflex `curl | bash` install grabs a version *ahead of the fleet*, the wrong direction.

**Why.** This is the same discipline the Kubernetes ecosystem itself runs on: the API is versioned, every tool tolerates a bounded version **skew** (kubectl supports one minor either side of the server; node components trail the control plane within a bound), and upgrades walk one minor at a time. Following the master at that pace keeps the fleet inside every tool's tested skew window at all times. And the class split gives the policy its rungs for free, because **platform → dev → prod is a natural staging order for versions too**: a Kubernetes minor lands on the platform cluster, soaks, climbs to dev, then to prod, and the same order carries chart bumps and controller upgrades (5.11). The three-minor spread also matches what managed Kubernetes will hold you to: AKS supports N..N-2, so a fleet on next/current/stable sits exactly inside the supported window when Act VIII absorbs it - the ladder practised locally is the one the cloud enforces.

**How.** Pins live in `clusters/versions.yaml`, one per class rung. `./scripts/check` derives every local tool pin from the dependency graph and FAILs with the exact install one-liner; `./scripts/check-flux-aks-parity` scrapes [Microsoft's release notes](https://learn.microsoft.com/azure/azure-arc/kubernetes/flux-gitops-release-notes) and compares (PASS on the same minor line, FAIL on minor drift with the pin command, WARN if the scrape breaks). Re-run it at each stage start; it also runs on a CI schedule so drift surfaces without anyone remembering to look.

**Where.** Stage 00 (the toolchain gate), stage 07 (the ladder recorded), stage 16 (the ladder climbs), Act VIII (the managed extension the pin anticipated).

---

## Part 5 - Operating rules

These are the claims the platform is built to make true. Each is taught by a stage and measured by a drill; here they are stated once, with the failure each was written against.

### 5.1 The loop invariant: merge → reconcile → observable outcome → human informed

Every stage preserves it; every feature multiplies it (a loop per cluster, per tenant, per PR). A loop without feedback is fire-and-forget, not GitOps. That is why Act I does not end at "Flux applies it" but at "the commit wears the result". No stage may leave the reader blind. *Stage 04; every act checkpoint's drill 3.*

### 5.2 The cluster is derivable from git - and every act proves it

**Every act ends with a rebuild-from-nothing, and the definition of "nothing" is the act's most important sentence.** `act-N-drill` rebuilds the state at the end of act N from git and runs its checkpoint; act N+1's cover says "not in this state? run `act-N-drill`". Through Act VI "nothing" means every kind cluster; git and a handful of root keys survive (the IOUs, 5.3). Act VII narrows it to the cluster, because the cloud resources it reconciles hold *data* and *identity trust*; Act VIII widens it to the region. The drill cannot manufacture history: DORA, the change record and the evidence dossier read git and the metric store. So it is a rebuild mechanism, not a way to skip. *Every act checkpoint's drill 1.*

### 5.3 The IOU pattern: do it the wrong way, loudly

Where a stage needs machinery a later stage builds, do it the wrong way *on purpose*, label it with the stage that pays back the debt, and make the checkpoint report it. Stage 04 creates the notification token imperatively, labelled "stage 06 pays back the debt"; stage 06 leaves one root key per cluster as the honest residue; Act V and Act VII each shrink the list. The debt motivates the later stage, and `checkpoint-NN` is era-aware so a rebuild reports exactly which IOU is outstanding. *Stage 04 onward.*

### 5.4 The ladder is a practice, not a mechanism

Promotion order (platform → dev → prod) is folders, PR discipline and evidence gates. **No controller enforces it**, and the course says so at every opportunity, because assuming it is a controller feature is how teams stop guarding it. Three corollaries. First, **entry is automatic, ascent is not**: a version *arriving* (a robot moving the dev tag, Renovate bumping a chart) is `pin`; the same version *moving up a rung*, always a PR against evidence, is `promote`. Second, **the ladder only gates what lives on a rung**: a change under `base/` reaches every cluster at once with no promotion, so `base/`, `clusters/`, `infrastructure/`, the access lists and the gates themselves need owners (stage 21) and a rendered diff (stage 12). Third, **a base change rides the ladder as overlay patches, then absorbs**: the change enters as a patch on one rung, promotes rung by rung with soak between, and once every rung renders it identically it is folded into `base/`, the overlay made a null-op, and the references removed - two cleanup steps kept separate on purpose, so "base absorbed it" and "references gone" need not be atomic. The absorption itself is a base edit whose rendered diff is empty, because the overlays already said everything it says. That empty rendered diff is the acceptance test for touching `base/` at all: a base PR whose render changes anything is a promotion skipping the ladder, wearing an absorption's clothes. *Stage 02; stage 07; stages 12, 13, 14, 21.*

### 5.5 Reconcile scope is not change scope

A shared source means **every cluster reconciles every commit**, which is not the same as every cluster changing: only the clusters whose *render* differs apply anything. So "reconciled" is never evidence of "affected"; the paths a commit touched decide that, and the evidence dossier reads them. *Act II checkpoint drill 4.*

### 5.6 Apply in git, validate at gates, never mutate at admission

Standards (the workload baseline: non-root, seccomp, dropped capabilities, read-only rootfs, requests/limits, never `:latest`) are a Kustomize component applied *in git*, then validated at every gate: conftest on rendered output in CI, PSA labels, Kyverno at admission. Admission **mutation** is banned: it makes the cluster diverge from what git shows, and git must tell the truth. *Stage 08; stages 23, 30.*

### 5.7 Converged is not working

Ready is a resource fact; an SLO is a user fact, and the course's own app proves they diverge: `/healthz` is static, so a bad storage config is Ready-and-green while every real request fails. Promotion therefore requires **two signatures**: convergence (dev's green context) and performance (a clean SLO window on the rung below, `slo-gate`). No traffic is a FAIL: absence of evidence is not health. Security signals are a third evidence class on different clocks, deliberately not in the gate (stage 30 demonstrates them). *Stage 09; Act III checkpoint drill 2.*

### 5.8 No stopwatch anywhere

Every number the course records, from rebuild time and lead time per rung to detection time and the four DORA numbers, comes from artifacts: commit timestamps, per-context status `created_at`, condition transitions, metric sample timestamps. A number you typed into a spreadsheet is a claim; one derived from what the fleet recorded is evidence. Corollary: **ask the cluster what it applied, ask git what you asked for, never let a green stand in for either**. A commit can wear a red the cluster already had, or a green it has not earned yet. *Every checkpoint; `rung-time`, `detect-time`, `dora`.*

### 5.9 Gates, not checks - and CI is a backstop that never fires

A gate prints `PASS`/`FAIL` with what it means and exits non-zero; bare unlabeled output is banned at checkpoints. Every gate is a pure function over the working tree where it can be, so the *same file* runs as a paste block, in CI, and from a git hook. Each member of the `*-gate` family turns one class of evidence into one verdict: `policy-gate`, `style-gate`, `commit-gate`, `path-gate`, `revert-gate`, `freeze-gate`, `slo-gate`. From stage 11 the hooks run them locally, and a red CI run on a *mechanical* check is a process failure: the hook should have caught it. *Stage 02 (first checkpoint), stage 08 (first gate), stage 11 (hooks).*

### 5.10 Secrets: the taxonomy, the ladder, and roll forward

Secrets divide into **dissolvable** (cloud credentials; a federation handshake replaces them outright) and **irreducible** (third-party keys with no federation on offer, held well instead of wished away). The ladder for irreducible ones: encrypted in git (SOPS, stage 06) → referenced, not stored (a vault pointer, stage 31). Three teeth: **git history keeps every old ciphertext**, so rotating means *revoking* the old value at the provider, never just committing a new one; **a secret is a pointer to state you don't own**, so a revert restores an address with nothing behind it and reconciles green: *for secrets, roll forward, never back* (`revert-gate`); and **assume the clone leaks**: a private repo is a delay, not a control, so reading the repo must not grant access to anything. *Stage 06; Act V; stage 31; [assume the clone leaks](appendices/repo-leak-posture.md).*

### 5.11 The platform is a workload

The ingress, the monitoring stack, Reloader, the policy engine: every platform component is a HelmRelease or a stamp in `infrastructure/`, pinned in git, promoted class by class up the same ladder as the app, and its upgrades are Renovate PRs with rendered diffs. A platform change that cannot ride the ladder is a platform change nobody can review. *Stage 05; stage 13.*

### 5.12 Hand-build, then the cloud absorbs

Every layer a managed service could provide is built by hand first: Flux by bootstrap, identity by a hand-assembled OIDC issuer, storage by Azurite, policy by Kyverno. When AKS, the managed OIDC issuer, real storage and managed image integrity arrive in Act VIII, the reader can read the diff and see exactly what the cloud is doing for them. "Small and readable" is the pass criterion. *Acts VII–VIII.*

### 5.13 Release channels: ascent is judged where members exist

An app release climbs **release channels**: engineering → internal → pilot → early access → general availability, a label on the binding, orthogonal to class. The climb is under three rules a gate can refuse: every app binding carries **exactly one `release-channel` label** from the registry; a channel's release moves **only forward, and only to what the next-faster channel is serving** after a clean soak window; and a fast-channel binding on a prod-class cluster is a **declared exception with an expiry**. The corollary that makes five tiers workable at any fleet size: **an empty channel is legal; its pointer follows its faster neighbour, and ascent evidence comes from the nearest *populated* faster channel, the gate naming whose soak window it judged.** Zero members is zero exposure, so no evidence is owed; without this, no-traffic-is-a-FAIL (5.7) would deadlock every ascent at the first unpopulated tier. *Stages 28–29; enforced by `channel-gate`, which ships with them; until then the app rides the class ladder as one implicit channel.*

### 5.14 Variants, flags and migrations: three lifecycles, three homes

Config that differs between stamps comes in exactly three kinds, and each has its own lifecycle and home. **Variants** are permanent named alternatives (sizing, tier, hub versus agent) a stamp selects; the selection outlives releases. **Feature flags** are feature-scoped: born default-off in the release that introduces the feature, promoted channel by channel, then removed. **Migration overlays** are change-scoped: expand/contract for config, staging the base change 5.4's third corollary describes. Two mechanical guards keep the temporary kinds honest. A release carries its flag and variant **schema with defaults**; selections live in stamp config and float across releases, so when a release's schema drops a flag, any stamp still setting it fails validation on the pin-move PR - dead settings cannot survive a pin move, and stamps on old releases legitimately keep theirs. And a migration overlay carries its **created date**, with CI nagging past an age budget, so a migration cannot stall silently mid-lifecycle. Mixing the three in one folder is the recorded pain this rule exists to prevent. *Variants: stages 08, 09, 22. Flags and the schema: stages 28-29, completed by the OCI quest. Migrations: the migrate-base-config quest, previewed at stage 02.*

---

## Quick reference

| # | Rule | One line | Enforced by | Record |
|---|---|---|---|---|
| 1.1 | Two repos | config says what runs where; app says what it is; nothing else lands in either | layout | [0013](seed/decisions/0013-clusters-class-cluster-layout-local-is-a-rung.md) |
| 1.2 | Merge policy | merge commit only; subject = PR title; set on day zero | repo settings (stage 00) | [0003](seed/decisions/0003-merge-commit-only.md) |
| 1.3 | Protection from day zero | rulesets on `main` and on every tag from the first commit, no bypass actors; the branch half grows per act, tags are immutable once created | ruleset (stages 00, 08, 11, 21), `check-repo` | [0002](seed/decisions/0002-protection-on-main-from-day-zero.md), [0039](seed/decisions/0039-tags-immutable-once-created.md) |
| 1.4 | Line endings | LF everywhere | `.gitattributes` |  |
| 2.1 | Commit convention | `type(scope):`, scope = blast radius, trailers, `!` = no clean revert | `commit-gate` | [0004](seed/decisions/0004-commit-convention-scope-is-blast-radius.md) |
| 2.2 | PR convention | title is the commit; body is the deployment record; never `--fill` | template, `pr-record` check (`commit-gate --subject`) | [0004](seed/decisions/0004-commit-convention-scope-is-blast-radius.md) |
| 2.3 | Git policy | the merge commit is the PR record | repo settings, `pull.rebase false` | [0003](seed/decisions/0003-merge-commit-only.md) |
| 2.4 | Every change is a PR | branch is scaffolding, PR is the artifact; read the diff, then merge | ruleset, `pr-open` | [0002](seed/decisions/0002-protection-on-main-from-day-zero.md), [0006](seed/decisions/0006-branch-names-type-issue-slug.md) |
| 2.5 | Every change has a work item | `Refs: #n` to an open issue, robots included; `Closes:` only when the PR is the whole item | `issue-gate`, `pr-record` check | [0005](seed/decisions/0005-every-change-cites-a-work-item.md) |
| 3.1 | File naming | `<name>.<kind>.yaml`, one resource per file | `checkpoint-02` | [0007](seed/decisions/0007-one-resource-per-file-typed-folders.md) |
| 3.2 | Folders | typed folders; `secrets/` is a debt register | `checkpoint-02` | [0007](seed/decisions/0007-one-resource-per-file-typed-folders.md) |
| 3.3 | Ordering | alphabetical unless semantic, and then commented | tool output | [0007](seed/decisions/0007-one-resource-per-file-typed-folders.md) |
| 3.4 | YAML style | kustomize's emitted style; flow banned | `style-gate` (kustofmt + yamllint) | [0008](seed/decisions/0008-yaml-style-is-the-tools-style.md) |
| 3.5 | The tool writes the file | `kustomize create/edit`, `flux create --export`; yq quarantined | review | [0008](seed/decisions/0008-yaml-style-is-the-tools-style.md) |
| 3.6 | Identifier alignment | one string, seven homes; alerts carry identifiers | `evidence`, naming | [0009](seed/decisions/0009-identifier-alignment-one-string-seven-homes.md) |
| 4.1 | Render rule | one master per tool; kubectl never renders | `scripts/check` | [0010](seed/decisions/0010-one-master-per-tool-kubectl-never-renders.md) |
| 4.2 | Provisioning | filters from pinned images; operators installed | command pins | [0011](seed/decisions/0011-filters-from-images-operators-installed.md) |
| 4.3 | Version policy | follow the master, skew bounded as Kubernetes' own; versions climb the class ladder | `scripts/check`, `versions.yaml` | [0012](seed/decisions/0012-follow-the-master-at-kubernetes-pace.md) |
| 5.1 | Loop invariant | merge → reconcile → outcome → human informed | stage 04, drill 3 |  |
| 5.2 | Rebuild from nothing | every act; "nothing" defined per act | `act-N-drill` |  |
| 5.3 | IOU | wrong way, loudly, labelled | era-aware checkpoints |  |
| 5.4 | Ladder is a practice | entry automatic, ascent by PR; off-rung paths need owners; base absorbs only what every rung already renders | `path-gate`, CODEOWNERS | [0017](seed/decisions/0017-automation-writes-only-at-the-entry-rung.md) |
| 5.5 | Reconcile ≠ change | paths decide who is affected | `evidence` |[0024](seed/decisions/0024-codeowners-by-effective-blast-radius.md) |
| 5.6 | Apply in git, validate at gates | never mutate at admission | `policy-gate`, Kyverno validate | [0019](seed/decisions/0019-apply-in-git-validate-at-gates-never-mutate-at-admission.md) |
| 5.7 | Converged is not working | two signatures for promotion | `slo-gate` | [0021](seed/decisions/0021-slo-gate-is-the-second-signature.md) |
| 5.8 | No stopwatch | numbers from artifacts | `rung-time`, `detect-time`, `dora` | [0022](seed/decisions/0022-dora-from-artifacts-no-stopwatch.md) |
| 5.9 | Gates, not checks | PASS/FAIL, pure functions, hooks first | `*-gate`, hooks | [0020](seed/decisions/0020-gates-not-checks-ci-is-a-backstop.md) |
| 5.10 | Secrets | dissolvable vs irreducible; revoke on rotate; roll forward; assume the clone leaks | `revert-gate`, `checkpoint-06` | [0018](seed/decisions/0018-secrets-taxonomy-class-keys-roll-forward.md) |
| 5.11 | Platform is a workload | `infrastructure/` rides the ladder | stage 13, Renovate |[0028](seed/decisions/0028-infrastructure-names-operational-role.md), [0029](seed/decisions/0029-managed-first-disposable-infrastructure-in-place-patches.md), [0034](seed/decisions/0034-renovate-not-dependabot-for-the-config-repo.md) |
| 5.12 | Hand-build, then absorb | the diff is the lesson | Act VIII checkpoints |[0029](seed/decisions/0029-managed-first-disposable-infrastructure-in-place-patches.md) |
| 5.13 | Release channels | one `release-channel` label per binding; ascent forward, judged where members exist; an empty channel follows its neighbour | `channel-gate`, shipped with stage 28 | [0016](seed/decisions/0016-release-channels-as-a-label-ascent-judged-where-members-exist.md) |
| 5.14 | Three lifecycles | variants select, flags expire by schema at the pin move, migrations expand/contract and absorb | pin-move validation (stage 28) and the migration age nag (the migrate quest) | [0037](seed/decisions/0037-variants-flags-and-migration-overlays-three-lifecycles.md) |

---

**Next:** [00 - Prerequisites & the app repo](act-1/stage-00.md)
