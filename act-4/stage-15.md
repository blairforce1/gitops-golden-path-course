# Stage 15 - The event that arrives (push, not poll)

[← 14 - Image automation (the robot on the dev rung)](stage-14.md) · [Walkthrough index](../README.md)

> **Where you are:** the root of the config repo, on `main`. **Starting state:** 14 complete and the fleet live. If it isn't, the previous act's `act-3-drill` rebuilds it from git (git is at HEAD, so everything since comes back with it). **Why here:** it replaces the latency in the mechanism stage 14 built, so doing it first would have nothing to shorten. Assumes image automation is running.

**Goal:** stage 14's robot **polls**. `flux create image repository app --interval=5m` means the cluster asks a registry every five minutes whether anything appeared, and on average the answer arrives two and a half minutes after it was true. That wait is pure latency in your lead time: it is doing no work, gating nothing, and [stage 10](../act-3/stage-10.md) is measuring it.

This stage makes the build **tell** the cluster instead, using a standard the CI tool and the CD tool both already speak: a [CDEvent](https://cdevents.dev/), posted to a Flux `Receiver`, which reconciles the affected resources on arrival.

The architectural sentence to hold on to, because it is the whole design and it is easy to get backwards:

> **Push accelerates; poll guarantees. You keep both.**

The interval stays exactly as it was. A lost event costs you the old latency, not correctness, and that is the only property that makes an event-driven trigger safe to put in front of a reconciler.

One IOU, stated up front the way [rule 5.3](../rules.md#53-the-iou-pattern-do-it-the-wrong-way-loudly) asks: a kind fleet has no address a build can reach, so in this stage *you* play the build and post the event by hand. The cluster half is real and stays; the caller is a stand-in, the robot keeps polling after the stage, and the lead time stage 10 measures does not move until the cluster has a public address, which stage 33 ([Act VIII](../README.md#act-viii---absorption)) gives it.

Terminology reminder: a *stamp* is a Flux `Kustomization` CR.

## Why CDEvents, and not just a webhook

Flux already has `generic` and `generic-hmac` Receiver types: point anything at them and they fire. So the interesting question is why a *specification* is worth the ceremony.

[CDEvents](https://cdevents.dev/) is a CD Foundation spec that puts a shared vocabulary on top of CloudEvents, so a build system and a delivery system that have never heard of each other can still agree on what happened: `dev.cdevents.artifact.published`, `dev.cdevents.change.merged`, `dev.cdevents.service.deployed`. Tekton, Jenkins, Spinnaker and Harbor emit or consume them; Flux **receives** them natively as of the `v1` Receiver API.

The payoff is not this one hop. It is that the same event that reconciles your cluster can also feed a metrics pipeline, an audit store, and somebody else's tool, without any of them parsing your bespoke JSON. A `generic` webhook is a wire between two things you own; a CDEvent is an interface.

Verify Flux's support on your own fleet before trusting a page:

```sh
kubectl --context kind-ggp-local-01 get crd receivers.notification.toolkit.fluxcd.io \
  -o jsonpath='{range .spec.versions[*]}{.name}{": "}{.schema.openAPIV3Schema.properties.spec.properties.type.enum}{"\n"}{end}'
```

```
v1: ["generic","generic-hmac","github","gitlab","bitbucket","harbor","dockerhub","quay","gcr","nexus","acr","cdevents"]
v1beta2: [... no cdevents ...]
```

`cdevents` is in **`v1` only**. If you author against `v1beta2` the field is silently not there.

## Steps

### 1. Measure what you are about to remove

Honest before-and-after, from artifacts, the way every other number in this course is taken. The `ImageRepository` is on the platform cluster because the robot is ([stage 14 step 1](stage-14.md#1-two-more-controllers-and-an-honest-credential-decision)), so that is where the interval lives and where the event must land:

```sh
kubectl --context kind-ggp-local-01 -n flux-system get imagerepository app \
  -o jsonpath='{.spec.interval}{"  last scan: "}{.status.lastScanResult.scanTime}{"\n"}'
```

```text
5m0s  last scan: <RFC 3339 time, within the last five minutes>
```

Whatever that interval says, **half of it is your average wait**, and the whole of it is your worst case. Write both down; steps 5 and 6 compare against them.

### 2. The token, then the Receiver

The Receiver's URL is derived from a secret, so the secret comes first. It is the only credential there is: the CDEvents receiver checks no header and no signature, so the unguessable path *is* the authentication, and whoever holds the token can compute it. It lives in `secrets/` under the [folder convention](../README.md), encrypted like everything since stage 06, and the `cluster-secrets` stamp applies it:

```sh
TOKEN=$(head -c 32 /dev/urandom | base64 | tr -d '=+/')
kubectl create secret generic cdevents-token \
  --namespace flux-system --from-literal=token="$TOKEN" \
  --dry-run=client -o yaml > clusters/platform/local-01/secrets/cdevents-token.secret.yaml
sops encrypt --in-place clusters/platform/local-01/secrets/cdevents-token.secret.yaml
(cd clusters/platform/local-01/secrets && kustomize edit add resource cdevents-token.secret.yaml)
```

Then the event type, read rather than typed. A CDEvent type carries its own version (`dev.cdevents.artifact.published.0.2.0`), the controller parses every payload with a pinned CDEvents SDK, and that SDK knows one version of each type: a payload naming a newer one is refused before any filter is consulted. So the version the Receiver names is the version the controller speaks, and the controller's `go.mod` says which:

```sh
nc=$(kubectl --context kind-ggp-local-01 -n flux-system get deploy notification-controller -o jsonpath='{.spec.template.spec.containers[0].image}'); nc=${nc##*:}
sdk=$(gh api "repos/fluxcd/notification-controller/contents/go.mod?ref=$nc" --jq .content | base64 -d | awk '/cdevents\/sdk-go/ {print $2}')
read -r CDE_SPEC CDE_TYPE < <(gh api "repos/cdevents/spec/contents/conformance/artifact_published.json?ref=$sdk" --jq .content | base64 -d | yq -p=json '(.context.version // .context.specversion) + " " + .context.type')
echo "notification-controller $nc speaks CDEvents $CDE_SPEC: $CDE_TYPE"
```

```text
notification-controller v1.8.4 speaks CDEvents 0.4.1: dev.cdevents.artifact.published.0.2.0
```

```sh
flux create receiver app-artifact-published \
  --type=cdevents \
  --event="$CDE_TYPE" \
  --resource=ImageRepository/app \
  --secret-ref=cdevents-token \
  --namespace=flux-system \
  --export > clusters/platform/local-01/resources/app-artifact-published.receiver.yaml
(cd clusters/platform/local-01/resources && kustomize edit add resource app-artifact-published.receiver.yaml)
```

Three things in that command are decisions, not defaults:

- **`--event` names the type the filter accepts, and the filter reads the request's `Ce-Type` header to decide.** The value you gave, `dev.cdevents.artifact.published.0.2.0`, becomes `.spec.events`; at request time the controller compares that list with the `Ce-Type` header (CloudEvents' binary-mode type header), case-insensitively, and with nothing in the body. The body is parsed and validated by the SDK; the header is what the filter reads. A request without it is refused as `the CDEvent "" is not authorised`, which the caller sees as a 400 with an empty body; the reason lands in the controller's log only. Step 5 sends it.
- **One `--resource`, the `ImageRepository`.** The rest of the chain is already event-driven inside the cluster: the policy re-evaluates when the scan changes, the automation runs when the policy changes (its own interval is the fallback), the PR merges on its checks, and each cluster's `flux-system` source poll picks up `main` within its minute. Naming the `app-dev` stamp here would reconcile it at event time, minutes before the pin exists in git, and change nothing.
- **The Receiver lives on `local-01` only**, beside the `ImageRepository` it pokes: a Receiver reaches resources in its own cluster, and the robot runs on platform. It is still the dev rung's privilege, exactly as stage 14 framed it: a build may accelerate *dev's* scan. Prod is a human PR on dev's evidence, and a Receiver in front of prod would hand the build system the promotion decision.

```sh
git add clusters/platform/local-01
./scripts/pr-open feat/19/cdevents-receiver "feat(local-01): CDEvents receiver accelerates the dev image pin" <<'EOF'
## What is moving
A Receiver on local-01 for the app's artifact-published CDEvent, poking the ImageRepository the robot reads, and the token its path derives from.

## Why now
The registry poll stays as the guarantee; the event removes its latency.

## Evidence
The Receiver names one resource and the event type version the controller's SDK speaks; nothing on dev-01 or prod-01.

## If it is wrong
Revert this merge; the poll carries on.

Refs: #19
EOF
```

Read it; when the diff is what the body claims:

```sh
gh pr checks --watch --fail-fast \
&& gh pr merge --merge --delete-branch \
&& git switch main \
&& git pull
flux reconcile source git flux-system --context kind-ggp-local-01
flux reconcile kustomization cluster-secrets --context kind-ggp-local-01
flux reconcile kustomization flux-system --context kind-ggp-local-01
flux reconcile receiver app-artifact-published --context kind-ggp-local-01
```

The secret before the Receiver, on purpose: a Receiver whose secret has not landed goes not-ready and waits for its own interval, and the last line turns that wait into a second.

### 3. Find the path, then expose it

The Receiver's URL is `/hook/<sha256 of token+name+namespace>`, unguessable by design. The controller reports it once the object is Ready:

```sh
kubectl --context kind-ggp-local-01 -n flux-system get receiver app-artifact-published \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}  {.status.webhookPath}{"\n"}'
```

```text
True  /hook/<64 hex characters>
```

`notification-controller` serves it on the `webhook-receiver` Service. For the drill, a port-forward is enough and keeps the cluster off the internet. It runs in the background of this same terminal, because step 5 stops it by the PID captured here:

```sh
kubectl --context kind-ggp-local-01 -n flux-system port-forward svc/webhook-receiver 9292:80 >/dev/null &
PF=$!   # capture the PID: job numbers (%1) break on re-runs and in scripts
for i in $(seq 1 20); do curl -s -o /dev/null localhost:9292 && break; sleep 0.5; done
```

For a real fleet this is an Ingress on the traefik you installed in [stage 05](../act-2/stage-05.md), and it is **the first thing in this course that accepts unsolicited traffic from outside**. Treat it accordingly: TLS, an ingress rule scoped to the one path rather than the whole Service, and the token rotated like any credential, because the path is all the authentication there is.

### 4. Mint a release and compose its event

The stage-14 release dance, then the event a build would send. Mint first, because the event carries the artifact's digest and the registry must have it before the Receiver is told to look:

```sh
source ./env.sh
cd "$APP_DIR" && git pull
TAG="v0.1.1-run$(date +%Y%m%d%H%M%S)"
git tag "$TAG" && git push origin "$TAG"
echo -n "waiting for the registry to have ${TAG#v} (multi-arch build, ~2-3m) "
until docker manifest inspect $APP_IMAGE:${TAG#v} >/dev/null 2>&1; do printf .; sleep 10; done; echo
cd -
```

The CDEvent is JSON with a `context` and a `subject`; the [spec's conformance example](https://github.com/cdevents/spec/blob/main/conformance/artifact_published.json) at the SDK's version is the authority for the shape, and both version strings come from step 2's derivation:

```sh
digest=$(gh api /user/packages/container/$APP_REPO/versions --jq ".[] | select(.metadata.container.tags[] == \"${TAG#v}\") | .name")
cat > /tmp/cdevent.json <<EOF
{
  "context": {
    "version": "$CDE_SPEC",
    "id": "$(uuidgen)",
    "source": "/github/$GH_OWNER/$APP_REPO/actions",
    "type": "$CDE_TYPE",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  },
  "subject": {
    "id": "pkg:oci/$APP_REPO@$digest?repository_url=$APP_IMAGE",
    "source": "/github/$GH_OWNER/$APP_REPO/actions",
    "type": "artifact",
    "content": {}
  }
}
EOF
yq -p=json -oy '.subject.id' /tmp/cdevent.json
```

```text
pkg:oci/gitops-golden-path-app@sha256:<digest>?repository_url=ghcr.io/<owner>/gitops-golden-path-app
```

The digest is the registry's own record for the tag: a package version's name is the digest of its manifest, and for a multi-arch build that is the index the policy resolves and the kubelet pulls by. Nothing downstream trusts the event's copy of it. The Receiver only triggers a scan, the policy records the digest it resolves from the registry itself, and the two are compared where the policy's line is read.

Note `subject.id` is a [purl](https://github.com/package-url/purl-spec), not a tag: `pkg:oci/…@sha256:…`. That is deliberate in the spec and worth keeping: **a tag says where to look, a digest says what you got**, and an event whose subject is mutable is an event you cannot audit later. The same instinct stage 14 built into every pin.

On a fleet the build can reach, this block is one step at the end of the app repo's publish workflow, after the push: derive the digest, compose, POST with the `Ce-Type` header to the Receiver's URL held as a repository secret. This course posts the same event by hand from the laptop, because a port-forward is not a place GitHub Actions can reach, and that is the only difference.

### 5. The drill: watch the wait disappear

Two terminals. The watch goes in a **new** one, the fleet's own view:

```sh
flux get image repository app --context kind-ggp-local-01 --watch
```

The announce stays in the terminal you have been using since step 2, because it reads `CDE_TYPE` from the derivation, `PF` from the port-forward and `TAG` from the mint, and none of those exist anywhere else. Post, and measure from artifacts rather than the screen: the scan time before, the post, and the scan time moving:

```sh
path=$(kubectl --context kind-ggp-local-01 -n flux-system get receiver app-artifact-published -o jsonpath='{.status.webhookPath}')
before=$(kubectl --context kind-ggp-local-01 -n flux-system get imagerepository app -o jsonpath='{.status.lastScanResult.scanTime}')
t0=$(date +%s)
curl -s -o /dev/null -w 'webhook: HTTP %{http_code}\n' -X POST "http://localhost:9292$path" \
  -H 'Content-Type: application/json' -H "Ce-Type: $CDE_TYPE" --data-binary @/tmp/cdevent.json
until [ "$(kubectl --context kind-ggp-local-01 -n flux-system get imagerepository app -o jsonpath='{.status.lastScanResult.scanTime}')" != "$before" ]; do sleep 1; done
echo "scan fired $(( $(date +%s) - t0 ))s after the event; the interval is $(kubectl --context kind-ggp-local-01 -n flux-system get imagerepository app -o jsonpath='{.spec.interval}')"
```

```text
webhook: HTTP 200
scan fired 2s after the event; the interval is 5m0s
```

Then the chain the scan starts, the one stage 14 built, which needs no event of its own:

```sh
flux get image policy app --context kind-ggp-local-01
until pr=$(gh pr list --author app/github-actions --state all --limit 1 --json number,state,title --jq '.[] | "#\(.number)  \(.state)  \(.title)"' | grep "${TAG#v}"); do printf .; sleep 5; done; echo; echo "$pr"
```

```text
NAME  IMAGE                                       TAG    READY  MESSAGE
app   ghcr.io/<owner>/gitops-golden-path-app      <tag>  True   Latest image tag for … resolved to <tag> with digest sha256:<digest> (previously …)
#<n>  OPEN  pin(app-dev): app <tag>
```

Within a CI run more it merges itself and dev rolls, the stage 14 shape. **Record the number.** The interval you wrote down in step 1 was the old worst case; the seconds the gate printed are the new one. On this fleet that is minutes to seconds, and it is the first latency in the course removed by *architecture* rather than by tuning a number down. That matters, because tuning the interval down costs registry requests forever and this costs nothing when nothing is happening.

While the port-forward is still up, see the refusal you will one day meet, because a type-version mismatch looks like a network problem from the outside and like this from the inside:

```sh
curl -s -o /dev/null -w 'wrong type: HTTP %{http_code}\n' -X POST "http://localhost:9292$path" \
  -H 'Content-Type: application/json' -H "Ce-Type: dev.cdevents.change.merged.0.2.0" --data-binary @/tmp/cdevent.json
kubectl --context kind-ggp-local-01 -n flux-system logs deploy/notification-controller --since=1m | grep -o 'the CDEvent .* is not authorised'
```

```text
wrong type: HTTP 400
the CDEvent \"dev.cdevents.change.merged.0.2.0\" is not authorised
```

Stop the port-forward when you are done. A leaked one is silent and looks exactly like a working one:

```sh
kill $PF
```

### 6. Prove the guarantee still holds

The point of keeping the poll. The webhook is gone (the port-forward you just killed), so the next release announces nothing, and the system must be slower, not broken:

```sh
source ./env.sh
cd "$APP_DIR" && git pull
TAG="v0.1.1-run$(date +%Y%m%d%H%M%S)"
git tag "$TAG" && git push origin "$TAG"
echo -n "waiting for the registry to have ${TAG#v} (multi-arch build, ~2-3m) "
until docker manifest inspect $APP_IMAGE:${TAG#v} >/dev/null 2>&1; do printf .; sleep 10; done; echo
cd -
t0=$(date +%s)
until [ "$(kubectl --context kind-ggp-local-01 -n flux-system get imagepolicy app -o jsonpath='{.status.latestRef.tag}')" = "${TAG#v}" ]; do printf .; sleep 5; done; echo
echo "the poll found ${TAG#v} $(( $(date +%s) - t0 ))s after the registry had it; the interval is $(kubectl --context kind-ggp-local-01 -n flux-system get imagerepository app -o jsonpath='{.spec.interval}')"
```

```text
the poll found <tag> <up to 300>s after the registry had it; the interval is 5m0s
```

The robot's PR follows, with no event behind it:

```sh
until pr=$(gh pr list --author app/github-actions --state all --limit 1 --json number,state,title --jq '.[] | "#\(.number)  \(.state)  \(.title)"' | grep "${TAG#v}"); do printf .; sleep 5; done; echo; echo "$pr"
```

```text
#<n>  OPEN  pin(app-dev): app <tag>
```

The pin still moves, within the interval, exactly as it did before this stage existed. **That is the acceptance test for any event-driven trigger in front of a reconciler**: turn the events off and the system must still converge, just later. If it does not, the events have become a source of truth, and you have rebuilt a push pipeline with extra steps.

## Stop & measure

- [ ] The Receiver is Ready with a path, on the platform cluster and nowhere else:

```sh
kubectl --context kind-ggp-local-01 -n flux-system get receiver app-artifact-published -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}  {.status.webhookPath}{"\n"}'
for c in kind-ggp-dev-01 kind-ggp-prod-01; do printf "%s: " $c; kubectl --context $c -n flux-system get receiver 2>&1; done
```

```text
True  /hook/<64 hex characters>
kind-ggp-dev-01: No resources found in flux-system namespace.
kind-ggp-prod-01: No resources found in flux-system namespace.
```

Prod has none because prod is a human PR on dev's evidence; dev-01 has none because the scan it would accelerate runs on the platform cluster.

- [ ] The interval is unchanged and the event beat it:

```sh
kubectl --context kind-ggp-local-01 -n flux-system get imagerepository app -o jsonpath='{.spec.interval}{"\n"}'
```

`5m0s`, unchanged; and the drill's gate line read `scan fired <single digits>s after the event`.

- [ ] With the webhook unreachable, the poll still moved the pin: step 6's line read a number no larger than the interval, and the robot landed both releases:

```sh
gh pr list --author app/github-actions --state merged --limit 2 --json number,title --jq '.[] | "#\(.number)  \(.title)"'
```

```text
#<n>  pin(app-dev): app <step 6 tag>
#<n>  pin(app-dev): app <step 5 tag>
```

- [ ] A payload with the wrong type was refused, and the refusal is on record:

```sh
kubectl --context kind-ggp-local-01 -n flux-system logs deploy/notification-controller | grep -c 'is not authorised'
```

`1` or more; the line names the type it refused, which is how a version-suffix mismatch is seen rather than guessed.

Tag the boundary ([using the course §5](../using-the-course.md#5-tags-at-every-boundary)):

```sh
git tag stage-15 \
&& git push origin stage-15 \
&& gh issue close 19 --comment "stage-15 tagged"
```

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `cdevents` rejected as an invalid `type` | Object authored against `v1beta2` | The `cdevents` type exists in **`v1` only**; check `apiVersion` on the file |
| 404 from the webhook | Path is derived from the token; the secret changed, or you typed the name | Re-read `.status.webhookPath`; it changes whenever the token does |
| 400 with an empty body | The controller refused the request and logged why: no `Ce-Type` header or one outside `.spec.events` (`is not authorised`), a type version its SDK does not know (`value must be 'dev.cdevents.artifact.published.0.2.0'`), or a malformed payload | `kubectl --context kind-ggp-local-01 -n flux-system logs deploy/notification-controller --since=5m` and read the `unable to validate payload` line; send the header, and take both versions from step 2's derivation |
| 200, scan time unchanged | The Receiver names another resource, or the port-forward is on another cluster | `.spec.resources` on the Receiver reads `ImageRepository/app`; the `--context` on the port-forward, not the current context |
| Receiver not Ready, secret not found | The Receiver reconciled before `cluster-secrets` applied the token | Step 2's four reconciles, in that order |
| It works, then stops after a rebuild | The Receiver is on the cluster; the *token* was cluster-local | It is in `secrets/` and encrypted; a rebuild restores it via `cluster-secrets`, which is why it went in git |
| Scan fired but no robot branch | The tag is not one the policy's filter admits ([stage 14 step 2](stage-14.md#2-what-to-watch-and-what-counts-as-newer)), or the policy had already resolved it | `flux get image policy app --context kind-ggp-local-01` |

## What you learned

**Poll and push answer different questions, and a mature system runs both.** The interval is the guarantee: it converges with no cooperation from anything outside the cluster, which is the property that survives a broken CI system, a rotated token, and a network partition. The event is an accelerant, and its worst failure is a return to the old speed. Any design where a missing event means a missing deployment has quietly turned the reconciler back into a pipeline.

**What this stage leaves owing.** The Receiver, its token and the acceptance test are in git and will not change; the build's call is not, because nothing on GitHub's runners can reach this fleet. Until stage 33 wires the publish workflow to the platform cluster's public address, every release still arrives by the poll, and the seconds you measured in step 5 are a rehearsal, not the fleet's lead time.

**A specification earns its keep at the second consumer.** One webhook between your build and your cluster does not need CDEvents. The moment a metrics store, an audit log, or another team's tool wants the same fact, a shared vocabulary is the difference between one integration and N.

And one gap worth knowing you are standing in: **Flux receives CDEvents but does not emit them.** Its 29 notification `Provider` types include Slack, PagerDuty, Datadog and OpenTelemetry. None of them is CDEvents. So the fleet can be *told* that an artifact was published, but cannot itself tell the world that a service was deployed, which is the event everyone downstream actually wants. That asymmetry is a real, current hole in an otherwise complete story. It is exactly the shape of a small tool: a **stateless translator**, not an operator, because Flux's `Alert` and `Provider` CRs already express which events go where. A `Provider{type: generic}` pointing at it, and it re-publishes Flux's event stream as spec-conformant CDEvents. If you build it, the one trap to avoid is [stage 10](../act-3/stage-10.md)'s: emitting `service.deployed` on every successful reconcile rather than on every revision *change* would report a deployment every interval, and inflate everyone's downstream delivery metrics tenfold.

---

**Next:** [16 - The version ladder climbs](stage-16.md)
