# Stage 01 - Plain manifests (the pain)

[← 00 - Prerequisites & the app repo](stage-00.md) · [Walkthrough index](../README.md)

> **Where you are:** the root of the config repo (`gitops-golden-path`), on `main`, for the cluster scripts and `env.sh`. The manifests themselves go into the **app repo's `deploy/`** via `$APP_DIR`, because that is where plain manifests really live before a config repo exists: the app team's kubectl folder, next to the code. Stage 02 lifts them out.

**Goal:** the app and Azurite running via raw `kubectl apply`, so the absence of an audit trail is *experienced*, not asserted. The pain of this stage is not typing YAML: you write YAML under every approach. It's that once applied, **you cannot answer which version of the YAML is deployed, what was attempted before, by whom, or why.**

## Steps

### 1. Cluster up

```sh
chmod +x scripts/cluster-up scripts/cluster-down
./scripts/cluster-up
```

First run takes a while: kind pulls its node image (roughly a gigabyte: it's an entire Kubernetes node in a container) before the cluster can boot, so expect a few minutes on the initial `cluster-up` and quiet console while the pull runs. Every later `cluster-up` reuses the cached image and completes in under a minute. That is what makes the destroy-and-recreate habit (step 4, and the act checkpoint's timed rebuild) cheap enough to be a reflex.

### 2. Create the manifests (paste, then read them - the content matters, the typing doesn't)

Files follow the naming convention ([rule 3.1](../rules.md#31-file-naming-metadatanamekindyaml)): `<metadata.name>.<kind>.yaml`, one resource per file: the filename *is* the resource's identity.

```sh
source ./env.sh
mkdir -p "$APP_DIR/deploy"

cat > "$APP_DIR/deploy/ggp.namespace.yaml" <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: ggp
EOF

cat > "$APP_DIR/deploy/azurite.deployment.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: azurite
  namespace: ggp
spec:
  replicas: 1
  selector:
    matchLabels:
      app: azurite
  template:
    metadata:
      labels:
        app: azurite
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

cat > "$APP_DIR/deploy/azurite.service.yaml" <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: azurite
  namespace: ggp
spec:
  selector:
    app: azurite
  ports:
  - port: 10000
    targetPort: 10000
EOF

cat > "$APP_DIR/deploy/app.deployment.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app
  namespace: ggp
spec:
  replicas: 1
  selector:
    matchLabels:
      app: app
  template:
    metadata:
      labels:
        app: app
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

cat > "$APP_DIR/deploy/app.service.yaml" <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: app
  namespace: ggp
spec:
  selector:
    app: app
  ports:
  - port: 8080
    targetPort: 8080
EOF
```

Now read them. Three things worth noticing: the image tag is exact (`0.1.0`, from stage 00); the connection string is the *documented public* Azurite dev key with the `BlobEndpoint` host set to the Service name `azurite` (not 127.0.0.1; pods reach each other by Service DNS); and Azurite runs with `--skipApiVersionCheck`, because the emulator perpetually trails the SDK's API version (a current `Azure.Storage.Blobs` sends an `x-ms-version` newer than Azurite supports, and without the flag every storage call fails 400). Acceptable for an emulator; one more instance of the boundary this course keeps stating: *Azurite emulates storage, not Azure.*

> **If you're an experienced Kubernetes engineer, this YAML should be setting off alarms**: no probes, no `securityContext`, no resource requests/limits, no pull-policy discipline. That's deliberate, not ignorance: this stage's subject is the missing audit trail, and hardening added now would be noise. The full workload baseline (probes, non-root securityContext, limits, named ports) arrives in stage 08 as a Kustomize component, applied by one overlay line, then *enforced* at CI and admission in later stages. The absence of probes gets felt concretely in stage 04's break exercise. If nothing here looked wrong to you, stage 08 explains why it should have.

The files are in a git repo. Commit them, so the next section can show you exactly how little that buys:

```sh
# every block that spends $APP_DIR re-derives it: an unset var and git -C "" silently mean "right here"
source ./env.sh
git -C "$APP_DIR" add deploy
git -C "$APP_DIR" commit -m "feat: add kubectl manifests for the app and its Azurite"
git -C "$APP_DIR" push
```

### 3. Apply - and meet your first ordering failure

```sh
source ./env.sh
kubectl apply -f "$APP_DIR/deploy/"
```

This **half-fails on first run, deterministically**: `kubectl apply -f <dir>` processes files alphabetically, `app.deployment.yaml` … `ggp.namespace.yaml`, so everything is rejected with `namespaces "ggp" not found` before the namespace, which sorts last, exists. Welcome to resource ordering, the course's first encounter with it. kubectl has **no dependency ordering at all**, so with plain manifests the fix is explicit. *You* sequence the applies:

```sh
source ./env.sh
# dependencies first - ordering is your job now
kubectl apply -f "$APP_DIR/deploy/ggp.namespace.yaml"
# then everything (re-applying namespace.yaml is a no-op: apply is idempotent)
kubectl apply -f "$APP_DIR/deploy/"
# first pull of both images takes a moment
kubectl -n ggp wait --for=condition=Ready pod --all --timeout=180s
kubectl -n ggp get pods                                               # both Running
```

Notice what that first line really is: ordering knowledge that lives nowhere but this document and your memory. Nothing in the manifests records that `ggp.namespace.yaml` must go first: every runbook, every colleague, every future you must simply know. That's stage 01's theme wearing a different hat, and it gets fixed twice later: Kustomize sorts namespaces first when building (stage 02), and `dependsOn` generalises ordering to whole dependency graphs, recorded in config (stage 08).

### 4. Check the app

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

> The readiness loop is the background-process rule; see conventions: port-forward takes a beat to establish, and `curl -s` would otherwise swallow the connection-refused failures silently. The `; echo` keeps responses off your prompt line; `-i | head -1` makes the 204 visible, since a no-content success otherwise prints nothing at all.

### 5. Experience the pain (do all three, and run the interrogations)

**1. Invisible drift.** Mutate, then try to find out who did it:

```sh
source ./env.sh
kubectl -n ggp scale deploy/app --replicas=3

# UP-TO-DATE 3 - the cluster obeyed (READY catches up within seconds)
kubectl -n ggp get deploy app
# live state no longer matches the file (replicas 3 vs 1)
kubectl diff -f "$APP_DIR/deploy/app.deployment.yaml"
# (colour tip: kubectl diff delegates via an env var - set once per shell for coloured output:
#   export KUBECTL_EXTERNAL_DIFF="diff -u -N --color=always")
kubectl -n ggp get events --sort-by=.lastTimestamp | tail -5
# events show "Scaled up replica set..." attributed to deployment-controller - the machinery, never the human.
# Nothing anywhere records WHO ran the scale command, or why.
```

**2. No version identity.** Change the image, then try to say what's deployed:

```sh
source ./env.sh
kubectl -n ggp set image deploy/app app=$APP_IMAGE:latest

kubectl -n ggp get deploy app -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
# → :latest. Which VERSION of the deployment YAML is deployed? Not the file on disk:
kubectl diff -f "$APP_DIR/deploy/app.deployment.yaml" # diverged again - image AND replicas
kubectl -n ggp rollout history deploy/app
# → revisions exist, but CHANGE-CAUSE is <none>: no who, no why, no link to any file or review.
```

**3. No recovery.** Destroy, then try to get back what was running:

```sh
source ./env.sh
./scripts/cluster-down && ./scripts/cluster-up

kubectl get ns ggp                                     # Error: NotFound - everything is gone
# The only way back is you, reapplying from disk. But note what disk contains:
grep -E 'replicas|image:' "$APP_DIR/deploy/app.deployment.yaml"
# → replicas: 1, image :0.1.0 - the scale-to-3 and the :latest edit died with the cluster, unrecorded.
# What was ACTUALLY running is now unanswerable, permanently.
```

**Then restore the working state: yes, explicitly; this is the stage's end state** (and notice you had to remember, unprompted, that the namespace goes first: the ordering knowledge stages 02 and 08 move into config):

```sh
source ./env.sh
kubectl apply -f "$APP_DIR/deploy/ggp.namespace.yaml"
kubectl apply -f "$APP_DIR/deploy/"
kubectl -n ggp wait --for=condition=Ready pod --all --timeout=180s
```

**End state:** cluster `ggp-local-01` running with the app repo's `deploy/` applied and the blob round-trip working. Stage 02 starts from exactly here.

## Stop & measure

- [ ] Blob round-trip works (`PUT` then `GET` returns the payload).
- [ ] You can articulate, from experience just now, three specific failures: no actor record, no reviewable diff, no recoverable desired state.
- [ ] `kubectl -n ggp get events`: note that even these expire (~1h). Try to answer "who scaled app to 3?" You can't.

**Measured outcome:** working system; zero durable operational record.

- [ ] Close the work item, from the config repo:

```sh
gh issue close 2 --comment "stage 01 complete"
```

## Audit artifacts produced

**None. That is the lesson.** The manifests are committed, and it changed nothing: git records what you *wrote*, not what ran. The scale-to-3 and the `:latest` edit never touched a file. `kubectl apply` leaves no durable record of who changed what, why, with whose approval, or what the intended state was. Every remaining stage of this course adds evidence this stage cannot produce, starting with stage 02, where intent first becomes a file.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `namespaces "ggp" not found` on first apply | Alphabetical file ordering: namespace applies last; kubectl has no dependency ordering | Expected; apply `ggp.namespace.yaml` explicitly first (step 3). Fixed properly by Kustomize in stage 02 |
| `port-forward` exits: `services "app" not found` / connection refused | Apply half-failed, or pods not Ready yet | Apply in order (step 3), then `kubectl wait` before port-forwarding |
| Curls print nothing after starting the port-forward | Raced the forward's establishment; `-s` hides the failures | Use the readiness loop (step 4); to see what's actually happening, retry a curl with `-v` |
| App pod `ImagePullBackOff` | GHCR package still private | Stage 00 stop-and-measure was skipped; set package public |
| App 500s on `/notes/*`; app logs say `The API version ... is not supported by Azurite` | SDK newer than the emulator | `--skipApiVersionCheck` in the Azurite args (step 2 has it); re-apply and let the pod restart. Diagnose any 500 with `kubectl -n ggp logs deploy/app --tail=25`; the exception names the layer |
| App 500s on `/notes/*` (other) | Connection string wrong (key typo, or `azurite` host wrong) | Copy the full documented string; `BlobEndpoint` host must match the Service name |
| Azurite pod running, app can't connect | Blob host bound to loopback | Args must include `--blobHost 0.0.0.0` |
| `port-forward` dies immediately | Wrong service name/port | `kubectl -n ggp get svc` and match names |
| kind create fails under podman | Rootless cgroups delegation | See kind's rootless docs; usually the systemd delegation drop-in, then retry |
| "How do I upgrade the cluster's Kubernetes?" | Wrong mental model: kind clusters are replaced, never upgraded | Update the kind binary, then `cluster-down`/`cluster-up` (new default node image); pin a version with `KIND_NODE_IMAGE=kindest/node:vX.Y.Z@sha256:…` from kind's release notes. Cheap replacement is the point: the platform definition lives in git |

## What you learned, and what's next

You ran a real workload, and experienced that `kubectl apply` leaves nothing behind: no actor, no reviewable diff, no recoverable desired state. Even the cluster's events forget within the hour. Everything worked, and nothing was accountable.

**Next:** the first fix - the manifests leave the app repo for a **config repo** whose only job is to say what runs where, and intent becomes a *file with history*. Kustomize gives that repo its structure (base + overlays), a label vocabulary the whole course will grow into, and the habit of asserting on rendered output instead of eyeballing it.

---

**Next:** [02 - Kustomize](stage-02.md)
