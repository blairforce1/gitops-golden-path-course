# 0011. Filters run from pinned images; operators install natively

- **Status:** accepted
- **Date:** 2026-08-11
- **Deciders:** blairforce1, with Claude Code
- **Supersedes:** none

## Context

"Works locally, fails in CI" is almost always a version difference in a checking tool. A repo that lists tool versions in a README relies on every contributor and every runner reading it. Some tools are pure functions over files or stdin; others hold credentials, talk to a cluster, manage local machine state, or are SDKs, and those cannot sensibly run in a throwaway container.

## Decision

A tool that is a pure function over files or stdin with no credentials, cluster access or local state (kubeconform, conftest, trivy, yamllint, kustofmt, git-cliff) runs as a container with a pinned tag; the pin lives in the command and CI runs the identical image. A tool that holds credentials (gh), talks to the cluster (kubectl, flux), manages local state (kind, podman), writes files constantly (kustomize) or is an SDK installs natively, at the version its master dictates ([0010](0010-one-master-per-tool-kubectl-never-renders.md)). Borderline constant-use filters (yq) go native for ergonomics. The command idiom is `docker run --rm -v "$PWD:/work:ro,z" <image>@<tag>`, and where an image runs as a non-root user the portable form is piping through stdin and letting the host write.

## Considered options

- **Everything native, versions in a README.** Environment parity as an aspiration.
- **Everything in containers.** kubectl and flux need kubeconfigs and credentials; kind manages the container runtime itself; the friction outweighs the parity.
- **A dev-container or toolbox image.** Solves the workstation, not CI, unless CI also runs it; and it hides which tool is pinned to which master.

## Consequences

- Easier: for every containerised check, the local paste block, the hook and the CI job run the same bytes; environment parity is a property.
- Harder: podman-as-docker and rootless runtimes need the `:z` label and the stdin idiom; container UIDs cannot write into a bind mount that the host owns.
- Follow-up: the toolbox appendix lists every tool with its install class.

## Where it is taught or enforced

Rule 4.2; stage 00; every gate from stage 02 on follows it; `appendices/toolbox.md`; using-the-course §6 (the command idiom).
