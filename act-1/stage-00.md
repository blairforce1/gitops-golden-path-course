# Stage 00 - Prerequisites & the app repo

[Walkthrough index](../README.md)

> **Where you are:** the directory that will hold both repos side by side. Step 1 creates and enters the **config repo** (`gitops-golden-path`), seeded from this course; step 3 creates the **app repo** (`gitops-golden-path-app`) beside it, where the rest of this stage happens. You arrive with `git` and an authenticated `gh` (`gh auth status` says logged in): step 1 uses both before step 2 has verified anything, and every other tool waits for step 2.

> **Before anything:** read [the GitOps rules](../rules.md). They are the set of disciplines this course adopts from the first commit, each with its reason: repository configuration, the commit and PR conventions, file and folder naming, the tool rules. Step 1 below applies the day-zero ones; the rest are enforced by the scripts it seeds.

**Goal:** tooling verified, and the demo app published as a public image that pulls anonymously. The config repo never builds the app.

> Convention: the app is a **prop**. It arrives whole from a template, and nothing in it is a lesson. Manifests in later stages are **lesson files** and get written by hand. See the [course README](../README.md).

## Steps

### 1. The config repo - create it, and seed it from the course

Two repos, side by side, for the whole course: the **config repo** says what runs where, the **app repo** says what the app is. The config repo starts as a standard GitOps repo and stays one; nothing course-shaped ever lands in it. Before anything else it gets one thing from this course: the tooling. The gates, checkpoints and drills under `scripts/` are copied in now rather than pasted stage by stage, because a real platform repo *keeps* its acceptance tests, and because stage 01 already needs `cluster-up`.

```sh
COURSE="$(pwd)"        # run this from the root of your clone of the course
cd ..                  # the config repo goes beside it
gh repo create "$(gh api user --jq .login)/gitops-golden-path" --private --clone \
  --description "GitOps config repo: Flux, Kustomize, SOPS, a promotion ladder, fleet observability - built stage by stage" \
  || gh repo clone "$(gh api user --jq .login)/gitops-golden-path"    # already exists? clone it instead
cd gitops-golden-path
cp -r "$COURSE/seed/." .   # the whole seed - a literal image of this repo at day zero, dotfiles included
chmod +x scripts/*         # belt and braces: a zip download loses the execute bits
git add -A
git commit -m "chore(scripts): seed the gates, checkpoints, drills, skills, decisions and templates from the course"
git push -u origin main
```

Then the day-zero configuration. Every `gh api` call in this stage names the repo as `{owner}/{repo}`, placeholders gh fills from the repository you are standing in; from the wrong directory, the merge policy and the ruleset below land on your course clone instead. One line settles where you are:

```sh
# → <owner>/gitops-golden-path - the repo every call below configures
gh repo view --json nameWithOwner --jq .nameWithOwner
```

Now the merge policy ([rule 1.2](../rules.md#12-repository-configuration-the-merge-policy-is-set-before-the-first-pr)) and the two local settings that keep it true on this clone. Set now, before there is a PR for it to matter to, because the first PR that lands under GitHub's default squash-or-merge subject has already rewritten a commit:

```sh
gh api -X PATCH "repos/{owner}/{repo}" \
  -F allow_merge_commit=true -F allow_squash_merge=false -F allow_rebase_merge=false \
  -f merge_commit_title=PR_TITLE -f merge_commit_message=PR_BODY \
  -F delete_branch_on_merge=true -F allow_auto_merge=true \
  --jq '"merge: \(.allow_merge_commit)  squash: \(.allow_squash_merge)  rebase: \(.allow_rebase_merge)  subject: \(.merge_commit_title)  auto: \(.allow_auto_merge)"'
git config --local pull.rebase false        # merges here too
# the vocabulary in your editor; per clone - git will not let a repo set this
git config --local commit.template .gitmessage
```

Then the other half of day zero: protection on `main`, before there is anything on `main` worth protecting ([rule 1.3](../rules.md#13-protection-from-day-zero-nothing-reaches-main-except-a-merged-pr)). The push you just made was the last direct one this repository will ever take. A ruleset, not the older per-branch protection API: rulesets are named, can be amended in place (stage 08 adds a required check, stage 21 adds owners), and their bypass list is explicit. This one has none:

```sh
gh api -X POST "repos/{owner}/{repo}/rulesets" --input - <<'EOF'
{
  "name": "main",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": true,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": true,
        "allowed_merge_methods": ["merge"]
      } }
  ]
}
EOF
# → deletion  non_fast_forward  pull_request
gh api "repos/{owner}/{repo}/rules/branches/main" --jq '.[].type'
# the same, from the seeded helper that later stages amend it with
./scripts/ruleset show
```

Read the one number: **approvals 0**. A team sets 1 here and adds CODEOWNERS (stage 21); this course cannot, because GitHub refuses to let you approve your own PR and there is one of you. What *is* enforced from this second: nothing reaches `main` except a merged PR, nobody can force-push over history a cluster has already reported running, and the merge method is the one the settings above chose. No bypass actors: not you as admin, not the robot stage 14 hires. The course's own tooling honours this too: `flux bootstrap`, which pushes straight to a branch, is replaced at stage 03 by the three files it would have written, landed by PR.

Prove the control exists before you rely on it, with an empty commit that must be refused:

```sh
git commit --allow-empty -m "test(main): a direct push must be refused" && git push
# → remote: ... GH013: Repository rule violations found ... Changes must be made through a pull request
git reset -q --hard origin/main    # the refused commit never existed on the remote; now it never existed here
```

> A `403` naming your plan on the ruleset call instead of `GH013` here means the account is not on Pro: the README's one assumption, and the wrong place to discover it, which is why it is here. And if the push *succeeds*, read that as the result it is: there is no control, and every "refused" in this course is now a choice you make. The README's free-plan box lists the other six places you will notice.

Tags get the same day-zero treatment, with one difference: **creation stays open**. This repo is tagged at every stage and act boundary ([using the course §5](../using-the-course.md#5-tags-at-every-boundary)), and those tags are save points and range markers: the act drills rebuild to them, and later stages read ranges between them. A tag you can move is an audit trail you can rewrite, so a second ruleset blocks update and deletion for every tag while leaving minting free:

```sh
gh api -X POST "repos/{owner}/{repo}/rulesets" --input - <<'EOF'
{
  "name": "tags",
  "target": "tag",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["~ALL"], "exclude": [] } },
  "rules": [
    { "type": "update" },
    { "type": "deletion" },
    { "type": "non_fast_forward" }
  ]
}
EOF
./scripts/ruleset show     # both rulesets: what a merge requires, and that tags are permanent
```

No proof push for this one, deliberately: with deletion blocked, a scratch tag would be permanent. It is the one control in this repo you take on faith until the first time you mistype a tag - and the repair that day is disabling the `tags` ruleset in the repo settings, fixing, re-enabling: a visible bypass, never a force-push. The app repo is untouched; its `v*` tags stay ordinary.

**The backlog.** The course is also a backlog, and from now on it lives in this repo: a milestone per act, an issue per stage and per act checkpoint, seeded now, before the first PR, so the numbers are the same for every reader (`#1` is stage 00, `#9` is stage 07, `#44` is the Act VIII checkpoint) and the walkthrough cites them literally. From stage 02 every PR carries a `Refs: #<issue>` trailer naming the work item it advances ([rule 2.5](../rules.md#25-every-change-has-a-work-item-the-trailer-is-the-reason)); from stage 11 a required check refuses a PR that cites nothing, or cites finished work. The seeder refuses a repo that already has an issue or a PR, because issues and PRs share one number sequence and a stray one would shift every number after it:

```sh
source ./env.sh
# preview first: all 44 work items, from the README's act tables, no API calls
"$COURSE/tools/seed-backlog" --roster
# from the course checkout: prints number → stage as it goes
"$COURSE/tools/seed-backlog" "$GH_OWNER/$CONFIG_REPO"
# day zero, read back as PASS/FAIL - re-run it whenever you doubt the repo
./scripts/check-repo
# your backlog for this act, in walk order; the milestone bar is "where am I"
gh issue list --milestone "Act I - The complete loop" --search "sort:created-asc"
```

One sorting note, portal-side: GitHub lists issues newest-first, which for a seeded backlog means *backwards* - stage 00 at the bottom, the Act VIII checkpoint on top. Seeding in reverse would not fix it: issue numbers are creation order, and `#1` must be stage 00. Sort at the reading end instead; the seeder prints the walk-order link (`sort:created-asc`), worth bookmarking.

`check-repo` is a real platform script, not a course prop. It reads back everything this step configured: merge policy, ruleset, seeds, this clone's settings, the backlog. And it keeps doing so for the life of the repo.

Private is the honest default for a config repo. What visibility does and doesn't buy is stage 21's subject and the [leak-posture appendix](../appendices/repo-leak-posture.md)'s. Note the plain `chore`: tooling, not platform config. The first *config* commit is stage 02's, and that is where the commit convention gets taught. It is also the first PR, so `.github/pull_request_template.md` is already in place for it.

### 2. Verify tooling

```sh
for t in kind kubectl flux kustomize helm gh yq; do command -v $t >/dev/null && echo "ok  $t" || echo "MISSING  $t"; done
kind --version          # 0.31+
gh auth status          # logged in as YOUR account
# the toolchain gate: flux, kustomize, helm, kubectl - each pinned to its one authority;
# every FAIL prescribes its own install one-liner
./scripts/check
```

Any name in that list new to you? [The toolbox appendix](../appendices/toolbox.md) gives every tool a one-line job description, how the course uses it, and why it installs the way it does.


One more piece before installing anything: **the walkthrough contains no account names, yours or anyone's**. Every identity fact (GitHub owner, repo names, image path, app-repo location) derives at runtime from your `gh` login and this repo's git remote, via `env.sh` at the repo root ([using the course §4](../using-the-course.md#4-identity-the-tutorial-names-no-accounts)). Any paste block that needs identity starts with `source ./env.sh`; `gh api` calls use gh's native `{owner}/{repo}` placeholders; scripts derive from the remote themselves. Look at what you'll be sourcing, and note it stores nothing:

```sh
cat env.sh
source ./env.sh
echo "$GH_OWNER / $CONFIG_REPO -> $APP_IMAGE"   # sanity: your identity, derived, not typed
```

Anything MISSING installs from your package manager or the vendor's instructions as usual, **except flux, kustomize, helm, and kubectl**, which are *pinned*, each to exactly one authority (the **render rule**, [rule 4.1](../rules.md#41-the-render-rule-one-authority-per-tool-and-kubectl-never-renders)): flux to the AKS-supported release (the reflex `curl | bash` install grabs latest, which runs *ahead*; see the version policy below); kustomize and helm to the libraries the flux controllers *actually embed*, sometimes pinned **back** by a go.mod `replace` to dodge an upstream regression, so neither "latest" nor flux's own version string is the truth; kubectl to the dev rung of the Kubernetes version ladder (`clusters/versions.yaml`; the pin file is born at stage 06 and the ladder declared at stage 07, so today any current kubectl serves and the ladder gate says SKIP). Don't guess any pin: `./scripts/check` derives them all from the dependency graph and FAILs with the exact install one-liner for anything wrong.

```sh
./scripts/check-flux-aks-parity
# → FAIL  local flux CLI not found or version unparseable
#         install it pinned to the AKS release: curl -s https://fluxcd.io/install.sh | FLUX_VERSION=<aks release> bash
```

Container runtime: **docker, or podman wearing docker's name**. The walkthrough writes `docker` throughout (the majority idiom). Podman users (a fine minority) bridge once and every command pastes unchanged. **Use a shim, not a shell alias**: aliases don't expand in scripts or in tools that exec `docker`. The rest of the container idiom is [using the course §6](../using-the-course.md#6-command-idiom-docker-fully-qualified-images-roz), first exercised at stage 02: fully-qualified image references, `:ro,z` mounts, kill-by-PID.

```sh
# preferred: your distro's podman-docker package (installs a real /usr/bin/docker shim):
sudo dnf install podman-docker        # Fedora; apt install podman-docker on Debian/Ubuntu
# or, package-manager-free - a two-line shim:
printf '#!/bin/sh\nexec podman "$@"\n' | sudo tee /usr/local/bin/docker >/dev/null
sudo chmod +x /usr/local/bin/docker

docker --version                      # → "podman version x.y.z" - the bridge works
```

`scripts/cluster-up` detects docker-that-is-podman and still sets kind's podman provider correctly: kind is the one tool that must know the truth.

**Flux version policy** ([rule 4.3](../rules.md#43-the-version-policy-follow-the-authority-at-the-pace-kubernetes-sets)): the local Flux mirrors the release bundled in AKS's `microsoft.flux` extension. Act VIII's "AKS absorbs what you built by hand" is only honest if local and managed Flux agree, and OSS Flux typically runs a minor ahead of the extension. `./scripts/check-flux-aks-parity` scrapes [Microsoft's release notes](https://learn.microsoft.com/azure/azure-arc/kubernetes/flux-gitops-release-notes) and compares (PASS on same minor line, FAIL on minor drift with the pin command, WARN if the scrape breaks). Re-run it at each stage start; it also runs on a schedule in CI so drift surfaces without anyone remembering to look.

Deliberately **not** in the install list: kubeconform, and later conftest/trivy. Pure filters run as version-pinned containers instead (the tool provisioning rule, [rule 4.2](../rules.md#42-tool-provisioning-filters-from-images-operators-installed)): pinned in the command, identical image in CI. First use: stage 02's schema check.

### 3. Create the public app repo - from the course's template

The app is a **prop**: a deliberately boring .NET API with one Azurite dependency, whose only job is to be deployed. Writing it teaches nothing about GitOps, so you do not write it. The course publishes it as a GitHub template repository, and one command gives you your own copy: your history, your Actions runs, your image, none of the .NET scaffolding on your screen.

```sh
source ./env.sh               # from the config repo root, where env.sh lives
# the app repo goes beside the config repo - derived from env.sh, not assumed from where you stand
cd "$(dirname "$APP_DIR")"
# read it: the directory that holds your gitops-golden-path checkout, and nothing app-shaped yet
pwd
gh repo create "$GH_OWNER/$APP_REPO" --template blairforce1/gitops-golden-path-app-template --public \
  --description "Demo app for gitops-golden-path: a deliberately boring .NET API with one Azurite dependency" --clone
cd "$APP_REPO"
```

> The template lives at a fixed address the way the course's tooling does; everything it generates is owned by *your* account, per [using the course §4](../using-the-course.md#4-identity-the-tutorial-names-no-accounts).

### 4. Read what you received

Nine files. The app itself (`src/App`, a minimal API: `/healthz`, and PUT/GET `/notes/{id}` against a blob container; resist improving it), git hygiene committed rather than assumed (`.gitattributes` forcing LF, because advice about `core.autocrlf` doesn't survive a clone), a two-stage `Dockerfile`, and the one file worth reading closely, `.github/workflows/publish.yaml`:

```sh
cat .github/workflows/publish.yaml
```

What to notice: it fires **only on `v*` tags** - a release is a deliberate act, and an ordinary push builds nothing (a `branches: [main]` trigger here would fire on the template generation itself, because the generated repo's initial commit is a push like any other; also, two triggers matching one commit would build it twice, and two builds of the same commit are two *different* digests wearing different labels); it logs into GHCR with the run's own `GITHUB_TOKEN` (no secret you created); the image name derives from `${{ github.repository }}`, so your copy publishes under your owner with no edit; `docker/metadata-action` gives the one build three labels (`sha-…`, which *is* the commit id; the semver; `latest`, meaning latest release); and it builds `linux/amd64` and `linux/arm64` in one pass. One commit, one run, one digest, three labels: the provenance chain the stop-and-measure walks.

### 5. Publish, tag, and make the package public

Template generation fired no workflow, *because* the trigger is release tags only; the push below fires none either, and exists for its own lesson. Note that it lands **directly on `main`**: the app repo deliberately has no ruleset. The platform's controls belong to the config repo; an app team's own repo makes its own rules. And that freedom is the prop's, not a recommendation: a real app repo deserves the same day-zero protections as the config repo ([rules 1.2](../rules.md#12-repository-configuration-the-merge-policy-is-set-before-the-first-pr) and [1.3](../rules.md#13-protection-from-day-zero-nothing-reaches-main-except-a-merged-pr) are not platform-specific), and its team would set them the same way, on day zero. This one stays bare because everything that ever lands here is course scaffolding: stage 01's throwaway manifests, and the version tags later stages push to give the automation something to notice. The protection lessons happen in the repo where you do the work.

```sh
git commit --allow-empty -m "chore: first publish"
git push
git tag v0.1.0 && git push --tags
```

Note the plain `chore:`. This is the **app repo**, not the platform. The [commit convention](../appendices/commit-convention.md) you adopt in stage 02 has a domain vocabulary (`pin`, `promote`, `bind`, …) that describes a config repo; an ordinary .NET service gets the ordinary types. The grammar describes a platform, and the app is a thing the platform ships.

**Then a portal step - one of the very few in the course, because it cannot be scripted.** In the browser: GitHub → the `gitops-golden-path-app` **package** (not the repo) → Package settings → Danger zone → Change visibility → **Public**. Packages default to private even in public repos, and the packages API has no visibility endpoint, so the portal is the only route; the stop-and-measure below fails until this is done.

Why public at all: every cluster in Acts I-VI pulls this image **anonymously** - kind nodes, no `imagePullSecrets`, no registry credential to mint, mount, rotate or leak while the subject is the GitOps machinery itself. Be clear that this is a *teaching* posture, not the production one. A real platform's images live in a **private** registry and the cluster authenticates to pull with an identity of its own, not a shared token; the registry sits inside the trust boundary, with its own access review. The course pays this debt where it belongs: stage 30 adds the integrity half (the cluster demands signatures and attestations before running anything), and Act VIII hardens the pull side when the fleet moves onto managed clusters and the registry moves with it (stage 34).

## Stop & measure

> Tag mapping: git tag `v0.1.0` → image tag **`0.1.0`** (`type=semver,pattern={{version}}` strips the `v`). Expect **one** Actions run, for the tag push, titled with the tagged commit's message; the tag lives in the run's ref column. The `main` pushes (the generation's initial commit, your `chore: first publish`) fired nothing. In the registry, `0.1.0`, `sha-…` and `latest` are three labels on a single digest.

- [ ] The CI run is green:

```sh
source ./env.sh
gh run list -R "$GH_OWNER/$APP_REPO" --limit 1
```
- [ ] The registry shows what you think it shows:

```sh
cd ../gitops-golden-path   # back to the config repo - stage 01 starts here anyway
source ./env.sh
# via the GitHub API - tags, digest, timestamp per version
# (needs the read:packages scope: grant once with `gh auth refresh -s read:packages`):
gh api /user/packages/container/gitops-golden-path-app/versions \
  --jq '.[] | {tags: .metadata.container.tags, digest: .name, created: .created_at}'
# via the registry itself - what the cluster will see:
docker manifest inspect $APP_IMAGE:0.1.0
```

  Expected: a manifest list with **four** entries: `linux/amd64` and `linux/arm64` (the images), plus two `unknown/unknown` entries annotated `attestation-manifest`. Two anticipated questions:
  - **Where's Windows?** Not needed: the platform list is where the *container runs*, and every cluster here has Linux nodes. Windows readers run Linux images too (Docker Desktop, podman machine and WSL2 all execute in a Linux VM); `os: windows` images only matter for Windows Server node pools, which are out of scope. amd64 + arm64 covers every reader, Intel or Apple silicon.
  - **What are the `unknown/unknown` entries?** BuildKit **provenance attestations** (SLSA build provenance, on by default in `build-push-action` v6), one per architecture, each referencing its image by digest. Supply-chain evidence that came free with the default build; stage 11 formalises trusting it. Keep them.

- [ ] The GitHub portal view agrees. Three routes to the same page:
  - Repo page → **Packages** (right-hand sidebar) → `gitops-golden-path-app`;
  - Your profile → **Packages** tab (lists every package you own);
  - Direct: `github.com/<owner>/gitops-golden-path-app/pkgs/container/gitops-golden-path-app`.

  On the package page verify: the tag list shows `0.1.0`, `latest` and the `sha-…` tag, all on one version; the **OS/Arch** entries for the version show `linux/amd64` and `linux/arm64`; the digest matches what `docker pull` reported; the visibility badge says **Public**; and the package is linked to the source repo (the link appears because the workflow pushed with the repo's `GITHUB_TOKEN`). Visibility lives at Package page → **Package settings** → Danger zone → Change visibility.

- [ ] Anonymous pull works (the load-bearing check: no credentials, fresh-machine semantics):

```sh
source ./env.sh
docker pull $APP_IMAGE:0.1.0
docker run --rm -d --name ggp-smoke -p 8090:8080 \
  -e STORAGE_CONNECTION_STRING=placeholder \
  $APP_IMAGE:0.1.0
# must show ggp-smoke Up - empty means the run failed; read its error before trusting anything below
docker ps --filter name=ggp-smoke --format '{{.Names}}  {{.Status}}'
for i in $(seq 1 20); do curl -sf localhost:8090/healthz && break; sleep 0.5; done; echo
# → {"status":"ok"}
docker stop ggp-smoke    # --rm removes it; port 8090 is free again
```

> Named + detached + readiness loop + explicit stop: a smoke test must not race the app's startup, and must not leave a stray container holding the port. The `docker ps` read-back between run and curl is load-bearing: if the run failed - a squatted port, say - curl still gets an answer from whatever already holds the port, and a smoke test that can pass against the wrong server is worse than none. Host port 8090, not 8080: 8080 is the most-squatted port on a development machine, and from stage 05 this course's own ingress holds it. Ignore the startup `Overriding HTTP_PORTS` warning: the base image defaults the port one way, `ASPNETCORE_URLS` sets it the other; same result.

**Measured outcome:** image pullable anonymously, multi-arch confirmed, pull digest matches the Actions run's build digest (commit → run → digest → registry: the provenance chain, closed by hand; stage 30 automates trusting it); `/healthz` answers without storage (liveness must not depend on the dependency).

- [ ] Close the work item, the first of the forty-four, and the Act I milestone bar moves:

```sh
gh issue close 1 --comment "stage 00 complete"
```

## Audit artifacts produced

- The Actions run is a **build provenance record**: exactly which commit produced which image digest, on which runner, when. Note the digest: stage 30 will sign it, and stage 04 will connect deploys back to commits the same way.
- **SLSA provenance attestations, for free**: BuildKit attached one per architecture (the `unknown/unknown` manifest entries) without being asked to. The registry already carries machine-readable evidence of how each image was built, before we've done anything deliberate about supply chain. First sighting of the course's thesis: auditability comes free, by default; stage 30 only teaches the cluster to *demand* it.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `gh api .../rulesets` → 403 `Upgrade to GitHub Pro or make this repository public` | Free plan, private repo; rulesets are a paid feature there | The README's one assumption: upgrade the account, or accept stage 21's argument and make the config repo public |
| `git push` to `main` succeeds after the ruleset | Ruleset created but `enforcement` is not `active`, or it targets a different ref | `gh api repos/{owner}/{repo}/rulesets`: check `enforcement`; the include must be `~DEFAULT_BRANCH` |
| `pull` → 403/denied | Package visibility still private | Package settings → Change visibility → Public |
| The package is already Public on first publish | A package of this name existed before and was public; a recreated package can arrive with the prior visibility | Nothing to do - verify the badge and move on |
| `manifest unknown` | Tag didn't build (the workflow fires only on `v*` tags) | Check the Actions run for the tag push |
| `gh run list` shows no run after the tag push; `:0.1.0` → `manifest unknown` | The tag never reached the remote, or was pushed from a detached state | Retag and re-push: `git tag -d v0.1.0 && git push origin :refs/tags/v0.1.0 && git tag v0.1.0 && git push --tags` |
| `gh api .../versions` → 403 needs `read:packages` | gh token scope | `gh auth refresh -s read:packages`, or use the package web page; `docker manifest inspect` needs no auth for public packages |
| `curl /healthz` connection refused | App binds 8080 in-container via `ASPNETCORE_URLS` | Confirm `-p 8090:8080` and the env var line in the Dockerfile |
| `curl` returns nothing right after `docker run` | Race: app not listening yet | Use the readiness loop above, never bare `run &` + instant curl |
| `Address already in use` on the host port | Something else holds it: a previous smoke container, another dev server, or a kind fleet from an earlier pass at this course (its ingress binds 8080-8082) | `docker ps` and `ss -ltnp` name the holder; stop it, or change the host half of `-p` |
| `curl` answers but the `docker ps` read-back was empty | The run failed and the answer came from whatever holds the port - the smoke test proved nothing | Fix the port collision first, then re-run the whole block |
| (Windows) scripts fail with `'bash\r': No such file or directory` | CRLF checkout, no `.gitattributes` | Add the `.gitattributes` above, then `git add --renormalize .` and commit |
| `seed-backlog` refuses: already has an issue or PR | Something was created before the seed: a test issue, a PR opened early | Numbers are shared and positional; delete the repo and start step 1 again, or accept that every `#n` in the walkthrough is off by the count |

## What you learned, and what's next

You published a multi-arch image that anyone can pull, and you verified it three ways: API, registry, portal. That closed the provenance chain (commit → run → digest → registry) by hand. The registry even carries SLSA attestations: auditability you got for free, without asking. The app itself taught you nothing, deliberately: it's a prop, and it stays one.

**Next:** run it on a cluster the worst way - raw `kubectl apply` - so that when GitOps machinery arrives you know precisely which pains it exists to remove.

---

**Next:** [01 - Plain manifests (the pain)](stage-01.md)
