# Stage 12 - Rendered diff (blast radius on every PR)

[← 11 - Shift left (git hooks, and the style gate)](stage-11.md) · [Walkthrough index](../README.md)

> **Where you are:** the root of the config repo, on `main`. **Starting state:** 11 complete and the fleet live. If it isn't, the previous act's `act-3-drill` rebuilds it from git (git is at HEAD, so everything since comes back with it). **Why here:** every PR after this one carries its own blast radius, including Renovate's (stage 13) and the robot's (stage 14). The earlier it lands, the more it pays. Works identically before or after stage 13's restructure.

**Goal:** stage 07's sharpest gate was "read the PR diff: one line, the prod pin; that *is* the blast radius." But a YAML diff is the blast radius only when the change is a pin; a base edit, an overlay patch, a component toggle can each fan out into renders the file diff doesn't show. This quest adds CI that **renders every kustomize root at base and head and comments the *rendered* diff on the PR**: the reviewer approves what the clusters will actually receive.

## The rules, applied to CI

Two parts of the render rule do the heavy lifting. **CI installs kustomize from the same pin** (`clusters/versions.yaml`), so the comment shows what kustomize-controller's effective library will produce, not what some runner-image version feels like producing. And **keyless CI still renders ciphertext** (the stage-06 dividend): sops files pass through `kustomize build` untouched, so a secret change shows up as an `ENC[...]` blob replacing another, *present in the blast radius, unreadable in the log*, with no key material anywhere near a runner. Known gap, named: binding-level transforms belong to `flux build`, which rule 4.1 currently holds as advisory. Those are the transforms living on a *stamp*, the Flux `Kustomization` CR, rather than in the overlay it points at (`spec.patches`, `postBuild` substitution). The raw file diff in the PR covers those CRs; revisit when the parity gate says the flux CLI agrees with the controller.

## Steps

### 1. The workflow

The whole file, pasted; the pre-commit hook from stage 11 lints it as it is committed:

```sh
cat > .github/workflows/rendered-diff.yaml <<'EOF'
name: rendered-diff
on: pull_request
permissions:
  contents: read
  pull-requests: write
jobs:
  render:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4
      with:
        path: head
    - uses: actions/checkout@v4
      with:
        path: base
        ref: "${{ github.event.pull_request.base.sha }}"
    - name: install pinned kustomize
      # the render rule: the pin in clusters/versions.yaml, read from the PR side
      run: |
        v=$(yq -r '.kustomize' head/clusters/versions.yaml)
        curl -sfL --retry 3 --retry-delay 5 "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv$v/kustomize_v${v}_linux_amd64.tar.gz" \
          | sudo tar xz -C /usr/local/bin
        kustomize version
    - name: render both sides, diff every root
      # a root is every path a Flux Kustomization in clusters/ points at, on either
      # side: what some cluster receives, not what some folder is called
      run: |
        roots() { (cd "$1" && grep -rhE '^ +path: \./' clusters/ | sed -E 's|^ +path: \./||; s|/$||' | sort -u); }
        { echo '<!-- rendered-diff -->'; echo '## Rendered blast radius'; } > comment.md
        changed=0
        for d in $( (roots head; roots base) | sort -u); do
          for side in base head; do
            if [ -f "$side/$d/kustomization.yaml" ]; then
              (cd "$side" && kustomize build "$d") > "/tmp/$side.yaml" 2>"/tmp/$side.err" \
                || echo "BUILD FAILED: $(cat "/tmp/$side.err")" > "/tmp/$side.yaml"
            else
              echo "(root absent on $side)" > "/tmp/$side.yaml"
            fi
          done
          if ! diff -u /tmp/base.yaml /tmp/head.yaml > /tmp/d.diff; then
            changed=1
            n=$(grep -c '^[-+][^-+]' /tmp/d.diff)
            { echo "<details><summary><code>$d</code> ($n lines)</summary>"; echo
              echo '```diff'; head -300 /tmp/d.diff; echo '```'; echo '</details>'; } >> comment.md
          fi
        done
        [ "$changed" = 1 ] || echo 'No rendered change - this PR alters nothing any cluster receives.' >> comment.md
    - name: sticky comment
      # one comment per PR, edited on every push; the marker line finds it again
      env:
        GH_TOKEN: ${{ github.token }}
        PR: ${{ github.event.number }}
      run: |
        cd head
        id=$(gh api "repos/{owner}/{repo}/issues/$PR/comments" \
          --jq '.[] | select(.body | startswith("<!-- rendered-diff -->")) | .id' | head -1)
        if [ -n "$id" ]; then
          gh api -X PATCH "repos/{owner}/{repo}/issues/comments/$id" -F body=@../comment.md > /dev/null
        else
          gh pr comment "$PR" --body-file ../comment.md
        fi
EOF
```

Read what matters. **The render set is derived, not listed:** a root is every `path:` a Flux Kustomization under `clusters/` points at, on either side of the PR, so the set is "what some cluster receives" and it follows the fleet through stage 13's restructure and stage 22's tenants with no edit here. Both sides' roots are unioned, so a deleted root still reports. **A failed build lands in the diff** as a `BUILD FAILED` block instead of failing silently green. **Output is capped per root** at 300 lines; past that the message is "this is not a one-line change", which is itself the review signal. **The comment is sticky:** one per PR, found again by its marker line and edited on every push, not a pile. And the workflow runs on its own PR: `pull_request` takes the workflow file from the PR's merge ref, so the first comment is this PR's.

```sh
git add .github/workflows/rendered-diff.yaml
./scripts/pr-open ci/16/rendered-diff "ci: rendered blast radius commented on every PR" <<'EOF'
## What is moving
A workflow that renders every root on both sides of a PR and comments the diff, sticky, capped per root.

## Why now
A one-line base edit is a fleet-wide change; the file diff cannot show that, the render diff can.

## Evidence
This PR touches no manifests, so its own comment should say so - the first proof.

## If it is wrong
Revert this merge; reviews go back to reading file diffs.

Refs: #16
EOF
```

Read it, then wait for the comment and read that; when both say what the body claims:

```sh
gh pr checks --watch --fail-fast \
&& gh pr merge --merge --delete-branch \
&& git switch main \
&& git pull
```

Expect the comment to be one line under its heading: `No rendered change - this PR alters nothing any cluster receives.`

### 2. Prove it on a real one-liner

A pin move on the dev overlay, on a branch that never merges:

```sh
source ./env.sh
git switch -c pin/16/rendered-diff-demo
(cd apps/overlays/dev && kustomize edit set image $APP_IMAGE:0.0.0-rendered-diff-demo)
git add apps/overlays/dev
git commit -m "pin(app-dev): demo pin move for rendered-diff, never merges"
git push -u origin pin/16/rendered-diff-demo
gh pr create --title "pin(app-dev): demo pin move for rendered-diff, never merges" --body "Throwaway - exists to receive the bot comment; closes unmerged.

Refs: #16"
```

Gate: within a minute or two the PR carries one comment. Read it back without leaving the terminal:

```sh
gh pr checks --watch
n=$(gh pr view pin/16/rendered-diff-demo --json number -q .number)
gh api "repos/{owner}/{repo}/issues/$n/comments" \
  --jq '.[] | select(.body | startswith("<!-- rendered-diff -->")) | .body' \
  | grep -E '<summary>|^[-+] +image:|^No rendered'
```

Exactly one root, exactly two rendered lines, the image out and the image in:

```
<details><summary><code>apps/overlays/dev</code> (2 lines)</summary>
-        image: ghcr.io/<owner>/gitops-golden-path-app:<the dev pin>
+        image: ghcr.io/<owner>/gitops-golden-path-app:0.0.0-rendered-diff-demo
```

The stage-07 sentence, mechanised. Then throw the demo away:

```sh
gh pr close pin/16/rendered-diff-demo --delete-branch
git switch main && git branch -D pin/16/rendered-diff-demo 2>/dev/null; git pull
```

### 3. Prove the fan-out case - the one file diffs can't review

A one-line *base* edit renders into every consumer. One label on the base, on a branch that never merges:

```sh
git switch -c feat/16/rendered-diff-fanout
(cd apps/base && kustomize edit set label demo:rendered-diff)
git add apps/base
git commit -m "feat(base): demo label for rendered-diff fan-out, never merges"
git push -u origin feat/16/rendered-diff-fanout
gh pr create --title "feat(base): demo label for rendered-diff fan-out, never merges" --body "Throwaway - one line on the base, to watch it fan out; closes unmerged.

Refs: #16"
```

```sh
gh pr checks --watch
n=$(gh pr view feat/16/rendered-diff-fanout --json number -q .number)
gh api "repos/{owner}/{repo}/issues/$n/comments" \
  --jq '.[] | select(.body | startswith("<!-- rendered-diff -->")) | .body' \
  | grep -E '<summary>|^No rendered'
```

The file diff is one line. The comment shows every overlay that consumes the base, twelve rendered lines each, the label landing on all six resources the base emits:

```
<details><summary><code>apps/overlays/dev</code> (12 lines)</summary>
<details><summary><code>apps/overlays/prod</code> (12 lines)</summary>
```

That asymmetry, a small diff with a wide radius, is the review trap this stage exists to close. Close it unmerged, as before:

```sh
gh pr close feat/16/rendered-diff-fanout --delete-branch
git switch main && git branch -D feat/16/rendered-diff-fanout 2>/dev/null; git pull
```

## Stop & measure

- [ ] Three PRs carried the comment and only the first merged. One pass over all three, each with its state and its rendered roots:

```sh
for b in ci/16/rendered-diff pin/16/rendered-diff-demo feat/16/rendered-diff-fanout; do
  n=$(gh pr list --state all --head "$b" --json number -q '.[0].number')
  echo "== #$n $b: $(gh pr view "$n" --json state,mergedAt -q '.state + (if .mergedAt then " merged" else " never merged" end)')"
  gh api "repos/{owner}/{repo}/issues/$n/comments" \
    --jq '.[] | select(.body | startswith("<!-- rendered-diff -->")) | .body' \
    | grep -E '<summary>|^No rendered'
done
```

Expected shape:

```
== #N ci/16/rendered-diff: MERGED merged
No rendered change - this PR alters nothing any cluster receives.
== #N pin/16/rendered-diff-demo: CLOSED never merged
<details><summary><code>apps/overlays/dev</code> (2 lines)</summary>
== #N feat/16/rendered-diff-fanout: CLOSED never merged
<details><summary><code>apps/overlays/dev</code> (12 lines)</summary>
<details><summary><code>apps/overlays/prod</code> (12 lines)</summary>
```

- [ ] Say out loud which reviewer mistake each demo prevents: the pin move is the change a file diff reviews well, and the base edit is the one it cannot. A secret-touching PR, when one comes (stage 17), will show `ENC[...]` replacing `ENC[...]`: the radius visible, the values not, no key near a runner.

Tag the boundary ([using the course §5](../using-the-course.md#5-tags-at-every-boundary)):

```sh
git tag stage-12 \
&& git push origin stage-12 \
&& gh issue close 16 --comment "stage-12 tagged"
```

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| No comment appears | Actions disabled on the repo, or the job failed before its last step | Repo → Actions tab, or `gh run list --workflow=rendered-diff` and read the failed step's log |
| `Resource not accessible by integration` on commenting | The workflow's `permissions:` block missing or trimmed | `pull-requests: write` is required; the default token is read-only without it |
| Comment shows a `BUILD FAILED` block | The PR genuinely breaks a render; this is the feature | Fix the overlay; the reviewer just got saved a red cluster |
| Comment names a root the PR did not touch | Something the PR changed is consumed there: a base, a component, a shared file. This is the feature too | Read that root's diff; if the fan-out was not intended, the change belongs on an overlay |
| CI's render differs from your local one | Local kustomize drifted off the pin | `./scripts/check-kustomize-flux-parity`; CI reads the pin, workstations rot |

## What you learned

Review the render, not the diff: CI now computes what every root *becomes* under a PR, with the repo's own pinned renderer, and puts it where the approval happens. Small-diff/wide-radius changes stopped being reviewable by vibes. **Next:** [stage 14, image automation](stage-14.md) adds the robot whose PRs this comment will keep honest.

---

**Next:** [13 - Platform promotion (change the ingress version)](stage-13.md)
