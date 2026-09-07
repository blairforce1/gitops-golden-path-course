# Stage 06 - Secrets

[← 05 - Helm via Flux](stage-05.md) · [Walkthrough index](../README.md)

> **Where you are:** the config repo root, on `main`, kubectl context `kind-ggp-local-01`. **Starting state:** stage 05's end state. Ingress live, `checkpoint-05` passing.

**Goal:** secrets encrypted in git with SOPS + age under **class-scoped keys**, decrypted only inside the cluster; the stage-04 token IOU paid; `secrets/` established as the debt register it's designed to be ([rule 3.2](../rules.md#32-folder-convention-everything-has-a-place)). The secret under encryption first is Azurite's `devstoreaccount1` connection string. Publicly documented, zero-risk, and that's the point: **encrypting a secret everyone knows proves the workflow is the protection**, separate from the value being protected.

Mainline alternatives, positioned honestly: **sealed-secrets** encrypts *to a cluster* (the controller's key is the root; cluster gone = ciphertexts orphaned, the wrong shape for our rebuild-not-repair posture); **external-secrets** doesn't store secrets at all, it fetches them from a manager: the right end state, and exactly what returns in stage 31 with Key Vault. SOPS + age is the local-friendly mainline because it needs no external service and keeps the git-is-truth property.

One honest taxonomy before any commands: **secrets divide into dissolvable and irreducible.** Cloud-resource credentials are dissolvable: a federation handshake replaces them outright, and stages 31–35 do exactly that. Third-party keys are irreducible: SaaS API keys, SMTP passwords, payment-provider keys, and this course's own github-status-token, because GitHub offers no federation for posting commit statuses. Nothing magics those away; the question is how to hold them well, and the ladder is this stage now (encrypted in git), referenced-not-stored in stage 31 (an ExternalSecret pointing at a vault: git holds the pointer, the value never lands in a clone; whether the pointer names a *version* decides if rotation stays a reviewed diff or becomes invisible, which the [clone-leak appendix](../appendices/repo-leak-posture.md#where-the-irreducible-secrets-should-live) argues out). Carry one sharp edge from day one: **git history retains every old ciphertext**, so rotating a secret means *revoking* the old value at the provider, never just committing a new one. Anyone holding a leaked age key reads your history, not your tip. ([Stage 17, key rotation](../act-5/stage-17.md) exists because of exactly this, and the [assume the clone leaks](../appendices/repo-leak-posture.md) appendix draws the wider conclusion: a clone cannot be revoked, so rotation is a schedule, not an incident response.)

## Steps

### 1. Tools and class keys

Two tools, one job each. **sops** (Secrets OPerationS; Mozilla originally, now a CNCF project under `getsops`) is a *structure-aware* file encryptor: it encrypts the **values** in a YAML/JSON/env file and leaves the keys readable, so an encrypted Secret still looks like a Secret: reviewable shape, diffable structure, greppable names. It appends a `sops:` metadata block recording who can decrypt it and an integrity MAC. It does no key management of its own; it delegates that to a backend (age here; PGP, AWS/GCP KMS, or Azure Key Vault in other setups; the stage-31 move is swapping this backend, not the workflow). **age** is a modern file-encryption tool built as the deliberately-boring replacement for PGP: tiny X25519 keypairs, no keyservers, no web of trust, no config. A public key is one short `age1...` string you can paste into a file, a private key is one line on disk.

Composed, they work like this: for each file, sops generates a random *data key*, encrypts the values with it (AES256-GCM), then wraps that data key to every age recipient listed for the file's path. The wrapped copies ride in the `sops:` block. That mechanism is why everything later in this stage works the way it does: anyone can encrypt (wrapping needs only *public* keys), adding or removing a reader means re-wrapping the data key (`sops updatekeys`), and `encrypted_regex` can leave `kind:`/`metadata:` plaintext because encryption is per-value, not per-file.

sops and age install natively (they hold key material, not container-filter candidates), and they install **pinned**: kustomize-controller decrypts what your sops encrypts, using the sops and age libraries embedded in its own go.mod, so those are the authorities, per the render rule. Cross-version sops history is real (the 3.8 MAC-computation change broke older decryptors), and upstream sops runs ahead of the controller's library, so an unpinned "latest" writes ciphertext ahead of the fleet's decryptor. Don't guess either version: the gate derives both from the controller's go.mod (and it's part of `./scripts/check` from now on):

```sh
./scripts/check-sops-flux-parity    # the "embeds" line names the derived sops and age versions
```

Set the two versions from the gate's output, then install. No package manager here. A package manager can't install a pinned version, but a release binary can, and both tools are single static binaries, so one block covers Linux and macOS:

```sh
SOPS_V=3.11.0    # yours: from the gate's derived truth, not from memory
AGE_V=1.2.1      # ditto
os=$(uname -s | tr '[:upper:]' '[:lower:]')
arch=$(uname -m | sed 's/x86_64/amd64/; s/aarch64/arm64/')
mkdir -p ~/.local/bin
curl -sSLo ~/.local/bin/sops \
  "https://github.com/getsops/sops/releases/download/v${SOPS_V}/sops-v${SOPS_V}.${os}.${arch}"
chmod +x ~/.local/bin/sops
curl -sSL "https://github.com/FiloSottile/age/releases/download/v${AGE_V}/age-v${AGE_V}-${os}-${arch}.tar.gz" \
  | tar -xz -C ~/.local/bin --strip-components=1 age/age age/age-keygen
```

And now the repo starts *recording* pins. **`clusters/versions.yaml` is born here**: the render rule's ledger, one line per tool whose authority is a dependency graph rather than "latest". kustomize and helm have been installed at derived versions since stage 00, but nothing in git said so; sops and age join as they arrive. The block below derives every value from the binaries the gates just proved correct, so the file records truth instead of repeating a guess:

```sh
mkdir -p clusters
cat > clusters/versions.yaml <<EOF
# Render-tool pins (rule 4.1): one authority per tool, derived, never guessed.
# kustomize: kustomize-controller's EFFECTIVE library (a go.mod replace wins
#   over the require line) - local renders must equal cluster renders.
# helm: helm-controller's embedded helm library IS the CLI version, digit for digit.
# sops/age: kustomize-controller's decryptor must decrypt what these encrypt.
# After any flux bump the check-*-flux-parity gates re-derive all four and
# prescribe the pin updates. Stage 07 adds the Kubernetes ladder to this file.
kustomize: "$(kustomize version | grep -o '[0-9][0-9.]*' | head -1)"
helm: "$(helm version --template '{{.Version}}' | tr -d v)"
sops: "$SOPS_V"
age: "$AGE_V"
EOF
./scripts/check-sops-flux-parity    # six PASS lines now: derived, pinned and installed agree
```

Three keys, one per **cluster class**, the scoping decided in the fleet design: a DR move within a class needs no re-encryption, and a cluster holds exactly the class keys for the stamps it hosts (*stamps*: the Flux `Kustomization` CRs applying git paths to the cluster, stage 03's coinage). Private keys live outside git, in one place:

```sh
mkdir -p ~/.config/gitops-golden-path/age
for class in platform dev prod; do
  [ -f ~/.config/gitops-golden-path/age/$class.agekey ] || \
    age-keygen -o ~/.config/gitops-golden-path/age/$class.agekey
done
```

**Team boundary, stated now, at the point of creation, because it trips people later:** what you just made is a *single-operator* key model, three class private keys on one workstation. The split of what that breaks is non-obvious, so learn it precisely. Teammates can **encrypt new secrets with zero key exchange**: `.sops.yaml` recipients are *public* keys and they're in git, so adding a secret works from any fresh clone on day one. What funnels through this one machine is everything else: **reading or editing existing ciphertext, bootstrapping or rebuilding a cluster** (the sops-age root Secret is filled from these files; DR-as-rebuild silently depends on this laptop surviving), **and rotation**. That's bus factor 1 with no offboarding story. The team-grade fix that needs no cloud is **per-principal recipients**: each path rule lists the class *cluster* key plus each authorised human's personal key, `sops updatekeys` re-wraps ciphertext when the roster changes, no private key is ever shared, and offboarding is remove-recipient-then-rotate, rehearsed at stage 18. The endgame is stage 31, where key custody moves to Key Vault (sops speaks `azure_kv` natively) and rotation/audit go server-side. Either way, one rule survives every model: **the root key needs a home that outlives a laptop**, a team vault or password-manager entry, named before DR asks.

### 2. `.sops.yaml` - the encryption policy, in git

`.sops.yaml` is the **encryption policy, versioned like everything else**: an ordered list of `creation_rules`, each binding a `path_regex` to the recipients whose keys can decrypt files created under that path. First matching rule wins, so *where a secret lives decides who can read it*. This is the class split made cryptographic, not just organisational: platform, dev and prod ciphertext each wrap to their own class key, which buys two things. **Blast radius**: a leaked dev key opens dev's secrets and nothing else; prod stays sealed. **Permission as policy**: decrypt rights are a recipient list in a reviewed file, so in the per-principal model (`stage 18`) granting a team decrypt on dev-but-not-prod is a one-line diff on the dev rule, and the PR that grants it is the audit record:

```sh
P=$(age-keygen -y ~/.config/gitops-golden-path/age/platform.agekey)
D=$(age-keygen -y ~/.config/gitops-golden-path/age/dev.agekey)
R=$(age-keygen -y ~/.config/gitops-golden-path/age/prod.agekey)

cat > .sops.yaml <<EOF
creation_rules:
- path_regex: clusters/platform/.*
  encrypted_regex: ^(data|stringData)$
  age: $P
- path_regex: clusters/dev/.*|apps/overlays/dev/.*
  encrypted_regex: ^(data|stringData)$
  age: $D
- path_regex: clusters/prod/.*|apps/overlays/prod/.*
  encrypted_regex: ^(data|stringData)$
  age: $R
EOF
```

The second half of each rule, `encrypted_regex`, scopes encryption *within* the file: only fields matching `^(data|stringData)$`, a Secret's payload, are ciphered, while `kind`, `metadata` and names stay readable, so encrypted files still diff, grep and review like YAML (and `kustomize create --autodetect` still parses them). One consequence to respect: the sops MAC covers the *whole* file, plaintext fields included. So never hand-edit even the readable parts of an encrypted file (a sed over `metadata`, a hand-fixed namespace); the cluster rejects it as tampering at decrypt time. Encrypted files change through `sops edit`/`sops set`, or by regenerating and re-encrypting.

### 3. The cluster's root key - the debt, consolidated

Each cluster gets one imperative secret: its age identities. `local-01` hosts platform-class stamps *and* the `app-dev` stamp (dev class), so it holds both keys:

```sh
cat ~/.config/gitops-golden-path/age/platform.agekey \
    ~/.config/gitops-golden-path/age/dev.agekey \
    > ~/.config/gitops-golden-path/age/local-01.agekey
kubectl -n flux-system create secret generic sops-age \
  --from-file=age.agekey=$HOME/.config/gitops-golden-path/age/local-01.agekey
```

Be clear-eyed about what just happened: **the debt didn't vanish, it consolidated.** Before: every secret imperative, recreated by hand per rebuild. After: N secrets encrypted in git, *one* root key outside it per cluster. That root key is the new IOU: smaller, but real; the workload-identity stages exist to drain it. (The full secrets rule is [rule 5.10](../rules.md#510-secrets-the-taxonomy-the-ladder-and-roll-forward): dissolvable vs irreducible, the ladder, roll forward.)

### 4. Pay the stage-04 IOU

The token secret becomes a git-managed, encrypted resource under the cluster's own `secrets/` folder (self-contained kustomization, per the folder convention):

```sh
mkdir -p clusters/platform/local-01/secrets
kubectl create secret generic github-status-token \
  --namespace flux-system \
  --from-literal=token=$(gh auth token) \
  --dry-run=client -o yaml > clusters/platform/local-01/secrets/github-status-token.secret.yaml
sops encrypt --in-place clusters/platform/local-01/secrets/github-status-token.secret.yaml

(cd clusters/platform/local-01/secrets && kustomize create --autodetect)
```

Open the encrypted file: values are `ENC[AES256_GCM,...]`, structure intact, plus a `sops:` metadata block naming the age recipient. That file is safe in git: the review surface is the *shape*, the workflow is the protection.

A new stamp reconciles the folder, with **decryption declared on the stamp**. Decryption is the consuming Kustomization's property, never a global:

```sh
# --health-check-timeout writes the CR's spec.timeout; bare --timeout is the CLI's own operation timeout
flux create kustomization cluster-secrets \
  --source=GitRepository/flux-system \
  --path="./clusters/platform/local-01/secrets" \
  --prune --wait --health-check-timeout=2m --interval=5m \
  --decryption-provider=sops --decryption-secret=sops-age \
  --export > clusters/platform/local-01/resources/cluster-secrets.kustomization.yaml
```

Read what it wrote. The flags are the day-2 vocabulary (`--decryption-provider`/`--decryption-secret` is how every future encrypted path gets wired), and the file shows where they landed: a `decryption:` block on the stamp's spec.

Same commit, same lesson as stage 05: **the new stamp goes on an Alert's allowlist now, not later.** A `cluster-secrets` failure is a *decryption* failure, a wrong key or a mis-scoped `.sops.yaml` rule, and exactly the event that must never be silent-and-green:

```sh
flux create alert cluster-secrets-status \
  --provider-ref=github-status \
  --event-source="Kustomization/cluster-secrets" --event-severity=info \
  --export > clusters/platform/local-01/resources/cluster-secrets-status.alert.yaml
```

**Now the gotcha that makes this stage's structure load-bearing.** The bootstrap stamp (`flux-system`) reconciles `./clusters/platform/local-01` with a *generated* kustomization, which recurses **everything**, including the new `secrets/` folder. The flux-system stamp has no decryption (rightly; it's tool-managed), so it would try to apply ciphertext and go red. The fix is the general rule: **a path holding encrypted files must only be reconciled by a stamp that declares decryption**. So the cluster root goes explicit, and `secrets/` is deliberately *not* on its list:

```sh
(cd clusters/platform/local-01/resources && kustomize create --autodetect)
(cd clusters/platform/local-01 && kustomize create --resources flux-system,resources)
```

> `resources/` gains its own `kustomization.yaml` so the root can include it as one entry; from now on, a new stamp file means `kustomize edit add resource` in that folder. Explicit beats generated the moment a folder holds something not everyone may read.

### 5. The app's secret moves out of plaintext

The connection string currently sits as a plaintext literal in `apps/base/config/`, flagged as debt since stage 02. It becomes an encrypted Secret **per overlay** (secrets are class-scoped, so they can't live in the class-agnostic base):

```sh
for env in dev prod; do
  mkdir -p apps/overlays/$env/secrets
  kubectl create secret generic app-secrets \
    --namespace ggp \
    --from-literal=STORAGE_CONNECTION_STRING='DefaultEndpointsProtocol=http;AccountName=devstoreaccount1;AccountKey=Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==;BlobEndpoint=http://azurite:10000/devstoreaccount1;' \
    --dry-run=client -o yaml > apps/overlays/$env/secrets/app-secrets.secret.yaml
  sops encrypt --in-place apps/overlays/$env/secrets/app-secrets.secret.yaml
  (cd apps/overlays/$env/secrets && kustomize create --autodetect)
  (cd apps/overlays/$env && kustomize edit add resource secrets)
done
```

Why a committed encrypted *resource* and not a `secretGenerator` fed encrypted inputs? Flux supports the generator route (the controller decrypts generator input files too), but it breaks the render rule. In the cluster the pipeline is **decrypt → build → apply**, so the generator's name-suffix hash is computed over *plaintext*; locally, `kustomize build` knows nothing about sops and would hash the *ciphertext*. The generated names diverge, and local render ≠ cluster render, the exact property the whole toolchain is pinned to protect. A plain encrypted resource keeps the renders structurally identical everywhere, differing only in the `data:` values, which is also what lets checkpoints and CI validate shape and blast radius **with no decryption key anywhere in CI**, and lets a rendered diff show *that* a secret changed without showing the value. The honest trade: generator-hashed secrets get rollout-on-change for free (new hash → new name → Deployment re-rolls); a plain resource updates in place, and running pods keep their old value until something restarts them. Know that when you rotate. [Stage 19, Reloader](../act-5/stage-19.md) closes exactly this gap: **stakater/Reloader**, installed by HelmRelease like any third-party dependency (the stage-05 pattern), watches annotated workloads and rolls them when a referenced Secret or ConfigMap changes. Rollout-on-change recovered without sacrificing render parity, and the opt-in lives in git as an annotation.

Point the deployment at the Secret, and retire the config generator whose only literal just moved. Written whole, the stage-02 way: a `yq` edit re-emits the whole file in yq's own list style, and this PR's diff should show a five-line `env` change, not a reformat:

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
        - containerPort: 8080
        env:
        - name: STORAGE_CONNECTION_STRING
          valueFrom:
            secretKeyRef:
              name: app-secrets
              key: STORAGE_CONNECTION_STRING
EOF

(cd apps/base && kustomize edit remove resource config/)
git rm -r apps/base/config
```

And the `app-dev` stamp learns to decrypt (it now renders an encrypted path). This file is safe for `yq`: flux generated it, it holds no lists, and path assignments write block style:

```sh
yq -i '.spec.decryption.provider = "sops" | .spec.decryption.secretRef.name = "sops-age"' \
  clusters/platform/local-01/resources/app-dev.kustomization.yaml
```

### 6. Commit, converge, and burn the imperative secret

```sh
git add .sops.yaml clusters/versions.yaml clusters/platform/local-01 apps
./scripts/pr-open feat/8/sops "feat(secrets): SOPS and age with class-scoped keys; stage-04 IOU paid" <<'EOF'
## What is moving
.sops.yaml with one age recipient per class; clusters/versions.yaml born with the four render-tool pins; the status token and the app's connection string as ciphertext under secrets/; a cluster-secrets stamp on local-01; app-dev learns to decrypt.

## Why now
The stage-04 IOU: a token that lived only in the cluster now lives in git, encrypted, and git restores it.

## Evidence
checkpoint-06 will pass only if every file under secrets/ is ciphertext; the diff shows no plaintext values.

## If it is wrong
Revert this merge and recreate the imperative secret - rotate the token if the ciphertext was ever wrong.

Refs: #8
EOF
```

Read it; when the diff is what the body claims:

```sh
gh pr merge --merge --delete-branch \
&& git switch main \
&& git pull
flux reconcile kustomization flux-system --with-source
flux reconcile kustomization cluster-secrets
flux reconcile kustomization app-dev
```

Gate. Both stamps green before the deletion below:

```sh
kubectl -n flux-system get kustomization cluster-secrets app-dev
```

Now the proof the debt is paid. Delete the hand-made secret and watch git put it back:

```sh
kubectl -n flux-system delete secret github-status-token
flux reconcile kustomization cluster-secrets
# → cluster-secrets: Flux owns it now
kubectl -n flux-system get secret github-status-token \
  -o jsonpath='{.metadata.labels.kustomize\.toolkit\.fluxcd\.io/name}{"\n"}'
```

## Stop & measure

```sh
./scripts/checkpoint-06
```

Live check: the blob round-trip from checkpoint-03 still passes. The app is now fed its connection string through an encrypted-at-rest, decrypted-in-cluster path, and nothing about the app changed.

Tag the boundary ([using the course §5](../using-the-course.md#5-tags-at-every-boundary)):

```sh
git tag stage-06 \
&& git push origin stage-06 \
&& gh issue close 8 --comment "stage-06 tagged"
```

## Audit artifacts produced

- **The debt register is countable:** `find . -path '*/secrets/*' -name '*.secret.yaml'` lists every stored secret in the platform. The workload-identity stages drain it two ways: dissolvable (cloud) secrets go to zero, irreducible third-party keys convert to ExternalSecret pointers with no value in them. Progress is a folder listing either way.
- Every secret has a **git history under encryption**: who added it, when it rotated (a rotation is a visible re-encrypted diff), reviewed like any other change.
- `.sops.yaml` is the **access policy as code**: which class can read which path, diffable and reviewed.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `no matching creation rules found` on encrypt | File path doesn't match any `path_regex` (check from repo root) | Run sops from the repo root; fix the regex, not the file location |
| Kustomization red: `failed to decrypt` | `sops-age` secret missing, or missing the class key for this path | Recreate the root-key secret (step 3) with every class key this cluster's stamps need |
| Decrypt fails only after editing a secret | File edited without sops; MAC now stale | Always edit via `sops edit <file>`; it re-encrypts and re-MACs on save |
| Secret decrypts but app gets old value | Secret changed, pod didn't restart (env vars are read at start) | This stage accepts it (restart the pod); generators-with-hash return as the fix when config churn justifies it |
| After a rebuild everything is red on decryption | The root key is the surviving IOU; a fresh cluster doesn't have it | Step 3 is now part of cold start; the act checkpoint and `act-1-drill` gain this step |

## What you learned, and what's next

Secrets are now git citizens: encrypted at rest, path-scoped to class keys, decrypted only by the consuming stamp, with rotation and review inheriting the ordinary PR loop. The residual debt is named and singular: one root key per cluster. Stage 07 hands the `dev`/`prod` keys their real clusters. The cold-start recipe changed with this stage, and the tooling knows: `act-1-drill` pays whichever IOU the repo's era calls for (root key post-06, raw token before), and `checkpoint-04` reads Flux's ownership labels to report the token as imperative or git-restored.

**What this stage owes, and where it is paid.** What you built here is a *workflow*; operating it is Act V, on a fleet of three class keys where the strain actually shows: [stage 17, key rotation](../act-5/stage-17.md) (zero-downtime rotation, and why git history makes it two rotations), [stage 18, team keys](../act-5/stage-18.md) (grant and offboard as one-line reviewed diffs), [stage 19, Reloader](../act-5/stage-19.md) (rotated values actually reaching pods), [stage 20, roll forward](../act-5/stage-20.md) (why reverting a secret succeeds and breaks everything anyway). Stages 17 and 18 are the local practice that Key Vault custody (stage 31) later absorbs. Rehearse while the age keys still carry the load; stage 19 gets *more* necessary after 31, not less.

---

**Next:** [07 - Environments & promotion](stage-07.md)
