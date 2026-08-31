# Stage 02 - Kustomize

[← 01 - Plain manifests (the pain)](stage-01.md) · [Walkthrough index](../README.md)

> **Where you are:** the config repo root (created and seeded at stage 00, beside the app repo), on `main`. **Starting state:** stage 01's end state: cluster running with the plain manifests applied. (If you tore down since: `./scripts/cluster-up`, then stage 01 step 3.)

**Goal:** the stage-01 manifests restructured into base + overlays, the label taxonomy applied with starter values, and the config-testing habit started: assert on rendered output.

## Steps

### 1. Restructure

Every "thing" (an app base, an override instance) segregates its YAML into **typed folders** per the folder convention ([rule 3.2](../rules.md#32-folder-convention-everything-has-a-place)): `resources/`, `patches/`, `replacements/`, `secrets/`, `config/`, `components/`. Folders appear when first populated, not as empty scaffolding; stage 01's flat directory is deliberately pre-convention (naive is the point there, and `kubectl apply -f` doesn't even recurse).

**This is the structure this stage builds.** It is here so you can see where you are going; do not create it by hand. The paste block below and the `kustomize edit` steps that follow produce every folder and file in it:

```
apps/
  base/
    kustomization.yaml
    resources/
      ggp.namespace.yaml
      azurite.deployment.yaml
      azurite.service.yaml
      app.deployment.yaml
      app.service.yaml
  overlays/
    dev/
      kustomization.yaml
      patches/
    prod/
      kustomization.yaml
      patches/
```

Start with the skeleton: create the base and overlay folders, lift stage 01's manifests out of the app repo into `base/resources/`, and let kustomize scaffold the three `kustomization.yaml` files:

```sh
mkdir -p apps/base/resources apps/overlays/dev apps/overlays/prod
source ./env.sh
# lifted out of the app repo; its copy retires in step 7, once the render proves nothing was lost
cp "$APP_DIR"/deploy/*.yaml apps/base/resources/

# scaffolds kustomization.yaml, resources/-prefixed
(cd apps/base         && kustomize create --autodetect --recursive)
(cd apps/overlays/dev  && kustomize create --resources ../../base)
(cd apps/overlays/prod && kustomize create --resources ../../base)

# the full render - yq only pretty-prints it
kustomize build apps/overlays/dev | yq
# the same render, filtered to a kind/name inventory
kustomize build apps/overlays/dev | yq -N '.kind + "/" + .metadata.name'
# → Namespace/ggp
#   Service/app
#   Service/azurite
#   Deployment/app
#   Deployment/azurite
```

What `kustomize create` did: the base's `kustomization.yaml` pulls the five resource files together into one buildable unit, and each overlay's simply points at the base (browse the generated files; they're minimal: apiVersion, kind, a resource list). What the build output shows: every resource assembled and emitted **in the correct dependency order**, the Namespace before the things that live inside it, regardless of the alphabetical file order that tripped stage 01. That ordering dance is already gone, and no one had to remember anything. The unfiltered build is worth scrolling once: kustomize is not magic. It applies the declarative overlay on top of the base and emits ordinary, complete YAML. And notice what you rendered: **one overlay of the two that now exist**. `apps/overlays/dev` and `apps/overlays/prod` are two instances of the same base, each with its own render; swap `dev` for `prod` in the build command and today's output is identical, because nothing distinguishes them yet - the rest of this stage and the overlays' `patches/` are what pull them apart. That render, per overlay, is the real artifact; every later gate, diff and deploy in the course operates on it.

> Scaffolding by CLI, per the tool-writes-the-file rule, [rule 3.5](../rules.md#35-the-tool-writes-the-file). The same rule governs the next steps: **`kustomize edit` wherever the emitted file is as good as a hand-written one; whole-file writes where the CLI can't express the content**, meaning comments, and readable inline patches. Each exception states its reason where it occurs. CLI behaviour and emitted style are those of the pinned kustomize, stage 00's prerequisites.

### 2. The label taxonomy, with starter values

Added with `kustomize edit`: the tool writes the file, you read the result. **One label per command**: the comma-separated multi-label form silently corrupts (everything after the first colon becomes one giant value).

```sh
(cd apps/base &&
  kustomize edit add label --without-selector app.kubernetes.io/part-of:gitops-golden-path &&
  kustomize edit add label --without-selector platform.example.com/tenant:platform &&
  kustomize edit add label --without-selector platform.example.com/release:v0.1.0)

(cd apps/overlays/dev &&
  kustomize edit add label --without-selector platform.example.com/environment:dev &&
  kustomize edit add label --without-selector platform.example.com/class:dev)

(cd apps/overlays/prod &&
  kustomize edit add label --without-selector platform.example.com/environment:prod &&
  kustomize edit add label --without-selector platform.example.com/class:prod)

cat apps/base/kustomization.yaml
```

Read what it wrote: a `labels:` entry (the modern field; the CLI's default `add label` without the flag writes the *deprecated* `commonLabels`), pairs alphabetised, and no `includeSelectors` line, because false is the default, so the tool omits it. **`--without-selector` matters**: baking mutable labels into selectors turns future label changes into immutable-field apply errors (stage 04 demonstrates that failure class deliberately).

These starter values are deliberately boring: one tenant, one release, the same value everywhere. The *vocabulary* comes first; the features that select on it arrive in later stages. **One label is deliberately absent: `release-channel`.** A *release channel* is how exposed a release is, engineering → internal → pilot → early access → general availability. It is **schedule, not identity**, and schedule never bakes into a base: it belongs on the *binding* (the cluster's folder of stamp CRs), where stage 28 declares it, so moving a tenant to another channel is a one-line binding diff instead of a base value rendered wrongly into everyone's output.

**Later stages must never edit `base/` to add tenancy, channels or classes.** This is the **open/closed principle** applied to config layers: the base is closed to modification, open to extension. The reason is blast radius. Every overlay renders *through* the base, so a base edit reaches every cluster's output at once, and no ladder rung gets to soak it first. Two consequences:

- **The test, per feature.** When tenancy (stage 22) or release channels (stage 28) arrive, `git diff` scoped to `apps/base/` on that PR shows nothing. The whole feature lands as overlay and binding additions.
- **The exception, with its own discipline.** Base changes are not forbidden; a version bump or a baseline improvement is ordinary work. But the route is the ladder, not a direct edit. The change enters as an overlay patch on one rung. It promotes rung by rung, on evidence, with soak between (stage 13 rehearses exactly this with a chart pin). Once every rung renders it identically, it is **absorbed into base** and the patches are deleted: a base edit whose rendered diff is empty, because the overlays already said everything it says. Controls guard the whole route: a rendered blast-radius diff on every PR (stage 12), and required owners on `base/` (stage 21).

To be concrete about how that plays out for `tenant`: when multi-tenancy lands (stage 22), each tenant *stamp* (the Flux `Kustomization` CR that stage 03 introduces and names) gets an overlay that sets `platform.example.com/tenant: <customer-id>` with its own labels transformer. Overlay transformers run after base, so the override wins, while the base default stays `platform`, which remains *correct* for everything the platform itself owns (the shared Azurite, monitoring, Flux). The platform is tenant zero.

### 2b. The ecosystem's vocabulary (standard labels)

Two vocabularies coexist from here on. The **ecosystem's** is [Kubernetes' recommended labels](https://kubernetes.io/docs/concepts/overview/working-with-objects/common-labels/), `app.kubernetes.io/*`, facts about a workload that third-party tooling reads; the **platform's** (`platform.example.com/*`) is facts about the fleet. `part-of` is already applied by the base transformer; `name` and `component` are per-workload facts, so they live in the manifests. Overwrite all four manifests: the delta is just the two standard labels in `metadata.labels` and (for the Deployments) the pod template.

One note on the prefix before you paste: `example.com` is the standard placeholder domain, used so the platform's labels are visibly *ours* against the ecosystem's and any third party's. In your own fleet, use your organisation's domain: `platform.northwind.com/tenant`, `platform.acme.org/class`. The point is a prefix nobody else's tooling claims. While following the course, keep `example.com`: the checkpoints and later stages grep for it.

```sh
source ./env.sh
cat > apps/base/resources/azurite.deployment.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: azurite
  namespace: ggp
  labels:
    app.kubernetes.io/name: azurite
    app.kubernetes.io/component: storage-emulator
spec:
  replicas: 1
  selector:
    matchLabels:
      app: azurite
  template:
    metadata:
      labels:
        app: azurite
        app.kubernetes.io/name: azurite
        app.kubernetes.io/component: storage-emulator
    spec:
      containers:
      - name: azurite
        image: mcr.microsoft.com/azure-storage/azurite
        args:
        - azurite-blob
        - --blobHost
        - 0.0.0.0
        - --skipApiVersionCheck
        ports:
        - containerPort: 10000
EOF

cat > apps/base/resources/azurite.service.yaml <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: azurite
  namespace: ggp
  labels:
    app.kubernetes.io/name: azurite
    app.kubernetes.io/component: storage-emulator
spec:
  selector:
    app: azurite
  ports:
  - port: 10000
    targetPort: 10000
EOF

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
        - containerPort: 8080
        env:
        - name: STORAGE_CONNECTION_STRING
          value: "DefaultEndpointsProtocol=http;AccountName=devstoreaccount1;AccountKey=Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==;BlobEndpoint=http://azurite:10000/devstoreaccount1;"
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
  - port: 8080
    targetPort: 8080
EOF
```

Two notes. First, the **selectors stay on the plain `app:` label**: convention says select on `name` + `instance`, but our selectors predate the standard set and selectors are immutable: changing them now would be a delete-and-recreate (stage 04 demonstrates that failure class). A scar worth having: adopt the standard labels *before* your first apply, and your selectors can follow convention from birth. Second, the rest of the standard set arrives when its distinguishing feature exists: `instance` is the stamp identifier (stage 10); `version` gets stamped by release machinery, never by hand, because a hand-maintained version label is drift bait; and `managed-by`'s answer arrives with Flux itself, which labels everything it applies (`kustomize.toolkit.fluxcd.io/name`; you'll see it in stage 03).

### 3. Overlay differences, both patch styles

Prod gets a **strategic-merge patch** (a fragment of the real resource, merged in). The patch file is authored, since it's a manifest fragment and the content is the lesson, then registered with the CLI:

```sh
mkdir -p apps/overlays/prod/patches
cat > apps/overlays/prod/patches/app.deployment.patch.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app
  namespace: ggp
spec:
  replicas: 2
EOF

(cd apps/overlays/prod && kustomize edit add patch --path patches/app.deployment.patch.yaml)
```

Dev gets a **JSON6902 patch** (surgical operations against paths) so both grammars get exercised. Per the folder convention, **patches are always files in `patches/`, never inline in the kustomization**, because segregation is meaningless if patches can hide.

The file rule also sidesteps the CLI's inline-patch weakness. Hand this same patch to `kustomize edit add patch --patch '<json>'` and the pinned CLI records it in the kustomization like this:

```yaml
patches:
- patch: '[{"op": "add", "path": "/spec/template/metadata/annotations", "value": {"platform.example.com/managed-by":
    "kustomize"}}]'
  target:
    kind: Deployment
    name: app
```

The whole patch becomes one quoted JSON string, line-wrapped at a column limit, so the break lands mid-JSON rather than at an operation boundary. Two costs follow. Reading it means parsing JSON inside YAML: no `- op:` lines to scan, no syntax highlighting, flow style everywhere. And any future change to any part of the patch rewrites the whole string, so the diff says "the patch changed" instead of *which operation* changed; the file form's diff is the one changed line in `patches/`, with the kustomization untouched. Small diffs you can review at a glance are a tenet here (stage 12 builds a whole gate on reading rendered diffs), so the config that produces them doesn't get to be the noisy part.

The file form dissolves all of that, so this registers cleanly too, target flags included (JSON6902 patch files need an explicit target):

```sh
mkdir -p apps/overlays/dev/patches
cat > apps/overlays/dev/patches/app.deployment.patch.yaml <<'EOF'
- op: add
  path: /spec/template/metadata/annotations
  value:
    platform.example.com/managed-by: kustomize
EOF

(cd apps/overlays/dev && kustomize edit add patch --path patches/app.deployment.patch.yaml --kind Deployment --name app)
cat apps/overlays/dev/kustomization.yaml   # read: a patches entry with path + target
```

Rule of thumb worth internalising: strategic-merge for "this resource differs here" (readable as the resource); JSON6902 for surgical or list-index operations merge semantics can't express.

### 4. The generator gotcha

Move the connection string out of the Deployment and into a `configMapGenerator`, which lives in its own **`config/` folder as a self-contained kustomization** (generators plus their file-based inputs co-locate there, per the folder convention; the parent includes the folder as one line). Three writes: the new `config/kustomization.yaml`; the base kustomization gaining one `config/` resource entry; and `app.deployment.yaml`'s `env` becoming a `configMapKeyRef` (the Service file is untouched; the delta lands in exactly one file):

```sh
source ./env.sh
mkdir -p apps/base/config
cat > apps/base/config/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
configMapGenerator:
# Plaintext secret material in git is wrong, and stays wrong until stage 06 pays back the debt
# (and moves it where debt lives: a secrets/ folder).
# It is tolerable here only because this is Azurite's PUBLICLY DOCUMENTED dev key - the perfect prop.
- literals:
  - STORAGE_CONNECTION_STRING=DefaultEndpointsProtocol=http;AccountName=devstoreaccount1;AccountKey=Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==;BlobEndpoint=http://azurite:10000/devstoreaccount1;
  name: app-config
  namespace: ggp
EOF

cat > apps/base/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- config/
- resources/app.deployment.yaml
- resources/app.service.yaml
- resources/azurite.deployment.yaml
- resources/azurite.service.yaml
- resources/ggp.namespace.yaml
labels:
- pairs:
    app.kubernetes.io/part-of: gitops-golden-path
    platform.example.com/release: v0.1.0
    platform.example.com/tenant: platform
EOF

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
        - containerPort: 8080
        env:
        - name: STORAGE_CONNECTION_STRING
          valueFrom:
            configMapKeyRef:
              name: app-config
              key: STORAGE_CONNECTION_STRING
EOF

```

> Written whole rather than CLI'd for one reason: the debt comment. `kustomize edit add configmap` writes this exact generator but cannot write comments, and the comment is the point. Note also what just worked across a folder boundary: the generated ConfigMap lives in `config/`'s kustomization, the Deployment referencing it lives in `resources/`, and the name-hash rewriting still connects them, because both are part of the same build.

Now watch the gotcha happen:

```sh
kustomize build apps/overlays/dev | grep -E 'name: app-config'
# → app-config-<hash> everywhere - generator names carry a content hash, and kustomize
#   rewrote the Deployment's configMapKeyRef to match. Change the literal, rebuild: new hash.
```

That hash-rename is what makes rollouts happen automatically on config change, and what breaks anything referencing the ConfigMap by a bare, unrewritten name (a string in an argument, a resource kustomize doesn't know about). Remember this for later.

### 5. Assert on rendered output (config-testing rung 1)

The *mechanism* is worth seeing raw once, a query over rendered output compared against intent:

```sh
kustomize build apps/overlays/prod | yq 'select(.kind=="Deployment" and .metadata.name=="app").spec.replicas'
# → 2   (the strategic-merge patch, observed in the render)
```

But a pasted block of bare queries produces unlabeled values nobody can map back, so the checks live in a **checkpoint script**: every check prints `PASS`/`FAIL` plus what it means, the script exits non-zero on any failure, and CI later runs this exact file, so the checkpoint and the pipeline can never disagree.

```sh
chmod +x scripts/checkpoint-02
./scripts/checkpoint-02
```

Expected:

```
== checkpoint-02: kustomize renders what we meant ==
PASS  dev overlay builds
PASS  prod overlay builds
PASS  prod output schema-valid (kubeconform)
PASS  app replicas in dev = 1
PASS  app replicas in prod = 2 (strategic-merge patch applied)
PASS  class=prod label on every prod resource (taxonomy universal)
PASS  standard labels on every Deployment
PASS  dev JSON6902 patch applied (managed-by annotation)
PASS  generated ConfigMap carries content hash (app-config-<hash>)
PASS  configMapKeyRef rewritten to the hashed name (cross-folder wiring works)

checkpoint-02: 10 passed, 0 failed
```

> First run pulls the kubeconform image, one-time noise. Podman-shim users: `sudo touch /etc/containers/nodocker` silences the "Emulate Docker CLI" banner.

### 6. Apply via the overlay and re-verify the app

No teardown first, and that's the lesson. The overlay renders the **same resource identities** (group/kind/namespace/name) as stage 01, and identity is what the cluster keys on, not which files produced the YAML. Apply converges the live state in place; pods roll only where the pod spec actually changed (the app's env became a `configMapKeyRef`; both templates gained labels), and the Services and Namespace update without drama:

```sh
kustomize build apps/overlays/dev | kubectl apply -f -
kubectl -n ggp wait --for=condition=Ready pod --all --timeout=180s
kubectl -n ggp get pods
```

> Not `kubectl apply -k`: kubectl embeds its *own*, usually stale, kustomize. The render rule ([rule 4.1](../rules.md#41-the-render-rule-one-master-per-tool-and-kubectl-never-renders)) pins rendering to the standalone `kustomize`, so the thing you apply is the thing your checkpoints asserted on. kubectl is the API client, never the renderer.

Two things to notice. First, no namespace-first dance: `kustomize build` emits namespaces before the things inside them, stage 01's ordering knowledge moved into tooling. Second, a caveat wearing a foreshadow: **`kubectl apply` never prunes.** Had the overlay stopped rendering something stage 01 created, applying over the top would have silently orphaned it on the cluster. Flux's `prune: true` closes exactly that gap in stage 03.

Then verify the app end to end (repeated in full; a checkpoint you can paste beats a pointer to an earlier page):

```sh
# local 8090: the cluster itself publishes 8080 for ingress (baked in at cluster-up)
kubectl -n ggp port-forward svc/app 8090:8080 >/dev/null &
PF=$!   # capture the PID: job numbers (%1) break on re-runs and in scripts
for i in $(seq 1 20); do curl -sf localhost:8090/healthz >/dev/null && break; sleep 0.5; done

curl -s localhost:8090/healthz; echo                                # {"status":"ok"}
curl -si -X PUT localhost:8090/notes/hello -d 'world' | head -1     # HTTP/1.1 204 No Content
curl -s localhost:8090/notes/hello; echo                            # world

kill $PF   # stop the port-forward when done
```

### 7. Commit it - the first PR

Stage 01's lesson was that `kubectl apply` leaves no record. This stage's claim is that **intent is now a file with history**, and that claim is not true until you commit. So this is the first *config* commit against the config repo (stage 00's seed was tooling, and took a plain `chore`). It is also the first **PR**, because stage 00's ruleset accepts nothing else, and the right moment to fix the convention every later commit follows, because retrofitting one is far more work than adopting one.

The rule: [**Conventional Commits**](https://www.conventionalcommits.org/), `type(scope): description`, with a vocabulary that fits a config repo rather than an application. This is [rule 2.1](../rules.md#21-the-commit-convention-the-subject-is-a-field-not-a-sentence), adopted at the first config commit because retrofitting a convention is not a fun thing to do. And the body's last line is a **trailer**: `Refs: #3`, the work item this change advances, seeded into your backlog as issue #3 before the first PR existed ([rule 2.5](../rules.md#25-every-change-has-a-work-item-the-trailer-is-the-reason)). A change that cites no work item is a change nobody asked for: from stage 04 `pr-open` refuses one, and from stage 11 so does the merge.

Seven lines, and every change this repository ever takes will be these seven lines ([rule 2.4](../rules.md#24-every-change-is-a-pr-the-branch-is-scaffolding-the-pr-is-the-artifact)). Type all seven by hand this stage and next. From stage 04, `pr-open` scripts the first four (branch, commit, push, open); the last three (read the diff, merge, return to main) are never scripted, in this course or after it, because the merge is a decision and the diff is what informs it:

```sh
# 1. a branch: type/work-item/slug - scaffolding, gone on merge
git switch -c feat/3/overlays
git add apps
# 2. the subject is the PR title
git commit -m "feat(overlays): base plus dev and prod; environment difference becomes a diff"
git push -u origin feat/3/overlays                 # 3.
gh pr create --title "feat(overlays): base plus dev and prod; environment difference becomes a diff" \
  --body "## What is moving
The stage-01 manifests, restructured: apps/base plus dev and prod overlays with the label taxonomy at starter values.

## Why now
Stage 01 showed that kubectl apply leaves no record; from here intent is a file with history.

## Evidence
checkpoint-02 PASS; the dev/prod render diff is exactly three intended hunks.

## If it is wrong
Revert this merge - nothing runs from git yet.

Refs: #3"   # 4. the body is the record; the template's headings, filled - and the trailer is the work item
gh pr diff                                  # 5. READ IT - the merge is the gate, and today the gate is you
```

The block ends before the merge on purpose, and so does every block in this course that opens a PR: a paste that prints the diff and merges in the same breath has already decided, and nobody read anything. When the diff shows exactly what the body claims:

```sh
gh pr merge --merge --delete-branch         # 6. merge commit, title + (#N) as subject; branch deleted
git switch main && git pull                 # 7. back on main, at the merge commit
```

> Aside: GitHub's commit list now shows this change **twice** with the same subject - once as the branch commit ("committed", no PR link) and once as the merge commit ("authored", linking the PR). That is the merge strategy working, not duplication: the subject you typed became the PR title, and the merge settings write the PR title back as the merge commit's subject (plus the PR number, ` (#58)`-style), so the two match by design. Everything that matters (the PR link, and from stage 04 the status tick) lives on the *merge* commit, because `main` only ever advances by merges - and `git log --first-parent --oneline` is how you read history at merge level when the pairs get noisy.

Why a PR for a change only you will ever read: because the ruleset that refuses a direct push is the same one that will refuse a colleague's push to `apps/base/` in a year, and it cannot tell the difference, which is the point ([rule 1.3](../rules.md#13-protection-from-day-zero-nothing-reaches-main-except-a-merged-pr)). Line 5 is the habit the next four stages exist to build: read the diff before the merge, even when you wrote it ten seconds ago. By stage 08 CI reads it too; by stage 12 the reviewer sees what the *clusters* will receive; by stage 21 the right reviewer is summoned by path. None of those will change what you just typed.

And retire the app repo's copy. From here the config repo says what runs, the app repo says what the app is, and two sources of truth is the drift stage 01 just showed you, in slow motion:

```sh
source ./env.sh
git -C "$APP_DIR" rm -r -q deploy
git -C "$APP_DIR" commit -m "chore: retire deploy/, the config repo owns what runs"
git -C "$APP_DIR" push
```

### 7b. The subject is a field, not a sentence

Go back to the subject the PR carried, `feat(overlays): base plus dev and prod; environment difference becomes a diff`, and read it as three fields, not a sentence:

- **`feat`**: the *type*. Alongside the standard set (`feat` `fix` `docs` `refactor` `test` `ci` `chore` `revert`) this repo uses seven domain types, because a platform does not add features so much as move versions around: **`pin`** (a version *arrives* at its entry rung), **`promote`** (a version *climbs* a rung, by PR), **`bind`** (point a cluster at a path, stage 03), **`rotate`** (a secret value changes, stage 06), **`access`** (who can decrypt, or who must review), **`policy`** (what is allowed), **`break`** (deliberate failure injection, stage 04). You will type `pin` and `promote` more than anything else.
- **`(overlays)`**: the *scope*, and it is always **the blast radius**, what this change can reach. Not the folder you happened to edit: `overlays` here because both environments render from what you just wrote. A stamp name (`app-prod`), a cluster (`prod-01`), a class (`dev`), or a tree (`base`, `clusters`, `policy`) are the legal values.
- **the description**: imperative, under 72 characters, no trailing period. Imperative means the command form: "add database connection string", not "added database connection string" or "adds database connection string". The test: it should complete the sentence "if applied, this commit will ...".

**Why bother, concretely.** Three things become possible that a prose subject cannot give you, and each one shows up later in this course:

| | |
|---|---|
| **A queryable blast radius** | `git log --first-parent --basic-regexp --grep='^promote(app-prod): '` answers "what has ever shipped to prod"; stage 07's promotion ladder and the act checkpoints all look commits up this way |
| **Release notes per cluster** | a cluster reports the revision it applied; that range plus a typed history renders notes for *that cluster*, with no tagging ceremony (stage 26) |
| **An audit you can query by type** | "every `policy:` change this quarter", "every `access:` change to prod"; the questions auditors actually ask, answered from git alone |

The scope is doing double duty on purpose. It is the same identifier that will name the stamp, the namespace, the label, the metric and the CODEOWNERS path, so an alert firing on `app-prod` and a commit scoped `app-prod` need no lookup table between them.

References go in **trailers**, never in the scope. One trailer is always there, the work item:

```
promote(app-prod): app 0.1.1

Dev soaked 24h; slo-gate green.

Refs: #9
```

> `#9` is stage 07's issue, where that promotion actually happens. `Closes:` exists too, reserved for a PR that *is* the whole work item: it fires on merge, and merge is not verification.

Make it habitual rather than remembered: the template is repo policy (`.gitmessage`, seeded at stage 00 and already wired in by that step's `commit.template` line, which is local because git deliberately refuses to let a clone set your editor behaviour, and it is right to). Read it once, now, so the vocabulary is in front of you the next time `git commit` opens an editor:

```sh
cat .gitmessage
```

Full vocabulary, the scope registry, and the nine rules that make the awkward cases decidable: [the commit convention](../appendices/commit-convention.md). How merges preserve it, merge-commit-only, and why: [the git policy](../appendices/git-policy.md). Side quest [stage 26](../act-6/stage-26.md) is where this stops being discipline and starts paying out.

**End state:** cluster running with the **dev overlay** applied over the stage-01 resources, converged in place; the plain manifests are no longer the source of anything, and **the restructure is merged** under the commit convention, as the repository's first PR. Stage 03 starts from exactly here.

## Stop & measure

- [ ] `scripts/checkpoint-02` reports all PASS, exit 0 (covers builds, schema, patches, taxonomy, generator wiring):

```sh
./scripts/checkpoint-02
```

- [ ] Blob round-trip still works via the dev overlay (live check; the script only judges renders):

```sh
# local 8090: the cluster itself publishes 8080 for ingress (baked in at cluster-up)
kubectl -n ggp port-forward svc/app 8090:8080 >/dev/null &
PF=$!   # capture the PID: job numbers (%1) break on re-runs and in scripts
for i in $(seq 1 20); do curl -sf localhost:8090/healthz >/dev/null && break; sleep 0.5; done

curl -s localhost:8090/healthz; echo                                # {"status":"ok"}
curl -si -X PUT localhost:8090/notes/hello -d 'world' | head -1     # HTTP/1.1 204 No Content
curl -s localhost:8090/notes/hello; echo                            # world

kill $PF   # stop the port-forward when done
```
- [ ] `git diff` of this stage shows intent as reviewable text.
- [ ] The restructure is committed and pushed, and its subject parses as `type(scope): description`. `git log -1 --format=%s` reads back three fields, not a sentence.

**Measured outcome:** environment difference is now a computable diff:

```sh
diff -u --color <(kustomize build apps/overlays/dev) <(kustomize build apps/overlays/prod)
```

Every hunk must be an *intended* delta, and there are exactly three kinds: the `environment`/`class` label values (on every resource), app `replicas: 1` vs `2` (prod's strategic-merge patch), and dev's `managed-by` annotation (dev's JSON6902 patch). Any hunk outside those three classes is an overlay doing something you didn't intend.

Tag the boundary ([using the course §5](../using-the-course.md#5-tags-at-every-boundary)):

```sh
git tag stage-02 \
&& git push origin stage-02 \
&& gh issue close 3 --comment "stage-02 tagged"
```

## Audit artifacts produced

- **Intent is now a file with history**: the first durable record of desired state, diffable and (from stage 03) reviewable.
- **A typed change record**: the first commit under the [commit convention](../appendices/commit-convention.md). The subject is a queryable field carrying the change's blast radius, not prose. Every audit query in Act II reads it.
- **Rendered output is deterministic**: the same input renders identically anywhere, the property every later verification (goldens, blast radius, evidence queries) stands on.
- Still absent: any binding between this record and what the *cluster* runs. The manual apply is still an unrecorded human act. Stage 03 closes that.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `labels` ignored / warning about commonLabels | Old kustomize, or `edit add label` used without `--without-selector` (writes the deprecated field) | kustomize v5.8+ and the `--without-selector` flag; check `kustomize version` |
| One label carries a giant comma-filled value | The comma-separated multi-label form silently corrupts | One `kustomize edit add label` command per label; delete the bad pair from the file by hand |
| App loses the connection string after generator move | Deployment still uses literal `env:` | Switch to `configMapKeyRef`/`envFrom` referencing the generated name |
| Service selector no longer matches pods | Labels baked into selectors | `includeSelectors: false`, and delete/recreate if selectors already mutated |
| `yq` returns nothing at all | yq v3 vs v4 syntax | Commands above are yq v4 (`yq 'select(...)'`) |
| kubeconform rejects CRD-less resources oddly | Strict mode + missing schemas | `-ignore-missing-schemas` is acceptable here; revisit at stage 09 |

## What you learned, and what's next

Intent is now a diffable, history-carrying file: environment differences are computable, the platform vocabulary exists (at starter values, waiting for the features that will select on it), correctness is asserted against rendered output, and the commit that records all of it carries a **typed subject**, a blast radius a later query can filter on rather than prose a later reader must interpret. What's still missing is any *binding* between this record and the cluster: the manual apply is still an unrecorded human act, and the cluster still drifts silently.

**Next:** Flux closes that gap. The cluster starts pulling its state from this repo, drift gets corrected by machinery, and `kubectl apply` retires for good.

---

**Next:** [03 - Flux bootstrap](stage-03.md)
