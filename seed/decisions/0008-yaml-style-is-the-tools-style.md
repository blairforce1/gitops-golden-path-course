# 0008. YAML style is the tool's style, and the tool writes the file

- **Status:** accepted
- **Date:** 2026-08-20
- **Deciders:** blairforce1, with Claude Code
- **Supersedes:** none

## Context

Half the YAML in a config repo is written or rewritten by kustomize and flux, in their own emitted style: two-space maps, sequence items not indented under their key, block style throughout. Any other house style fights the tools forever, and reformatting noise hides real diffs. Hand-authored flow style (`{a: b}`, `[x, y]`) creeps in from examples and violates the convention silently. `kustomize cfg fmt` was removed in kustomize v5, and yq, the obvious edit tool, re-indents every sequence in a file it touches. Editor settings cannot express sequence indentation.

## Decision

All YAML follows kustomize's emitted style. Flow style is banned in authored YAML except for genuinely empty collections (`emptyDir: {}`) and where flow is a tool's own syntax, called out where it occurs. The tool writes the file: `kustomize create`/`edit` for inventories, `flux create <kind> --export` for stamps, sources, Alerts and Providers; whole-file writes only for content the CLI cannot express, each stating its reason. yq is quarantined to scalar and map edits on sequence-free files. The formatter is kustofmt, a thin wrapper over kustomize's own kyaml library, run as a pinned container: `style-gate` checks, `style-fix` rewrites, yamllint is the backstop for what formatting cannot express. Inline comments get one space; aligned comment columns are not built, because the formatter collapses them.

## Considered options

- **google/yamlfmt.** Converts flow arrays and reproduces kustomize's sequence style, but has no flow-map normalisation (most real violations were maps), cannot preserve a leading `---` per file, and has no sops awareness.
- **yamllint alone.** Encodes the whole convention as configuration (`braces`/`brackets: forbid: non-empty` is the flow ban) and reports; it cannot fix. Kept as the backstop.
- **Round-tripping resources through `kustomize build`.** Works for Kubernetes resources and is byte-identical; does not cover workflows and configs, which is what the formatter is for.
- **A different house style.** Fights every tool-written file.

## Consequences

- Easier: the house style is a byte comparison against what kyaml emits, not a description; `.yamllint.yaml` at the root is the convention as one file read by terminal, hooks, CI and editors.
- Harder: sops-encrypted files are lint-exempt for a hard reason (the MAC covers plaintext structure), and tool-owned trees (`flux-system/`) are excluded by the caller, because kustofmt has no ignore config by design.
- Harder: two CLI traps have to be taught: `flux create kustomization --health-check-timeout` versus the bare `--timeout`, and `kustomize create` refusing to overwrite.
- Follow-up: kustofmt is its own public repository and is consumed like any pinned filter ([0011](0011-filters-from-images-operators-installed.md)).

## Where it is taught or enforced

Rules 3.4 and 3.5; stated at stage 02; the gate and the hooks arrive at stage 11; `scripts/style-gate`, `scripts/style-fix`, `.yamllint.yaml`.
