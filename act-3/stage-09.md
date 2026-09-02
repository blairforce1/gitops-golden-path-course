# Stage 09 - Fleet observability

[← 08 - Dependencies & health](stage-08.md) · [Walkthrough index](../README.md)

> **Where you are:** the config repo root, on `main`, three clusters live, explicit `--context` on everything. **Starting state:** stage 08's end state: ordering enforced, baseline gated, `checkpoint-08` passing.

**Goal:** the stage-04 loop at fleet scale, in two halves. First, **the machinery**: with three clusters today, and thirty some day, "which of my stamps is unhealthy, and since when" (*stamps*: the Flux `Kustomization` CRs applying each git path) is answered by a dashboard fed from every cluster. Hub and spoke, the platform cluster running the full stack, dev and prod remote-writing into it with their cluster identity. Then the half most GitOps tutorials skip, **the service**: Ready is a *resource* fact, and a service can be fully Ready while failing every user it has. So the fleet gets **SLIs** (measured indicators, taken at the ingress), **SLOs** (explicit targets with error budgets, versioned in git), burn-rate alerts, and a promotion gate: **changes climb the ladder on error-budget evidence, not just convergence evidence; the ladder is the platform→dev→prod order, which is folders and PR discipline, no controller.** Converged is not working ([rule 5.7](../rules.md#57-converged-is-not-working)): from here on, promotion takes two signatures.

## Steps

### 1. Make `infrastructure/` explicit before it grows

Until now the infrastructure stamp reconciled `./infrastructure` with a *generated* kustomization: fine while one component lived there, wrong the moment variants exist (a generated root includes **everything**, and monitoring must not deploy identically everywhere). Explicit beats generated the moment content diverges. Per the authoring convention, the tool writes the file (`--resources` is exactly how an explicit-selection root is expressed; note `--autodetect` would defeat the whole point by scooping up the variants):

```sh
(cd infrastructure && kustomize create --resources traefik)
```

Monitoring arrives as two **named variants** beside it, `monitoring-hub/` and `monitoring-agent/`, and each cluster *binds the variant it needs*. This is the variance posture from the design record, exercised: structured variants selected by binding, no conditional templating anywhere. A *variant* in the [rule 5.14](../rules.md#514-variants-flags-and-migrations-three-lifecycles-three-homes) sense: a permanent named alternative whose selection outlives releases, unlike a feature flag (channel-scoped, stage 28) or a migration overlay (change-scoped, the migrate-base-config quest).

### 2. Named cluster facts - the substitution allowlist earns its place

The agent variant needs exactly two facts that genuinely differ per cluster: *what this cluster is called* and *where the hub is*. These are the allowlist case for `postBuild.substituteFrom`, named cluster facts, nothing else:

```sh
for c in platform/local-01 dev/dev-01 prod/prod-01; do
  name=${c#*/}
  cat > clusters/$c/resources/cluster-facts.configmap.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-facts
  namespace: flux-system
data:
  cluster_name: "$name"
  monitoring_hub: "http://ggp-local-01-control-plane:30090"
EOF
  (cd clusters/$c/resources && kustomize edit add resource cluster-facts.configmap.yaml)
done
```

> Why a name and not an IP: `ggp-local-01-control-plane` is the platform node's container name on the shared kind network, and both runtimes resolve container names there (docker's embedded DNS, podman's aardvark; kind wires each node's resolver so pods forwarding through CoreDNS get the same answer). The name survives what an IP does not: node containers draw a fresh IP on every reboot and rebuild, but keep their name for the life of the fleet. On AKS this fact becomes a private endpoint, and the lesson is identical: commit the stable endpoint, never a discovered address. If your environment turns out not to resolve container names, pin the IP instead (`docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ggp-local-01-control-plane`) and re-run `scripts/refresh-hub-address` after any reboot or rebuild; it re-derives the IP into every cluster's facts for exactly this case.

### 3. The hub - the full stack, via the machinery we already own

kube-prometheus-stack, installed exactly like Traefik was: HelmRepository + pinned HelmRelease. The platform-is-a-workload principle applied to monitoring itself.

```sh
mkdir -p infrastructure/monitoring-hub/resources
# kustomize create refuses to overwrite; this keeps the block re-runnable
rm -f infrastructure/monitoring-hub/kustomization.yaml
# custom resources belong in the -crs tree below; clear any an earlier layout left here,
# or --autodetect will pull them back into the stack stamp and re-create the CRD deadlock
rm -f infrastructure/monitoring-hub/resources/traefik.servicemonitor.yaml \
      infrastructure/monitoring-hub/resources/flux-system.podmonitor.yaml \
      infrastructure/monitoring-hub/resources/app-slo.prometheusrule.yaml
cat > infrastructure/monitoring-hub/resources/monitoring.namespace.yaml <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: monitoring
EOF

cat > infrastructure/monitoring-hub/resources/prometheus-community.helmrepository.yaml <<'EOF'
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: prometheus-community
  namespace: monitoring
spec:
  interval: 1h
  url: https://prometheus-community.github.io/helm-charts
EOF

cat > infrastructure/monitoring-hub/resources/kube-prometheus-stack.helmrelease.yaml <<'EOF'
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: kube-prometheus-stack
  namespace: monitoring
spec:
  interval: 30m
  timeout: 10m
  chart:
    spec:
      chart: kube-prometheus-stack
      version: "77.5.0" # pinned - Renovate takes this over in stage 13
      sourceRef:
        kind: HelmRepository
        name: prometheus-community
  values:
    prometheus:
      service:
        type: NodePort # the spokes' remote-write endpoint (container-to-container);
        nodePort: 30090 # from the HOST, use port-forward - see step 8
      prometheusSpec:
        enableRemoteWriteReceiver: true # the spokes write here
        externalLabels:
          cluster: ${cluster_name}
    grafana:
      sidecar:
        dashboards:
          enabled: true # any ConfigMap labeled grafana_dashboard=1 becomes a dashboard
    kube-state-metrics:
      # The chart's OWN feature switch - not a hand-rolled ConfigMap. Turning this on
      # is what makes the chart mount the config, pass the flag, AND grant the
      # apiextensions/customresourcedefinitions RBAC that CRS informers require.
      customResourceState:
        enabled: true
        config:
          spec:
            resources:
            - groupVersionKind:
                group: kustomize.toolkit.fluxcd.io
                version: v1
                kind: Kustomization
              metricNamePrefix: gotk
              metrics:
              - name: resource_info
                help: The current state of a Flux Kustomization resource.
                each:
                  type: Info
                  info:
                    labelsFromPath:
                      name:
                      - metadata
                      - name
                labelsFromPath:
                  exported_namespace:
                  - metadata
                  - namespace
                  ready:
                  - status
                  - conditions
                  - "[type=Ready]"
                  - status
                  revision:
                  - status
                  - lastAppliedRevision
                  suspended:
                  - spec
                  - suspend
            - groupVersionKind:
                group: helm.toolkit.fluxcd.io
                version: v2
                kind: HelmRelease
              metricNamePrefix: gotk
              metrics:
              - name: resource_info
                help: The current state of a Flux HelmRelease resource.
                each:
                  type: Info
                  info:
                    labelsFromPath:
                      name:
                      - metadata
                      - name
                labelsFromPath:
                  exported_namespace:
                  - metadata
                  - namespace
                  ready:
                  - status
                  - conditions
                  - "[type=Ready]"
                  - status
                  revision:
                  - status
                  - history
                  - "0"
                  - chartVersion
                  suspended:
                  - spec
                  - suspend
            - groupVersionKind:
                group: source.toolkit.fluxcd.io
                version: v1
                kind: GitRepository
              metricNamePrefix: gotk
              metrics:
              - name: resource_info
                help: The current state of a Flux GitRepository resource.
                each:
                  type: Info
                  info:
                    labelsFromPath:
                      name:
                      - metadata
                      - name
                labelsFromPath:
                  exported_namespace:
                  - metadata
                  - namespace
                  ready:
                  - status
                  - conditions
                  - "[type=Ready]"
                  - status
                  revision:
                  - status
                  - artifact
                  - revision
                  suspended:
                  - spec
                  - suspend
            - groupVersionKind:
                group: source.toolkit.fluxcd.io
                version: v1
                kind: HelmRepository
              metricNamePrefix: gotk
              metrics:
              - name: resource_info
                help: The current state of a Flux HelmRepository resource.
                each:
                  type: Info
                  info:
                    labelsFromPath:
                      name:
                      - metadata
                      - name
                labelsFromPath:
                  exported_namespace:
                  - metadata
                  - namespace
                  ready:
                  - status
                  - conditions
                  - "[type=Ready]"
                  - status
                  revision:
                  - status
                  - artifact
                  - revision
                  suspended:
                  - spec
                  - suspend
      rbac:
        extraRules:
        - apiGroups:
          - helm.toolkit.fluxcd.io
          - kustomize.toolkit.fluxcd.io
          - source.toolkit.fluxcd.io
          resources:
          - gitrepositories
          - helmreleases
          - helmrepositories
          - kustomizations
          verbs:
          - list
          - watch
EOF

(cd infrastructure/monitoring-hub && kustomize create --autodetect --recursive)

# The CUSTOM RESOURCES live in their own tree, because they need CRDs that the stack
# above installs. Stage 08's promise coming due: "a stamp that ships CRs depends on
# the stamp that ships their CRDs" - step 5 wires exactly that.
mkdir -p infrastructure/monitoring-hub-crs/resources
rm -f infrastructure/monitoring-hub-crs/kustomization.yaml
cat > infrastructure/monitoring-hub-crs/resources/flux-system.podmonitor.yaml <<'EOF'
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: flux-system
  namespace: monitoring
  labels:
    release: kube-prometheus-stack # the operator's selector; unlabeled = never selected
spec:
  namespaceSelector:
    matchNames:
    - flux-system
  selector:
    matchExpressions:
    - key: app
      operator: In
      values:
      - helm-controller
      - image-automation-controller
      - image-reflector-controller
      - kustomize-controller
      - notification-controller
      - source-controller
  podMetricsEndpoints:
  - port: http-prom
EOF

(cd infrastructure/monitoring-hub-crs && kustomize create --autodetect --recursive)
```

Three load-bearing pieces, all worth reading before moving on.

**`customResourceState` is the chart's own feature switch, and using it isn't a stylistic preference.** kube-state-metrics can export the state of any CR: that's how per-stamp Ready/suspended/revision become metrics with a `cluster` label, which is precisely the "which stamp, which cluster, since when" query. You *can* wire it by hand (your own ConfigMap, `extraArgs`, `volumes`, `volumeMounts`) and it will look right: flag passed, file mounted, pod Running, no errors on the surface. It produces **zero metrics**, because CRS informers also need `list`/`watch` on `customresourcedefinitions.apiextensions.k8s.io`, and the chart only adds that rule when *its own switch* is on. Stage 05's values-path scar, second verse: there a plausible-but-wrong values *path* was silently ignored; here a plausible-but-wrong *approach* was silently under-privileged. **When a chart offers a feature switch, use it: the switch owns more than the flag it sets.**

**`exported_namespace` is not a typo.** Each CRS series already carries a `namespace` label from the scraped pod (kube-state-metrics' own), so the CR's namespace must be published under a non-colliding name, the same `exported_*` collision the Traefik SLIs meet in step 7. Flux's dashboard filters on `exported_namespace`; a config that omits it renders every panel empty while every metric exists.

**The PodMonitor covers the dashboard's other half.** `gotk_resource_info` (from kube-state-metrics) answers *what state is each stamp in*; `gotk_reconcile_duration_seconds_*`, scraped from the Flux controllers themselves, answers *how long reconciles take and how often they fail*. Note its `release: kube-prometheus-stack` label: the operator's selectors are label-scoped, and an unlabeled PodMonitor or ServiceMonitor isn't rejected; it's simply **never selected**. Silent, green, and dark, which is this act's recurring villain.

Vendor Flux's control-plane dashboard for the sidecar to pick up:

```sh
mkdir -p infrastructure/monitoring-hub/config
curl -sSLo infrastructure/monitoring-hub/config/cluster.json \
  https://raw.githubusercontent.com/fluxcd/flux2-monitoring-example/main/monitoring/configs/dashboards/cluster.json
cat > infrastructure/monitoring-hub/config/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
configMapGenerator:
- name: flux-dashboard
  namespace: monitoring
  files:
  - cluster.json
  options:
    labels:
      grafana_dashboard: "1"
EOF
(cd infrastructure/monitoring-hub && kustomize edit add resource config)
```

### 4. The agent variant - same stack, simplified to only ship metrics

```sh
mkdir -p infrastructure/monitoring-agent/resources
# kustomize create refuses to overwrite; this keeps the block re-runnable
rm -f infrastructure/monitoring-agent/kustomization.yaml
# custom resources belong in the -crs tree below; clear any an earlier layout left here,
# or --autodetect will pull them back into the stack stamp and re-create the CRD deadlock
rm -f infrastructure/monitoring-agent/resources/traefik.servicemonitor.yaml \
      infrastructure/monitoring-agent/resources/flux-system.podmonitor.yaml \
      infrastructure/monitoring-agent/resources/app-slo.prometheusrule.yaml
cp infrastructure/monitoring-hub/resources/monitoring.namespace.yaml \
   infrastructure/monitoring-hub/resources/prometheus-community.helmrepository.yaml \
   infrastructure/monitoring-agent/resources/

cat > infrastructure/monitoring-agent/resources/kube-prometheus-stack.helmrelease.yaml <<'EOF'
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: kube-prometheus-stack
  namespace: monitoring
spec:
  interval: 30m
  timeout: 10m
  chart:
    spec:
      chart: kube-prometheus-stack
      version: "77.5.0"
      sourceRef:
        kind: HelmRepository
        name: prometheus-community
  values:
    alertmanager:
      enabled: false
    grafana:
      enabled: false
    defaultRules:
      create: false # the hub evaluates rules for the whole fleet; a spoke doing it too is a second writer
    prometheus:
      prometheusSpec:
        retention: 2h # ships metrics on, keeps nothing worth storing
        externalLabels:
          cluster: ${cluster_name}
        remoteWrite:
        - url: ${monitoring_hub}/api/v1/write
    kube-state-metrics:
      # The chart's OWN feature switch - not a hand-rolled ConfigMap. Turning this on
      # is what makes the chart mount the config, pass the flag, AND grant the
      # apiextensions/customresourcedefinitions RBAC that CRS informers require.
      customResourceState:
        enabled: true
        config:
          spec:
            resources:
            - groupVersionKind:
                group: kustomize.toolkit.fluxcd.io
                version: v1
                kind: Kustomization
              metricNamePrefix: gotk
              metrics:
              - name: resource_info
                help: The current state of a Flux Kustomization resource.
                each:
                  type: Info
                  info:
                    labelsFromPath:
                      name:
                      - metadata
                      - name
                labelsFromPath:
                  exported_namespace:
                  - metadata
                  - namespace
                  ready:
                  - status
                  - conditions
                  - "[type=Ready]"
                  - status
                  revision:
                  - status
                  - lastAppliedRevision
                  suspended:
                  - spec
                  - suspend
            - groupVersionKind:
                group: helm.toolkit.fluxcd.io
                version: v2
                kind: HelmRelease
              metricNamePrefix: gotk
              metrics:
              - name: resource_info
                help: The current state of a Flux HelmRelease resource.
                each:
                  type: Info
                  info:
                    labelsFromPath:
                      name:
                      - metadata
                      - name
                labelsFromPath:
                  exported_namespace:
                  - metadata
                  - namespace
                  ready:
                  - status
                  - conditions
                  - "[type=Ready]"
                  - status
                  revision:
                  - status
                  - history
                  - "0"
                  - chartVersion
                  suspended:
                  - spec
                  - suspend
            - groupVersionKind:
                group: source.toolkit.fluxcd.io
                version: v1
                kind: GitRepository
              metricNamePrefix: gotk
              metrics:
              - name: resource_info
                help: The current state of a Flux GitRepository resource.
                each:
                  type: Info
                  info:
                    labelsFromPath:
                      name:
                      - metadata
                      - name
                labelsFromPath:
                  exported_namespace:
                  - metadata
                  - namespace
                  ready:
                  - status
                  - conditions
                  - "[type=Ready]"
                  - status
                  revision:
                  - status
                  - artifact
                  - revision
                  suspended:
                  - spec
                  - suspend
            - groupVersionKind:
                group: source.toolkit.fluxcd.io
                version: v1
                kind: HelmRepository
              metricNamePrefix: gotk
              metrics:
              - name: resource_info
                help: The current state of a Flux HelmRepository resource.
                each:
                  type: Info
                  info:
                    labelsFromPath:
                      name:
                      - metadata
                      - name
                labelsFromPath:
                  exported_namespace:
                  - metadata
                  - namespace
                  ready:
                  - status
                  - conditions
                  - "[type=Ready]"
                  - status
                  revision:
                  - status
                  - artifact
                  - revision
                  suspended:
                  - spec
                  - suspend
      rbac:
        extraRules:
        - apiGroups:
          - helm.toolkit.fluxcd.io
          - kustomize.toolkit.fluxcd.io
          - source.toolkit.fluxcd.io
          resources:
          - gitrepositories
          - helmreleases
          - helmrepositories
          - kustomizations
          verbs:
          - list
          - watch
EOF

(cd infrastructure/monitoring-agent && kustomize create --autodetect --recursive)

# and the agent's CR tree - the PodMonitor is identical, the hub's PrometheusRule is not copied
mkdir -p infrastructure/monitoring-agent-crs/resources
rm -f infrastructure/monitoring-agent-crs/kustomization.yaml
cp infrastructure/monitoring-hub-crs/resources/flux-system.podmonitor.yaml \
   infrastructure/monitoring-agent-crs/resources/
(cd infrastructure/monitoring-agent-crs && kustomize create --autodetect --recursive)
```

One value in that block earns a paragraph: `defaultRules.create: false`. The chart ships about thirty-five rule files (the `node_namespace_pod_container:*`, `count:up1` and friends every kube-prometheus dashboard is built on), and by default every installation evaluates them. On a hub-and-spoke fleet that is one evaluator too many. The hub's copies aggregate `by (cluster, ...)`, so the hub already writes a `cluster="dev-01"` version of every rule series from the raw samples dev-01 sends; a spoke evaluating the same rule and remote-writing the result is a second writer to the same series. Prometheus keeps whichever sample arrives first and refuses the other as out of order, and it refuses the whole batch that sample arrived in, two thousand samples at a time, `gotk_resource_info` included. Measured on this fleet: prod's copies arrived two seconds ahead of the hub's and got through; dev's arrived a few seconds behind and lost most of what it sent, and the dashboard's sources table showed two clusters where there were three. Spokes ship raw samples. Rules are evaluated once, where the data lives.

### 5. Bind the variants - and tell the Alerts

Each cluster gets a `monitoring` stamp pointing at its variant, substituting its named facts, alerted per the allowlist lesson:

```sh
for c in platform/local-01:monitoring-hub dev/dev-01:monitoring-agent prod/prod-01:monitoring-agent; do
  path=${c%%:*}; variant=${c#*:}
  cat > clusters/$path/resources/monitoring.kustomization.yaml <<EOF
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: monitoring
  namespace: flux-system
spec:
  interval: 5m
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./infrastructure/$variant
  prune: true
  wait: true
  timeout: 10m
  dependsOn:
  - name: infrastructure
  postBuild:
    substituteFrom:
    - kind: ConfigMap
      name: cluster-facts
EOF
  # the SECOND stamp: the custom resources, gated on the stack that installs their CRDs
  cat > clusters/$path/resources/monitoring-crs.kustomization.yaml <<EOF
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: monitoring-crs
  namespace: flux-system
spec:
  interval: 5m
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./infrastructure/$variant-crs
  prune: true
  wait: true
  timeout: 5m
  dependsOn:
  - name: monitoring
EOF
  for stamp in monitoring monitoring-crs; do
    sed "s/name: infrastructure\$/name: $stamp/; s/infrastructure-status/$stamp-status/" \
      clusters/$path/resources/infrastructure-status.alert.yaml \
      > clusters/$path/resources/$stamp-status.alert.yaml
  done
  (cd clusters/$path/resources && kustomize edit add resource \
    monitoring.kustomization.yaml monitoring-status.alert.yaml \
    monitoring-crs.kustomization.yaml monitoring-crs-status.alert.yaml)
done

git add infrastructure clusters
./scripts/pr-open feat/12/monitoring-hub "feat(monitoring): hub on local-01, agents remote-writing from dev and prod" <<'EOF'
## What is moving
kube-prometheus-stack as the hub on local-01; agent-mode Prometheus on dev-01 and prod-01 remote-writing to it; a monitoring stamp and Alert per cluster.

## Why now
Three clusters, one terminal: the commit statuses answer "did it land", not "what is the fleet doing".

## Evidence
Renders per cluster differ only in the external cluster label and the hub address; every new stamp has its Alert.

## If it is wrong
Revert this merge; prune removes the stacks.

Refs: #12
EOF
```

Read it; when the diff is what the body claims:

> **The merge block has a new first line, from here to the end of the course.** Stage 08's ruleset requires the `rendered-policy` check, so a merge attempted before the check has reported is refused (`the base branch policy prohibits the merge`). `gh pr checks --watch --fail-fast` waits for every check to finish and stops the line at the first red one; only then does the merge run. Reading the diff usually takes longer than the check does, so most of the time the wait is nothing, but the line stays: it is the pre-merge verdict being read before the merge, which is the whole point of having one.

```sh
gh pr checks --watch --fail-fast \
&& gh pr merge --merge --delete-branch \
&& git switch main \
&& git pull
for ctx in kind-ggp-local-01 kind-ggp-dev-01 kind-ggp-prod-01; do
  flux reconcile kustomization flux-system --with-source --context $ctx
done
```

This is a big pull (the stack is heavy); give it minutes, then gate on all three clusters' `monitoring` **and** `monitoring-crs` stamps being Ready before the drill.

**Why two stamps and not one: the CRD deadlock.** kube-prometheus-stack's chart *creates* the Prometheus-Operator CRDs (`ServiceMonitor`, `PodMonitor`, `PrometheusRule`); the objects added in steps 7 and 8 are instances of exactly those kinds. Put both in one stamp and a **fresh** cluster deadlocks: kustomize-controller server-side dry-runs the whole set before applying any of it, the CR fails with `no matches for kind "ServiceMonitor"` because its CRD doesn't exist *yet*, and that failure aborts the entire apply, including the HelmRelease that would have created the CRD. Nothing installs; the stamp never goes Ready. The cruel part is that one stamp works perfectly when you build it incrementally, because the chart lands in an earlier commit than the CRs. Only a from-scratch rebuild reveals the cycle. That's stage 08's promise coming due (*"a stamp that ships CRs depends on the stamp that ships their CRDs"*), and it is exactly why the Act III checkpoint rebuilds the whole fleet from nothing: **order-independence is a property you can only prove by starting over.**

### 6. The fleet drill - one broken stamp among many, found from the dashboard

Open Grafana. The port-forward blocks, and the dashboard has to stay up for the whole drill (break, read, restore), so give it a **second terminal**: open one, `cd` to the config repo root, run this there and leave it running. Every other step of this drill happens in your first terminal:

```sh
kubectl --context kind-ggp-local-01 -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
```

| | |
|---|---|
| **URL** | <http://localhost:3000> |
| **Username** | `admin` |
| **Password** | `prom-operator` (the chart's default, fine for a local hub; a real one sets `grafana.adminPassword` from a secret) |
| **Dashboard** | *Flux Cluster Stats* (the vendored `cluster.json` from step 3, via the sidebar's search) |

Every stamp on every cluster is a row with a `cluster` label. One honest asymmetry to know about before you read the panels.

**External labels are applied on the way *out*, not in local storage.** `externalLabels: cluster: ${cluster_name}` stamps every series a Prometheus *sends* (remote-write, federation, alerts), so the spokes' data lands on the hub correctly labeled `dev-01` / `prod-01`. The hub's own scrapes never leave the hub, so they keep no `cluster` label at all: the platform cluster shows up as the blank entry in any `by (cluster)` grouping. It's a genuine wrinkle of collapsing hub and spoke into one Prometheus: a production hub is usually a *pure aggregator* (it scrapes nothing locally; every cluster including the platform one runs an agent), and then every series is labeled by construction. Consequence to remember: `./scripts/slo-gate local-01` finds nothing, because there is nothing labeled `local-01`. The gate's rungs are `dev-01` and `prod-01`, which is where the ladder does its work anyway.

Now break prod, quietly, as if you weren't the one doing it:

```sh
source ./env.sh
(cd apps/overlays/prod && kustomize edit set image $APP_IMAGE:9.9.9)
git add apps/overlays/prod
./scripts/pr-open break/12/prod "break(app-prod): absent image" <<'EOF'
## What is moving
Prod's app pin to 9.9.9, which does not exist.

## Why now
Stage 09 drill: find a broken rung from the dashboard, not from scrolling statuses.

## Evidence
None - the break is the experiment.

## If it is wrong
The next PR reverts this merge.

Refs: #12
EOF
```

Read it; when the diff is what the body claims:

```sh
gh pr checks --watch --fail-fast \
&& gh pr merge --merge --delete-branch \
&& git switch main \
&& git pull
```

What you will see first is not the break. The merge is a push, and on every push each stamp with `dependsOn` goes Ready=**False** (`DependencyNotReady`) until the stamp it depends on has applied the new revision, re-checked every 30s: `app-dev`, `monitoring` and `monitoring-crs` flash red down their chains for a minute or so, then clear. Let the cascade settle. The row that stays red is the incident.

Work the incident **from the dashboard only**: which stamp is not Ready, on which cluster, since when (`gotk_resource_info{ready!="True"}`: the panel names `app-prod` on `cluster=prod-01`, with a timestamp). Not Ready has two colours here, and the failing row wears the quieter one most of the time. Each attempt runs the 3m health check with the row at **Unknown** (`Reconciliation in progress`), gives up (`HealthCheckFailed`, Ready=**False**), and under stage 08's `retryInterval: 30s` starts the next attempt half a minute later. So the row reads Unknown for about three minutes in every three and a half, red for the rest, and never Ready: a row that stays out of Ready across a few refreshes is the incident, whichever of the two it shows at the moment you look. The `Not Ready` count at the top of the dashboard reads only `ready="False"`, so it sits at 0 for most of a real failure; the table is the honest view. Then, and only then, triage with the stage-04 ladder *on the cluster the dashboard named*, and restore:

```sh
flux get kustomizations --context kind-ggp-prod-01
flux events --context kind-ggp-prod-01 --for Kustomization/app-prod | tail -3
sha=$(./scripts/commit-by-subject --prefix 'break(app-prod): ')   # the break by its subject, never by HEAD
./scripts/pr-revert "$sha" "Drill done: the dashboard named the rung, the ladder named the cause."
```

Read it; when the diff is what the body claims:

```sh
gh pr checks --watch --fail-fast \
&& gh pr merge --merge --delete-branch \
&& git switch main \
&& git pull
```

Watch the dashboard row for `app-prod` return to Ready. That is the end of the drill: Ctrl-C in the second terminal closes the port-forward.

The point of the drill: at fleet scale you didn't scroll three clusters' worth of statuses. The dashboard aggregated, the commit status confirmed, the ladder localized. Detection, attribution, restore: each tool doing the one job it's shaped for.

**Attribution ends at a reason code, and the codes are a vocabulary, not a sentence.** `flux events` did not say "reconciliation failed"; it named the **reason** on the Ready condition, from a short, enumerable set, and that distinction is the audit deliverable: the dashboard's `ready="False"` locates, the reason *answers*. The fleet can produce two so far. `DependencyNotReady` is ordering doing its job: the cascade in the troubleshooting table, cleared in one retry. `HealthCheckFailed` is stage 08's `wait: true` judging a rollout that never went Ready, which is where this drill's absent image lands. A third state is deliberately neither: a suspended stamp is not failing, it is *told not to converge*, which is why step 3's `customResourceState` exports `suspended` as its own label instead of letting it wear either colour. The set grows as the platform grows teeth: stage 30 adds `VerificationError` (an artifact that failed signature verification) and the admission denial, arriving as `ReconciliationFailed` carrying the policy's own message. Key the alert or the report on the reason and it stays exact; key it on "not Ready" and it collapses five different facts into one page, an answer for a dashboard, never for an audit.

### 7. SLIs - measure the service, not the resource

Everything so far watches the *machinery*: stamps Ready, releases installed, pods Available. None of it can see the failure mode that matters most: **a service that is fully Ready and failing its users**. The app makes this concrete: `/healthz` is static (it proves the process answers, nothing more), so a bad storage config leaves every resource green while every real request returns 500. Detecting that takes a **Service Level Indicator**, a measurement of what users experience: request success rate, latency. And the cheapest correct place to take it is one you already run: **the ingress sees every request**, and Traefik exports per-service request counts (by status code) and duration histograms out of the box. Your first SLIs cost zero app changes. (When the app matures, its own `/metrics` adds depth: per-endpoint, per-dependency; the lesson is you don't wait for that to start.)

Two pieces. Traefik's metrics endpoint gets a plain Service (in the traefik tree: no CRDs involved, so it's safe at the infrastructure layer), and the *scrape*, a ServiceMonitor, which **is** a monitoring CRD, goes in the monitoring variants, whose stamp already `dependsOn` infrastructure. Put the ServiceMonitor in traefik's own release and a fresh rebuild deadlocks: infrastructure would need CRDs that only arrive with monitoring, which waits for infrastructure. Filing each piece by what it depends on is stage 08's lesson doing quiet work:

```sh
# yq is safe here: this file holds no list, so its re-indent has nothing to touch
yq -i '.spec.values.metrics.prometheus.service.enabled = true' \
  infrastructure/traefik/resources/traefik.helmrelease.yaml

for v in monitoring-hub-crs monitoring-agent-crs; do
  cat > infrastructure/$v/resources/traefik.servicemonitor.yaml <<'EOF'
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: traefik
  namespace: monitoring
  labels:
    release: kube-prometheus-stack # step 3's lesson: unlabeled = never selected
spec:
  namespaceSelector:
    matchNames:
    - traefik
  selector:
    matchLabels:
      app.kubernetes.io/name: traefik
  endpoints:
  - port: metrics
EOF
  (cd infrastructure/$v && kustomize edit add resource resources/traefik.servicemonitor.yaml)
done
```

One scrape mechanic worth knowing before you query: Traefik labels its own series with `service` (e.g. `ggp-app-8080@kubernetes`), Prometheus reserves that label for the scrape target, so on the hub the label arrives as **`exported_service`**. Every query below uses it.

### 8. SLOs - the target is policy, so it lives in git

An SLI is a measurement; a **Service Level Objective** is a commitment about it. Here: **99% of app requests succeed, over 30 days**. The complement is the **error budget**: the 1% you're allowed to fail, which for a month is about **7¼ hours** of total outage. That budget is the whole point of the exercise: it converts "don't break things" into a number you can spend deliberately on releases, experiments and risk.

The SLO ships as a PrometheusRule **on the hub only**: the agents ship samples, the hub judges, and the hub is where alertmanager lives. One rule set covers the fleet because the `cluster` label rides through every expression.

```sh
cat > infrastructure/monitoring-hub-crs/resources/app-slo.prometheusrule.yaml <<'EOF'
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: app-slo
  namespace: monitoring
  labels:
    release: kube-prometheus-stack # the operator's rule selector
spec:
  groups:
  - name: app-slo
    interval: 30s
    rules:
    # THE PROMISE. The only place the target number is written. Everything below
    # derives from it, and so does scripts/slo-gate - change it here, once.
    - record: slo:app_availability:target
      expr: vector(0.99)
    # THE INGREDIENTS. Two counters, summed per cluster, as per-second rates.
    - record: slo:app_requests:rate5m
      expr: sum by (cluster) (rate(traefik_service_requests_total{exported_service=~"ggp-app-.*"}[5m]))
    # `or (... * 0)` is load-bearing: with no 5xx at all the selector matches nothing
    # and this rule would produce NO SERIES, taking availability down with it. See below.
    - record: slo:app_errors:rate5m
      expr: sum by (cluster) (rate(traefik_service_requests_total{exported_service=~"ggp-app-.*",code=~"5.."}[5m]))
            or (slo:app_requests:rate5m * 0)
    # THE INDICATORS. What a dashboard plots and a human reads.
    # `> 0` on the denominator: with no requests at all, availability is genuinely
    # undefined - better absent than a NaN that spreads through panels. See below.
    - record: slo:app_availability:ratio_rate5m
      expr: 1 - (slo:app_errors:rate5m / (slo:app_requests:rate5m > 0))
    - record: slo:app_latency_p95:5m
      expr: histogram_quantile(0.95, sum by (cluster, le) (rate(traefik_service_request_duration_seconds_bucket{exported_service=~"ggp-app-.*"}[5m])))
            and on (cluster) (slo:app_requests:rate5m > 0)
    # THE ALARM. Not "are there errors" but "is the budget draining fast enough to care".
    - alert: AppErrorBudgetFastBurn
      expr: (slo:app_errors:rate5m / slo:app_requests:rate5m)
            > (14.4 * (1 - scalar(slo:app_availability:target)))
      for: 2m
      labels:
        severity: critical
      annotations:
        summary: "app on {{ $labels.cluster }} is burning its 30d error budget at >=14.4x"
        description: "5xx ratio {{ $value | humanizePercentage }} - at this rate the month's entire error budget is gone in about two days."
EOF
(cd infrastructure/monitoring-hub-crs && kustomize edit add resource resources/app-slo.prometheusrule.yaml)

git add infrastructure
./scripts/pr-open feat/12/slo-rules "feat(monitoring-crs): SLIs at the ingress, SLO and fast-burn alert on the hub" <<'EOF'
## What is moving
ServiceMonitors for Traefik on every cluster; recording rules for the app's availability SLI and a fast-burn alert, on the hub.

## Why now
Converged is not working: the fleet needs a signal that measures the service, not the reconciler.

## Evidence
Rules load on the hub; the SLI resolves per cluster once traffic flows.

## If it is wrong
Revert this merge; nothing the app runs depends on it.

Refs: #12
EOF
```

Read it; when the diff is what the body claims:

```sh
gh pr checks --watch --fail-fast \
&& gh pr merge --merge --delete-branch \
&& git switch main \
&& git pull
for ctx in kind-ggp-local-01 kind-ggp-dev-01 kind-ggp-prod-01; do
  flux reconcile kustomization infrastructure --with-source --context $ctx
  flux reconcile kustomization monitoring --with-source --context $ctx
done
```

### Reading the rule file

Six entries look like a lot for one promise. They're four different jobs, and separating them is what makes the SLO maintainable:

| Entry | Kind | Job |
|---|---|---|
| `slo:app_availability:target` | recording | **The promise itself**, as data. `vector(0.99)` is a constant series, which sounds odd until you notice the payoff: the number is now *queryable*, so the alert and `scripts/slo-gate` both read it instead of each hard-coding 0.99 |
| `slo:app_requests:rate5m` | recording | Total request rate per cluster, the denominator |
| `slo:app_errors:rate5m` | recording | 5xx rate per cluster, the numerator, with a zero floor so it exists even when nothing is failing |
| `slo:app_availability:ratio_rate5m` | recording | The SLI a human reads: the fraction of requests succeeding right now |
| `slo:app_latency_p95:5m` | recording | The second SLI: slow is a failure mode too, and one no `Ready` check can see |
| `AppErrorBudgetFastBurn` | **alert** | The only entry that pages anyone |

**Why recording rules instead of writing the query where it's needed?** Three reasons, in order of importance. They're **one definition, many consumers**: dashboard panels, the alert, and the promotion gate all mean exactly the same thing by "availability", because they all read the same series. The classic failure mode here is a dashboard and an alert that disagree because someone edited one query. They're **an abstraction boundary**: the day these SLIs come from the app's own `/metrics` instead of Traefik, you rewrite two expressions and every consumer follows unchanged. And they're **precomputed** every 30s (`interval`), so heavy histogram maths happens once rather than per dashboard refresh.

The `slo:app_requests:rate5m` shape isn't decoration either. It's Prometheus's own convention, `level:metric:operations`: the aggregation level (`slo`), what's measured, and what was done to it. The colons are legal only in recording-rule names, so a `:` in a metric name tells you instantly you're reading a derived series, not raw instrumentation.

**Absent is not zero: the trap that bites every first SLO.** A healthy service produces *no* 5xx series at all: the selector `code=~"5.."` matches nothing, `sum by (cluster)` over nothing is nothing, and the division that follows has no series to match against. Availability doesn't come out as `1`, it comes out **empty**, which renders as "No Data" on a dashboard and reads identically to *the monitoring is broken*. The healthier your service, the more your SLI looks dead. `or (slo:app_requests:rate5m * 0)` supplies the missing zero: where errors exist the real value wins; where they don't, the request series is multiplied by zero to mint a `0` on the same `cluster` label. (A promtool unit test makes the trap concrete: without the `or`, availability is `nil` under all-200s traffic; with it, `1`.) Note `scripts/slo-gate` handles the same absence in bash: an empty error total becomes `0`, because a gate that can't tell "no failures" from "no data" would pass a rung it never measured.

**Its mirror image: undefined is not zero either.** The `or` above fixes *no errors*; the opposite case is *no requests*, and it wants the opposite treatment. A cluster serving nothing has no availability figure. You cannot compute a success ratio over zero requests, and `0/0` in PromQL is `NaN`, which spreads through dashboards and aggregations as a value that looks like data. `(slo:app_requests:rate5m > 0)` filters the denominator to clusters that actually served traffic, so an idle cluster's SLI is *absent* rather than nonsense. The two guards together give the three honest answers: **traffic and no errors ⇒ 1**, **traffic with errors ⇒ the real ratio**, **no traffic ⇒ nothing to report**. That last one is the same judgement `scripts/slo-gate` makes when it refuses to promote a rung with no traffic evidence. Absence of failure is not evidence of health, in the query language and in the gate alike.

> In this fleet you'll see the idle case immediately: the platform cluster runs its own Traefik and nobody is driving traffic through `:8080`, so before this guard it produced an unlabeled `NaN` row, unlabeled because the hub's own series carry no `cluster` label, per the external-labels note in step 5.

**Where 14.4 comes from.** Alerting on "any errors" pages you for noise; alerting on "the budget is draining unsustainably" pages you for the thing that actually threatens the promise. **Burn rate** is the ratio of your current error rate to the rate that would exhaust the budget exactly at the period's end: burn 1× for 30 days and you land precisely on 99%. Burn **14.4×** and the whole month's budget is gone in `30 / 14.4 ≈ 2 days`, the Google SRE workbook's canonical fast-burn threshold, which for a 99% target means a sustained 14.4% error rate (`14.4 × 0.01`). `for: 2m` keeps a brief blip from paging. This is the workbook's multiwindow ladder trimmed to its fast rung for teachability; production adds a slow-burn pair (typically 6× over 6h and 1× over 3d) so gradual erosion is caught too: a ticket, not a page.

**How to change the SLO.** One line, and not a `yq` line: the rules are a list, and yq would hand the whole file back in its own indentation (stage 08 step 1). The target is written in exactly one place, so an exact substitution is the whole edit:

```sh
sed -i 's/vector(0.99)/vector(0.999)/' infrastructure/monitoring-hub-crs/resources/app-slo.prometheusrule.yaml
```

Commit it and everything follows: the fast-burn alert re-derives its threshold (99.9% ⇒ pages at a 1.44% error rate, ten times more sensitive), and `slo-gate` reads the new target on its next run, so the promotion ladder tightens in the same commit. Three consequences worth understanding before you tighten it, because a target is a commitment and not an aspiration: the monthly budget shrinks from ~7¼ hours to ~44 minutes; every deployment now spends a visible fraction of it; and a target the team can't actually hold produces alert fatigue, which is *worse* than a modest target honoured. Pick the number you'd defend in a review, then let git record who defended it. The history of this file is the history of what this platform promised its users.

**Check the rules before the cluster does.** PromQL typos deploy perfectly well and then simply never fire. An alert that is silently wrong is worse than no alert, because you believe you're covered. `promtool` validates rule syntax offline, and it's the same binary Prometheus itself ships:

```sh
yq '.spec' infrastructure/monitoring-hub-crs/resources/app-slo.prometheusrule.yaml \
  | docker run --rm -i --entrypoint promtool docker.io/prom/prometheus:v3.5.0 check rules /dev/stdin
```

Expect `SUCCESS: 6 rules found`. Note the shape: `yq` peels the rules out of the CR wrapper (promtool wants a rules file, not a Kubernetes object) and pipes them **through stdin, with no bind mount at all**. That's deliberate. Mounting is where containerised filters get fiddly: podman flatly refuses to SELinux-relabel `/tmp`, and pinned images typically run as an unprivileged uid that can't read your files anyway (see [stage 11](../act-4/stage-11.md)). A pipe has no uid and no labels to negotiate, which is exactly why the tool-provisioning rule prefers filters that read stdin. Going further is worthwhile on a real SLO: `promtool test rules` runs **unit tests against alert rules**: you feed synthetic series and assert which alerts fire, so "does 20% errors page us, and does 5% not?" becomes a test rather than a hope.

Make that sentence a file. A unit test for alert rules feeds synthetic series into the rule set and asserts which alerts fire, and when. The rules file it reads is derived from the CR at test time, so the target stays written in one place:

```sh
mkdir -p tests
cat > tests/app-slo.test.yaml <<'EOF'
# promtool unit tests for the SLO rules: synthetic counters in, alert verdicts out.
# app-slo.rules.yaml is derived from the PrometheusRule at test time (stage 09 step 8).
rule_files:
- app-slo.rules.yaml
evaluation_interval: 30s
tests:
# 100 req/s on prod-01, 20 of them 5xx. The budget burns at 20x: the alert must page.
- interval: 30s
  input_series:
  - series: 'traefik_service_requests_total{cluster="prod-01", exported_service="ggp-app-8080@kubernetes", code="200"}'
    values: '0+2400x40'
  - series: 'traefik_service_requests_total{cluster="prod-01", exported_service="ggp-app-8080@kubernetes", code="503"}'
    values: '0+600x40'
  alert_rule_test:
  - eval_time: 10m
    alertname: AppErrorBudgetFastBurn
    exp_alerts:
    - exp_labels:
        severity: critical
        cluster: prod-01
      exp_annotations:
        summary: app on prod-01 is burning its 30d error budget at >=14.4x
        description: 5xx ratio 20% - at this rate the month's entire error budget is gone in about two days.
# The same traffic with 5 in 100 failing. Under 14.4x: the alert must stay silent.
- interval: 30s
  input_series:
  - series: 'traefik_service_requests_total{cluster="prod-01", exported_service="ggp-app-8080@kubernetes", code="200"}'
    values: '0+2850x40'
  - series: 'traefik_service_requests_total{cluster="prod-01", exported_service="ggp-app-8080@kubernetes", code="503"}'
    values: '0+150x40'
  alert_rule_test:
  - eval_time: 10m
    alertname: AppErrorBudgetFastBurn
    exp_alerts: []
# No 5xx series at all. Availability must read 1, not vanish: the "absent is not zero" guard.
- interval: 30s
  input_series:
  - series: 'traefik_service_requests_total{cluster="dev-01", exported_service="ggp-app-8080@kubernetes", code="200"}'
    values: '0+3000x40'
  promql_expr_test:
  - expr: slo:app_availability:ratio_rate5m
    eval_time: 10m
    exp_samples:
    - labels: 'slo:app_availability:ratio_rate5m{cluster="dev-01"}'
      value: 1
EOF

yq '.spec' infrastructure/monitoring-hub-crs/resources/app-slo.prometheusrule.yaml > /tmp/app-slo.rules.yaml
cp tests/app-slo.test.yaml /tmp/
tar -C /tmp -c app-slo.rules.yaml app-slo.test.yaml \
  | docker run --rm -i --entrypoint sh docker.io/prom/prometheus:v3.5.0 \
      -c 'cd /tmp && tar x && promtool test rules app-slo.test.yaml'
# →   SUCCESS
```

Three verdicts in that file: 20 errors in every 100 requests pages (`severity=critical`, `cluster=prod-01`, both annotations rendered), 5 in 100 does not, and a service with no 5xx series at all reads availability 1 rather than nothing, which is the absent-is-not-zero guard under test. The `values` notation is `start+step x count`: `0+2400x40` is a counter growing by 2400 every 30s, 80 requests a second, for twenty minutes. The tar over stdin is the same no-mount posture as the check above, carrying two files instead of one. A test that cannot fail proves nothing, so break it once, then put it back:

```sh
sed -i 's/0+150x40/0+510x40/' tests/app-slo.test.yaml   # 15 in 100: past the 14.4% threshold
cp tests/app-slo.test.yaml /tmp/ && tar -C /tmp -c app-slo.rules.yaml app-slo.test.yaml \
  | docker run --rm -i --entrypoint sh docker.io/prom/prometheus:v3.5.0 \
      -c 'cd /tmp && tar x && promtool test rules app-slo.test.yaml'
# →   FAILED: ... exp:[], got:[ ... alertname="AppErrorBudgetFastBurn" ...
sed -i 's/0+510x40/0+150x40/' tests/app-slo.test.yaml   # and back
```

The test lives beside the rules it guards, outside any kustomize tree so nothing ever tries to apply it:

```sh
git add tests
./scripts/pr-open test/12/slo-rules "test(monitoring-crs): unit tests for the SLO rules and the burn alert" <<'EOF'
## What is moving
tests/app-slo.test.yaml: promtool unit tests for the SLO recording rules and AppErrorBudgetFastBurn.

## Why now
The rules are policy, and a policy nobody can test is a hope. Three verdicts pinned: 20% pages, 5% does not, no 5xx reads 1.

## Evidence
promtool test rules SUCCESS against the rules derived from the CR; a 15% mutation fails as it should.

## If it is wrong
Revert this merge; the rules are untouched either way.

Refs: #12
EOF
```

Read it; when the diff is what the body claims:

```sh
gh pr checks --watch --fail-fast \
&& gh pr merge --merge --delete-branch \
&& git switch main \
&& git pull
```

**Why the gate doesn't just read `slo:app_availability:ratio_rate5m`.** The recording rules are *instantaneous*: a 5-minute moving picture, right for dashboards and alerts. A promotion gate asks a different question: *did this rung hold up across its whole soak window?* So `slo-gate` integrates counters over the window you pass it (`increase(...[10m])`), which is arithmetically not the same as sampling a 5-minute ratio at one instant: the average of a ratio isn't the ratio of the totals. Same SLI, different question, and only the target is shared.

Give the rule a minute before you query it: prometheus-operator regenerates the rule files, the config-reloader reloads them, and the group evaluates once, up to about a minute after the reconcile. `slo-gate` waits for exactly this, so a "not recorded" complaint that survives 60s is a real problem (usually the `release` label) rather than impatience.

SLIs need traffic to measure: an idle service has no availability figure, only silence. So from here to the end of the stage you need a **second terminal running a probe, continuously**. Open one now, start the loop below, and *leave it alone until stage 09 is finished*: every gate, watch and drill that follows reads the traffic it generates, and a gap in the probe shows up later as a mysterious dip you'll waste time diagnosing. (Ctrl-C only at the very end of step 9.)

```sh
curl -s -X PUT -d 'slo probe' http://localhost:8081/notes/slo
while true; do curl -s -o /dev/null http://localhost:8081/notes/slo; sleep 0.5; done
```

Gate on the recording rules resolving, per cluster (the hub answers from the host over the kind docker network):

```sh
kubectl --context kind-ggp-local-01 -n monitoring port-forward svc/kube-prometheus-stack-prometheus 19090:9090 >/dev/null 2>&1 &
PF=$!   # capture the PID: job numbers (%1) break on re-runs and in scripts
until curl -s -o /dev/null http://localhost:19090/-/ready; do sleep 1; done

# one helper, three questions - PromQL does the arithmetic so the shell does not
slo() { curl -s "http://localhost:19090/api/v1/query" --data-urlencode "query=$1" \
        | yq -p=json -r '.data.result[] | ((.metric.cluster // "(hub)") + " " + .value[1])'; }

printf 'SLO target      %.2f%%\n' "$(slo 'slo:app_availability:target * 100' | awk '{print $2}')"
slo '100 * slo:app_availability:ratio_rate5m' | awk '{printf "availability    %-9s %8.3f%%\n", $1, $2}'
slo '1000 * slo:app_latency_p95:5m'           | awk '{printf "p95 latency     %-9s %8.1f ms\n", $1, $2}'
kill $PF
```

The expected shape is a small status board rather than a wall of JSON:

```
SLO target      99.00%
availability    dev-01     100.000%
p95 latency     dev-01         95.2 ms
```

Two things about that output are worth noticing. **Only clusters with traffic appear**: your probe drives `dev-01`, so the platform and prod clusters are correctly absent rather than showing `NaN` (both indicator rules carry the `requests > 0` guard for exactly this). And **the arithmetic happens in PromQL, not in the shell**: asking Prometheus for `100 * ratio` and `1000 * p95` means the query returns numbers already in the units you want to read, so the shell only has to align columns. A raw `.data.result` dump is fine for debugging, but a gate a human is supposed to *read* deserves units and a header.

> Port-forward, not the hub's NodePort: a NodePort on a kind node answers *other containers*, which is how the spokes remote-write, but not necessarily the host. Under rootless podman the container network isn't routable from the host at all, so the node-IP form works for some readers and silently hangs for others. `port-forward` goes through the API server and works for everyone.

### 9. Gate the ladder on the error budget

The promotion contract so far: prod follows dev's **green context**, convergence evidence. This step adds the second signature: **performance evidence.** `scripts/slo-gate <cluster> [window]` asks the hub whether a rung *met its SLO over its soak window*: availability against target, p95 latency, no burning alerts, and (deliberately) **no traffic is a FAIL**. Absence of evidence is not health, and a rung that saw no requests has proven nothing worth promoting.

```sh
./scripts/slo-gate dev-01 10m
```

From here on the ladder's rule is: **a change climbs when the rung below converged *and* its error budget survived the soak.** The Act III checkpoint's promotion drill runs this gate before the prod PR. Note the window semantics: the gate looks *backward*, so a recent incident keeps blocking until it ages out of the window. That's not friction, that *is* the soak.

**The gate also refuses a candidate it hasn't measured.** Two merges in quick succession are the trap the window alone misses: the first lands, starts hurting, and the second's gate run still passes, because a 10-minute window that sampled 90 seconds of the new code was mostly certifying its healthy predecessor. The evidence is real; it's about the wrong revision. So the gate opens with two questions about the candidate, in order. *Arrival*: is the revision the rung applied the one git says `main` is? Between a merge and the end of its rollout the rung is still running the predecessor, and a gate run then would certify the old code with a long residency and a straight face; so it asks the cluster what it applied and git what you asked for, and refuses while they differ. *Residency*: when did that revision first appear in `gotk_resource_info`? Arrival is a metric sample, exactly like detection, and a candidate younger than `SLO_MIN_SOAK` is a FAIL for the same reason no traffic is: absence of evidence is not health. If you ran the gate straight after merging step 8's test PR, you have already seen one of these lines refuse - that's the mechanism working, not a fault; wait it out and re-run. The default is `2m`, deliberately only "long enough for evidence to exist at all" (one reconcile plus a rate-window edge), because this walkthrough merges every few minutes and a full-window soak would refuse every honest gate in it. A production ladder sets the tunable to the window itself - `SLO_MIN_SOAK=10m ./scripts/slo-gate dev-01 10m` - so the evidence always covers the candidate. One honest wrinkle: the revision is the applied *source* revision, so an unrelated merge to main also resets the clock. Over-strict, and truthfully so: the bits on the rung did change.

**The gate certifies a revision; the promotion moves a tag.** Those are two names for what ought to be one thing, and nothing in the machinery checks that they agree. `slo-gate` answers "did the code dev applied at `main`'s revision hold its budget"; the promote PR moves prod's pin to an image tag. Promote the previous build by hand, or let a second build land on dev between the gate and the merge and then promote "what dev runs now" without re-running it, and prod receives an artifact that was never measured behind a green gate. What ties the two today is convention: the version token the commit grammar puts in `pin(app-dev): app V` and `promote(app-prod): app V`, and the `promote` skill reading the tag off dev's overlay in the same breath as it runs the gate, never taking one as an argument. That is a join by naming, and it holds exactly as long as every promotion goes through it. The production shape makes the verdict travel with the artifact instead: the gate names the image digest it certified, from the pod dev was running and not from the overlay, and prod's admission refuses any digest that carries no such verdict. [Stage 14](../act-4/stage-14.md) closes the first half: from there a pin carries the image digest, the promotion copies the digest dev's pod is running, and the policy gate refuses a tag-only pin on any rung, so the artifact prod receives is the one the gate measured, by construction. Stage 30 adds the second half, signatures on those digests and admission that verifies them. Until stage 14, read every promote PR with one question in mind: is this the tag dev proved?

**What about security signals: CVEs, signatures, SBOMs?** A third evidence class exists, and it's deliberately *not* wired into this gate, because it works on different clocks. Per-change security gates run at **entry** (the app repo's CI refusing an image that fails the scan) and at **admission** (the cluster refusing an unsigned image), before and below the promotion ladder, not on it. And most CVE signal arrives **asynchronously**: a scanner verdict lands against an image that was scanned clean, promoted on both signatures, and is green right now, which makes it a *remediation loop* (find every affected stamp, patch through the channels), not a promotion window. Stage 30 builds all three on the rails this stage just proved: the scan gate, admission enforcement, and the SBOM-driven CVE drill. Until then, read the two-signature contract as what it is: convergence + performance, with provenance still owed.

Now the drill this whole arc exists for: **a bad release that every existing gate waves through.** Ship a plausible config change to dev that breaks the app's storage access (a wrong-but-well-formed connection string, patched straight into the container env, exactly the shape of a real botched release):

```sh
cat > apps/overlays/dev/patches/app.deployment.patch.yaml <<'EOF'
- op: replace
  path: /spec/template/spec/containers/0/env/0
  value:
    name: STORAGE_CONNECTION_STRING
    value: "DefaultEndpointsProtocol=http;AccountName=devstoreaccount1;AccountKey=Tm90QVJlYWxLZXlKdXN0VmFsaWRCYXNlNjQ=;BlobEndpoint=http://azurite:10000/devstoreaccount1;"
- op: add
  path: /spec/template/metadata/annotations
  value:
    platform.example.com/managed-by: kustomize
EOF
git add apps/overlays/dev
./scripts/pr-open feat/12/dev-storage-config "feat(app-dev): storage config change" <<'EOF'
## What is moving
Dev's storage connection string, to an account key that is valid base64 and wrong.

## Why now
Stage 09 drill: a change that converges green and fails the service - the SLO must refuse promotion.

## Evidence
None - the point is that every convergence signal will stay green.

## If it is wrong
It is wrong by design; the next PR reverts it.

Refs: #12
EOF
```

Read it; when the diff is what the body claims:

```sh
gh pr checks --watch --fail-fast \
&& gh pr merge --merge --delete-branch \
&& git switch main \
&& git pull
flux reconcile kustomization app-dev --with-source --context kind-ggp-dev-01
```

Note the subject: `feat(app-dev): storage config change`. It is honest, it parses, and it is completely innocent: no `break(...)`, no hint. That is deliberate and it is the lesson: **a plausible commit message is not evidence.** The [commit convention](../appendices/commit-convention.md) makes a change *queryable*, not *truthful*: it tells you what the author claimed the change was. What it actually did is a question only the SLO can answer, which is why the next few minutes matter.

Watch every existing signal call it good, then watch the SLO call it what it is:

First, the three signals that will lie to you. Run these as soon as the rollout lands:

```sh
flux get kustomizations --context kind-ggp-dev-01
printf 'liveness   GET /healthz     %s\n' "$(curl -s http://localhost:8081/healthz)"
printf 'real work  GET /notes/slo   HTTP %s\n' "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8081/notes/slo)"
```

```
NAME            REVISION           SUSPENDED  READY  MESSAGE
app-dev         main@sha1:f9f6c16f False      True   Applied revision: main@sha1:f9f6c16f
...
liveness   GET /healthz     {"status":"ok"}
real work  GET /notes/slo   HTTP 500
```

Sit with those three lines: stamp Ready, status green, health check passing. **Convergence said yes** while every real request fails, because `/healthz` never asks the question users ask.

**Now the part that needs patience, and it is the lesson, not an inconvenience.** Do *not* run the gate yet: SLIs are `rate()` windows over five minutes, so a service that just started failing still looks mostly healthy. The window is full of the successes it served a minute ago. Watch the indicator actually move:

```sh
./scripts/slo-watch dev-01
```

Expect roughly this, and read the clock as much as the numbers:

| Elapsed after the break | What you see |
|---|---|
| ~0–30s | availability still near 100%: the 5m window is dominated by healthy history |
| ~1 min | availability visibly falling (~80%) as failures accumulate |
| ~2–3 min | `ALERT` flips to **FIRING**: the 5m error ratio has been over 14.4% for the rule's `for: 2m` |
| ~5 min | availability bottoms out near 0%: the whole window is now failures |

Ctrl-C the watch once the alert is firing, then ask the gate:

```sh
./scripts/slo-gate dev-01 10m
```

**FAIL**: availability under target, and the burn alert firing. That's the promotion refused: not because someone noticed, but because the evidence says so. (Run it too early and it *passes*, which is not a bug: it's the same window arithmetic, and it's why a soak has a length.)

Now restore, and watch the second half of the lesson: recovery is not instant either.

```sh
./scripts/pr-revert "slo-gate refused the promotion; restore dev and watch the window recover."
```

Read it; when the diff is what the body claims:

```sh
gh pr checks --watch --fail-fast \
&& gh pr merge --merge --delete-branch \
&& git switch main \
&& git pull
flux reconcile kustomization app-dev --with-source --context kind-ggp-dev-01
```

```sh
./scripts/slo-watch dev-01
```

The pod is healthy again within seconds, and the SLI is *not*. It climbs as the bad minutes roll out of the 5-minute window: 60%, 75%, 90%. The alert clears only when the ratio falls back under threshold. Give it about five minutes to return to 100%. Then compare two windows, which is the closing point of the whole stage:

```sh
./scripts/slo-gate dev-01 10m   # still FAIL - the 10-minute window still contains the incident
./scripts/slo-gate dev-01 2m    # PASS - the recovered service, judged on post-fix evidence alone
```

Both verdicts are correct, and that is the idea. The gate isn't a health check, it's **soak evidence over a window**: the fix converged in seconds, but the *right* to promote returns only when the window you chose is clean. Choosing that window is a real decision: short enough to ship, long enough to mean something.

Keep the traffic loop running a little longer: two of the checks below read the SLIs it feeds, and they are its last customers.

## Stop & measure

- [ ] `scripts/checkpoint-09` reports all PASS, exit 0. The bullets below are the live half unpacked:

```sh
./scripts/checkpoint-09
```

- [ ] Prometheus on the hub knows all three clusters, and `slo:app_availability:ratio_rate5m` resolves for every cluster with traffic in the window - dev-01, while your probe runs. The hub's own row prints as `(hub)`: its local scrapes carry no cluster label, because externalLabels apply on egress (step 8 said why). During step 9's drill this ratio showed dev-01 near zero **while every convergence signal stayed green**. Say that sentence out loud, it's the stage's thesis:

```sh
kubectl --context kind-ggp-local-01 -n monitoring port-forward svc/kube-prometheus-stack-prometheus 19090:9090 >/dev/null 2>&1 &
PF=$!   # capture the PID: job numbers (%1) break on re-runs and in scripts
until curl -s -o /dev/null http://localhost:19090/-/ready; do sleep 1; done

# step 8's helper again: cluster label and value, the hub's unlabeled scrapes named
slo() { curl -s "http://localhost:19090/api/v1/query" --data-urlencode "query=$1" \
        | yq -p=json -r '.data.result[] | ((.metric.cluster // "(hub)") + " " + .value[1])'; }

echo "clusters the hub sees:"
slo 'count by (cluster) (up)'                 | awk '{printf "  %-9s %4d targets up\n", $1, $2}'
echo "availability, clusters with traffic in the last 5m:"
slo '100 * slo:app_availability:ratio_rate5m' | awk '{printf "  %-9s %8.3f%%\n", $1, $2}'

kill $PF   # stop the port-forward when done
```

The expected shape, three rows then one:

```
clusters the hub sees:
  dev-01      20 targets up
  (hub)       22 targets up
  prod-01     20 targets up
availability, clusters with traffic in the last 5m:
  dev-01     100.000%
```

A missing cluster row is remote write failing (troubleshooting below); a missing availability row means no traffic reached that cluster in the window - if dev-01's is absent, your probe stopped.

- [ ] The SLO gate agrees with the ratio it reads:

```sh
# passes on a clean window - it failed during step 9's drill
./scripts/slo-gate dev-01 10m
```

Now stop the traffic loop (Ctrl-C in its terminal); the checks above were its last customers.

- [ ] The Grafana Flux dashboard shows every stamp Ready across the fleet, and showed `app-prod` red during the drill.

Tag the boundary ([using the course §5](../using-the-course.md#5-tags-at-every-boundary)):

```sh
git tag stage-09 \
&& git push origin stage-09 \
&& gh issue close 12 --comment "stage-09 tagged"
```

## Audit artifacts produced

- **Metrics with a cluster label are the fleet's flight recorder**: "was prod healthy at 14:02" is a range query, not a recollection. Retention is the honest caveat: metrics age out (hub retention default, spokes 2h); statuses on commits remain the durable per-change record. Telemetry and evidence are different artifacts; the platform now has both.
- The `monitoring` stamps, variants, and cluster-facts are all in git: the observability stack itself has provenance, pins, and a promotion path.
- **The SLO is a reviewed artifact**: `app-slo.prometheusrule.yaml`'s git history is the record of what the platform promised users, who changed the promise, and when. And every promotion now carries a second, queryable justification alongside the PR and the statuses: the gate's window over the rung below's SLIs.

## AI enhancement

**How.** Two skills apply here. `fleet-triage` runs the ladder at fleet scale: given the red row from the dashboard (`gotk_resource_info{name,cluster}`), it names the binding and the context, walks the layers, and reads `detect-time`'s timeline beside the status sequence, so "since when" comes from artifacts. `promote` uses step 9's `slo-gate` as the second signature from now on, and refuses a promotion on no traffic. Call `fleet-triage` with the red row's `name` and `cluster` labels; `promote` with the stamp and the target rung, as at stage 07.

**Why.** At twelve stamps the judgment is which red is a failure and which is the dependency cascade, and whether a green is about the revision the cluster applied. That is reading order and discrimination, not a new query.

**Where.** Step 6 (the fleet drill): break by PR, watch the dashboard, then ask `fleet-triage` with the row's identifiers and compare. Step 9: the next promotion goes through `promote`.

**Verify.** The skill's layer and reason match `flux events`; its "since when" matches `detect-time`; it never suggests a `kubectl` fix or a suspend; `promote` stops on `slo-gate` FAIL and quotes the gate.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `monitoring` stamp red: substitution failure | `cluster-facts` ConfigMap missing on that cluster | Step 2 loops over all three. Check it landed and the root kustomization includes it |
| `curl` to the hub's NodePort hangs or returns nothing from your terminal | Container-network NodePorts aren't reachable from the host under rootless podman (and aren't guaranteed under docker either) | Use `kubectl port-forward` for anything host-side, as the gates and `scripts/slo-gate` do; the NodePort exists for the *spokes*, which reach it container-to-container |
| `kill: %1: no such job`, or a query returns data you can't explain | A port-forward from an earlier run is still holding the port. The new one dies on bind, the readiness loop passes against the *old* forward, and there is no job to kill | `pgrep -af 'port-forward'`, kill the strays, re-run. The blocks capture `PF=$!` for this reason, but a forward leaked by an earlier crash outlives the shell that made it |
| The hub's own metrics have an empty `cluster` label (`local-01` never appears) | Expected: `externalLabels` apply to data a Prometheus *sends*, not to what it stores locally, and the hub scrapes itself | Nothing to fix here; a production hub scrapes nothing locally (pure aggregator) and every cluster runs an agent. Note `slo-gate local-01` has no data by the same token |
| No `cluster=dev-01` series on the hub | Remote write can't reach the hub | Test the route the spokes use, container to container: `docker exec ggp-dev-01-control-plane curl -s http://ggp-local-01-control-plane:30090/-/ready`. If the name doesn't resolve, pin the IP via `scripts/refresh-hub-address` (step 2's fallback); if it answers, read the spoke's Prometheus logs for the refusal |
| A spoke's series are patchy, or some kinds never arrive (the sources table short a cluster); the spoke logs `non-recoverable error` on remote write and the hub logs `Out of order sample from remote write` | Two writers to one series: the spoke evaluates the chart's recording rules as well as the hub, and whichever copy arrives second is refused with its whole batch | `defaultRules.create: false` on the agent variant (step 4). Spokes ship raw samples; the hub is the only evaluator |
| HelmRelease timeout on first install | The stack is a heavy pull | `timeout: 10m` is set for exactly this; check `kubectl -n monitoring get pods` for progress before assuming failure |
| `gh pr merge`: `the base branch policy prohibits the merge` | The check has not reported yet; the ruleset refuses the merge until it does | Run `gh pr checks --watch --fail-fast` first, as every merge block from step 5 on does |
| `gh pr checks`: `no checks reported on the '<branch>' branch` | The workflow run has not registered yet (it can take seconds after `pr-open`) | Wait a few seconds and rerun the block |
| kube-state-metrics crashloops | customResourceState config vs chart version drift | `kubectl -n monitoring logs deploy/kube-prometheus-stack-kube-state-metrics`. Field paths in the config are chart-version sensitive; fix the config, it's one values block |
| **Flux dashboard renders but every panel is empty** | The commonest cause is no `gotk_resource_info` at all. Check first: `count(gotk_resource_info)` on the hub | Walk the chain in order: (a) kube-state-metrics logs showing `cannot list resource "customresourcedefinitions"` means CRS was wired by hand instead of via `customResourceState.enabled`, the switch that grants that RBAC (step 3); (b) series exist but panels are empty ⇒ the config omits `exported_namespace`; (c) the state panels work but reconcile-duration panels don't ⇒ the PodMonitor is missing or unlabeled |
| A ServiceMonitor/PodMonitor exists but its target never appears in Prometheus | It isn't labeled `release: kube-prometheus-stack`. The operator's selectors are label-scoped, and a non-matching monitor is ignored, not rejected | Add the label. There is no error to find: this failure is silent and green, exactly like stage 04's Alert allowlist |
| A failing stamp shows `Unknown` far more than `Not Ready` | Each retry restarts the health check: Unknown for the `--health-check-timeout` (3m), Ready=False for the `retryInterval` (30s), repeat. The dashboard's `Not Ready` count reads only `ready="False"` | Read the table, not the count: a row out of Ready across several refreshes is failing, whichever colour it wears. `ready!="True"` in a query; `flux events` for the reason |
| Several stamps go red together on every commit, then clear | `DependencyNotReady`: Flux marks a dependent Ready=**False** (not Unknown) while the stamp it `dependsOn` reconciles the new revision, so ordering, working correctly, looks exactly like failure | Nothing to fix. Tell them apart by duration: the cascade clears in one retry (~30s), a real failure doesn't. Alert with `for:` ≥ 2m; read the reason from `flux events`, since `gotk_resource_info` carries no reason label (add one to `customResourceState` if your panels need to filter on it, at the usual cardinality price) |
| Dashboard empty but Prometheus has data | Sidecar didn't pick up the ConfigMap | The `grafana_dashboard: "1"` label is the contract. Confirm it survived the generator |
| Two Prometheus instances fighting over rule CRDs | Both hub and agent charts install prometheus-operator CRDs | Expected on kind at this scale; if webhook conflicts bite, disable `crds` on the agent release and note it as a variant divergence |
| No `traefik_service_*` series on the hub | ServiceMonitor selector doesn't match the metrics Service's labels, or the metrics Service never rendered | `kubectl -n traefik get svc --show-labels`. The chart's metrics service must exist (step 7's values line) and carry `app.kubernetes.io/name: traefik` |
| SLI queries return nothing despite scraping | Wrong label: Traefik's `service` label arrives as `exported_service` after scrape relabeling | Step 7's note: all `slo:*` rules use `exported_service` |
| `slo-gate` FAILs with "no traffic evidence" | Nothing is exercising the service, or the probe loop stopped | That's the gate working: a rung with no requests has proven nothing; restart step 8's loop |
| `slo-gate` FAILs with "candidate applied on dev-01 - the rung is running X, main is Y" right after a merge | The stamp has not applied your merge yet: the source interval, then the rollout under `wait: true` (a new image tag pulls before the pod is Ready) | The gate working: anything it measured now would be about the predecessor. `flux get kustomizations --context kind-ggp-dev-01` until `app-dev` names main's sha, then re-run; `flux reconcile kustomization flux-system --with-source` skips the interval |
| `slo-gate` FAILs with "candidate soaked NNs of the 2m required" right after a merge | Residency enforcement: the rung's revision is younger than the evidence window, so the window mostly measured its predecessor | Also the gate working - the two-quick-merges trap, caught. Wait out `SLO_MIN_SOAK` (default `2m`) and re-run; `SLO_MIN_SOAK=30s` for a what-if; a production ladder sets it to the full window |
| Fast-burn alert never fires during the drill | The rule selector label is missing, or the `for: 2m` hasn't elapsed under sustained errors | `release: kube-prometheus-stack` on the PrometheusRule is the operator's contract; keep the traffic loop running |
| `slo-gate` still red after the fix converged | Expected: the incident hasn't aged out of the gate's window | Window semantics are the lesson: soak evidence, not a live health check; re-run with a shorter window to judge post-fix traffic only |

## What you learned, and what's next

The loop's outcome layer now scales, and it learned the difference between its two questions. Statuses and `gotk_resource_info` answer "did this change land, is the machinery healthy"; SLIs answer "is the *service* keeping its promise". The drill proved they can disagree: a rollout that converged green while failing every request, caught only by the error budget, blocked from prod only by the gate. Promotion now requires both signatures: convergence (green context) and performance (a clean SLO window on the rung below). Variants + named cluster facts did the configuration work without a single conditional; the SLO itself is a reviewed file with a history. That completes Act III, *you'd know when it breaks*: ordering, standards and observability with teeth, on top of Act II's ladder and secrets. Stage 10 turns the history the fleet has been recording since stage 03 into the four numbers, and then the act checkpoint exercises it all end to end and takes the act's numbers.

---

**Next:** [10 - The four numbers (DORA, per cluster and per tenant)](stage-10.md)