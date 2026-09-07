# Stage 05 - Helm via Flux

[← Act I checkpoint](../act-1/act-checkpoint.md) · [Walkthrough index](../README.md)

> **Where you are:** the config repo root, on `main`, kubectl context `kind-ggp-local-01`. **Starting state:** Act I's end state. Platform cluster green, `checkpoint-03` and `checkpoint-04` passing, app-dev reconciling `apps/overlays/dev`.

**Goal:** the first third-party dependency (Traefik) managed by Flux through Helm, living in a new `infrastructure/` tree that is split from apps because platform components are not workloads, and the app reachable through a real Ingress instead of a port-forward.

## Steps

### 1. Rebuild the cluster - the rule, demonstrated

Ingress on kind needs `extraPortMappings` baked into the cluster config at creation time, and kind cannot add a port mapping to a live cluster. Nothing in this step edits a file: the mappings have been in `scripts/cluster-up` since stage 00 seeded it. The script writes the kind config each time it creates a cluster, mapping host `8080`/`8443` (overridable via `HTTP_PORT`/`HTTPS_PORT`) to node ports 80/443 and labelling the node `ingress-ready=true`. Read the block it writes:

```sh
grep -B 4 -A 6 extraPortMappings scripts/cluster-up
```

Your running cluster came from the same script, so it already carries the mappings. The rebuild below is the rule practised while it costs nothing: a creation-time setting a live cluster lacks is where a mutate-your-cluster walkthrough apologises. Here it's the rule: **clusters are replaced, never upgraded**. The platform definition lives in git, and Act I's checkpoint measured the full rebuild at 77 seconds.

```sh
source ./env.sh
./scripts/cluster-down && ./scripts/cluster-up

# stage 03's cluster-side lines, scripted: install, deploy key, sync
./scripts/cluster-sync clusters/platform/local-01
kubectl -n flux-system create secret generic github-status-token \
  --from-literal=token=$(gh auth token)   # the stage-04 IOU - stage 06 finally pays back the debt
```

Nothing was committed: the components and the sync pair are what merged at stage 03, and the new cluster took them from git. The old deploy key was replaced under the same title, because a rebuilt cluster is a new identity. That is the whole rebuild story from here on, and it is why the drill runners can do it unattended. Gate. Do not proceed until the platform is back:

```sh
echo -n "waiting for the platform (checkpoint-03 passes; usually 1-3m) "
until ./scripts/checkpoint-03 >/dev/null 2>&1; do printf .; sleep 10; done; echo
./scripts/checkpoint-03 && ./scripts/checkpoint-04
```

Act-opening toolchain gate (new since Act I: the fleet act leans harder on local renders matching cluster renders):

```sh
# every tool against its authority: flux<->AKS, kustomize & helm<->the
# controllers' embedded libraries, kubectl<->the dev rung
./scripts/check
```

### 2. The `infrastructure/` tree

**Why Traefik, and why the choice is itself a lesson:** the obvious pick, ingress-nginx, *retired*. Upstream maintenance ended March 2026 after the November 2025 SIG announcement, and even AKS's managed NGINX (the app-routing add-on) sunsets in November 2026. Controllers are workloads with lifecycles, which is exactly the platform-is-a-workload principle this act keeps returning to: stage 13 rehearses swapping a controller by PR precisely because reality just demonstrated you'll need to. Traefik is actively maintained and speaks both the Ingress API (used here) and its successor, the Gateway API, the direction AKS is heading, so the migration path stays open.

Platform components get their own top-level tree: they are dependencies the apps stand on, not apps. Same folder convention as everywhere else: typed folders, one resource per file, `<name>.<kind>.yaml`. And the platform is itself a workload ([rule 5.11](../rules.md#511-the-platform-is-a-workload)), pinned in git, promoted like one; stage 13 makes that mechanical.

```sh
mkdir -p infrastructure/traefik/resources
```

```sh
cat > infrastructure/traefik/resources/traefik.namespace.yaml <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: traefik
EOF

flux create source helm traefik -n traefik \
  --url=https://traefik.github.io/charts --interval=1h \
  --export > infrastructure/traefik/resources/traefik.helmrepository.yaml

cat > infrastructure/traefik/resources/traefik.helmrelease.yaml <<'EOF'
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: traefik
  namespace: traefik
spec:
  interval: 30m
  chart:
    spec:
      chart: traefik
      version: "41.2.0" # pinned - Renovate takes this over in stage 13
      sourceRef:
        kind: HelmRepository
        name: traefik
  values:
    ports:
      web:
        hostPort: 80 # binds the node's 80; kind maps it to host 8080
      websecure:
        hostPort: 443 # likewise 443 -> host 8443
    service:
      spec:
        # NB: type sits under service.spec in this chart, not service.type
        type: ClusterIP # hostPort does the exposure; no LoadBalancer to pretend with
    nodeSelector:
      ingress-ready: "true"
    updateStrategy:
      rollingUpdate:
        maxSurge: 0 # a host port cannot surge: replace the pod, then start the new one
        maxUnavailable: 1
EOF

(cd infrastructure/traefik && kustomize create --autodetect --recursive)
```

Read what you pasted (these are lesson files): the **HelmRepository** is a source, like the GitRepository from stage 03. Source-controller polls it and caches chart artifacts. The **HelmRelease** is a stamp-shaped declaration for helm-controller (a *stamp* being the course's word for a Flux `Kustomization` CR; this is its Helm sibling): chart, *pinned* version, values. The version pin is the whole point: upgrades become a one-line git diff riding the same loop as everything else.

One hard-won caution about the `values:` block: **values paths are the chart's API, and most charts don't validate them**. A key at the wrong path is silently ignored and the chart's default wins (this chart takes the service type at `service.spec.type`; a plausible-looking `service.type` is dead, and the default LoadBalancer then waits forever for an IP kind will never assign). Before trusting a values block, check the paths against the *pinned* chart version. This is exactly what the pinned helm CLI is for:

```sh
helm repo add traefik https://traefik.github.io/charts
helm show values traefik/traefik --version 41.2.0 | less
```

And one value that is there for a day you have not met yet. The chart's default rollout is a surge: start the new pod, then stop the old. A pod holding host ports 80 and 443 leaves no free ports on a one-node cluster, so the surge pod can never schedule and the first chart upgrade times out with `FailedScheduling: didn't have free ports`. `updateStrategy` inverts it, stop then start, which is the only rollout that works with host ports on a node. The production shape is a DaemonSet, one pod per node, rolled node by node; on kind, replacement is the honest version of the same thing.

### 3. Bind it to the cluster, and tell the Alert about it

The stamp, same shape as `app-dev`. And remember stage 04's sharpest lesson: **Alert `eventSources` is an allowlist; a resource not on it fails silently and green**. The new stamp gets its own Alert in the same commit, or its failures are invisible.

```sh
# --health-check-timeout writes the CR's spec.timeout; bare --timeout is the CLI's own operation timeout
flux create kustomization infrastructure \
  --source=GitRepository/flux-system --path=./infrastructure \
  --prune --wait --health-check-timeout=5m --interval=5m \
  --export > clusters/platform/local-01/resources/infrastructure.kustomization.yaml

flux create alert infrastructure-status \
  --provider-ref=github-status \
  --event-source="Kustomization/infrastructure" --event-severity=info \
  --export > clusters/platform/local-01/resources/infrastructure-status.alert.yaml

git add infrastructure clusters/platform/local-01/resources
./scripts/pr-open feat/7/traefik "feat(infrastructure): traefik via HelmRelease, alerted" <<'EOF'
## What is moving
A new tree, infrastructure/, with Traefik as a HelmRelease; a stamp for it on local-01, with its own Alert.

## Why now
Ingress on kind needs a controller, and the platform is a workload like any other.

## Evidence
Chart pinned; the stamp waits on health with a 5m timeout; the Alert allowlists the new stamp so its failures are not silent.

## If it is wrong
Revert this merge; prune removes the release.

Refs: #7
EOF
```

Read it; when the diff is what the body claims:

```sh
gh pr merge --merge --delete-branch \
&& git switch main \
&& git pull
flux reconcile kustomization flux-system --with-source
```

### 4. The app grows an Ingress

Into the base. Every environment gets one; hosts differentiate later, so the rule is a catch-all for now:

```sh
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
              number: 8080 # unnamed for now - stage 08's baseline names ports, and this becomes `name: http`
EOF
(cd apps/base && kustomize edit add resource resources/app.ingress.yaml)

git add apps/base
./scripts/pr-open feat/7/base-ingress "feat(base): app Ingress via traefik" <<'EOF'
## What is moving
An Ingress for the app, in base - every overlay inherits it.

## Why now
Traffic should enter through the controller just installed, not a port-forward.

## Evidence
Render diff is one new resource per overlay; the class label rides along.

## If it is wrong
Revert this merge - the app stays reachable by port-forward.

Refs: #7
EOF
```

Read it; when the diff is what the body claims:

```sh
gh pr merge --merge --delete-branch \
&& git switch main \
&& git pull
flux reconcile kustomization app-dev --with-source
```

### 5. Helm vs Kustomize - the rule of thumb

Stated once, applied for the rest of the course: **third-party software arrives by Helm** (the upstream chart is the supported interface; you pin versions and set values), **your own config is Kustomize** (bases and overlays you fully own, patched per environment, no templating language between you and the YAML). HelmReleases live under `infrastructure/`; your workloads live under overlay trees. The smell to avoid is wrapping your own app in a chart to configure it: that buys a template engine where a patch would do.

## Stop & measure

- [ ] `scripts/checkpoint-05` reports all PASS, exit 0 (source, release and stamp Ready, chart at the pinned version, the Alert present, ingress answering, the applied revision wearing two greens). The bullets below are the live half unpacked, for reading and for understanding a FAIL:

```sh
./scripts/checkpoint-05
```

- [ ] Traffic enters through Traefik, no port-forward anywhere. `/healthz`, not `/`: the app has no root route, so `/` returns the *app's* 404 through a perfectly healthy ingress:

```sh
curl -s http://localhost:8080/healthz; echo   # {"status":"ok"}
```

- [ ] The revision the infrastructure stamp applied wears **two** green contexts, `kustomization/infrastructure/<id>` alongside `kustomization/app-dev/<id>`: the loop reports per stamp:

```sh
rev=$(kubectl -n flux-system get kustomization infrastructure \
  -o jsonpath='{.status.lastAppliedRevision}')
gh api "repos/{owner}/{repo}"/commits/${rev##*:}/status --jq '.statuses[].context'
# → kustomization/infrastructure/<id>
# → kustomization/app-dev/<id>
```

Tag the boundary ([using the course §5](../using-the-course.md#5-tags-at-every-boundary)):

```sh
git tag stage-05 \
&& git push origin stage-05 \
&& gh issue close 7 --comment "stage-05 tagged"
```

## Audit artifacts produced

- The chart **version pin in git**: every future Traefik upgrade is a one-line diff with an author, a PR, and a status. Patching evidence an auditor can query.
- `helm history -n traefik traefik`: helm-controller's releases are real Helm releases; the in-cluster release ledger matches the git pins.
- A second status context per commit: outcomes are now attributed per stamp, not per cluster.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `curl localhost:8080` connection refused | Cluster built before this stage's port mappings | `./scripts/cluster-down && ./scripts/cluster-up`; the mappings only exist if the config had them at create time (that's why step 1 rebuilds) |
| `curl localhost:8080/<path>` returns 404 | Traefik answered, so ports and controller are fine: either no route matched (Ingress missing, `ingressClassName` mismatch) or the route matched and the **app** 404'd the path (`/` is not a route; the app serves `/healthz` and `/notes/{id}`) | `kubectl -n ggp get ingress` and `kubectl get ingressclass` for the route side; `curl localhost:8080/healthz` to split router-404 from app-404 |
| HelmRelease stuck `install retries exhausted` | Bad values or chart version typo | `kubectl -n traefik describe helmrelease traefik`, then `flux logs --kind=HelmRelease`; fix in git, `flux reconcile helmrelease traefik -n traefik` |
| HelmRelease `Stalled` with `context deadline exceeded`; helm logs repeat `Service does not have load balancer ingress IP address` | A values key at the wrong path was silently ignored, so the default `LoadBalancer` Service rendered; on kind an external IP never arrives, so helm's install wait runs out its 5m timeout | Verify paths with `helm show values` against the pinned version (service type is `service.spec.type` here); fix in git, push, `flux reconcile helmrelease traefik -n traefik --with-source`; the spec change resets the stall and retries the install |
| Controller pod Pending | `nodeSelector: ingress-ready` but the node label is missing (old cluster-up) | Rebuild via step 1; `kubectl get nodes --show-labels` to confirm |
| `port is already allocated` on cluster-up | Another process (or another kind cluster) owns host 8080/8443 | `HTTP_PORT`/`HTTPS_PORT` env overrides; stage 07 assigns each cluster its own pair |
| Infrastructure breaks but no red X | The new stamp isn't in any Alert's `eventSources` | Step 3 ships the Alert in the same commit; the stage-04 allowlist lesson, applied |

## What you learned, and what's next

Third-party software is a pinned, declarative dependency now: source + release + values in git, upgrades by diff, failures on the commit. The infrastructure/apps split gives dependencies their own tree and their own stamp. Stage 08 makes the ordering between them explicit with `dependsOn`. Still glaring: a plaintext connection string in `apps/base/config/` and an imperative token secret recreated by hand at every rebuild. Stage 06 pays both debts.

---

**Next:** [06 - Secrets](stage-06.md)
