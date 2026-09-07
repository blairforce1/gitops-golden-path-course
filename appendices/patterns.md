# GitOps patterns

[Walkthrough index](../README.md) · [The GitOps rules](../rules.md) · [What the rules buy](what-the-rules-buy.md)

The rules say what the platform obeys. A pattern is a way of working that several stages use and none of them names, collected here so a stage can point at it instead of re-teaching it. Each entry has the same shape: the pattern in one sentence, why it holds, where the course does it, and what enforces it. A pattern earns an entry when two stages use it and neither names it.

| # | Pattern | One line | Where |
|---|---|---|---|
| 1 | [Base and overlays, twice](#1-base-and-overlays-twice) | base says what is true everywhere, an overlay per class says what is true there, a binding picks one; apps and infrastructure take the shape in separate trees | stages 02, 13 |
| 2 | [Restructure first, then change](#2-restructure-first-then-change) | change the shape in a PR whose renders are byte-identical and reviewed as such; then change the value, riding the ladder | stages 02, 08, 11, 13 |
| 3 | [Base is sacred](#3-base-is-sacred) | base has no rung, so it accepts only changes whose rendered diff is empty; a new value enters as an overlay patch and is absorbed; `base-gate` refuses the rest | stages 12, 13, 21 |
| 4 | [Promotion is a pointer move](#4-promotion-is-a-pointer-move) | every ascent re-points one line at an artifact that does not change: a tag, a chart version, a path, a minor | stages 07, 13, 14, 16 |
| 5 | [Read it, never retype it](#5-read-it-never-retype-it) | every fact has one home and everything else derives from it; a second copy is a second authority nobody reads | stages 11, 12, 13 |
| 6 | [Retire in two steps](#6-retire-in-two-steps) | stop reading a thing before deleting it; nothing is removed while something still points at it | stages 13, 20, the migrate quest |
| 7 | [Three verdicts, not two](#7-three-verdicts-not-two) | a gate that cannot judge says SKIP, and SKIP is never a PASS | stages 09, 10, 11, 27 |
| 8 | [One change in flight per rung](#8-one-change-in-flight-per-rung) | a rung carries one change under evaluation at a time, so a red has one candidate; a practice with soft teeth | stages 07, 09, 13 |
| 9 | [Follow the authority, at every layer](#9-follow-the-authority-at-every-layer) | the platform tracks its authorities inside their skew window; so do the controllers on it and the workloads on them, with the same pins, checks and ladder | stages 00, 03, 07, 13, 16 |

The three are one idea seen from three sides, and each one is easy to miss because the stages teach it by doing rather than by naming it. The first is the shape of the tree. The second is how the shape is allowed to change. The third is the consequence for the one part of the shape that has no rung.

## 1. Base and overlays, twice

The shape, in one sentence: **base holds the resources, an overlay per class holds that class's differences as patches, and a cluster's binding points at one overlay.** [Stage 02](../act-1/stage-02.md) builds it for the app under `apps/`; [stage 13](../act-4/stage-13.md) builds the same shape for the ingress under `infrastructure/`, and every later platform component takes it too.

```
apps/                                infrastructure/
├── base/                            ├── base/
│   └── resources/…                  │   └── traefik/resources/…
└── overlays/                        └── overlays/
    ├── dev/patches/…                    ├── platform/patches/…
    └── prod/patches/…                   ├── dev/patches/…
                                         └── prod/patches/…
clusters/<class>/<cluster>/resources/<stamp>.kustomization.yaml   path: ./apps/overlays/dev
```

Why this shape and not another is [rule 3.2](../rules.md#32-folder-convention-everything-has-a-place) and [record 0007](../seed/decisions/0007-one-resource-per-file-typed-folders.md). What matters here is what the shape buys: **promotion is a diff between two folders on one branch**, an environment is a folder rather than a branch, and a change reaches a class by landing in that class's overlay. That is the whole mechanism of the ladder ([rule 5.4](../rules.md#54-the-ladder-is-a-practice-not-a-mechanism)); no controller enforces the order, the folders make it visible and the PRs walk it.

Two things in the picture are deliberate and worth stating.

**`clusters/` is bindings, never overlays.** A cluster folder holds the stamps, Alerts and Provider that bind the cluster to what it applies, and nothing that changes what is applied. Class-level differences live in the overlay; cluster-level identity lives in the binding ([record 0015](../seed/decisions/0015-bindings-live-in-the-cluster-folder.md)). Put a patch in a cluster folder and that cluster has quietly become its own class, with a rung nobody drew.

**The app tree and the infrastructure tree stay apart, though they share a shape.** The reasons are operational, not aesthetic:

- **They change at different rates for different reasons.** An app release arrives daily, moved by the image robot at the dev rung ([stage 14](../act-4/stage-14.md)). A chart or controller bump arrives when upstream releases, moved by Renovate at the platform rung ([stage 13](../act-4/stage-13.md)). The entry rung is per artifact class ([the commit convention](commit-convention.md), rule 2), and two robots with two fences need two trees to fence.
- **They have different blast radii and different reviewers.** A change under `infrastructure/` reaches every workload on every cluster of that class; it is a `path-gate` row of its own and an owner of its own ([stage 21](../act-5/stage-21.md)). An app change reaches one stamp. Mixing them means the wider review applies to everything or to nothing.
- **They must never share a PR.** Apps stand on infrastructure (`dependsOn`, [stage 08](../act-3/stage-08.md)), so a PR that bumps the ingress and promotes the app has two failure modes and one revert. One change per PR ([rule 2.4](../rules.md#24-every-change-is-a-pr-the-branch-is-scaffolding-the-pr-is-the-artifact)) is only possible when the two lifecycles have two homes.
- **They climb the same rungs on independent clocks.** The infrastructure ladder and the app ladder use the same three classes, but a chart soaking on platform says nothing about an app release soaking on dev. Two trees make two ladders; one tree would make one ladder that neither change actually rode.

The platform is a workload ([rule 5.11](../rules.md#511-the-platform-is-a-workload), [record 0028](../seed/decisions/0028-infrastructure-names-operational-role.md)): pinned in git, promoted by class, upgraded by PR with a rendered diff. Sharing the shape is what makes that sentence true. Sharing the tree would make it false.

## 2. Restructure first, then change

The stages meet this pattern every time a change needs a shape the tree does not yet have. The pattern has two PRs, and the order is the point.

**PR one changes the shape and nothing else.** Files move, kustomizations are regenerated, a patch appears that says exactly what the base already said. The test is mechanical: **render every root the fleet consumes before and after, and the outputs are byte-identical.** The PR is typed `refactor`, its body says which roots were compared and that the diff was empty, and the reviewer reads that claim, checks the receipt, and approves a change whose whole content is "the cluster will not notice". [Stage 13 step 2](../act-4/stage-13.md#2-restructure-base--class-overlays-version-pinned-per-class) is the clearest instance: the baseline is captured in step 1, the restructure is compared against it for all four roots, and only then does anything rebind.

**PR two, and every PR after, makes the change in the new shape, riding the ladder.** In stage 13 that is a binding move per rung, then a version bump per rung, each on the previous rung's evidence. Each of those PRs asks its reviewer one question, "is this value right for this rung", and never "did the move break anything", because that question was answered and closed a PR ago.

Why the order matters:

- **One question per review.** A PR that moves files and changes a value has two questions and one diff, and the second question hides inside the noise of the first. Split them and each review is short and exact.
- **The revert is clean.** Reverting the value change never reverts the shape, so a rollback is one rung's worth of change and not a re-restructure. The two-parent merge ([the git policy](git-policy.md)) is what makes the revert land on exactly one of the two.
- **The proof is mechanical.** "Byte-identical renders" is a diff of two files, not a reading of YAML. The reviewer's job on PR one is to confirm the receipt exists and covers every root, and that is a job a tired reviewer can still do.
- **The change then has a ladder to ride.** The shape exists so the value can enter at one rung and climb. Change the value in the same PR that creates the rungs and it has reached every class before the ladder existed.

**The receipt is a before-file.** Capture the live thing before the change and again after, and diff the two: a render to a file (stage 11 keeps `/tmp/dev-before.yaml`), a release revision per cluster (stage 13 keeps `/tmp/infra-revisions-before.txt`), a status sequence (the checkpoints). Never by eye, and never from memory of what it looked like. How the receipt is produced, in the course's own idiom: render each consumed root to a file before the change, render again after, `diff` the pairs, and paste the result under the PR's Evidence heading. The rendered-diff comment ([stage 12](../act-4/stage-12.md)) does this for you when a root already existed on both sides; when the restructure creates a root, the comment shows the new root as pure additions and the old root unchanged, so the local diff against the baseline is the proof and the comment is the corroboration. Stage 13's step 2 says which is which.

The pattern recurs. [Stage 02](../act-1/stage-02.md) lifts flat manifests into base and overlays with a checkpoint that asserts on the render. [Stage 08](../act-3/stage-08.md) re-authors hand-written files through their owning tool and shows the apply is a no-op. [Stage 11](../act-4/stage-11.md) reformats the whole tree and proves both overlays render byte-identical before the commit. [Stage 13](../act-4/stage-13.md) restructures the infrastructure tree, then moves three bindings, then bumps three pins. The migrate-base-config quest makes the pattern a lifecycle, with the migration overlay as PR one's home ([rule 5.14](../rules.md#514-variants-flags-and-migrations-three-lifecycles-three-homes)). Once you can see it, most "risky" config changes decompose into a refactor with an empty diff and a value change with a rung.

## 3. Base is sacred

Base is the part of every render that reaches every cluster of every class at once. There is no rung to gate it on, no overlay to soak it in, no cluster that gets it first. So the rule for base follows from the ladder rather than from caution: **base accepts only changes whose rendered diff is empty** ([rule 5.4](../rules.md#54-the-ladder-is-a-practice-not-a-mechanism), third corollary).

What that permits, concretely:

- **Absorption.** A change entered as an overlay patch on one rung, promoted rung by rung, and once every rung renders it identically it is folded into base and the overlays' copies removed. The base edit's rendered diff is empty by construction, because the overlays already said everything it says. That is the acceptance test, and it is the *only* legitimate way a new value reaches base.
- **Retiring a pin nobody reads.** Stage 13's last PR deletes the chart version from base's HelmRelease, after the last binding has left the old root. Every overlay patch supplies its own version, so no root any cluster consumes renders differently, and the comment says so. Doing it in the same PR as the re-bind is not safe, even though the end state is identical: a re-pointed stamp reconciles the new commit under its old path once before the binding lands, and base with no version is "latest" for that reconcile.
- **Adding what does not render.** A comment, a file the kustomization does not include, a reordering the emitter normalises. Empty diff, so allowed, and the gate rather than a person decides.

What it forbids: a value change, a new resource, a changed default, however small and however "obviously safe". Each of those reaches every cluster at once and skips the ladder. The tell is simple: **a base PR whose rendered diff is not empty is a promotion skipping the ladder, wearing a refactor's clothes.** A new resource enters the same way a new value does, as an overlay resource on one rung, promoted, then absorbed.

**The temptation, and what it costs.** The change is one line, it is obviously safe, the ladder would take three PRs and two soak windows, and it is Friday. Landing it in base directly is the shortcut every team takes once, and the reasons it costs more than it saves are specific:

- **The classes are not the same cluster.** Platform, dev and prod run different Kubernetes minors by design ([rule 4.3](../rules.md#43-the-version-policy-follow-the-authority-at-the-pace-kubernetes-sets)), different admission policy (prod's is stricter from stage 23 on), and different chart versions mid-bump. A manifest that is valid on dev's minor can be refused on prod's; a field that prod's policy forbids is one dev's allows. The ladder exists to find that on the rung that tolerates it.
- **Something else is on the ladder.** A chart bump soaking on platform, a release soaking on dev. A base change that lands everywhere at once meets each of those mid-flight, and when a rung goes red there are now two candidates and no way to tell which. The ladder keeps one change in motion per rung so the evidence stays attributable ([pattern 8](#8-one-change-in-flight-per-rung)).
- **There is no control group.** When a change reaches every cluster in the same minute, the healthy cluster you would have compared against does not exist. On the ladder the rung below is always the last known good.
- **No soak means no evidence.** Convergence is one signature and a clean window is the other ([rule 5.7](../rules.md#57-converged-is-not-working)). A base change has neither, on any rung, so promotion evidence for it is not late, it is absent.
- **The revert is fleet-wide too.** Undoing a base change reconciles every cluster again at once, which is the same exposure in the other direction, at the moment you are least sure what is wrong.
- **The record lies.** "What changed prod today" is answered by a commit that also changed everything else, and the audit query that finds prod's changes ([the compliance evidence map](compliance-map.md)) cannot separate them.
- **The first exception ends the rule.** After it, "small" is a judgement, and every base PR argues it is the small kind.

The reviewer's protocol for any PR touching `base/`:

1. Read the rendered-diff comment before the YAML. If it is empty on every root, the PR is what it says. If it is not, stop; the question is now "which rung should this enter at", and the answer is never "all of them".
2. Check the PR body names the roots compared. A receipt that covers one overlay is not a receipt.
3. Expect `refactor` as the type. `feat` or `fix` on a base PR is the author telling you they think the render changed, and `base-gate` refuses it on that alone.

The controls that hold this without a reviewer's memory: the rendered diff on every PR ([stage 12](../act-4/stage-12.md)); `base-gate` ([stage 21](../act-5/stage-21.md)), a required check that refuses a base change unless every root some cluster consumes renders byte-identical and the title's type is one that renders empty, so the protocol above is what the reviewer confirms rather than what they compute; the base rows in `path-gate` and the owners on them, and the ladder's own vocabulary, where a base edit is never `promote` because there is nothing to promote to. The migrate-base-config quest adds the last piece, an age budget on the overlay that stages a base change, so an absorption cannot stall halfway and leave a value living in two places.

The first three in one line: keep the shape, change the shape only with an empty diff, and let nothing but an empty diff into the part of the shape that has no rung.

## 4. Promotion is a pointer move

**Every ascent is one line that re-points at an artifact that does not change.** An image tag in the dev overlay ([stage 07](../act-2/stage-07.md), moved by the robot at [stage 14](../act-4/stage-14.md)); a chart version in a class overlay's patch ([stage 13](../act-4/stage-13.md)); a stamp's `spec.path` when a binding moves rung ([stage 13](../act-4/stage-13.md)); a Kubernetes minor in `clusters/versions.yaml` ([stage 16](../act-4/stage-16.md)); later a release channel's pointer. The artifact, the image, the chart, the tree, was built and reviewed once; what climbs is the reference.

Why it holds:

- **The diff is one line, so the review is one question.** The rendered-diff comment on a promotion shows one changed value per root, and a reviewer reads it in seconds.
- **The revert is one line.** Re-point back and the rung is where it was, with nothing rebuilt.
- **The evidence attaches to the artifact, not the copy.** A tag that soaked on dev is the same bytes on prod, so dev's clean window is evidence about prod's future, which is the whole premise of the ladder ([rule 5.7](../rules.md#57-converged-is-not-working)).
- **The vocabulary falls out.** `pin` is a pointer arriving, `promote` a pointer climbing, `bind` a pointer to a tree moving ([the commit convention](commit-convention.md)); each is a one-line change with a type that says which.

What enforces it: nothing forbids a promotion that also edits the artifact, but two things make it visible. The rendered diff shows more than one line, and the commit convention refuses `promote` for a change that does more than move a pin (rule 3 of the convention's nine).

## 5. Read it, never retype it

**Every fact has one home, and everything else derives from it.** The kustofmt pin is read off `clusters/versions.yaml`, never typed into the gate ([stage 11](../act-4/stage-11.md)). CI installs kustomize from the same file ([stage 12](../act-4/stage-12.md)). The class overlays' version is read off base with one `yq` line, so the parity gate cannot fail on a typed digit ([stage 13](../act-4/stage-13.md)). `slo-gate` reads the target from the SLO rule in git, so the promise lives in one place. Stage 12's render roots are derived from the bindings rather than listed, so they follow the fleet through every restructure.

Why it holds: a second copy is a second authority, and the moment the two disagree nobody knows which one the fleet believes. Stage 13's last rung says it in passing when it deletes base's version: "a pin there would be a second authority nobody reads." The same logic retires a hand-kept list of roots, a version in a README, a target in a dashboard.

What enforces it: the parity gates ([rule 4.1](../rules.md#41-the-render-rule-one-authority-per-tool-and-kubectl-never-renders)) catch two copies of a pin drifting apart; `base-gate` catches base and an overlay both supplying a value; and the paste blocks are written so a value appears once, in a variable read from its file.

## 6. Retire in two steps

**Stop reading a thing, then delete it. Nothing is removed while something still points at it.** Stage 13 deletes base's chart version in a PR of its own, after the last binding has left the old root. [Rule 5.4](../rules.md#54-the-ladder-is-a-practice-not-a-mechanism) keeps "base absorbed it" and "the overlays' references are gone" as two steps on purpose. Act V drains `secrets/` by turning each file into a pointer before the file goes ([stage 20](../act-5/stage-20.md) is where the pointer's decay is measured). The migrate quest makes a migration overlay a null-op, proves it, and only then deletes it.

Why it holds:

- **Each step has an empty diff or a one-line diff.** "Stop reading" is a pointer move (pattern 4); "delete" is then a refactor with an empty render (pattern 2). Merged into one PR they are a change whose render moves in a way no reader can predict from the diff.
- **The revert of either step is safe.** Reverting a deletion that nothing read restores a file nothing reads. Reverting a deletion that something still read restores a broken reference in between.
- **The register stays countable.** `secrets/` is emptied file by file, each one converted first, so `find` on the folder is the debt at every moment ([rule 3.2](../rules.md#32-folder-convention-everything-has-a-place)).

What enforces it: `base-gate` refuses the deletion from base while a consumed root still renders it; `revert-gate` refuses a secret's pointer moving backwards; and the migrate quest's age budget stops the first step from stalling before the second.

## 7. Three verdicts, not two

**A gate that cannot judge says `SKIP`, and a `SKIP` is never a `PASS`.** `dora`, `detect-time` and `slo-gate` say SKIP before the hub exists ([stage 09](../act-3/stage-09.md) brings it), and each says where the judge arrives. The kustofmt parity gate said SKIP before the pin existed ([stage 11](../act-4/stage-11.md)). `freeze-gate` with no calendar says OK and names the file ([stage 27](../act-6/stage-27.md)). The era-aware checkpoints report which IOU is outstanding rather than failing a stage that has not paid it yet ([rule 5.3](../rules.md#53-the-iou-pattern-do-it-the-wrong-way-loudly)).

Why it holds:

- **Absence of a judge is not a green.** Promotion needs two signatures ([rule 5.7](../rules.md#57-converged-is-not-working)); before the SLO exists there is one, and the gate must say so rather than wave the rung through.
- **A FAIL for a missing judge trains people to ignore FAIL.** A gate that is red for three stages because its input does not exist yet is a gate nobody reads by the fourth.
- **The verdict names the era.** "SKIP: no SLO in git yet, lands at stage 09" tells a rebuilt repo exactly where it stands, which is what lets `act-N-drill` run any checkpoint against any state.

What enforces it: the gate family's own convention ([rule 5.9](../rules.md#59-gates-not-checks---and-ci-is-a-backstop-that-never-fires)): `PASS`/`FAIL`/`SKIP` lines, each with the reason, exit 0 on SKIP, and a reader who treats SKIP as a to-do rather than a result.

## 8. One change in flight per rung

**A rung carries one change under evaluation at a time.** Stage 13 moves one binding per PR and bumps one pin per PR, each on the previous rung's evidence. Stage 07's first promotion waits for dev's green before prod's PR is opened. Stage 09's soak window is the time a rung spends with one candidate and nothing else moving. The image robot works on one standing branch, so it holds one open PR at a time ([stage 14](../act-4/stage-14.md)).

Why it holds:

- **A red has one candidate.** Two changes landing on a rung inside one window and a red between them is an incident with two suspects and no evidence that separates them.
- **The soak window is about one thing.** `slo-gate` judges a window as evidence for the candidate on the rung; two candidates in the window and the clean window belongs to neither.
- **Batching is a decision, not an accident.** When two changes must move together, they move as one PR with one title, and the evidence is about the pair. A release channel's waves make that explicit at scale.

What enforces it: honestly, little. `slo-gate`'s minimum soak refuses evidence gathered before the candidate arrived, the robots' fences keep two robots off one rung, and the freeze holds a rung still. The rest is the discipline of opening the next PR after the last one's window, which is why this is a pattern and not a rule.

## 9. Follow the authority, at every layer

**The platform tracks each of its authorities inside that authority's skew window, and so does everything that runs on it.** [Rule 4.3](../rules.md#43-the-version-policy-follow-the-authority-at-the-pace-kubernetes-sets) states it for the platform: Flux follows the AKS extension, kustomize follows the controller, Kubernetes climbs the class ladder one minor at a time, each class at most one minor from the next, which is the N plus or minus one window Kubernetes itself supports between components. The pattern is that the same discipline applies at every layer above:

- **The controllers on the platform** track the Kubernetes APIs they use. Flux, the policy engine, the secrets operator and the ingress each publish which minors they support, and each rides the ladder as a chart bump by PR with a rendered diff ([stage 13](../act-4/stage-13.md), Renovate at the platform rung), soaked on the rung whose Kubernetes minor is newest before it meets the one that is oldest ([stage 16](../act-4/stage-16.md)).
- **The workloads on the controllers** track the APIs *they* use: the runtime and its SDK, the base image, the cloud and third-party APIs with versioned contracts that deprecate on a calendar nobody in the config repo controls. The half of this that lives in the app repo takes the same shape with the same tool: pin the SDK and the base image, take the robot's bump through the app's own CI, and let the new tag arrive at dev by the robot. That repo is outside this course's stages, which is why the pattern is stated here rather than taught there.

Why it holds:

- **The skew window is where the tests were run.** Every tool tolerates a bounded version difference from what it talks to, and inside that window is the only place its maintainers tested. Following the authority keeps every pair in its window at all times; chasing latest at one layer pushes a neighbour out of its window silently.
- **One ladder serves every layer.** The class ladder built for Kubernetes minors is the same three rungs a chart bump, a controller upgrade and an SDK bump climb. Building the discipline into the platform once, as pins, parity checks and a promotion order, means every layer above inherits it rather than inventing its own.
- **Drift is silent and cumulative.** A layer that falls two versions behind its authority does not fail; it stops being upgradeable in one step, and the catch-up is the risky change the ladder exists to avoid. The scheduled parity check exists so that drift surfaces without anyone remembering to look.
- **The cloud enforces it anyway.** Managed Kubernetes supports a fixed window of minors; a fleet practised at next, current and stable arrives inside that window ([rule 4.3](../rules.md#43-the-version-policy-follow-the-authority-at-the-pace-kubernetes-sets)), and the same is true of every managed API a workload calls.

What enforces it: `scripts/check` and the parity gates for the platform's pins, `check-version-ladder` for the class spread, the scheduled `check-flux-aks-parity` for drift against the authority, Renovate for the controllers, and the ladder for all of them. The workload layer's enforcement is the app repo's, and it is the same tools.
