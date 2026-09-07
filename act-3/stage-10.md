# Stage 10 - The four numbers (DORA, per cluster and per tenant)

[← 09 - Fleet observability](stage-09.md) · [Walkthrough index](../README.md)

> **Where you are:** the root of the config repo, on `main`. **Starting state:** 09 complete and the fleet live. If it isn't, the previous act's `act-2-drill` rebuilds it from git (git is at HEAD, so everything since comes back with it). **Why here:** stage 09 built the store this stage reads: the hub has been recording stamp revisions and workload generations since it came up, so the first run already has real history in it - stage 09's drills included, counted honestly as changes and incidents. The commit end of lead time comes from git, not from retention, so it reaches back further than the hub does. Gains a per-tenant dimension at stage 22 and loses nothing without it.

**Goal:** Act I already claims these numbers. [Stage 03](../act-1/stage-03.md) calls a rollback "your first DORA lead-time data point"; [stage 04](../act-1/stage-04.md) calls the break/revert pairs "your first change-failure-rate and MTTR data points (DORA #3 and #4)". Three metrics named, one never mentioned, and **nothing anywhere computes them**. This stage pays that debt: all four, over a window, from artifacts, **scoped to production, because that is what DORA measures**, with everything else available as a labelled diagnostic rather than as four more readings someone will quote.

The rule is the one the checkpoints already run on: **no stopwatch anywhere** ([rule 5.8](../rules.md#58-no-stopwatch-anywhere)). A DORA number you typed into a spreadsheet is a claim; one derived from what the fleet recorded is evidence. That distinction is most of the value.

Terminology reminder: a *stamp* is a Flux `Kustomization` CR; a *rung* is a step on the promotion ladder.

## The number that lies

Start with the obvious query, because getting it wrong is the lesson. Flux exports `gotk_resource_info` for every stamp, and its `revision` label is the commit that stamp applied. So deployment frequency is "how often did `revision` change", right?

```sh
./scripts/dora --window 7d
```

The report answers on its last line, and the two ends of it are the lesson (your numbers will differ; the shape will not):

```
reconciles   63 stamp revision changes across all rungs produced 2 production
             application(s), which are 2 distinct change(s). Reconcile is not
             change, and an application is not a deployment.
```

**An order of magnitude too many.** Every cluster reconciles every commit, which is what a shared source *means*, so a stamp's `revision` advances on every push, including the docs commit that changed nothing it renders. Count those and the fleet reports a deployment rate an order of magnitude above what it actually shipped. The rest of this stage is how the script gets from the first number to the last one.

This is not a new lesson; it is [stage 07 §4](../act-2/stage-07.md#4-promotion-is-a-pr-that-moves-a-pin)'s **reconcile scope is the repo, change scope is the paths a commit touched**, arriving as a wrong number instead of a paragraph. It is also, in the wild, the single most common way this metric gets faked: it is trivially easy to compute, it is always flattering, and nobody checks.

## The two signals

The fix is to ask a question the *workload* can answer:

| Signal | Metric | Answers |
|---|---|---|
| the **stamp** | `gotk_resource_info{name,cluster,revision,ready}` | what Flux applied, and whether it held |
| the **workload** | `kube_deployment_metadata_generation{cluster,namespace,deployment}` | whether the spec actually changed |

A Deployment's `metadata.generation` increments **only when its spec changes**. A no-op reconcile leaves it alone. So:

| DORA metric | Derived from |
|---|---|
| **Deployment frequency** | generation increments per day |
| **Lead time for changes** | commit authored → the generation increment that carried it |
| **Change failure rate** | sustained not-Ready stamps ÷ deployments |
| **Time to restore service** | how long a sustained not-Ready lasted |

Both numbers stay on screen, because the gap between them is the finding.

## Two definitions to get right before any code

DORA's four metrics are **production** metrics. Every one of the definitions says so: how often you release *to production*, how long a commit takes *to reach production*, how often a *production* change fails, how long *production* takes to recover. That has two consequences a fleet makes sharp, and both are easy to get wrong in a way that flatters you.

### The unit is the change, not the application of the change

One commit that reaches fifty tenants is **one deployment**. Counting the fifty applications makes deployment frequency scale with *customer count*: onboard a customer, look 2% more elite. It is the same class of error as counting reconciles, one level up. Same for failure: a bad commit that breaks fifty tenants is **one failed change**, not fifty.

So `scripts/dora` groups production deployments **by revision** before counting anything, and the report says which is which:

```
reconciles   81 stamp revision changes across all rungs produced 5 production
             application(s), which are 5 distinct change(s). Reconcile is not
             change, and an application is not a deployment.
```

Three numbers, narrowing: what the fleet *reconciled*, what production *applied*, and what actually *shipped*. On a single-tenant fleet the last two are equal, which is exactly why this is worth fixing before [stage 22](../act-6/stage-22.md) makes them differ: the bug is invisible until the day it is large.

### Lead time is a feedback measurement, so it ends at the *first* production arrival

**Production is the last rung of the ladder**: whatever `--production` selects, and in this course that is the `prod-*` clusters. Not a cluster name, a *rung*: the place a change stops climbing.

And the metric ends the moment a change **first** lands there. Not the last tenant, the first.

That is a claim about what lead time is *for*. DORA's lead time measures the **feedback loop**: how long after committing does a developer learn whether the change was any good. That signal exists as soon as the change is running in production and serving real traffic: the fiftieth tenant tells the developer nothing the first one didn't. Waiting for the slowest tenant measures something else entirely, and something largely outside engineering's control: one customer's change-freeze window, one region's maintenance calendar. Mixing those into a metric about *delivery capability* makes it unusable for the only thing it is good for, which is watching your own pipeline get faster.

So the fastest arrival wins, and that is not a loophole: it is the measurement.

**"When is everyone safe?" is a real question and it gets its own number**, because conflating the two loses both:

```
  lead time for changes  median 10m    p95 10m     commit -> production, first arrival
  convergence  median 40m from the first production unit to the last (p95 40m),
               over 1 change that finished rolling out. This answers "when is
               everyone safe" - a real question, and deliberately NOT lead time.
```

Two numbers, two owners. Lead time is the pipeline's; convergence is the fleet's. A 10-minute lead time with a 40-minute convergence is a healthy pipeline in front of a slow rollout, and you would never see that if you added them together and called the total lead time.

### From where, to where - exactly

Vagueness here is how two teams compare lead times that measure different things. State the endpoints:

| | Endpoint | Artifact it comes from |
|---|---|---|
| **from** | the commit the production stamp applied | `gotk_resource_info{revision}`, joined to `git log` |
| **to** | that change first running on the production rung | `kube_deployment_metadata_generation` incrementing |

One structural fact sits inside that join, and everything evidence-shaped in this course leans on it: **nothing propagates from CI into the fleet: the revision is the join key.** No identifier travels from the commit through the controllers to the pod; each register (git, the stamp, the workload) records its own view independently, and every cross-register question is answered by joining those views on the revision each one recorded: this stage, [stage 26](../act-6/stage-26.md)'s change record, the promotion evidence. Which is why the endpoints must be stated this precisely: a join key you did not define is a join you cannot defend.

Read the **from** row again, because it is almost certainly not what you assumed. The commit the *production* stamp applied is the **promotion**: the commit or merge that moved the prod pin. It is **not** the dev commit, and it is **not** the app's source commit. The headline lead time therefore covers **merge-to-production and nothing else**, which on an automated fleet is minutes, and which is the least interesting interval in the whole chain.

Here is what that hides, from this repo's own history:

```
one real change, version 0.1.1-run20260812163232

  dev pin committed      2026-08-12 16:35
  promotion PR opened    2026-08-19 13:40   -> soak/wait  6d 21h 5m
  promotion PR merged    2026-08-19 13:51   -> review        10m 16s

  what the headline reports:  2m
  full commit-to-production:  6d 21h 16m
```

**Three orders of magnitude.** The pipeline was never the problem, and a metric that only measures the pipeline would have told you it was fine for a week.

This matters because it is what DORA is *for*. The four metrics exist to expose the inefficiency of the process, not to celebrate the automated part of it, and the automated part is exactly the part that is easy to measure, which is why so many implementations stop there.

### `--stages`: where the lead time actually goes

```sh
./scripts/dora --window 30d --stages
```

```
  change                         dev->PR      review merge->prod       TOTAL
  -------------------------  ----------- ----------- ----------- -----------
  0.1.1-run20260822213701            21m          3s          2m         23m
  median                             21m          3s          2m         23m
```

| Stage | From → to | What it tells you |
|---|---|---|
| **dev→PR** | the `pin(app-dev)` commit → the promotion PR being opened | Soak if deliberate, queue time if not, **and the two are indistinguishable from here**, which is why it is worth watching rather than assuming |
| **review** | PR opened → PR merged | Wall clock, so it includes waiting *for* a reviewer, usually the larger half, and the one a team can actually shorten |
| **merge→prod** | PR merged → running on prod | The only interval the headline covers |

The four numbers above needed none of this: they are metric samples and commit timestamps looked up by sha, and nothing in [Part 2 of the rules](../rules.md#part-2---the-change-record) was involved. This breakdown is where the convention starts to pay.

**Yes, PR review time is capturable, and precisely**: `gh pr list --json createdAt,mergedAt,mergeCommit` gives it to the second. The hard part was never the timestamps; it was the **join**. Linking a production deployment back to the dev commit that started it means recognising that two commits in different weeks describe the same change, and [the commit convention](../appendices/commit-convention.md) is what makes that a query rather than a guess:

```
pin(app-dev):     app 0.1.1-run20260822213701
promote(app-prod): app 0.1.1-run20260822213701
```

Same version token, two grammatical subjects, one join key. The diff carries the same tag, in `newTag` on each overlay, but reading it means parsing every promotion's diff against every pin's; the author and the timing say nothing. The subject makes the join one regex over one line. **This is the convention paying for itself in a way that would have been very hard to argue for in advance**, and it is worth noticing that the payoff arrived two acts after the discipline did.

### What is still not measured

The chain starts where the version *arrives in the config repo*. Everything before it lives in the **app repository** and is invisible here:

```
app source commit → CI build → image pushed → [ pin(app-dev) ← this tool starts here ]
```

That is a real gap, not a rounding error: CI build time and the wait for a registry scan ([stage 15](../act-4/stage-15.md) attacks the second) both sit in it. There is a second way to close it, and it closes the fragile join at the same time: **emit the chain as [CDEvents](https://cdevents.dev/)**. The vocabulary covers every boundary this section measures: `change_created`, `change_reviewed`, `change_merged`, `service_deployed`, `incident_detected`. And `context.chainId` carries the correlation that the version-token join reconstructs by hand. Two things stop that being the answer today: almost nothing emits them ([stage 15](../act-4/stage-15.md) shows Flux receiving and not emitting), and an event stream can only measure from the day you switch it on, whereas the numbers above were computed from history that predated any of this. **Events for correlation and timeliness; artifacts for truth and retroactivity**, the same trade stage 15 makes between push and poll, one level up. Closing it is mechanical rather than clever: the pin carries the image tag, the app repo tags releases with the same string, so `git log -1 --format=%ct <tag>` in the app repo is the true origin. The script names the gap instead of quietly starting the clock late, because **a lead time whose start point is undocumented is not comparable to anyone else's**, including your own from last quarter.

## Gaming this, deliberately and by accident

The point of the previous section is worth generalising, because the temptation when designing a metric is to make it hard to cheat, and that instinct produces metrics nobody can act on. **These four numbers are for you.** Gaming them is cheating yourself out of the only thing they provide, which is an honest view of whether your delivery is getting better. So the design here optimises for *meaning*, not for tamper-resistance.

Which puts the responsibility somewhere specific: **know what you are actually measuring.** Deliberate gaming is a management problem and mostly self-solving. Inadvertent gaming is the real hazard, because the numbers improve and nobody notices why:

| What happens | Why the number improves | What is actually true |
|---|---|---|
| **The first production tenant is a canary that takes no real traffic** | Lead time ends when a change reaches somewhere nobody uses | You are measuring a deploy to nobody. This, not the choice of first-vs-last, is the honest reason to care about which tenant is first. A canary must be *production*: real users, real traffic, real consequences ([stage 22](../act-6/stage-22.md) makes `house` the dogfood tenant precisely so it is) |
| **One logical change split across many commits** | Deployment frequency rises | Batch size did not change. Frequency is a proxy for small batches, and the proxy is easy to satisfy without the property |
| **Lead time measured from the merge commit** | Review and queue time vanishes from the number | The wait was real; you moved where the clock starts. This script reads the revision the cluster applied, so under merge-commit-only the clock starts at the merge. **Say so** rather than implying it covers review |
| **Long-lived branches** | Or the opposite: lead time looks terrible | Measured from the authoring commit, a two-week branch is a two-week lead time. That is arguably the correct signal, since DORA's findings favour trunk-based development, but it is a *branching* result, not a *pipeline* one, and reporting it as pipeline slowness sends people to fix the wrong thing |
| **Failed deployments excluded from frequency** | Both frequency and CFR improve at once | The most common accidental fraud in the set, and the giveaway is two metrics moving the right way together for no reason |
| **The robot re-pins an unchanged image** | Frequency rises with no change at all | Deduplicated here by revision, but worth knowing it is the failure mode automation introduces |

**Three rules that follow.** Publish the denominator, so a number built on five changes announces its own weakness. Never make these targets: a metric that is bonused is a metric that will be met, and DORA's own guidance is emphatic that they are diagnostics rather than goals. And when a number moves sharply, look for a change in *how it was measured* before believing a change in how you work.

## Partitioning is a diagnostic, not a metric

There is exactly **one** deployment frequency, and it is production's. So the default output is one block of four numbers, and everything else is explicitly labelled as something other than DORA:

```sh
./scripts/dora --window 30d                  # the four numbers. Production only.
./scripts/dora --window 30d --by tenant      # which customer is moving them
./scripts/dora --window 30d --rungs          # dev and platform - NOT DORA
```

```
DIAGNOSTIC - within production, by tenant. Not four more DORA readings: the metric
is the fleet number above, and this says which tenant is moving it.

  tenant          applied    lag (med)    lag (p95)
  acme                  1          10m          10m
  beta                  1          50m          50m

  applied = per-unit applications, NOT deployments. One change reaching every
  unit is one deployment; these rows sum to more and must never be added up.
```

Note the column is `applied`, not `deploys`, and the footnote forbids summing it. That is deliberate: **a partitioned view whose rows look like the headline metric will be added up by someone**, and the sum will exceed the real deployment count by the tenant multiplier.

Non-production rungs are available and labelled harder still, because dev lead time *is* a useful number: it is the feedback-loop number, and it tells you whether your inner loop is fast. It simply is not DORA. Publishing them in the same table is how "we deploy 60 times a day" ends up in a slide deck describing a fleet that ships five changes a week.

### The roll-up rule, for when you do aggregate

Wherever you legitimately combine partitions, one rule prevents the most common dashboard error:

> **Counts sum. Rates and percentiles do not, and neither rolls up from the summaries.**

Take two tenants at 1 failure in 1 change (100%) and 2 in 5 (40%). The mean of those rates is 70%; the actual rate is 3 in 6: **50%**. Averaging weights a tenant with one change identically to one with a thousand. It is Simpson's paradox with a dashboard in front of it: the name for the fact that a comparison can hold inside every group and still flip when the groups are pooled, because pooling re-weights each group by its size. (The textbook case is a drug that beats placebo in men and in women separately, and loses in the combined table.) The defence is the rule above, applied both ways: aggregate the events, never the rates. Percentiles are worse: a median of medians is not a median, and a p95 of p95s is not anything at all.

So `scripts/dora` recomputes every view from the **raw samples** and never lets one summary become the input to another. `--by` re-runs the whole computation. That is not inefficiency; it is the only way the numbers agree with each other.

**And always publish the denominator.** "CFR 40%" is a rumour. "2 incidents in 5 changes over 7 days" is a measurement, and it tells the reader immediately that the sample is too small to steer by, which the script also just says.

## What contaminates each number

Every one of these was met live in this course, which is why the script names them rather than hiding them:

| Contaminant | Effect | What the script does |
|---|---|---|
| **The `DependencyNotReady` cascade** ([checkpoint drill 3](act-checkpoint.md)) | Every push marks dependent stamps `Ready=False` for one scrape. Naively, **every commit is a failed deployment** | Discards not-Ready runs shorter than `--sustain` (90s default), the same duration-not-colour discriminator `detect-time` uses |
| **No-op reconciles** | 10× inflated deployment frequency | Counts workload generation, not stamp revision |
| **Prometheus' 11,000-point cap** | A 30-day window forces a coarse step; short events vanish | Scales the step to the window and **warns when it exceeds the sustain filter**, calling the counts a floor |
| **The laptop was shut** | An overnight break gives a 19-hour MTTR that measures your sleep | Nothing, and it should not. The number is real; the *system* was down. Say so in the report rather than filtering it |
| **Prometheus retention** | `--window 30d` against a 10-day retention silently reports a *quieter* fleet, not a shorter one: the rate is divided by 30 days of which 20 hold no data | Compares the first sample against the requested start, prints a `RETENTION` line, and **recomputes the rate over the span actually covered** (on this fleet that was the difference between 0.71/day and 2.05/day) |
| **Tiny n** | A median over 1 deployment is that deployment | Prints the count beside every derived number |

That last pair matters more than it looks. **DORA is a trend instrument, not a spot reading.** On a fleet this size a single drill moves every number, so the honest use here is *watching the shape change as you improve the pipeline*: the acts ahead each move one of these four, and now the movement is measured.

## What these numbers cannot tell you

State this next to the dashboard, or the dashboard will be misread:

- **Deployment frequency is not throughput.** A robot re-pinning the same image nightly scores well and ships nothing.
- **Lead time here is deploy lead time**, commit → running. DORA's fuller definition starts at *code committed*, which for an app change starts in the app repo, one CI build earlier. The course measures the half it can prove; say which half you are quoting.
- **Change failure rate counts what the health gate caught.** [Stage 09](stage-09.md)'s plausible bad release passed every check and still degraded the service: it is invisible here and visible in the SLO. **CFR measures your gates, not your quality**, and a suspiciously low one usually means weak health checks rather than good engineering.
- **None of them is a target.** Measured, they inform; targeted, they get gamed within a sprint: smaller commits to raise frequency, reclassified incidents to lower CFR. Publish them; do not bonus them.

## Stop & measure

- [ ] One block of four production numbers with its denominator, and the reconciles → applications → changes line narrows in that order (step 4 shows the shape):

```sh
./scripts/dora --window 7d
```
- The lead time is **commit → first production arrival**, and `convergence` is a separate line. With one production tenant you cannot tell them apart; with two you can. Add a second production tenant ([stage 22](../act-6/stage-22.md)) and confirm that one change reaching both counts as **one** deployment, with a lead time equal to the *faster* arrival and a convergence figure covering the gap.
- `--by tenant` reports a column called `applied`, not `deploys`, and its rows sum to more than the deployment count. Confirm you can explain why that is correct.
- `--rungs` shows dev and platform labelled as **not DORA**. If you ever quote a number from that block as a DORA metric, the label is there to stop you.
- `--stages` traces at least one change back past its promotion, and its `TOTAL` is visibly larger than the headline lead time. If it traces none, read the message: it means promotions are not going through PRs, or the subjects cannot be parsed, and both are worth knowing.
- You can state, in one sentence each, where the headline clock **starts** and where it **stops**, and name one interval it excludes.
- A deliberate break followed by a revert moves CFR and time-to-restore in the direction you predicted, and you can say which sample it landed in.

Tag the boundary ([using the course §5](../using-the-course.md#5-tags-at-every-boundary)):

```sh
git tag stage-10 \
&& git push origin stage-10 \
&& gh issue close 13 --comment "stage-10 tagged"
```

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `the hub rejected the query: exceeded maximum resolution of 11,000 points` | Window too long for the step | The script scales the step itself; if you overrode `DORA_STEP`, lower the window or raise the step |
| Every row shows `local-01*` with an asterisk | The hub scrapes its own metrics **locally**, and `externalLabels` are attached on **remote-write only**, never to local queries, so the platform cluster arrives with no `cluster` label | Expected. Either accept the naming, or relabel at scrape time on the hub's own jobs. Do not "fix" it by dropping the series, which is how a cluster disappears from a fleet report |
| CFR is 100% and you did not break anything | `--sustain` lower than the cascade's clear time on a slow machine | Raise `DORA_SUSTAIN`; the cascade clears in one retry interval, a real failure does not |
| `deploys` is 0 but the fleet clearly changed | The commits changed nothing the workload renders | Correct, and the point of the whole stage |
| Lead times are missing for some deployments | The applied revision is not in this clone | `git fetch`; the script excludes rather than guessing |

## What you learned

**A metric that is easy to compute is the one most likely to be wrong**, and on a fleet it is wrong twice, at two different levels. Counting stamp *reconciles* over-reports deployments tenfold, because every cluster reconciles every commit. Counting per-tenant *applications* over-reports them by the tenant multiplier, because one change reaching fifty customers is one deployment. Both are the same mistake: measuring the mechanical event instead of the meaningful one, and both produce numbers that flatter you and that nobody checks.

**DORA measures production, so the partition is a diagnostic and not a metric.** There is one deployment frequency. Which tenant is dragging it, and how much of the lead time is fleet rollout rather than pipeline, are the questions you ask *after* the number is bad, and they belong in a block labelled loudly enough that nobody quotes a dev figure as a delivery statistic.

**Lead time is a feedback measurement, so it ends at the first production arrival**: the developer learns whether the change was good the moment it serves real traffic, and the fiftieth tenant adds nothing. Waiting for the slowest tenant would fold customer change-freeze calendars into a metric about your own delivery capability. "When is everyone safe?" is a genuine question and gets its own line, **convergence**, because a 10-minute lead time behind a 40-minute rollout is a healthy pipeline in front of a slow fleet, a distinction that disappears the moment you add them together.

**An undocumented start point makes a lead time incomparable, including to your own, last quarter.** The headline here begins at the *promotion*, which on an automated fleet is minutes from production and is the least interesting interval in the chain. On one real change in this repo it reported 2 minutes for something that took 6 days 21 hours commit-to-production, almost all of it waiting for somebody to open a PR. DORA exists to expose that inefficiency; a metric that measures only the automated hop reports that the automated hop is fine.

**PR review time is capturable to the second: the timestamps were never the hard part.** `gh` has `createdAt` and `mergedAt`. The hard part is the *join*: recognising that a `pin(app-dev)` commit and a `promote(app-prod)` commit two weeks apart describe the same change. The diff holds the same tag but has to be parsed per commit; the author and the timing say nothing. The version token in their subjects links them in one regex, and it is there only because [the commit convention](../appendices/commit-convention.md) put it there. That payoff arrived three quests after the discipline did, which is roughly how conventions always pay.

**Design these for meaning, not for tamper-resistance.** They are yours; gaming them cheats only you. Which moves the real risk from deliberate cheating to *inadvertent* cheating, where the numbers improve and nobody notices why: a canary tenant that takes no real traffic, one change split across five commits, failed deployments quietly excluded. The guard is not a cleverer formula. It is publishing the denominator, refusing to make them targets, and checking whether the *measurement* changed before believing the *work* did.

---

**Next:** [Act III checkpoint](act-checkpoint.md)
