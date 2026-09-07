# The commit convention - a grammar for a config repo

[← walkthrough index](../README.md)

The course's first lesson is that `kubectl apply` leaves no record and a commit does
([stage 01](../act-1/stage-01.md) → [stage 02](../act-1/stage-02.md)). Every audit claim it makes
afterwards rests on metadata git supplies for free: author, timestamp, diff, status. This page adds
the one field git does *not* structure for you, **the subject line**, and states the grammar it
follows here.

This is not a style preference. Three scripts and four checkpoint drills already find commits *by
subject*, and the retrofit that produced this page began with a live bug: drill 4's lookup matched
a `Revert "Break: …"` instead of the break, because a prose subject is a substring, not a key. A
typed subject is queryable. **The convention exists to make the change record machine-readable, and
the readability is a by-product.**

## The shape

```
<type>(<scope>): <description>

<body - why, not what; the diff already says what>

<trailers>
```

Standard [Conventional Commits](https://www.conventionalcommits.org/), with a domain vocabulary,
because this repo's changes are not source-code changes. A config repo does not "add features"; it
pins versions, promotes them, binds clusters, rotates keys and grants access. Types that describe
*application* development would force every real change into `chore`, which is the same as having
no convention at all.

## Types

**Domain types**, the vocabulary of a GitOps config repo:

| Type | Means | Typical subject |
|---|---|---|
| `pin` | A version **arrives** at its entry rung, the automatic half of the ladder | `pin(app-dev): app 0.1.1` |
| `promote` | A change **climbs** a rung by PR, the deliberate half | `promote(app-prod): app 0.1.1` |
| `bind` | Create or re-point a stamp under `clusters/`: the pointer, nothing else | `bind(prod-01): app-prod stamp` |
| `rotate` | A key or secret **value** changes | `rotate(dev): class age key, overlap phase` |
| `access` | The **recipient or reviewer set** changes: who can decrypt, who must review | `access(dev): grant teammate decrypt` |
| `policy` | What is *allowed*: rule files, gate logic, branch protection, CODEOWNERS | `policy(base): require resource limits` |
| `break` | Deliberate failure injection: a game day, never a mistake | `break(app-prod): absent image` |

**Standard types** carry their usual meanings and cover everything else: `feat`, `fix`, `docs`,
`refactor`, `test`, `ci`, `chore`, `revert`.

## Scope is the blast radius

Not a component, not a folder you happened to edit: **what the change can reach**. This is the
same identifier the [alignment rule](repo-leak-posture.md#whichever-you-choose-make-the-identifier-the-same-string-everywhere)
already requires in the stamp name, the namespace, the label, the metric, the alert and the
CODEOWNERS path. The commit subject is its seventh home, and that is the whole point: an alert
naming `app-prod` and a commit scoped `app-prod` need no lookup table between them.

**The registry** lists every legal scope, in resolution order:

| Kind | Values | Use when |
|---|---|---|
| **Stamp** | `app-dev`, `app-prod`, `infrastructure`, `monitoring`, `monitoring-crs`, `cluster-secrets`, `flux-system` | The change reaches exactly what one stamp applies: the most common and the most useful |
| **Cluster** | `local-01`, `dev-01`, `prod-01` | The change reaches one cluster across several stamps: binding moves, cluster facts |
| **Class** | `platform`, `dev`, `prod` | The change reaches every cluster of a class: class overlays, class key scopes, ladder rungs |
| **Tree** | `base`, `overlays`, `clusters`, `infrastructure`, `policy`, `ci`, `hooks`, `scripts` | The change reaches whatever consumes that path, which is usually more than you think: `base` reaches all three classes with no promotion at all |

Note the deliberate collision: **`infrastructure` is both a stamp and a tree.** Rule 8 below resolves it.

## The nine deciding rules

A vocabulary that cannot decide the awkward cases is decoration. These are the cases.

**1. `pin` enters, `promote` climbs.** A version *arriving*, for example a robot moving the dev
image tag or Renovate bumping a chart in the platform overlay, is `pin`. That same version *moving up a rung*,
which is always a PR against evidence, is `promote`. The two types encode the rule that
[stage 07 §4](../act-2/stage-07.md#4-promotion-is-a-pr-that-moves-a-pin) teaches: entry is
automatic, ascent is not. If you can't tell which you're writing, ask whether a human approved it.

**2. The entry rung is per artifact class, not a fixed cluster.** Images enter at **dev** (the
robot's privilege, [stage 14](../act-4/stage-14.md)). Charts and Kubernetes minors
enter at **platform** ([stage 16](../act-4/stage-16.md)): platform is a
*rung*, not merely infrastructure. So `pin(platform): kubernetes 1.35` is correct and is **not** a
promotion to platform; the promotion is the next commit, `promote(dev): kubernetes 1.35`. Get this
wrong and the rule inverts on the page.

**3. `bind` only when nothing but the pointer changes.** Adding, removing or re-aiming a stamp file
under `clusters/` is `bind`. The moment the same commit also edits what that stamp *applies*, it is
no longer a binding change: split it, or type it by the payload. A `bind` commit's diff should be
readable in one screen and touch one folder.

**4. `rotate` is the value, `access` is the set.** Re-encrypting a secret under the same recipients
is `rotate`. Adding or removing a recipient, or changing who must review a path, is `access`, even
when the re-wrap it forces makes the diff look identical. The distinction is the audit question you
will actually be asked: *did the value change, or did the audience?*

**5. `policy` beats `ci` when one commit does both.** A commit that adds a rule *and* wires it into
a workflow is `policy`: the rule is the change, the wiring is delivery. `ci` is for the pipeline
itself: runners, caching, job structure, a workflow that runs an unchanged gate somewhere new.

**6. Never rewrite git's revert subject.** `git revert` composes `Revert "<original subject>"`
itself, and that is machine output: a durable link back to the commit it undoes. Leave it exactly
as git writes it. **`revert(scope):` is reserved for the hand-composed partial revert**: the one
[stage 20](../act-5/stage-20.md) teaches, where you keep secret material moving forward
while rolling the rest back. The split carries weight: a `revert(...)` subject in the log means a
human made a decision about what *not* to undo.

**7. Omit the scope when the blast radius is the fleet.** `policy: forbid :latest everywhere` is
correct with no parentheses. An empty scope is a signal, not laziness, and a scope of
`all`/`global`/`fleet` is banned, because it invites a query for a string that means "no filter".

**8. The registry resolves ambiguity; type breaks the tie.** Any scope must appear in the table
above. Where a name is both a stamp and a tree, **it resolves as the tree unless the type is
`bind`**: `policy(infrastructure):` means the `infrastructure/` folder, `bind(infrastructure):`
means the stamp. One rule, because that collision is the only one, and inventing
`infrastructure-tree` would break the alignment rule that gave scopes their value.

**9. `!` means a revert will not save you.** Conventional Commits uses `type(scope)!:` for a change
that breaks a published API and forces a semver major. This repo publishes no API and computes no
version, so that meaning has nowhere to land, and a marker nobody can decide how to apply is worse
than no marker. It is redefined here, narrowly and operationally:

> **`!` declares that reverting this commit will not restore the previous state.**

Not "this is risky", not "this is large": specifically that the ladder's safety net does not apply,
because the thing the commit changed lives outside git and git cannot put it back. The cases are
fewer than instinct suggests:

| Marked `!` | Why a revert doesn't work |
|---|---|
| A version pin whose rung is **rebuilt** rather than upgraded in place ([stage 16](../act-4/stage-16.md)) | Reverting the pin does not un-rebuild the cluster; the old one is gone |
| A secret rotated **after** its old key was retired ([stage 17](../act-5/stage-17.md)) | A revert restores the old value's ciphertext, which the fleet decrypts and applies: the value the retired key exposed, and for a real secret one revoked at its provider |
| Any change whose old value the **provider revoked** ([stage 20](../act-5/stage-20.md)) | The revert reconciles green onto a dead credential: the failure mode with no error message |

Not marked: anything git can put back. A pin move, a replica count, a binding, a policy rule, a
base edit: all revert cleanly, and marking them dilutes the signal until nobody reads it.

**`!` requires a `Roll-forward:` trailer**, and the gate enforces it. A bare `!` is a warning with
no instruction, which is the least useful thing a commit can carry at 3am; and git-cliff, given no
reason, renders the marker as a duplicate of the subject line. Say what to do *instead* of
reverting:

```
pin(platform)!: kubernetes 1.35

The platform cluster is rebuilt, not upgraded in place.

Roll-forward: pin the previous minor and rebuild again - `CLASS=platform ./scripts/cluster-up`.
              Reverting this commit alone leaves versions.yaml disagreeing with a live cluster.
Refs: #131
```

**And the honest limit, which decides how much weight `!` can carry.** A marker that depends on
someone remembering it is a marker that will eventually be missing, at which point its *absence*
reads as "safe to revert", a false negative worse than never having had it. So `!` is a **declared
annotation, never the control**: [`scripts/revert-gate`](../act-5/stage-20.md) reads
the *diff* for secret material and cannot be forgotten, and it stays the authority. `!` adds the
author's knowledge on top: the cases a path check cannot see, like a cluster that no longer
exists. And `revert-gate` surfaces the `Roll-forward:` line when you try to undo one.

## Trailers carry the references

Issue IDs go in [git trailers](https://git-scm.com/docs/git-interpret-trailers), never in the
scope: the scope is the blast radius, and overloading it destroys the property that makes it
queryable.

```
promote(app-prod): app 0.1.1

Dev soaked 24h at 99.9% availability; slo-gate green.

Closes: #142
Refs: #98, #131
```

The trailers this repo uses:

| Trailer | Means |
|---|---|
| `Closes:` | what this change finishes: GitHub auto-closes on merge to the default branch |
| `Refs:` | what it touches without finishing: one of the two is mandatory on every PR ([rule 2.5](../rules.md#25-every-change-has-a-work-item-the-trailer-is-the-reason)) |
| `Roll-forward:` | **required whenever the subject carries `!`** ([rule 9](#the-nine-deciding-rules)): what to do *instead* of reverting |
| `Soak-waived:` | a promotion that cannot wait the soak `soak.yaml` declares: the reason, and who agreed; `soak-gate` passes it loudly ([stage 16](../act-4/stage-16.md)) |

`Closes:` for what this change finishes (GitHub auto-closes on merge to the default branch),
`Refs:` for what it touches. Multi-value is native: trailers are a list, so nothing has to be
invented for "two issues, one PR". `git log --format='%(trailers:key=Closes,valueonly)'` reads them
back, and git-cliff links them in release notes ([stage 26](../act-6/stage-26.md)).

## Two populations

The convention applies twice over, and conflating them causes the only real confusion:

- **Authoring commits**, this repo's own history: the walkthrough, the scripts, the gates. Ordinary
  software work, so ordinary types: `docs(convention)`, `feat(act-5)`, `fix(checkpoint)`.
- **Content commits**: what a learner types while building the platform. These are the config
  repo's real changes, so the **domain types are theirs alone**. A `docs:` commit never moves a pin,
  and a `pin:` commit never edits a walkthrough page.

**The scope means something different in each.** For content commits it is the blast radius, from
the registry above. For authoring commits there is no blast radius to name, nothing reconciles the
walkthrough, so the scope is the **doc area** being changed: `convention`, `git-policy`,
`checkpoint`, `act-5`, `scripts`, or a page's own number (`stage 14`). `commit-gate` enforces the
registry only where a domain type is used, which is the same line the two populations fall on.

**One exemption, stated so nobody guesses.** [Stage 00](../act-1/stage-00.md) commits to the **app
repo**, not the config repo: a different repository, an ordinary .NET service. It takes plain
`feat:`, and the domain vocabulary does not apply there. The grammar describes a platform; the app
is a thing the platform ships.

**One deliberate lie.** [Stage 09](../act-3/stage-09.md)'s "plausible bad release" keeps an innocent
subject, `feat(app-dev): storage config change`, because typing it `break` would spoil the drill.
That is the lesson, not an oversight: **a plausible commit message is not evidence.** The grammar
tells you what the author claimed, and the SLO tells you what happened.

**A second one, for the same reason.** [stage 20](../act-5/stage-20.md)'s
`rotate(dev-01): status token` is the textbook case for `!`, its whole drill is that reverting it
reconciles green onto a dead credential, and it is deliberately **left unmarked**. Marking it would
warn you, and the stage exists precisely to show that *nothing warns you*: the revert succeeds, the
stamp goes green, and the platform is broken in a way no signal reports. Both exceptions are the
same shape, and worth stating as a rule of their own: **a drill about a missing signal cannot supply
that signal in its own setup.**

## The lookup idiom

Typed subjects make commit lookups grammar queries instead of prose matches. Two forms, and the
difference matters:

**In paste blocks**, `git log` with the regex flavour pinned and **both ends anchored**:

```sh
sha=$(git log --format=%h --basic-regexp --grep='^pin(app-dev): app 0\.1\.1$' -1)
```

**In scripts**: an awk test on the subject field, which is literal, subject-only, and immune to
whatever `grep.patternType` the reader has configured. Two forms, chosen by what you know:

```sh
# you know the whole subject - exact
SHA=$(git log --max-count=500 --format='%H%x09%s' \
      | awk -F'\t' -v m="pin(app-dev): app $TAG" '$2 == m { print $1; exit }')

# you know only the type and scope - prefix
SHA=$(git log --max-count=500 --format='%H%x09%s' \
      | awk -F'\t' -v m="break($STAMP): " 'index($2, m) == 1 { print $1; exit }')
```

Four things to get right, each of which has already bitten this repo:

- **`--basic-regexp` is not decoration.** `(` and `)` are literal in BRE and *grouping* in ERE, so
  `-E` matches nothing and **exits 0**: a silent empty result, the worst failure mode a lookup has.
  `-F` matches literally but cannot anchor. Pin the flavour and the reader's config can't change
  what the block does.
- **Anchor the tail as well as the head.** `--grep='^pin(app-dev): app 0\.1\.1'` also matches
  `pin(app-dev): app 0.1.10`, and since `-1` takes the newest, the point release silently wins.
  `$` costs one character and removes the whole class.
- **`^` is what excludes the revert**, and it is worth knowing why. `git revert` writes
  `Revert "pin(app-dev): app 0.1.1"`, the original subject is *inside* the line, not at the start
  of it, so an anchored pattern skips it and an unanchored one finds it first (it is newer). That
  bug shipped in this course's own drill 4 until the retrofit; the anchor, not the scope, is the
  fix. The scope's job is different: it makes a `type(scope): ` **prefix** meaningful enough to
  select on at all.
- **`^` anchors to any line, including the body.** A body line beginning `promote(app-prod):` will
  match. Keep bodies prose, and prefer the awk form in scripts, where `%s` is the subject and
  nothing else.

And a standing caveat: **the grammar narrows, it does not identify.** `^pin(app-dev): app 0\.1\.1$`
finds every commit that pinned that version, which may legitimately be more than one. Take `-1`
deliberately, knowing it means *most recent*, and escape the dots: a bare `--grep='0.1.1'` is a
regex that also matches `0x1y1`.

## Enforcement

`scripts/commit-gate`, in the `*-gate` family, one grammar, four ways in:

- `commit-gate --file <path>` judges one message: the `commit-msg` hook
  ([stage 11](../act-4/stage-11.md)), and the `pr-record` CI job on a push, where the message is the
  merge commit's (or a robot's).
- `commit-gate --subject "<title>" ["<body>"]` judges a PR title as the subject it will become,
  `pr-open` before the PR exists, and the `pr-record` CI job on every PR event including `edited`,
  which the ruleset requires from stage 11, alongside `issue-gate` on the same body: the
  `Refs:`/`Closes:` trailer must name an open issue ([rule 2.5](../rules.md#25-every-change-has-a-work-item-the-trailer-is-the-reason)).
- `commit-gate --range <base>..<head>` lints real commits on demand (`origin/main..HEAD`, a release
  range, stage 26's history audit).
- `commit-gate --docs` extracts every `git commit -m`, `--title`, `pr-open` and `--commit-template`
  string from the walkthrough and lints it **identically**. The course holds itself to the standard
  it teaches, and that is a test rather than a promise.

Merge policy, protection and the PR record are the other half of this: see
[the git policy](git-policy.md).
