# 0007. One resource per file, named `<name>.<kind>.yaml`, in typed folders

- **Status:** accepted
- **Date:** 2026-08-11
- **Deciders:** blairforce1, with Claude Code
- **Supersedes:** none

## Context

A multi-document YAML file has no single name or kind, so it cannot be the address of anything: not a CODEOWNERS line, not a blast-radius row, not the target of an alert. Kubernetes examples default to multi-doc files and free-form names, and repos inherit the habit. Inside a folder, resources, patches, generators and secrets otherwise mix, so the question "where do I attach extra protection" has no structural answer, and the count of stored secrets is an audit rather than an `ls`.

## Decision

Every YAML resource file is `<metadata.name>.<kind>.yaml`, lowercase, dots in names replaced by dashes; patches are `<target>.<kind>.patch.yaml`, replacements `<target>.<kind>.replacement.yaml`. Exempt: `kustomization.yaml` and tool-generated trees. Each thing segregates its files into typed folders that appear when first populated: `resources/`, `patches/`, `replacements/`, `secrets/`, `config/`, `components/` (kustomize `Component` units only). `config/` and `secrets/` are self-contained kustomizations holding their own generators. Patches and replacements are always files, never inline. Arrays are alphabetical wherever order does not matter; a semantic order carries a comment. `secrets/` is a debt register: the folder exists to be emptied, and its endgame is conversion (every remaining file a pointer with a vault home).

## Considered options

- **Multi-document files per component.** Fewer files, no addressability; rejected.
- **Free-form names with a README convention.** Not checkable; the filename stops being the identity the moment one file breaks the pattern.
- **Flat folders.** Findability by grep only; nothing for CODEOWNERS or scanning to attach to.

## Consequences

- Easier: the filename is the resource's identity; blast-radius reports read as resource lists; per-type churn is `git log -- '*/patches/*'`; `find . -path '*/secrets/*'` is the countable secret debt; alert to file is a grep ([0009](0009-identifier-alignment-one-string-seven-homes.md)).
- Easier: generated files come out alphabetical ([0008](0008-yaml-style-is-the-tools-style.md)), so the ordering rule is free wherever the tool writes.
- Harder: more files, and a `kustomize create --autodetect --recursive` habit to keep inventories honest.
- Follow-up: the naming checks live in `checkpoint-02`; a hand-written list that needs a non-alphabetical order must say why.

## Where it is taught or enforced

Rules 3.1, 3.2, 3.3; stage 01 states it, stage 02 restructures to it, stage 06 makes `secrets/` a register, stage 08 introduces `components/`; `scripts/checkpoint-02`.
