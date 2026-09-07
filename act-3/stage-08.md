# Stage 08 - Dependencies & health

[← Act III checkpoint](../act-2/act-checkpoint.md) · [Walkthrough index](../README.md)

> **Where you are:** the config repo root, on `main`, three clusters live. **Starting state:** stage 07's end state: fleet bound, promotion rehearsed, `checkpoint-07` passing.

**Goal:** the ordering the folders imply becomes enforced (`dependsOn`), health becomes something stamps (the Flux `Kustomization` CRs applying each git path, stage 03's coinage) *wait for* rather than hope for, and workload standards arrive as a **Kustomize component applied in git and validated at gates**, the paired-controls rule's first appearance ([rule 5.6](../rules.md#56-apply-in-git-validate-at-gates-never-mutate-at-admission)). This stage arms six hardening standards in one change and lets the health layer judge the rollout, including an honest check for hardening's most famous wound.

## Steps

### 1. `dependsOn` - ordering as declaration

Today `app-dev` and `infrastructure` race at every cold start; apps have won by luck. Declare the truth on every cluster's app stamp: apps stand on infrastructure and secrets. Note the *how*: the obvious move is a `yq` edit, and it would be wrong. yq's emitter re-indents every sequence in a file to its own house style (indented dashes, no option to match kustomize/flux's indentless style), so a list-bearing yq edit silently reformats the file into exactly what stage 11's style gate rejects. The owning tool **re-authors** the file instead. Same flags as stage 03/06 plus two new ones, and the diff is precisely the added `dependsOn` and `retryInterval`:

```sh
for c in platform/local-01:app-dev:dev dev/dev-01:app-dev:dev prod/prod-01:app-prod:prod; do
  path=${c%%:*}; rest=${c#*:}; stamp=${rest%%:*}; overlay=${rest#*:}
  flux create kustomization $stamp \
    --source=GitRepository/flux-system --path="./apps/overlays/$overlay" \
    --prune --wait --health-check-timeout=3m --interval=5m --retry-interval=30s \
    --depends-on=cluster-secrets,infrastructure \
    --decryption-provider=sops --decryption-secret=sops-age \
    --export > clusters/$path/resources/$stamp.kustomization.yaml
done
git diff clusters   # read it: the dependsOn block and retryInterval are the change that matters
```

`cluster-secrets` decrypts too, and is what the app stamps now stand on, so it gets the retry as well. Same flags as stage 06, one more:

```sh
for path in platform/local-01 dev/dev-01 prod/prod-01; do
  flux create kustomization cluster-secrets \
    --source=GitRepository/flux-system --path="./clusters/$path/secrets" \
    --prune --wait --health-check-timeout=2m --interval=5m --retry-interval=30s \
    --decryption-provider=sops --decryption-secret=sops-age \
    --export > clusters/$path/resources/cluster-secrets.kustomization.yaml
done
git diff clusters/*/*/resources/cluster-secrets.kustomization.yaml   # one added line per cluster
```

Because stage 03 wrote these files by hand (pasted into the file, not emitted by `flux`) and this is their first pass through the tool that owns them, the diff will also show a one-time convergence to flux's emitted style: leading `---`, alphabetical spec keys, `5m0s`-style durations. All of it is semantically identical (the apply is a no-op), and the loop is **idempotent**: re-running it any number of times produces byte-identical files, which is exactly what makes regeneration safe as an editing model.

What it buys: a cold start now reconciles in dependency order, secrets and ingress ready before the app renders, `Retrying dependency not ready` instead of a burst of red. And a failed reconcile retries in 30s: a Secret not there yet, a dependency not Ready. Without `retryInterval` a failure waits out the stamp's `interval`, which is what the Act II checkpoint's rebuild spent most of its minutes doing after the root keys landed. The drift sweep stays at 5m; only failure retries faster. What it doesn't buy: `dependsOn` orders *stamps*, not resources inside one. Within a stamp, `wait: true` (which every stamp here already carries) is the health gate: the stamp isn't Ready until everything it applied is. For sharper gating, `spec.healthChecks` names specific resources. We stay with `wait: true` until a stamp grows too big for it, and say so when one does.

CRD ordering gets the same treatment when it bites: a stamp that ships CRs depends on the stamp that ships their CRDs. (Within one stamp, Flux orders CRDs before CRs itself.)

### 2. The workload baseline, as a component

Standards nobody has to remember: non-root, seccomp, dropped capabilities, read-only root filesystem, resource requests/limits, `imagePullPolicy: IfNotPresent` (safe *because* tags here are immutable, never `:latest`), and TCP probes. Delivered as a **kustomize Component** so every overlay opts in with one line - the mechanism that also carries *variants proper*, the permanent lifecycle of [rule 5.14](../rules.md#514-variants-flags-and-migrations-three-lifecycles-three-homes); stage 09 builds the first two, and flags and migration overlays get their own homes at stage 28 and the migrate-base-config quest:

```sh
mkdir -p apps/components/workload-baseline/patches

cat > apps/components/workload-baseline/patches/app.deployment.patch.yaml <<'EOF'
- op: add
  path: /spec/template/spec/securityContext
  value:
    runAsNonRoot: true
    runAsUser: 1654 # .NET 8+ images ship an `app` user at UID 1654
    seccompProfile:
      type: RuntimeDefault
- op: add
  path: /spec/template/spec/containers/0/securityContext
  value:
    allowPrivilegeEscalation: false
    readOnlyRootFilesystem: true
    capabilities:
      drop:
      - ALL
- op: add
  path: /spec/template/spec/containers/0/resources
  value:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 500m
      memory: 256Mi
- op: add
  path: /spec/template/spec/containers/0/imagePullPolicy
  value: IfNotPresent
- op: add
  path: /spec/template/spec/containers/0/livenessProbe
  value:
    tcpSocket:
      port: http
- op: add
  path: /spec/template/spec/containers/0/readinessProbe
  value:
    tcpSocket:
      port: http
EOF

cat > apps/components/workload-baseline/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1alpha1
kind: Component
patches:
- path: patches/app.deployment.patch.yaml
  target:
    kind: Deployment
    name: app
EOF
```

Scope stated honestly: the baseline targets **our** workload. Azurite is exempt: it's a third-party dev stand-in that runs as root and leaves the story in Act VII; exempting it is a *decision in git*, not an oversight. And read this component as an **example, not a prescription**: one baseline for one kind of workload. A real platform typically carries a *selection*: a web-API baseline like this one, a stricter one for payment or PII services, a looser one for batch jobs that legitimately need scratch disk, a vendor-shaped one for third-party images you can't harden. Each is its own component, each opted into per overlay with the same one line. What to standardise and where to draw the lines is entirely your situation's call; what this step demonstrates is the *mechanism*: components and patches turning "our standards" from a wiki page into composable, reviewable units. The point that matters is that every standard, and every exemption from one, is a deliberate choice recorded in git: reviewed in a PR, visible in the render diff, and traceable to the commit that made it.

The probes reference a port by **name**, so ports get names now, and the stage-05 ingress upgrades from number to name. Three files, and only the port lines change. Not with `yq`: step 1 said why (every list in each file would come back in yq's indented style). These files are hand-written, so the editing model is the one stages 02, 05 and 06 used: write the whole file again, exactly as it should read.

```sh
source ./env.sh
cat > apps/base/resources/app.deployment.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app
  namespace: ggp
  labels:
    app.kubernetes.io/name: app
    app.kubernetes.io/component: api
spec:
  replicas: 1
  selector:
    matchLabels:
      app: app
  template:
    metadata:
      labels:
        app: app
        app.kubernetes.io/name: app
        app.kubernetes.io/component: api
    spec:
      containers:
      - name: app
        image: $APP_IMAGE:0.1.0
        ports:
        - name: http
          containerPort: 8080
        env:
        - name: STORAGE_CONNECTION_STRING
          valueFrom:
            secretKeyRef:
              name: app-secrets
              key: STORAGE_CONNECTION_STRING
EOF

cat > apps/base/resources/app.service.yaml <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: app
  namespace: ggp
  labels:
    app.kubernetes.io/name: app
    app.kubernetes.io/component: api
spec:
  selector:
    app: app
  ports:
  - name: http
    port: 8080
    targetPort: http
EOF

cat > apps/base/resources/app.ingress.yaml <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app
  namespace: ggp
spec:
  ingressClassName: traefik
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: app
            port:
              name: http
EOF
git diff apps/base   # the port lines and nothing else; any other change means the file had drifted
```

Wire the component into both overlays:

```sh
(cd apps/overlays/dev  && kustomize edit add component ../../components/workload-baseline)
(cd apps/overlays/prod && kustomize edit add component ../../components/workload-baseline)
```

### 3. Ship it - and watch the health layer judge it

Merge exactly this: six hardening standards landing on a running service in one change. The classic story says what happens next: `readOnlyRootFilesystem` detonates on .NET's need for a writable `/tmp`, the pod crashloops, the red X arrives. Ship it and watch what *actually* happens:

```sh
git add apps clusters
./scripts/pr-open feat/11/workload-baseline "feat(overlays): workload baseline component and dependsOn ordering" <<'EOF'
## What is moving
A workload-baseline component (six hardening standards) included by every overlay; app stamps now dependsOn cluster-secrets and infrastructure; every decrypting stamp retries a failure at 30s.

## Why now
The fleet runs unhardened workloads, applies apps before the secrets and ingress they need, and waits out a 5m interval after a failed reconcile.

## Evidence
Render diff shows the securityContext on every Deployment; the health layer will judge the rest.

## If it is wrong
Revert this merge - the exemption pattern in the component is the intended fix path instead.

Refs: #11
EOF
```

Read it; when the diff is what the body claims:

```sh
gh pr merge --merge --delete-branch \
&& git switch main \
&& git pull
flux reconcile kustomization app-dev --with-source --context kind-ggp-local-01
```

Gate: the statuses stay **green**, the pod runs with zero restarts, and the baseline is demonstrably live:

```sh
gh api "repos/{owner}/{repo}/commits/$(git rev-parse HEAD)/status" \
  --jq '.statuses[] | .context + "  " + .state'
kubectl --context kind-ggp-local-01 -n ggp get pods -l app=app
kubectl --context kind-ggp-local-01 -n ggp get deploy app \
  -o jsonpath='{.spec.template.spec.containers[0].securityContext}{"\n"}'
curl -s http://localhost:8080/healthz; echo   # ; echo - the reply carries no trailing newline
```

**The wound that doesn't open:** the app sails through fully hardened. Why is worth knowing precisely, because it's the anatomy of every hardening rollout. The famous .NET casualties are all absent from a minimal API: no DataProtection keys written under the home directory (nothing here does auth or antiforgery), the runtime's diagnostics socket in `/tmp` fails *non-fatally* by design, Kestrel binds 8080 without root and needs no disk, and every real write this app performs goes to Azurite over the network. The general lesson survives, inverted: **hardening wounds are app-specific. You find yours by shipping the baseline where failure is cheap, not by trusting a checklist.** The usual suspects when one does open: temp files, key material, cache directories, JVM/CLR scratch paths. For .NET specifically, the full catalogue (DataProtection keys, upload buffering, diagnostics sockets, crash dumps, the runtime-codegen truth, and what AOT changes) is [an appendix](../appendices/dotnet-under-hardening.md).

When a workload of yours *does* hit it (crashloop, `Read-only file system` / `EROFS` in the logs), the fix belongs in the component, not the workload, as an explicit escape hatch per legitimate write path:

```sh
# only if your workload needs it - this course's app doesn't, so this block stays unrun
cat >> apps/components/workload-baseline/patches/app.deployment.patch.yaml <<'EOF'
- op: add
  path: /spec/template/spec/volumes
  value:
  - name: tmp
    emptyDir: {}
- op: add
  path: /spec/template/spec/containers/0/volumeMounts
  value:
  - name: tmp
    mountPath: /tmp
EOF
```

Two honest notes to close the step. First, the health layer *was* on duty the whole time: `wait: true` judged the hardened rollout, so the green is a verdict, not an absence. Stage 09's drills hand that same layer two real failures to catch (an absent image, then a Ready-but-failing config). Second, this step wired the baseline into dev **and prod in one commit**: course brevity, not the discipline. A real platform promotes a baseline like any other change: dev, soak, prod by PR. With [stage 12](../act-4/stage-12.md) in place, that PR carries the full rendered blast radius of every standard.

### 4. The gate: conftest on rendered output, and the first CI

The component *applies* the standards; nothing yet *verifies* them: a later refactor could silently drop the component and everything would stay green. Paired controls: policy checks run against **rendered output** (what the cluster will actually receive), with conftest as a pinned container per the tool-provisioning rule:

```sh
mkdir -p policy
cat > policy/workload-baseline.rego <<'EOF'
package main

deny contains msg if {
  input.kind == "Deployment"
  input.metadata.name == "app"
  not input.spec.template.spec.securityContext.runAsNonRoot
  msg := "app must run as non-root"
}

deny contains msg if {
  input.kind == "Deployment"
  some c in input.spec.template.spec.containers
  endswith(c.image, ":latest")
  msg := sprintf("%s: :latest is banned - immutable tags only", [c.image])
}

deny contains msg if {
  input.kind == "Deployment"
  input.metadata.name == "app"
  some c in input.spec.template.spec.containers
  not c.resources.limits
  msg := sprintf("%s: resource limits required", [c.name])
}
EOF

./scripts/policy-gate
```

The gate is a script, not an inline loop, for a reason that compounds: it's a **pure function over the working tree** (no cluster, no credentials), so the *same file* produces the verdict in every venue: this paste block now, the CI workflow next, and the pre-push git hook when stage 11 arrives. Three venues, one verdict, zero hand-copied drift.

And the identical check in CI, the repo's first workflow, because this is the first check that guards *future* changes rather than verifying present state:

```sh
mkdir -p .github/workflows
cat > .github/workflows/verify.yaml <<'EOF'
name: verify
on:
  pull_request:
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
EOF

git add policy .github
./scripts/pr-open policy/11/gate-ci "policy(overlays): conftest gates the rendered baseline, locally and in CI" <<'EOF'
## What is moving
policy/ (conftest rules over rendered overlays), scripts/policy-gate, and the repo's first workflow running it on every PR and every push to main.

## Why now
The baseline exists; nothing yet stops a PR from weakening it.

## Evidence
policy-gate PASS locally on this tree; this PR is the workflow's first run.

## If it is wrong
Revert this merge; the render is unaffected either way.

Refs: #11
EOF
```

Stop before merging: this is the first PR the repository has *checked*. The workflow you just opened the PR with is triggered by the PR itself, so a check appears on it before you merge. Watch it earn its keep (`--watch` blocks until every check reports, and fails if one fails):

```sh
gh pr checks --watch --fail-fast
```

When the checks report green:

```sh
gh pr merge --merge --delete-branch \
&& git switch main \
&& git pull
```

Then look at where the verdict *lives*: `gh pr view --web` shows the check on the PR; `gh run view --web` opens the run in the Actions tab. The green check was produced by the same `policy-gate` file you ran in your terminal minutes ago. From now on every PR in this repo carries that check *before* merge, and every PR and every merge spends a minute or two of GitHub-hosted runner time, which a private repository meters against the plan's monthly allowance (the README's "Before you start" gives the numbers; a run of the course stays well inside it).

**Now make it a requirement, not a decoration.** A check that merely appears can be merged past; the ruleset from stage 00 can be told to refuse the merge until it passes. One line. The ruleset is *amended*, never rewritten, and this is the first of three times it grows ([rule 1.3](../rules.md#13-protection-from-day-zero-nothing-reaches-main-except-a-merged-pr)):

```sh
./scripts/ruleset require-check rendered-policy     # the job's name is the check's name
./scripts/ruleset show
```

Two design notes while it is fresh. The workflow triggers on `pull_request` *and* on `push` to `main`, and that second trigger is not redundancy: a merge commit is a new commit the PR never contained, so `main` gets its own verdict. Stage 14 will lean on the `push` trigger for a reason that cannot be seen yet. And the check is not *strict* (the branch need not be up to date with `main`): a solo repo, or the robot stage 14 hires, would otherwise stall every time `main` moved under an open PR. From here, **a red check is a refused merge**, and stage 11 proves it on purpose.

**CI judges the diff; Flux reports the world**: the workflow's verdict lands on the PR before merge, the per-cluster statuses land after. Same commit, both halves of the story. On this one commit you can see all of them: the Actions check (pre-merge layer, exercised just now) alongside the nine per-cluster contexts (post-merge layer).

## Stop & measure

- [ ] `scripts/checkpoint-08` reports all PASS, exit 0 (ordering declared, standards applied in git and validated on rendered output). The bullets below are the live half unpacked:

```sh
./scripts/checkpoint-08
```

- [ ] The baseline is real **on the running pod**: applied in git, live in the cluster:

```sh
# the securityContext straight off the live pod - the baseline's fields, not the manifest's
kubectl --context kind-ggp-local-01 -n ggp get pod -l app=app \
  -o jsonpath='{.items[0].spec.containers[0].securityContext}'
```

- [ ] The baseline commit wears green on every cluster, a verdict from the same health layer that would have caught a wound. Paired with the live-pod read above, green provably means *hardened and running*, not merely unchanged:

```sh
gh api "repos/{owner}/{repo}"/commits/$(git rev-parse HEAD)/status \
  --jq '.state + "  (" + (.statuses | length | tostring) + " contexts)"'
# → success  (9 contexts)
```

Tag the boundary ([using the course §5](../using-the-course.md#5-tags-at-every-boundary)):

```sh
git tag stage-08 \
&& git push origin stage-08 \
&& gh issue close 11 --comment "stage-08 tagged"
```

## Audit artifacts produced

- The baseline is **one file with a git history**: when a standard changed, who changed it, and every workload that inherited it, answerable by `git log -- '*/components/workload-baseline/*'`.
- CI runs on every PR: a **pre-merge verdict artifact** (the check run) now exists alongside the post-merge statuses. The ruleset requires it, so the verdict is a control, not a comment.
- The exemption (azurite) is **in the diff, not in someone's head**.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| App crashloops after step 3 (`EROFS` / `Read-only file system` in logs) | The classic hardening wound: this workload writes somewhere the baseline sealed (temp files, key material, caches); our minimal API doesn't, most real apps do | Step 3's conditional escape-hatch block: one `emptyDir` per legitimate write path, in the component |
| `CreateContainerConfigError`: non-root check failed | Image runs as root and `runAsUser` doesn't exist in it | Confirm the image's user (`docker run --rm --entrypoint id <image>`); adjust `runAsUser`, don't remove `runAsNonRoot` |
| Probes failing, pod never Ready | Port rename (step 2) not applied everywhere; the probe targets `http` by name | All three `yq` edits in step 2 must land in the same commit as the component wiring |
| `dependsOn` never satisfied | Dependency name typo, or the dependency itself is red | `flux get kustomizations --context <ctx>`, then fix the failing dependency first; dependents queue behind it honestly |
| `short-name resolution enforced but cannot prompt without a TTY` | Podman (behind the docker shim) refuses unqualified image names when stdin is piped; it can't ask which registry you meant | Fully qualify the image (`docker.io/...`), now the convention for every image reference in the course |
| `open /policy: permission denied` inside the container | SELinux (enforcing on Fedora): the bind-mounted dir isn't labeled for container access | The `:ro,z` mount options: `z` relabels for the container, `ro` states the truth; a no-op on non-SELinux docker hosts |
| conftest passes locally, fails in CI | Policy or overlay drifted between working tree and commit | Both run the same pinned image on rendered output; the diff is your uncommitted changes, not the tools |

## What you learned, and what's next

Ordering is declared, health is waited on, and standards are code with a paired gate: applied by a component in git, verified by conftest on the rendered result, pre-merge in CI and post-merge on-cluster. The rule to carry forward: **apply in git, validate at gates, never mutate at admission**. Stage 30 adds the admission *validation* (Kyverno), and the cluster never runs something git doesn't show. Next: the fleet is three clusters reporting through one status API. Stage 09 gives it real observability, because "which of my stamps is unhealthy, and since when" should be a dashboard, not a scroll through commit statuses.

---

**Next:** [09 - Fleet observability](stage-09.md)
