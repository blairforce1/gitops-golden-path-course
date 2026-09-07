# The toolbox - every tool, its job, and how it installs

[← walkthrough index](../README.md)

Stage 00 verifies this toolchain and the gates keep it pinned; this page says what each tool *is*, how the course uses it, and why it installs the way it does. Two rules decide the install column: [rule 4.1](../rules.md#41-the-render-rule-one-authority-per-tool-and-kubectl-never-renders) pins each tool to exactly one authority, and [rule 4.2](../rules.md#42-tool-provisioning-filters-from-images-operators-installed) splits the population: pure filters run as pinned containers, everything that holds credentials, talks to a cluster, or manages local state installs natively.

---

## Installed natively (stage 00)

| Tool | What it is | How the course uses it | Pin |
|---|---|---|---|
| **kind** | Kubernetes clusters run as containers on your machine | Every cluster through Act VI, and the Act VII stages; `scripts/cluster-up` / `cluster-down` wrap it. After a reboot under podman the node containers stay stopped with their state intact: `podman start` them by name (`kind get clusters` lists the clusters, `<cluster>-control-plane` is the container) rather than rebuilding | Node image per class, from `clusters/versions.yaml` |
| **kubectl** | The Kubernetes API client | Reads and applies only. It never renders: `kubectl apply -k` is banned ([rule 4.1](../rules.md#41-the-render-rule-one-authority-per-tool-and-kubectl-never-renders)) | The dev rung of the version ladder |
| **flux** | The GitOps CLI for the Flux controllers | Generates the controller manifests, authors sources and stamps (`flux create … --export`), reports health (`flux get`, `flux check`) | The AKS `microsoft.flux` release ([rule 4.3](../rules.md#43-the-version-policy-follow-the-authority-at-the-pace-kubernetes-sets)) |
| **kustomize** | The overlay renderer: builds complete YAML from a base plus overlays | The canonical renderer (`kustomize build`), and the author of its own files (`kustomize create` / `edit`, [rule 3.5](../rules.md#35-the-tool-writes-the-file)) | kustomize-controller's *effective* library |
| **helm** | The chart renderer and package tool | Third-party platform components arrive as Flux `HelmRelease`s from stage 05; the local CLI is for inspection | helm-controller's embedded library |
| **gh** | GitHub's CLI | Repos, rulesets, PRs, issues, statuses, API calls; it holds your credentials, so it is never a container | Unpinned |
| **az** | Azure's CLI | Acts VII–VIII only; there is nothing to install before the subscription wall. Subscriptions, identities, federated credentials, Key Vault, AKS. Two kinds of add-on ride inside it: **Bicep** (`az bicep install`, az manages the binary) for stage 33's cluster, and the **`k8s-extension`** and **`k8s-configuration`** CLI extensions (`az extension add`) for stage 34's managed Flux. Like gh, it holds your credentials, so it is never a container | Unpinned |
| **yq** | A YAML filter and pretty-printer | Queries and displays rendered output everywhere. As an *editor* it is quarantined: it re-indents sequences ([rule 3.5](../rules.md#35-the-tool-writes-the-file)) | Unpinned; native for ergonomics (the borderline case in [rule 4.2](../rules.md#42-tool-provisioning-filters-from-images-operators-installed)) |
| **docker** (or podman wearing its name) | The container runtime | Runs kind's nodes and every pinned filter container. Podman users install a real shim once, never an alias ([using the course §6](../using-the-course.md#6-command-idiom-docker-fully-qualified-images-roz)) | Unpinned |
| **kustofmt** | The house formatter: byte-compares YAML against kustomize's own emitted style ([rule 3.4](../rules.md#34-yaml-style-adopt-the-tools-style-everywhere)) | `style-gate` checks (`-l`), `style-fix` rewrites (`-w`), and the pre-commit hook runs it on every commit from stage 11: a writer and an every-commit tool, so the operator side of [rule 4.2](../rules.md#42-tool-provisioning-filters-from-images-operators-installed) wins and it installs, at stage 11 | The kyaml the kustomize pin ships (`check-kustofmt-kustomize-parity`) |
| **sops** + **age** | Encrypts secrets committed to git, and the keys it encrypts to | Secrets from stage 06 on. They hold key material, so they install natively, as pinned release binaries | kustomize-controller's embedded decryption libraries |
| **dotnet** | The .NET SDK | Optional: only needed if you want to build or run the prop app locally. The app repo's CI builds and publishes the image the course actually deploys | Unpinned |

Do not guess any pin. `./scripts/check` derives them all from the dependency graph and, for anything wrong, FAILs with the exact install one-liner.

## Run as pinned containers (never installed)

Pure functions over files or stdin: no credentials, no cluster access, no local state. The pin lives in the command itself and CI runs the identical image, so "works locally, fails in CI" is structurally impossible for these checks.

| Tool | What it is | First use |
|---|---|---|
| **kubeconform** | Validates rendered YAML against the Kubernetes API schemas | Stage 02 (`checkpoint-02`) |
| **conftest** | Policy assertions (OPA/Rego) over rendered YAML | Stage 08 (`policy-gate`) |
| **yamllint** | The YAML lint backstop for what formatting cannot express | Stage 11 (`style-gate`) |
| **trivy** | Scans images and SBOMs for vulnerabilities | Stage 30 |

## Optional extras: a UI over the cluster

The course never depends on any of these; every verification is a script or a paste block. But if driving a cluster purely from the CLI feels like a lot, a client with a UI is a fine companion, and the standard labels stage 02 applies (`app.kubernetes.io/*`) are exactly what such tools group and display by:

- **k9s**: a terminal UI; stage 07 shows it driving a multi-cluster fleet.
- **[Lens](https://lenshq.io/download/)**: a desktop Kubernetes IDE.
- **[Headlamp](https://headlamp.dev/)**: a lighter open-source web UI, from the Kubernetes SIG.

All three are read-mostly clients feeding your eyeballs, not the cluster, so they stay unpinned and unmanaged by `versions.yaml`: the render rule has no claim on them.

---

[← walkthrough index](../README.md)
