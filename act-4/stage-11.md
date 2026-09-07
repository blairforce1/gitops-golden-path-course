# Stage 11 - Shift left (git hooks, and the style gate)

[← Act III checkpoint](../act-3/act-checkpoint.md) · [Walkthrough index](../README.md)

> **Where you are:** the root of the config repo, on `main`. **Starting state:** 10 complete and the fleet live. If it isn't, the previous act's `act-3-drill` rebuilds it from git (git is at HEAD, so everything since comes back with it). **Why here:** it needs the first CI to exist (stage 08), because the whole point is CI's relationship to your laptop, and it opens Act IV so that every file the remaining acts write is born gated.

**Goal:** the rule first, because it drives every step: **CI is a backstop, and a backstop should never fire** ([rule 5.9](../rules.md#59-gates-not-checks---and-ci-is-a-backstop-that-never-fires)). A red CI run on a *mechanical* check such as style, lint, or rendered policy is extremely annoying and time-consuming for exactly the people you want moving fast, and it's a process failure, not a code failure: the check existed, and it simply didn't run where the developer was. This stage moves the verdicts to the laptop. The YAML style convention becomes an executable gate, the gates become git hooks, and CI's job shrinks to what it should have been all along: catching what the courtesy layer missed.

The gate has two halves, because *format* and *lint* are different questions. **[kustofmt](https://github.com/blairforce1/kustofmt)** is the format authority: a single static binary wrapping kyaml's own formatter, the resurrection of the `kustomize cfg fmt` that kustomize v5 removed, so "the house style" stops being prose and becomes a byte-for-byte comparison against what kustomize and Flux themselves emit (the style itself is [rule 3.4](../rules.md#34-yaml-style-adopt-the-tools-style-everywhere)). **yamllint** covers what formatting can't express (truthy keys, duplicate keys, trailing whitespace). yamllint runs as a pinned container. kustofmt installs, pinned: it is a filter under `-l` and a writer under `-w`, and from step 5 it runs inside the pre-commit hook on every commit, so the operator side of [rule 4.2](../rules.md#42-tool-provisioning-filters-from-images-operators-installed) wins and a container start stays off the commit path. Its pin has an authority: kustofmt is only "what kustomize emits" while it links the kyaml the pinned kustomize ships, so its version is a lookup against the kustomize pin, not a choice, and a parity gate holds it there like every other render tool ([rule 4.1](../rules.md#41-the-render-rule-one-authority-per-tool-and-kubectl-never-renders)). CI installs the same release from the same pin, so every venue still reaches one verdict. One check runs before either half and needs neither tool: `layout-gate`, [rules 3.1 and 3.2](../rules.md#31-file-naming-metadatanamekindyaml) as a verdict (one resource per file, `<name>.<kind>.yaml` against the kind and name inside, a typed folder). `checkpoint-02` has run it since stage 02; `style-gate` runs it first, so from step 5 the hook and CI judge the folder rules without another line.

## Steps

### 1. The convention becomes a config file

kustofmt enforces the *shape* (indentless sequences, block over flow, canonical spacing) without configuration. That's the point of a formatter. yamllint covers the rest, and its config is where the remaining rules live. Write it at the repo root, where every venue (script, CI, hook, editor plugin) reads the same file:

```sh
cat > .yamllint.yaml <<'EOF'
extends: default
rules:
  braces:
    forbid: non-empty
  brackets:
    forbid: non-empty
  comments:
    min-spaces-from-content: 1
  document-start: disable
  indentation:
    spaces: 2
    indent-sequences: false
  line-length: disable
  truthy:
    ignore:
    - .github/workflows/
ignore:
- "**/flux-system/"
- "**/secrets/*.secret.yaml"
EOF
```

Read the `ignore` list. Each entry is a tool-owned tree, and one of them is load-bearing: **sops-encrypted files can never be reformatted**, because the MAC covers the whole file including its plaintext structure. A linter demanding indentation changes there is demanding you corrupt the file. The exemption isn't a shortcut; it's the stage-06 hand-edit rule wearing its lint costume. (`truthy` keeps its key check everywhere but the workflow tree, where GitHub Actions' `on:` is a key YAML 1.1 insists is a boolean: a per-rule `ignore`, scoped to the one tree that needs it, rather than switching the check off for every file; `document-start: disable` because flux exports open with `---` and kustomize files don't; both are the tool's style.) The gate runs yamllint `--strict`, so a warning fails it the same as an error: a rule that only warns is decoration, and the tree today carries none.

Then the formatter's pin. `style-gate` reads the kustofmt version from `clusters/versions.yaml`, the file every other render pin lives in, and refuses to run with any other version installed, or none. The version is not yours to pick: kustofmt cuts one release per kyaml and publishes the kustomize releases each one matches, so the pin for kustomize 5.8.1 is the release built on 5.8.1's kyaml. Append it, then run the gate that keeps it true:

```sh
cat >> clusters/versions.yaml <<'EOF'
# The formatter's pin (rule 3.4): kustofmt is kyaml's emitter, the library the
# kustomize pin above ships, so kustomize is its authority (rule 4.1). One kustofmt
# release exists per kyaml; check-kustofmt-kustomize-parity holds the two to one
# emitter and names the release to pin when the kustomize pin moves.
kustofmt: "0.1.5"
EOF
./scripts/check-kustofmt-kustomize-parity
```

Expect a FAIL, the stage-00 shape: nothing is installed yet, and the line carries the install. Run it, then the gate again:

```sh
v=$(yq -r '.kustofmt' clusters/versions.yaml)
curl -sfL --retry 3 --retry-delay 5 "https://github.com/blairforce1/kustofmt/releases/download/v$v/kustofmt_${v}_linux_amd64.tar.gz" | tar xz -C ~/.local/bin kustofmt
./scripts/check-kustofmt-kustomize-parity
```

Three PASS lines now: the installed binary is the pin and names the kyaml it links (its own `-version`, local), the pinned kustomize ships a kyaml (read off kustofmt's `compatibility.yaml`, the one fetch), and the two are equal. After a flux bump `check-kustomize-flux-parity` moves the kustomize pin, and this gate then FAILs naming the kustofmt release to pin beside it, and the install once you have; until then the formatter and the renderer are only the same emitter by coincidence. `./scripts/check` runs it with the rest from now on (it said SKIP before the pin existed).

### 2. Run the gate - and meet the debt

```sh
./scripts/style-gate
```

Expect **FAIL**, and read what it found. Which files depends on what was hand-written and never round-tripped through kustomize's emitter. The course's first hand-written YAML, the three files under `apps/base/resources/`, was the oldest debt until stage 08 re-authored them whole; what is left is whatever nobody re-authored since, and two shapes account for most of it: a long value wrapped by hand onto a second line (stage 09's PromQL expressions), which kustofmt joins back into one, and aligned comment columns, which it collapses to one space. Two things in that output are worth pausing on:

- Files ending `.secret.yaml` are never among the failures, and once the gate passes (step 3) it says why: each is reported **`sops-encrypted, skipped`**. That's not the gate being polite: reformatting them would corrupt the MAC, which covers the file's plaintext structure. The formatter refuses by default; `.yamllint.yaml` skips them for the same reason. The stage-06 hand-edit rule, enforced by two tools that never read that page.
- `flux-system/` is excluded by the *caller*, not by tool config. kustofmt has no ignore file, deliberately (neither does gofmt). Those manifests are `flux install --export` output, regenerated whenever Flux moves. Reformatting them would be a fight, not a fix.

That mix is the shape of real adoption: a convention enforced going forward, a backlog that waited for the day someone made it executable, and two categories of file that must be left alone on purpose.

### 3. Pay the debt with the render authority

Capture the renders first. The parity gate afterwards is the proof that formatting changed nothing the clusters can see:

```sh
kustomize build apps/overlays/dev > /tmp/dev-before.yaml
kustomize build apps/overlays/prod > /tmp/prod-before.yaml
```

```sh
./scripts/style-fix
```

Look at how `style-fix` calls the formatter: gofmt's shape exactly. `-l` lists the files whose bytes differ from the emitted style, `-w` rewrites that list and nothing else, so the script can name each file it touched and a sops file, which `-l` never lists, is never handed to `-w`. It also refuses to run unless the installed binary is the pin, the same check `style-gate` makes: a formatter one kyaml adrift would rewrite the tree into a style the renderer no longer emits.

Worth knowing even though you no longer need it: for Kubernetes *resources* specifically, a formatter was always available. **`kustomize build` emits the house style**, so round-tripping a resource file through a scratch kustomization normalizes it. That trick doesn't extend to workflows, lint configs or Helm values files, which is exactly the gap kustofmt fills.

The gate is three proofs, then commit:

```sh
diff <(kustomize build apps/overlays/dev) /tmp/dev-before.yaml && echo "dev render: byte-identical"
diff <(kustomize build apps/overlays/prod) /tmp/prod-before.yaml && echo "prod render: byte-identical"
./scripts/style-gate
```

The renders *couldn't* change: everything the cluster receives already passes through kustomize's emitter, so a source file's serialization was invisible to the fleet all along. For the files outside the overlays the receipt is `git diff --word-diff`: joins and spaces, never a value. (The diff may also put keys into kyaml's field order, the same one-time convergence to tool style stage 08 step 1 showed for flux exports.) For manifests, then, a formatter has been installed since stage 02; kustofmt is the same emitter reachable for every other YAML file, and in place.

```sh
git add .yamllint.yaml $(git diff --name-only)
./scripts/pr-open policy/15/style-gate "policy(scripts): style gate - convention as config; the hand-written debt paid" <<'EOF'
## What is moving
.yamllint.yaml (the convention as config), the kustofmt pin in clusters/versions.yaml (held to the kustomize pin by check-kustofmt-kustomize-parity), and the hand-written files style-fix normalised to kustomize's emitted style; git diff --stat names them.

## Why now
The style convention has been prose since stage 02; style-gate makes it a verdict.

## Evidence
Both overlay renders byte-identical before and after (the diff gate above); style-gate PASS on the tree.

## If it is wrong
Revert this merge - renders are unaffected either way.

Refs: #15
EOF
```

Read it; when the diff is what the body claims:

```sh
gh pr checks --watch --fail-fast \
&& gh pr merge --merge --delete-branch \
&& git switch main \
&& git pull
```

### 4. CI gains two jobs - the backstop half, and the title check

The whole updated workflow, pasted (not surgically edited: `verify.yaml` carries sequences, and the yq quarantine says list-bearing files get re-authored, never patched). Two jobs join `rendered-policy`: `style`, the backstop for step 5's hooks, and `pr-record`, which judges the two things no hook can ever see. Those two are the PR title, which [rule 1.2](../rules.md#12-repository-configuration-the-merge-policy-is-set-before-the-first-pr) turns into every subject on `main`, and the body's work-item trailer ([rule 2.5](../rules.md#25-every-change-has-a-work-item-the-trailer-is-the-reason)), which `pr-open` has been checking on your laptop since stage 04:

```sh
cat > .github/workflows/verify.yaml <<'EOF'
name: verify
on:
  pull_request:
    types:
    - opened
    - edited
    - synchronize
    - reopened
  push:
    branches:
    - main
jobs:
  rendered-policy:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4
    - name: install pinned kustomize
      # the runner ships SOME kustomize; we need the one that renders like the
      # cluster's kustomize-controller - the pin in clusters/versions.yaml
      # (see scripts/check-kustomize-flux-parity for how that pin is derived)
      run: |
        v=$(yq -r '.kustomize' clusters/versions.yaml)
        curl -sfL --retry 3 --retry-delay 5 "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv$v/kustomize_v${v}_linux_amd64.tar.gz" \
          | sudo tar xz -C /usr/local/bin
        kustomize version
    - name: render and test overlays
      # the identical file the paste block ran - CI is re-running your gate, not reimplementing it
      run: ./scripts/policy-gate
  style:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4
    - name: install pinned kustofmt
      # the formatter follows the kustomize pin's kyaml (clusters/versions.yaml);
      # style-gate refuses any other version, so CI installs the same one
      run: |
        v=$(yq -r '.kustofmt' clusters/versions.yaml)
        curl -sfL --retry 3 --retry-delay 5 "https://github.com/blairforce1/kustofmt/releases/download/v$v/kustofmt_${v}_linux_amd64.tar.gz" \
          | sudo tar xz -C /usr/local/bin kustofmt
        kustofmt -version
    - name: the same style-gate the hooks will run
      run: ./scripts/style-gate
  pr-record:
    runs-on: ubuntu-latest
    # the default token is the restricted one (contents and packages, read); this job
    # reads issues, so it says so. Naming one scope zeroes every scope not named.
    permissions:
      contents: read
      issues: read
      pull-requests: read
    steps:
    - uses: actions/checkout@v4
    - name: the title is the merge subject; the trailer is the work item
      env:
        # never inline ${{ }} in a run: script - a PR title is user input, and that
        # is the textbook Actions injection. env: hands it over as data.
        TITLE: ${{ github.event.pull_request.title }}
        BODY: ${{ github.event.pull_request.body }}
        GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        GH_REPO: ${{ github.repository }}
      run: |
        # on a PR: the title and body that WILL become the merge commit
        # on a push: the subject and body that a merge (or a robot) just produced,
        #            whose work item the merge may already have closed (--landed)
        if [ -n "$TITLE" ]; then
          ./scripts/commit-gate --subject "$TITLE" "$BODY"
          ./scripts/issue-gate "$BODY"
        else
          git log -1 --format=%B > "$RUNNER_TEMP/message"
          ./scripts/commit-gate --file "$RUNNER_TEMP/message"
          ./scripts/issue-gate --landed --file "$RUNNER_TEMP/message"
        fi
EOF
git add .github/workflows/verify.yaml
./scripts/pr-open ci/15/backstop "ci: style and pr-record jobs, the backstop half of three conventions" <<'EOF'
## What is moving
Two jobs in verify.yaml: style runs the gate the hooks will run; pr-record runs commit-gate on the PR title and issue-gate on its trailer (and, on a push, on the subject and trailer that landed). The pull_request trigger now lists `edited`, so a retitled or re-bodied PR is re-judged.

## Why now
A gate that runs only on laptops is advice; CI is the backstop that never fires. And the PR title is the one string no hook ever sees - it becomes the subject on main at merge time, after which nothing can rewrite it.

## Evidence
This PR is both jobs' first run - watch it before merging; its own title is the first one judged.

## If it is wrong
Revert this merge.

Refs: #15
EOF
```

Read the diff, then the checks-first merge, which is where you watch both jobs' first run:

```sh
gh pr checks --watch --fail-fast \
&& gh pr merge --merge --delete-branch \
&& git switch main \
&& git pull
# the second amendment: a red check on either is now a refused merge
./scripts/ruleset require-check style pr-record
```

Five details in `pr-record` are load-bearing.

- **The job declares its token's permissions.** The default `GITHUB_TOKEN` on a repo with the restricted setting reads contents and packages and nothing else, so a job that reads an issue gets a 403 and the gate reports the issue missing. `permissions:` names the scopes the job uses. Naming any scope sets every other scope to none, which is the least-privilege shape every job in this course carries from here.
- **`edited` is in the trigger list.** GitHub's default `pull_request` types omit it. Without it a reader who fixes a red title stays red, and a green PR can be retitled to prose a second before the merge.
- **The title and body arrive through `env:`, never inline in `run:`.** A PR title is user input, and `run: gate "${{ github.event.pull_request.title }}"` is the textbook Actions injection: on a public repo, anyone who can open a PR runs shell on your runner.
- **The body is passed too.** With `merge_commit_message=PR_BODY` the PR body *is* the commit body. This is the first check in the course that reads the deployment record, and the `Roll-forward:` trailer [rule 2.1](../rules.md#21-the-commit-convention-the-subject-is-a-field-not-a-sentence) demands beside `!` becomes checkable rather than noted.
- **On a push the job judges the commit, not a title.** On `main` that is the merge commit the PR just produced, the after-the-fact receipt. On the branch stage 14's robot will push to, it is the robot's own subject, which is the title its PR will carry, so the robot is held to the same grammar you are, on an event that carries no PR at all.

The same job runs `issue-gate` on the body: the `Refs:`/`Closes:` trailer must name an open issue in this repo, with `--landed` on a push because the merge may be exactly what closed it.

Three jobs now run on every PR event and every merge, on GitHub-hosted runners a private repository meters (the README's "Before you start" gives the allowance). Each is well under a minute; the day this stage takes stays inside an hour of Linux minutes, and the number to watch is on the account's usage page, not in this repo.

### 5. The hooks - the half that means CI never fires

Three hooks, committed like any other file, each just *calling the gates*: zero logic lives in a hook, so hooks can never drift from CI. `commit-msg` is the interesting one: it is the only hook that fires while you are **still holding the thing it rejected**, so a bad commit message is fixed in the same breath rather than becoming a rewrite later:

```sh
mkdir -p hooks
cat > hooks/pre-commit <<'EOF'
#!/usr/bin/env bash
# Courtesy layer, not enforcement - CI is the backstop (and --no-verify skips this).
# Lints only the YAML this commit touches, so it stays instant.
set -uo pipefail
files=$(git diff --cached --name-only --diff-filter=ACM -- '*.yaml' '*.yml')
[ -z "$files" ] && exit 0
# Checks, never rewrites: a hook that silently reformats staged content is a hook
# nobody trusts. If it fails, `./scripts/style-fix $files` and stage the result.
# shellcheck disable=SC2086
exec ./scripts/style-gate $files
EOF
cat > hooks/commit-msg <<'EOF'
#!/usr/bin/env bash
# The one hook that can fix its own failure: you are still holding the message.
# Grammar: appendices/commit-convention.md in the course repo
set -uo pipefail
exec ./scripts/commit-gate --file "$1"
EOF
cat > hooks/pre-push <<'EOF'
#!/usr/bin/env bash
# Exactly CI's jobs - a push that would fail CI fails here first, for free.
# Every gate runs and then the hook fails, as CI shows every job: a hook that
# stops at the first red hides the second, and one that just runs three gates
# in a row returns only the last one's verdict.
set -uo pipefail
fail=0
./scripts/style-gate || fail=1
./scripts/policy-gate || fail=1
./scripts/commit-gate --docs || fail=1
exit "$fail"
EOF
chmod +x hooks/pre-commit hooks/commit-msg hooks/pre-push
git config core.hooksPath hooks
git add hooks
./scripts/pr-open ci/15/hooks "ci(hooks): pre-commit lints the diff, pre-push runs CI's jobs" <<'EOF'
## What is moving
Three hooks under hooks/, each calling a gate script and nothing else; wired per clone by core.hooksPath.

## Why now
CI is the backstop; hooks are what make it never fire.

## Evidence
The hooks contain no logic - drift from CI is impossible by construction.

## If it is wrong
Revert this merge; clones that set core.hooksPath simply run nothing.

Refs: #15
EOF
```

Read it; when the diff is what the body claims:

```sh
gh pr checks --watch --fail-fast \
&& gh pr merge --merge --delete-branch \
&& git switch main \
&& git pull
```

Read the pre-push hook's shape once, because it is the one that is easy to get wrong: three gates in a row under `set -u` return the last gate's exit status, so a red style gate followed by a green commit gate is a push that goes through. The verdicts are collected and the hook fails at the end, after every gate has spoken, which is also what CI's three jobs do.

Two honest notes, both structural. **A repository cannot install its own hooks**: `git config core.hooksPath hooks` is per-clone, by design (a repo that could run arbitrary code on clone would be a supply-chain attack), so that one line is every teammate's setup step, and a fresh clone ships ungated. And **hooks are bypassable** (`--no-verify`), which together means hooks can only ever be the courtesy layer. That's not a weakness to paper over; it's why the backstop exists, and since stage 08 the backstop has teeth: a required check is a refused merge, not a red decoration. (Small print: pre-commit lints the *working-tree* version of staged files, good enough for a courtesy layer; the pre-push and CI runs judge what's actually committed.)

### 6. The drill - two bypasses, one backstop

Prove the layering by defeating it. A violation, smuggled past both hooks, caught by the only layer that doesn't take `--no-verify` for an answer:

```sh
git switch -c break/15/style-demo
cat > style-demo.yaml <<'EOF'
demo: {this: "is flow style", and: [it, is, banned]}
EOF
git add style-demo.yaml
```

```sh
# pre-commit: FAIL - read it, then...
git commit -m "break(scripts): a flow-style violation walks into a bar"
```

```sh
git commit --no-verify -m "break(scripts): a flow-style violation walks into a bar"
git push -u origin break/15/style-demo                        # pre-push: FAIL - then...
```

```sh
git push --no-verify -u origin break/15/style-demo
gh pr create --title "break(scripts): a flow-style violation walks into a bar" --body "Two hooks bypassed on purpose; this PR exists to watch the backstop catch what they missed. Closes unmerged.

Refs: #15"
```

Gate: the PR's `style` check goes **red**. The violation survived two deliberate bypasses and zero human vigilance, and the backstop still held. Now try to merge past it, because that is the bypass the ruleset exists to refuse:

```sh
gh pr checks --watch
gh pr merge --merge --delete-branch     # → refused: "the base branch policy prohibits the merge"
./scripts/ruleset show                  # required_status_checks names style: the line that refused you
```

The refusal names the policy, not the check; gh suggests `--auto` and `--admin` in the same breath, and the ruleset has no bypass actor, so `--admin` would be refused too.

Note the drill PR's `pr-record` check is *green*: the title obeys the grammar and the content doesn't. Two checks, two questions, two verdicts. Retitle it and watch the second one turn:

```sh
gh pr edit break/15/style-demo --title "fixed the yaml"    # the `edited` trigger re-runs verify
# → pr-record red too: that string would have been a subject on main
# (the run takes seconds to register: if the watch reports the previous run, run it again)
gh pr checks --watch
# put the title back, so the next red has one cause:
gh pr edit break/15/style-demo --title "break(scripts): a flow-style violation walks into a bar"
gh pr checks --watch                                       # → pr-record green again
# drop the trailer:
gh pr edit break/15/style-demo --body "Two hooks bypassed on purpose. No work item cited."
# → pr-record red for a second reason: a change nobody asked for (the log: no Closes:/Refs: trailer)
gh pr checks --watch
```

The job runs `commit-gate` and then `issue-gate` and stops at the first red, so a PR with a prose title and no trailer shows one reason at a time. That is why the title goes back before the trailer goes: each red has one cause, and the log names it.

That's the architecture in one screenshot, and note it's the *first* red CI this repo has ever produced, manufactured on purpose. The rule holds when it's the last. Clean up:

```sh
gh pr close break/15/style-demo --delete-branch
git switch main && git branch -D break/15/style-demo 2>/dev/null; git pull
```

## Stop & measure

- [ ] The gate is green on the whole tree, and the sops files are the only lines under its first PASS:

```sh
./scripts/style-gate
```

Expected: `PASS  format matches the kustomize/kyaml house style`, one `sops-encrypted, skipped` line per secret file, `PASS  yamllint clean`, then `style-gate: 2 passed, 0 failed`. The hand-written files were normalised in step 3 with byte-identical renders as the receipt.

- [ ] Three merges carry the stage, and the drill's PR closed without one:

```sh
gh pr list --state merged --search '"Refs: #15" in:body' --json number,title -q '.[] | "#\(.number)  \(.title)"'
gh pr view break/15/style-demo --json state,mergedAt -q '.state + "  merged: " + (.mergedAt // "never")'
```

Expected: the `policy(scripts)`, `ci` and `ci(hooks)` titles from steps 3 to 5, then `CLOSED  merged: never`.

- [ ] Both hooks fired in the drill, CI caught the double bypass, and the ruleset refused the merge. Say the layering out loud: *hooks make CI boring; CI makes hooks optional; the ruleset makes CI binding.* The line that did the refusing names all three checks:

```sh
./scripts/ruleset show | grep required_status_checks
```

- [ ] The three jobs are present and green on `main`, on the push run that judged the merge commit it ran on:

```sh
run=$(gh run list --workflow=verify --branch main --limit 1 --json databaseId -q '.[0].databaseId')
gh run view "$run" --json jobs,event,displayTitle -q '.event + "  " + .displayTitle, (.jobs[] | .name + "  " + .conclusion)'
```

Expected shape:

```
push  ci(hooks): pre-commit lints the diff, pre-push runs CI's jobs
rendered-policy  success
style  success
pr-record  success
```

Tag the boundary ([using the course §5](../using-the-course.md#5-tags-at-every-boundary)):

```sh
git tag stage-11 \
&& git push origin stage-11 \
&& gh issue close 15 --comment "stage-11 tagged"
```

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| style-gate flags a `*.secret.yaml` or `flux-system/` file | The ignore list changed, or the file moved out of its tool-owned home | Restore the exemption; sops files literally cannot be reformatted (the MAC covers plaintext structure), and tool-owned trees keep the tool's style |
| `check-kustofmt-kustomize-parity` FAIL after a flux bump | `check-kustomize-flux-parity` moved the kustomize pin and kustofmt still links the old kyaml | Pin the kustofmt release the FAIL line names (the `compatibility.yaml` row for the new kustomize); if the row is missing, kustofmt's watcher has not recorded the release yet and the pin is unverifiable until it does |
| Hooks never fire | `core.hooksPath` unset in *this* clone; repos can't self-install hooks | Step 5's `git config` line; it's part of every clone's setup, and CI covers the gap meanwhile |
| `truthy` on `on:` in a workflow | YAML 1.1 thinks `on` is a boolean, and the file is outside `.github/workflows/` (or the config did not land) | Step 1's `truthy: ignore:` exempts the workflow tree only; re-check `.yamllint.yaml` landed and the workflow lives where GitHub reads it |
| `truthy` on a key or value in a manifest | A key such as `yes`, `no`, `on`, `off` or `y`, or an unquoted value of one of those, which YAML 1.1 reads as a boolean | Quote it; the check is on everywhere but the workflow tree, and the gate is `--strict` so a warning is a FAIL |
| Step 3's parity diff is non-empty | Something other than formatting changed between the two renders: an edit slipped into the tree, or a stray file landed beside an overlay | `git status` and `git diff --stat`: only files `style-fix` rewrote should differ, and formatting cannot change a render. Revert the stray edit and re-run the diff |
| Gate passes locally, style job fails in CI | Same config, same pinned binary and container, so the difference is uncommitted work | `git status`; the verdict machinery cannot drift, only the inputs |
| `style-gate` or `style-fix` says `installed kustofmt is the pin` FAIL | No kustofmt on PATH, or a version other than the one `clusters/versions.yaml` pins | `./scripts/check-kustofmt-kustomize-parity` carries the install one-liner; the gates refuse any other version on purpose |
| `pr-record` red on a PR whose commits all passed the hook | The title is a separate string, typed at `gh pr create` or edited on the web, and the commit-msg hook never saw it | Retitle it (`gh pr edit <n> --title …`); the `edited` trigger re-judges it. `pr-open` lints the subject before the PR exists, which is why it never hits this |
| `pr-record` FAIL `cannot read #N` (or, on an older `issue-gate`, `#N does not exist`) for an issue `pr-open` passed a minute ago | The job's token cannot read issues: the `permissions:` block is missing from the job, or the repo's default token is the restricted one and the block names another scope only | Step 4's `permissions:` on the `pr-record` job (`issues: read` beside `contents: read`); the local gate ran as you, with your scopes |
| `pr-record` green on a revert PR, then red on the push to `main` that merged it: `not type(scope): description -> Revert "…" (#N)` | GitHub appends ` (#N)` to every merge subject, even under `merge_commit_title=PR_TITLE`; on a typed subject the grammar tolerates it, on a revert it lands after the closing quote | `commit-gate` strips the suffix before judging; a gate that does not is out of date, so sync it. The red run is the backstop reporting on a push, and blocked nothing |
| `pr-record` never reports on a branch a robot pushed | No `on.push.branches` entry for that branch, so no run, so no check; a `GITHUB_TOKEN` push raises no `pull_request` event | Stage 14 adds the robot's branch to the push trigger; the job judges the commit there |

## What you learned

The style convention stopped being prose: one config file, one gate script, four venues (terminal, pre-commit, pre-push, CI), and the layering is honest about which venue *enforces* (only the one you can't `--no-verify`). The PR title, the one string that becomes every subject on `main` and the one string no hook can see, is now judged by the same grammar before it can merge, and again as the commit it became; so is the work item it cites. The debt the convention accrued before it was executable got paid through the render authority, with byte-identical renders as the receipt. And the format half is no longer an opinion: kustofmt compares your files against what kyaml itself would emit, so "house style" is a diff, not a debate; its pin follows the kustomize pin the way kustomize follows the controller, held by the same kind of gate.

---

**Next:** [12 - Rendered diff (blast radius on every PR)](stage-12.md)
