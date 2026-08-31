# 0004. Conventional Commits with a domain vocabulary; the scope is the blast radius

- **Status:** accepted
- **Date:** 2026-08-24
- **Deciders:** blairforce1, with Claude Code
- **Supersedes:** none

## Context

A prose commit subject cannot answer the questions a config repo is asked: what shipped to prod between two revisions, which of those were promotions and which were versions arriving, every policy change this quarter, every access change to prod. Drills that find commits by subject are fragile against prose. And a convention adopted after the first commits exist is a migration or a permanent exception era. Conventional Commits gives the grammar but not the vocabulary: `feat`/`fix` do not describe a pin move, a promotion, a key rotation or a deliberate break, and its `!` marker ("breaks the published API") has no meaning in a repo that publishes none.

## Decision

Every commit is `type(scope): subject` with seven domain types beside the standard set: `pin` (a version arriving at its entry rung), `promote` (a version climbing by PR), `bind` (a stamp pointer), `rotate` (a secret value), `access` (a recipient or reviewer set), `policy` (what is allowed), `break` (deliberate failure injection). **The scope is the blast radius**, drawn from a registry (stamp, cluster, class, tree) and identical to the identifier the alignment rule already puts in the stamp name, namespace, label, metric, alert and CODEOWNERS path. Issue IDs are trailers, never the scope. `!` is redefined as "reverting this commit will not restore the previous state" and requires a `Roll-forward:` trailer. Nine deciding rules make the grammar decidable; the load-bearing one is that the entry rung is per artifact class (images enter at dev, charts and Kubernetes minors at platform), so `pin(platform)` is not a promotion.

## Considered options

- **Plain Conventional Commits.** Grammar without vocabulary; `chore: bump image` cannot be queried as a deployment.
- **Issue keys in the scope.** Collides with blast radius; trailers carry issue IDs without ambiguity.
- **`!` inherited as "breaking change".** Meaningless here and it would make a changelog generator print the subject as its own explanation.
- **Convention as a later stage.** Retrofitting rewrites every subject on `main` or leaves an unqueryable era.

## Consequences

- Easier: release notes per cluster derive from a revision range and group by type; audit queries are `--grep` over a grammar; the checkpoint drills match subjects by grammar rather than prose (`--basic-regexp`, never `-E`, where `(` becomes grouping).
- Harder: two commit populations must be kept apart: authoring commits (standard types, doc-area scopes) and content commits (domain types, registry scopes). The gate judges only the second.
- Harder: `!` is an annotation, never the control; `revert-gate` reads the diff for secret material and stays the authority ([0018](0018-secrets-taxonomy-class-keys-roll-forward.md)).
- Follow-up: the version token in a `pin`/`promote` subject is the join key that lets `dora --stages` connect the dev commit to the prod promotion.

## Where it is taught or enforced

Rules 2.1 and 2.2; taught at stage 02 step 7 (the first config commit); `appendices/commit-convention.md`; `scripts/commit-gate` in four modes (`--range`, `--file` for the `commit-msg` hook, `--subject` for the PR title via the `pr-record` check from stage 11, `--docs`); `.gitmessage` seeded at stage 00.
