# Stage 07 - Environments & promotion

[← 06 - Secrets](stage-06.md) · [Walkthrough index](../README.md)

> **Where you are:** the config repo root, on `main`. **Starting state:** stage 06's end state. One cluster (`kind-ggp-local-01`), secrets encrypted, all checkpoints green. **This stage ends with three clusters**, so from here on **every kubectl/flux command carries an explicit `--context`**: implicit current-context is how you break prod. That's a convention from this point forward, not a suggestion.

**Goal:** the fleet exists. `dev/dev-01` and `prod/prod-01` join `platform/local-01` in the layout that was deliberately "too deep" back in stage 03; a change promotes dev → prod **by PR**; and the whole platform proves itself as a disposable test environment (environment zero).

These two kind clusters are **stand-ins with a planned retirement**: Act VIII stands up AKS clusters as new fleet members and moves the stamps onto them by binding-move PR. (Terminology, once per page: a *stamp* is a Flux `Kustomization` CR; a cluster's *binding* is its `clusters/<class>/<cluster>/resources/` folder, the stamps and notification wiring it runs.) The layout you exercise here *is* the migration path.

## Steps

### 1. The version ladder - then two more clusters, each with its own ports

The fleet does **not** run one Kubernetes version, on purpose. `clusters/versions.yaml` pins a minor per class: **platform tests next, dev is current, prod is stable**, because that's what a real fleet looks like mid-rollout, which is always. It is also AKS's support window (N..N-2): when Act VIII absorbs the fleet, next/current/stable is exactly the set of minors a managed cluster is allowed to run. Upgrades enter at platform (the cluster nobody misses), soak, then walk down the ladder one PR per rung. No controller enforces any of this: the ladder is folders, PR discipline and evidence, a practice you guard ([rule 5.4](../rules.md#54-the-ladder-is-a-practice-not-a-mechanism)).

The constraint that falls out: **kubectl's client skew is ±1 minor, and the ladder spans three**, so only the *middle* rung reaches every cluster. The rule, enforced not remembered: **kubectl pins to the dev class**, and a dev upgrade PR bumps the kubectl pin in the same diff.

Declare the ladder in the pin file stage 06 created, and declare it the way that file demands: **derived, never guessed**. The minors are not this page's to state, because AKS's window moves and this page does not; the master is AKS's own release calendar ([rule 4.3](../rules.md#43-the-version-policy-follow-the-master-at-the-pace-kubernetes-sets)). `scripts/derive-ladder` scrapes the calendar for the three minors AKS supports today and asks the kindest/node registry for the newest patch image of each. Read what it derived; the numbers below are the window as this stage was written, and yours are today's:

```sh
./scripts/derive-ladder
# → AKS support window today: 1.36 1.35 1.34   (source: the AKS release calendar)
# →   platform  minor 1.36   node_image kindest/node:v1.36.4
# →   dev       minor 1.35   node_image kindest/node:v1.35.8   (kubectl pins here)
# →   prod      minor 1.34   node_image kindest/node:v1.34.11
```

Then write it. It appends to `clusters/versions.yaml`, and the fleet PR below carries it, so the declaration and the clusters it shapes land as one change. Derivation happens exactly once: from here the ladder moves only by PR (stage 16 climbs it), `derive-ladder` refuses to touch a declared ladder, and `scripts/check-k8s-aks-parity` (part of `./scripts/check` from now on) fails the day AKS's window moves on without the fleet:

```sh
./scripts/derive-ladder --write
```

Gate before creating anything:

```sh
# FAILs if your kubectl isn't on the dev rung - it hands out the pinned install command
./scripts/check-version-ladder
```

If it failed on your kubectl (a 1.36 client cannot legally talk to 1.34 prod), install the pinned one and re-run until green.

**Before the fleet: raise the host's inotify limits (Linux).** Every kind node shares the *host* kernel, and `fs.inotify.max_user_instances`/`max_user_watches` are **per-user** budgets, so three clusters' worth of kubelets, containerds and controllers drain one allowance, and distro defaults (`128` instances on Fedora) are sized for a desktop, not a fleet. Exhaustion looks like unrelated failures: pods crashlooping with `too many open files`, `failed to create fsnotify watcher`, a new cluster's control plane never going Ready. Check where you stand:

```sh
# the fleet needs at least: max_user_instances 1024, max_user_watches 524288
sysctl fs.inotify.max_user_instances fs.inotify.max_user_watches
```

If both values already meet those numbers, skip the block below; `cluster-up` warns at the same threshold, so a quiet cluster-up later means this stayed true. Otherwise raise and persist (kind's documented recommendation; no reboot needed):

```sh
sudo tee /etc/sysctl.d/99-kind-fleet.conf >/dev/null <<'EOF'
fs.inotify.max_user_instances = 1024
fs.inotify.max_user_watches = 524288
EOF
sudo sysctl --system >/dev/null
```

Side effects, honestly: the *limits* cost nothing. Kernel memory is consumed only by watches actually created (~1KB of unswappable memory each, so the watch ceiling bounds worst-case use at ~0.5GB). The conservative defaults exist as denial-of-service containment on multi-user systems. A higher per-user cap lets one runaway process pin more kernel memory. On a single-operator dev machine that trade is fine; on a shared box, know you're widening it. (macOS: these limits live inside the docker VM, which ships fleet-tolerant defaults, so this step is Linux-only.)

Then the clusters, each built from its class pin:

```sh
CLASS=dev  CLUSTER_NAME=ggp-dev-01  HTTP_PORT=8081 HTTPS_PORT=8444 ./scripts/cluster-up
CLASS=prod CLUSTER_NAME=ggp-prod-01 HTTP_PORT=8082 HTTPS_PORT=8445 ./scripts/cluster-up
```

> `ggp-local-01` was created before the ladder existed, on kind's bundled default node image - usually the platform pin, but that is the kind project's choice, not yours. `check-version-ladder` verifies live clusters against their class pins, so if the default drifted, this gate FAILs for `ggp-local-01` and prescribes the one-command rebuild.

Budget note: three kind clusters is roughly 3GB of RAM. And a naming note: kind names follow one rule, `ggp-<cluster-id>`, matching the git folders (`clusters/platform/local-01` runs as `ggp-local-01`). Even so, cluster *identity* lives in the git folder, not in the infra name: real fleets accrete legacy names, and a binding survives a renamed or replaced cluster unchanged, which Act VIII uses on purpose.

### 2. Bootstrap each into its own path

Each cluster gets its own bootstrap path and its own root key. `dev-01` holds only the dev class key; `prod-01` only prod. A cluster holds exactly the class keys for the stamps it hosts:

Each cluster's `flux-system/` is generated exactly as local-01's was at stage 03: same three files, its own path. All of it lands in one PR, because two clusters joining the fleet is one change:

```sh
source ./env.sh
for c in dev/dev-01 prod/prod-01; do
  mkdir -p clusters/$c/flux-system
  flux install --export > clusters/$c/flux-system/gotk-components.yaml
  flux create source git flux-system \
    --url=ssh://git@github.com/$GH_OWNER/$CONFIG_REPO --branch=main --interval=1m \
    --secret-ref=flux-system \
    --export > clusters/$c/flux-system/gotk-sync.yaml
  flux create kustomization flux-system \
    --source=GitRepository/flux-system --path=./clusters/$c \
    --prune --interval=10m \
    --export >> clusters/$c/flux-system/gotk-sync.yaml
  cp clusters/platform/local-01/flux-system/kustomization.yaml clusters/$c/flux-system/
done
git add clusters
./scripts/pr-open feat/9/fleet-dev-prod "feat(clusters): dev-01 and prod-01 join the fleet" <<'EOF'
## What is moving
Flux's components and self-sync pair for clusters/dev/dev-01 and clusters/prod/prod-01, each on its own path.

## Why now
The fleet exists from this merge; the two clusters are pointed at it in the next block.

## Evidence
Generated by the pinned CLI; each gotk-sync.yaml differs from local-01's by its path alone (diff them).

## If it is wrong
Nothing runs from it yet; revert this merge and regenerate.

Refs: #9
EOF
```

Read it; when the diff is what the body claims:

```sh
gh pr merge --merge --delete-branch \
&& git switch main \
&& git pull
```

Then point each cluster at its folder, and give each exactly the class key for the stamps it will host:

```sh
./scripts/cluster-sync clusters/dev/dev-01 --context kind-ggp-dev-01
kubectl --context kind-ggp-dev-01 -n flux-system create secret generic sops-age \
  --from-file=age.agekey=$HOME/.config/gitops-golden-path/age/dev.agekey

./scripts/cluster-sync clusters/prod/prod-01 --context kind-ggp-prod-01
kubectl --context kind-ggp-prod-01 -n flux-system create secret generic sops-age \
  --from-file=age.agekey=$HOME/.config/gitops-golden-path/age/prod.agekey
```

**Operator's aside (optional, skip freely):** from here on you're running a fleet from one terminal, and a per-cluster cockpit earns its keep. [k9s](https://k9scli.io) plus a multiplexer is the idiom. Both come straight from your package manager: `sudo dnf install k9s tmux` / `sudo apt install k9s tmux` / `brew install k9s tmux` (k9s also ships single-binary [releases](https://github.com/derailed/k9s/releases) if your distro lacks it). That channel is *correct* here, in pointed contrast to stage 06: "a package manager can't install a pin" cuts both ways, and for tools you deliberately don't pin, it's exactly the right installer. One pane per cluster, each *pinned* to its context, prod read-only:

```sh
tmux new-session -d -s fleet "k9s --context kind-ggp-local-01"
tmux split-window -h "k9s --context kind-ggp-dev-01"
tmux split-window -h "k9s --context kind-ggp-prod-01 --readonly"
tmux select-layout even-horizontal
tmux attach -t fleet
```

Note what this reinforces rather than replaces: pinned panes are the visual form of this stage's explicit-`--context` convention (no pane ever *is* an ambient current-context), and `--readonly` on prod is the promotion discipline as a UI property. And note what it is *not*: k9s answers questions about the cluster you're looking at; stage 09 exists for the question that matters at fleet scale: which of many stamps is unhealthy, and since when. No amount of panes answers that. Checkpoints remain the verification mechanism throughout; k9s is unpinned and unmanaged by `versions.yaml` deliberately (a read-mostly client feeding your eyeballs, not the cluster, so the render rule has no claim on it).

### 3. Bindings - the cluster is what its folder says

Each cluster's folder gets the same resource kinds `local-01` has: stamps, secrets, notification wiring. Dev first. It runs the dev overlay plus the infrastructure tree:

```sh
mkdir -p clusters/dev/dev-01/resources clusters/dev/dev-01/secrets

for f in infrastructure.kustomization.yaml infrastructure-status.alert.yaml \
         app-dev.kustomization.yaml app-dev-status.alert.yaml \
         cluster-secrets.kustomization.yaml cluster-secrets-status.alert.yaml \
         github-status.provider.yaml; do
  cp clusters/platform/local-01/resources/$f clusters/dev/dev-01/resources/
done
yq -i '.spec.path = "./clusters/dev/dev-01/secrets"' \
  clusters/dev/dev-01/resources/cluster-secrets.kustomization.yaml

# every cluster root is explicit, same reason as stage 06: secrets/ must stay off the bootstrap stamp's list
cp clusters/platform/local-01/kustomization.yaml clusters/dev/dev-01/kustomization.yaml
(cd clusters/dev/dev-01/resources && kustomize create --autodetect)

kubectl create secret generic github-status-token \
  --namespace flux-system --from-literal=token=$(gh auth token) \
  --dry-run=client -o yaml > clusters/dev/dev-01/secrets/github-status-token.secret.yaml
sops encrypt --in-place clusters/dev/dev-01/secrets/github-status-token.secret.yaml
(cd clusters/dev/dev-01/secrets && kustomize create --autodetect)
```

Prod is the same shape pointed at the prod overlay. The stamp is named `app-prod` and the file is named after it:

```sh
mkdir -p clusters/prod/prod-01/resources clusters/prod/prod-01/secrets

for f in infrastructure.kustomization.yaml infrastructure-status.alert.yaml \
         cluster-secrets.kustomization.yaml cluster-secrets-status.alert.yaml \
         github-status.provider.yaml; do
  cp clusters/platform/local-01/resources/$f clusters/prod/prod-01/resources/
done
yq -i '.spec.path = "./clusters/prod/prod-01/secrets"' \
  clusters/prod/prod-01/resources/cluster-secrets.kustomization.yaml

cp clusters/platform/local-01/kustomization.yaml clusters/prod/prod-01/kustomization.yaml

sed -e 's/app-dev/app-prod/g' -e 's#overlays/dev#overlays/prod#' \
  clusters/platform/local-01/resources/app-dev.kustomization.yaml \
  > clusters/prod/prod-01/resources/app-prod.kustomization.yaml
sed 's/app-dev/app-prod/g' \
  clusters/platform/local-01/resources/app-dev-status.alert.yaml \
  > clusters/prod/prod-01/resources/app-prod-status.alert.yaml
(cd clusters/prod/prod-01/resources && kustomize create --autodetect)

kubectl create secret generic github-status-token \
  --namespace flux-system --from-literal=token=$(gh auth token) \
  --dry-run=client -o yaml > clusters/prod/prod-01/secrets/github-status-token.secret.yaml
sops encrypt --in-place clusters/prod/prod-01/secrets/github-status-token.secret.yaml
(cd clusters/prod/prod-01/secrets && kustomize create --autodetect)
```

**Declared status identity.** One more per-cluster edit while the folders are open: the hex in each status context (`kustomization/app-dev/e3173055`) is the Provider object's truncated **UID**. That is accidental identity, and unstable: recreate a Provider and the suffix changes, orphaning the history thread. Each cluster's folder owns its Provider, so declare the suffix instead (`commitStatusExpr` is a CEL expression the notification-controller evaluates per event):

```sh
for c in platform/local-01 dev/dev-01 prod/prod-01; do
  EXPR="(event.involvedObject.kind + '/' + event.involvedObject.name).lowerAscii() + '/$(basename $c)'" \
    yq -i '.spec.commitStatusExpr = strenv(EXPR)' clusters/$c/resources/github-status.provider.yaml
done
```

Contexts now read `kustomization/app-dev/dev-01`: the name says *what* (which stamp, which overlay), the suffix says *where*, and both are declared in git rather than borrowed from a runtime UID. (Old commits keep their hex-suffixed statuses; the seam is harmless and dates the change.)

Expect the merge carrying this change to **race its own statuses**: every stamp reconciles the new revision, and each status is formatted with the Provider as it exists *at that moment in that cluster*. Events firing before the cluster applies the new Provider still go out hex-suffixed, so this one commit shows mostly hex, possibly both forms for a stamp that re-fired. Nothing is wrong; a notification-pipeline change can only affect the next event, never re-format ones already sent. The next merge wears declared names everywhere (or force it now: `flux reconcile` on a stamp emits a fresh event, re-stamping the current revision).

The prod overlay also gets an explicit image pin. **Prod is always pinned; the ladder is visible as a diff between overlay pins**:

```sh
source ./env.sh
(cd apps/overlays/prod && kustomize edit set image $APP_IMAGE:0.1.0)

git add clusters apps/overlays/prod
./scripts/pr-open bind/9/dev-prod "bind(clusters): dev-01 and prod-01; prod pinned behind dev" <<'EOF'
## What is moving
Bindings for dev-01 (app-dev, infrastructure, cluster-secrets) and prod-01 (app-prod, infrastructure, cluster-secrets), each with its Provider and Alerts; every Provider declares its status suffix; prod's overlay pinned to 0.1.0.

## Why now
The clusters sync but run nothing; this is what each one is.

## Evidence
The two new bindings are local-01's, re-pathed; the status suffix is declared, not borrowed from a UID; prod trails dev by one pin, visibly.

## If it is wrong
Revert this merge; prune empties the two clusters.

Refs: #9
EOF
```

Read it; when the diff is what the body claims:

```sh
gh pr merge --merge --delete-branch \
&& git switch main \
&& git pull
flux reconcile kustomization flux-system --with-source --context kind-ggp-dev-01
flux reconcile kustomization flux-system --with-source --context kind-ggp-prod-01
```

Gate: the merge commit should now collect **status contexts from multiple clusters** (`kustomization/app-dev/dev-01`, `kustomization/app-prod/prod-01`, …). The full set is one context per stamp per cluster. The `infrastructure` ones land late (each new cluster cold-installs Traefik first), and note the ordering you'll see meanwhile: apps go green before the infrastructure they stand on, because nothing enforces that ordering yet. Stage 08's `dependsOn` exists for exactly this. The suffix stage 04 explained finally earns its keep. Same stamp names, distinguishable verdicts, now with declared names doing the distinguishing:

```sh
gh api "repos/{owner}/{repo}/commits/$(git rev-parse HEAD)/status" \
  --jq '.statuses[] | .context + "  " + .state'
```

### 4. Promotion is a PR that moves a pin

Dev already runs a newer version than prod (compare the overlay pins). Promoting is copying the pin. The pin is a tag for now, and a tag is a label a registry lets anyone move; from [stage 14](../act-4/stage-14.md), when a robot starts writing pins, the pin names the artifact itself, by digest. Every change here has been a PR since stage 02; what is new is that this one **carries evidence**: dev's green context on the source commit is the case for the change, and the body is where it goes. The seven lines in full once more, because this is the PR the rest of the course keeps coming back to:

```sh
source ./env.sh
git switch -c promote/9/app
tag=$(yq '.images[0].newTag' apps/overlays/dev/kustomization.yaml)
(cd apps/overlays/prod && kustomize edit set image $APP_IMAGE:$tag)
git add apps/overlays/prod
git commit -m "promote(app-prod): app $tag"
git push -u origin promote/9/app
gh pr create --title "promote(app-prod): app $tag" \
  --body "Normally a comprehensive description goes here: what's moving, why now, and the evidence - for this ladder, the dev rung's green kustomization/app-dev/dev-01 context on the source commit.

Refs: #9"
```

> The PR body matters more than it looks: the merged PR *is* the deployment record ([rule 2.2](../rules.md#22-the-pr-convention-the-title-is-the-commit-the-body-is-the-deployment-record)), and `--fill` would copy the one-line commit and leave it empty. A real promotion PR carries the case for the change; here a placeholder marks the slot.

This is the first PR whose merge commit a *production* cluster will run, so the merge policy, **merge commit only, squash and rebase disabled, the PR title as the merge subject**, and the ruleset that makes the PR unavoidable both matter for the first time in a way that costs something. Both were set at stage 00 step 1 ([rule 1.2](../rules.md#12-repository-configuration-the-merge-policy-is-set-before-the-first-pr), [rule 1.3](../rules.md#13-protection-from-day-zero-nothing-reaches-main-except-a-merged-pr)); read them back before relying on them, because a repo setting is exactly the kind of thing a colleague "tidies":

```sh
gh api "repos/{owner}/{repo}" \
  --jq '"merge: \(.allow_merge_commit)  squash: \(.allow_squash_merge)  rebase: \(.allow_rebase_merge)  subject: \(.merge_commit_title)  body: \(.merge_commit_message)"'
# → merge: true  squash: false  rebase: false  subject: PR_TITLE  body: PR_BODY
#   (anything else: re-run the stage-00 block)
gh api "repos/{owner}/{repo}/rules/branches/main" --jq '[.[].type] | join("  ")'
# → deletion  non_fast_forward  pull_request   (anything less: the ruleset was "tidied")
```

Three reasons, all of which bite later in this course. **The merge commit is the only thing that points at the PR**: `git log --first-parent` is then the shipped-changes view and the full log the change-level view, which is exactly the split stage 26 needs for per-cluster release notes. **Squash replaces your commit** with one whose subject is the title plus ` (#N)` and whose body concatenates the branch messages: what you wrote is a fiction that never reaches `main`. (The merge commit's subject gains the same ` (#N)` suffix, but your commit lands beneath it, untouched.) And the Act II checkpoint looks promotions up *by subject*. **Rebase and squash both rewrite shas**, and a cluster's `lastAppliedRevision` is a sha it reported hours ago; rewrite it and the revision your fleet says it is running no longer exists.

The two `merge_commit_*` flags are the load-bearing half: GitHub's default merge subject is `Merge pull request #1 from owner/branch`, which puts the PR title on line 3 and makes the merge commit itself violate the [commit convention](../appendices/commit-convention.md) however carefully you titled the PR. `PR_TITLE` makes the subject the PR title; `PR_BODY` brings the body and its trailers down with it. Which promotes the **PR title to a first-class artifact**: it is the subject that reaches `main`. Full rationale: [the git policy](../appendices/git-policy.md).

Gate: read the PR diff. One line, the prod pin. That *is* the blast radius. (`scripts/pr-open` prints this read-back for you; going raw means the gate is yours to run):

```sh
gh pr diff
```

Then:

```sh
gh pr merge --merge --delete-branch
git switch main && git pull
```

Watch the merge commit's `app-prod` context go green: merge → reconcile → prod runs it, no kubectl anywhere.

**Every cluster reconciles every commit; that is not the same as every cluster changing.** All three clusters share one source, so all three fetch this commit and re-run their stamps. You will see that on the dashboard, because they briefly report it. But only prod's render *differs*, so only prod applies anything; dev and platform re-apply what they already had. **Reconcile scope is the whole repo; change scope is whichever paths a commit touched.**

Which is precisely why review has to be *path-aware*, and why the folder layout is a security control rather than tidiness. A one-line pin under `apps/overlays/prod/` reaches one cluster. The same one-line edit under `apps/base/` reaches **all of them, at once, with no promotion**: the ladder is only a ladder for things that live on a rung. The paths worth naming as protected, each for its own reason:

| Path | Why it needs its own reviewers |
|---|---|
| `apps/base/` | fans out to every environment simultaneously: the ladder cannot gate what isn't per-rung |
| `apps/overlays/prod/` | the production rung: the thing the whole ladder exists to protect |
| `clusters/` | the bindings: which stamp exists on which cluster, and what it points at. An edit here never touches a render's content; it changes which renders the cluster receives at all - *what the cluster is composed of*, a bigger move than any pin |
| `infrastructure/` | shared platform, every workload's blast radius |
| `.sops.yaml`, `secrets/` | the file *is* the access-control list ([stage 18](../act-5/stage-18.md)) |
| `policy/`, `.github/workflows/` | the gates themselves: a PR that weakens the check should be harder to merge than one that fails it |

The mechanism is `CODEOWNERS` plus the ruleset requiring owner review, and it composes with everything else here: [stage 12](../act-4/stage-12.md) shows the reviewer the *rendered* blast radius, CODEOWNERS makes sure the right reviewer is looking: blast radius and reviewer, the two halves of a review that means something. The ruleset already refuses anything that is not a PR; what it cannot yet do is say *whose* PR. [stage 21](../act-5/stage-21.md) adds that to the ruleset stage 00 created. Adopt the ladder on your own platform without it and you have folders that *describe* a promotion boundary without *enforcing* one.

**One more thing these two overlays are quietly doing.** `dev` and `prod` currently carry two meanings at once: *which rung of the ladder* and *which instance of the app*. That holds exactly while those are the same thing. Add a second customer and they separate permanently: an environment is a **rung** (things move through it sequentially, gated by evidence), a tenant is a **replica** (instances fan out in parallel, identical by default). [stage 22](../act-6/stage-22.md) performs that separation on two tenants, which is where the structural mistakes are cheap.

### 5. Branch-per-env: the antipattern, named

The road not taken: a `dev` branch, a `prod` branch, "promotion" as merges between them. It fails predictably: branches drift (hotfixes land on one, never the other), merge conflicts appear in *config* that no one authored, "what's on prod" requires branch archaeology, and every tool that assumes main-is-truth breaks. **Environments are folders on one branch, promotion is a pin move on main.** One history, one truth, promotion as an ordinary reviewed diff. (Flux's own docs take the same position; we're not being contrarian, we're being current.)

### 6. Environment zero - the platform as a disposable test rig

The second stated goal of the repo, now demonstrable in one block: a throwaway cluster running the *whole platform* from a feature branch, without bootstrap: no per-cluster deploy key, no `flux-system` commits, nothing on this cluster can ever write to git. One honest caveat before the block: "no credentials at all" is a **public-repo** property. A private config repo still needs a *read* credential, or the clone fails with GitHub's deliberately misleading `authentication required: Repository not found`. Private repos hide their very existence from anonymous callers, so bad auth wears a 404 costume. We borrow the session token the bootstraps already used; it's over-powered for the job, which is tolerable only because this cluster is minutes from deletion. A rig that lives longer deserves a fine-grained read-only PAT. (Public repo? The secret is harmless and the block works unchanged.)

```sh
source ./env.sh
git switch -c feat/9/env-zero-demo && git push -u origin feat/9/env-zero-demo
CLUSTER_NAME=ggp-zero HTTP_PORT=8083 HTTPS_PORT=8446 ./scripts/cluster-up
flux install --context kind-ggp-zero
flux create secret git platform-read --context kind-ggp-zero \
  --url=https://github.com/$GH_OWNER/$CONFIG_REPO \
  --username=git --password=$(gh auth token)
flux create source git platform --context kind-ggp-zero \
  --url=https://github.com/$GH_OWNER/$CONFIG_REPO \
  --branch=feat/9/env-zero-demo --interval=1m --secret-ref=platform-read
kubectl --context kind-ggp-zero -n flux-system create secret generic sops-age \
  --from-file=age.agekey=$HOME/.config/gitops-golden-path/age/dev.agekey
flux create kustomization app-dev --context kind-ggp-zero \
  --source=GitRepository/platform --path=./apps/overlays/dev \
  --prune=true --wait=true --interval=5m --decryption-provider=sops --decryption-secret=sops-age
```

Watch it assemble. In a second terminal, `--watch` streams every status transition as the platform materializes on the bare cluster:

```sh
flux get kustomizations --context kind-ggp-zero --watch
```

Nothing here is env-zero-specific: swap the context and this is the live view of any reconciliation in the course: the fleet bootstraps in step 2, a promotion landing, a break going red. It's the streaming counterpart to the one-shot `flux get` you've been running since stage 03.

Anything pushed to the branch is live on `ggp-zero` within a minute, a full-fidelity environment ahead of the dev→prod ladder. Then throw it away, because that's the point:

```sh
CLUSTER_NAME=ggp-zero ./scripts/cluster-down
# deleting the cluster that owned current-context UNSETS it - restore a deliberate one
kubectl config use-context kind-ggp-local-01
git switch main \
&& git push origin --delete feat/9/env-zero-demo \
&& git branch -D feat/9/env-zero-demo
```

## Stop & measure

- [ ] The ladder gate and the stage checkpoint both report all PASS, exit 0 (the fleet exists: three clusters, each running what its folder says). The bullets below are the live half unpacked:

```sh
./scripts/check-version-ladder && ./scripts/checkpoint-07
```

- [ ] Both new clusters answer through their own ingress (`/healthz`, not `/`: the app has no root route):

```sh
curl -s http://localhost:8081/healthz; echo   # {"status":"ok"} - dev-01
curl -s http://localhost:8082/healthz; echo   # {"status":"ok"} - prod-01
```

- [ ] After step 4, dev and prod pin the **same** app version; before it, prod trailed. And the ladder is legible in prod's own history:

```sh
yq '.images[0].newTag' apps/overlays/dev/kustomization.yaml apps/overlays/prod/kustomization.yaml
# → the same tag, twice
git log --oneline -- apps/overlays/prod
# → today's promote(app-prod) at the top; every version prod ever ran is a line here
```

Tag the boundary ([using the course §5](../using-the-course.md#5-tags-at-every-boundary)):

```sh
git tag stage-07 \
&& git push origin stage-07 \
&& gh issue close 9 --comment "stage-07 tagged"
```

## Audit artifacts produced

- **The promotion record is the PR**: author, approver, diff, timestamps, and the per-cluster statuses on the merge commit. "Who approved what's on prod and when did it land" is a link, not a meeting.
- Per-cluster status contexts on every commit: one commit, N verdicts, attributable to named clusters.
- `clusters/` is now a fleet manifest: what runs where is `ls` and `grep`, exactly the property the DR scenarios rely on.

## AI enhancement

**How.** The `promote` skill opens the promotion PR of step 4 on evidence: it reads the lower rung's pin and applied revision, checks the green context on the source commit, runs `slo-gate` (from stage 09 on), `freeze-gate` and `path-gate`, renders the overlay before and after the pin edit, and writes the body as the deployment record with every gate's output quoted. It stops at the PR; you merge after the diff. Call it with the stamp and the target rung; the version is never an argument, it is read from the rung below.

**Why.** A promotion is one line and a paragraph of evidence, and the paragraph is where hand-written PRs go thin. The skill sequences the checks and refuses on a red or absent signature in the gate's own words. The gates decide; the skill assembles.

**Where.** Step 4, the second time you promote. The first promotion is typed by hand so the seven lines are yours.

**Verify.** The PR diff is exactly the pin. The body's evidence lines match what `gh api .../statuses` and `slo-gate` print when you run them yourself. The version proposed is the lower rung's current, not newer. The skill did not merge.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Command hit the wrong cluster | Implicit current-context | The stage-top convention exists because everyone does this once. `--context` on everything; check with `kubectl config current-context` |
| Bare `kubectl`/`flux` says `the server could not find the requested resource` (even `get --raw /readyz`), days after env zero | Three-layer trap: `kind delete cluster` unset current-context (env zero owned it); contextless clients fall back to `localhost:8080`; that's *this course's Traefik port*: an ingress 404 wearing an API-server costume | `kubectl config use-context kind-ggp-local-01` (step 6's teardown now does). And note the convention just proved itself: every `--context`-carrying command kept working the whole time |
| Bootstrap for dev-01 undid nothing but git has a new commit | Expected: each bootstrap commits its own `flux-system` manifests | `git pull` before your next edit (step 2 does) |
| `port is already allocated` on cluster-up | Host port pair clashes with an existing cluster | Each cluster gets its own `HTTP_PORT`/`HTTPS_PORT` pair (8080/8081/8082 here) |
| prod-01 red on `cluster-secrets`: `failed to decrypt` | Its token secret was encrypted before `.sops.yaml` had a prod rule, or with the wrong path | Re-encrypt: `sops encrypt --in-place` from the repo root after fixing the rule |
| Statuses from dev and prod overwrite each other | They don't: contexts differ by suffix (declared per cluster in step 3; Provider-UID hex before that) | If you only see one, the other cluster's Provider/Alert or token secret is missing (the allowlist lesson, per cluster) |
| `ggp-zero`'s GitRepository never Ready: `authentication required: Repository not found` (and the Kustomization reports `Source artifact not found`) | The config repo is private and the source cloned anonymously: GitHub hides private repos' existence, so bad auth reads as "not found" | Step 6's `platform-read` secret + `--secret-ref` on the source; re-running the `flux create source git` line updates it in place |
| Laptop fans on takeoff | Three clusters is the budgeted load; environment zero makes it four | Tear down `ggp-zero` when done (step 6 does); it's disposable by design |
| Pods crashloop with `too many open files` / `failed to create fsnotify watcher`; a new cluster never goes Ready, often on the cluster you *didn't* just touch | Per-user inotify exhaustion: all kind nodes share the host kernel, and the fleet drained `fs.inotify.max_user_instances` (distro defaults are single-cluster-sized) | The sysctl block at the top of step 1: raise `max_user_instances` to 1024 and `max_user_watches` to 524288, persisted via `/etc/sysctl.d/` |
| Raised the limit, but `sysctl -n` still shows the old value | Another `sysctl.d` file sorts later and wins: `sysctl --system` applies files in lexical order, and desktop daemons write their own (KDE's `kde-inotify-survey` auto-generates `50-kde-inotify-survey-*.conf` when it sees exhaustion) | `grep -rn max_user /etc/sysctl.d/ /usr/lib/sysctl.d/` to find every writer; the step-1 file is named `99-…` precisely so it applies last. Keep it that way, and leave auto-generated files alone (they regenerate) |
| kubectl errors only against prod (`unsupported version skew` or odd API failures) | Client is on 1.36 and prod is 1.34, outside ±1 | The ladder rule exists for this: `./scripts/check-version-ladder` and install the dev-rung kubectl it prescribes |
| A cluster runs the wrong minor for its class | Built before the ladder file, or with a stale `KIND_NODE_IMAGE` | Rebuild it: `CLASS=<class> ./scripts/cluster-up` after `cluster-down`. Versions are pins, clusters are replaceable |

## What you learned, and what's next

Environments are folders, promotion is a reviewed pin move, and the same commit now carries a verdict per cluster. The fleet layout stopped being speculative: bindings, class keys, and statuses all did fleet work this stage. Still manual: ordering between infrastructure and apps is luck, and nothing enforces workload standards. Stage 08 fixes both.

**Where the ladder starts earning: Act IV.** Everything above was rehearsed by hand once; Act IV makes it *operated*, in the order the gates need: [stage 11: shift left](../act-4/stage-11.md) makes every later commit born gated, [stage 12: rendered diff](../act-4/stage-12.md) puts every future PR's rendered blast radius into the PR, [stage 13: platform promotion](../act-4/stage-13.md) gives the platform itself a per-class pin and hands it to Renovate (it restructures `infrastructure/`, which is why it waits until stages 08–09 are verified), [stage 14: image automation](../act-4/stage-14.md) hires the robot for the dev rung with exactly the human's dev privileges, [stage 15](../act-4/stage-15.md) makes the build *tell* the robot instead of the robot polling, and [stage 16: version rollout](../act-4/stage-16.md) climbs the whole version ladder one minor. The standing procedure, repeatable whenever kind ships the next rung.

---

**Next:** [Act II checkpoint](act-checkpoint.md)