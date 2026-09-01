---
name: audit-evidence
argument-hint: "[the question, verbatim] [sha | subject prefix | #PR | <stamp> <cluster> | a date window]"
description: >-
  Assemble an audit dossier for a change, a PR, a stamp or a time window from durable artifacts only (git, commit statuses, the PR record, the work item, what the cluster applied). Use when someone asks what ran where and when, who approved a change, what evidence gated it, whether a window held any change to production, or for the full evidence trail of one change. Also the closing step of a drill.
---

# audit-evidence

The answer to an audit question is a document whose every line points at an artifact. Memory, dashboards and terminal scrollback are not evidence. Git, the commit statuses, the PR record, the work item and the cluster's own reported revision are, and all of them outlive everyone who was on the call.

## 1. Shape the answer from the question

Keep the question verbatim; it is the dossier's title. Then pick the shape:

| The question is about | Start from | Shape |
|---|---|---|
| one change ("what happened with X") | a sha or a subject prefix | one change, end to end |
| one PR ("who approved #N and on what evidence") | the PR number | the PR record and its merge commit |
| one stamp ("what is prod running, since when") | stamp and cluster | current revision, the range since the last known one |
| a window ("every prod change between A and B") | dates, an optional path scope | the first-parent log, one line per PR, each traced |

## 2. Gather, artifact by artifact

Run these from the config repo root, on `main`, up to date. Every command reads; none writes.

**The change itself.** `scripts/evidence` prints the change, who touched its paths afterwards, the full status sequence, what the named cluster applied, and a plain-English answer. Accept a sha or a subject prefix; a prefix is anchored on the subject so a revert, which quotes the subject it undoes, cannot win.

```sh
./scripts/evidence <sha-or-subject-prefix> [stamp] [kube-context]
```

**The sequence, not the summary.** `.../commits/<sha>/status` returns only the latest state per context; the plural endpoint returns every posting in order, which is what shows a green whose description is not `reconciliation succeeded` (every non-error event posts as `success`). On Flux 2.8.x no failure posts; a context present on the parent commit and absent here is the red.

```sh
gh api "repos/{owner}/{repo}/commits/<sha>/statuses" --paginate \
  --jq 'sort_by(.created_at) | .[] | "\(.created_at)  \(.state)  \(.context)  \(.description // "")"'
```

**The registry.** Whether a tag exists is an artifact too, and it is what turns "health check failed" into a cause. The course's tool is `docker manifest inspect $APP_IMAGE:<tag>`: exit 0 present, non-zero absent.

**The PR record.** The merge commit's subject is the PR title and its body is the PR body, so the trailers are already in `git log`. The PR itself holds the reviews and the check rollup.

```sh
git log -1 --format=%B <merge-sha>                                   # title, body, Refs:/Closes:, Roll-forward:, Freeze-override:
gh pr list --state merged --search <merge-sha> --json number,title,mergedAt,mergedBy
gh pr view <number> --json reviews,statusCheckRollup,mergedBy,mergedAt,author,labels
```

**The work item.** The trailer names it; the issue carries who asked and when.

```sh
gh issue view <n> --json number,title,state,createdAt,closedAt,milestone,labels
```

**What a cluster runs now, and what it ran over a range.** `lastAppliedRevision` is now. The stamp's `status.history` is one entry per render digest with the revision, first and last reconcile times, count and last status: a failed render shows as `HealthCheckFailed` and never reaches `lastAppliedRevision`, and a revert that restores the same bytes shares the earlier entry. Beyond that, the status sequence (one success per applied revision, timestamped) and, where it is scraped, the metric store.

```sh
kubectl --context <ctx> -n flux-system get kustomization <stamp> -o jsonpath='{.status.lastAppliedRevision}{"\n"}'
kubectl --context <ctx> -n flux-system get kustomization <stamp> -o json \
  | jq -r '.status.history[] | .firstReconciled + "  " + .lastReconciled + "  x" + (.totalReconciliations|tostring)
           + "  " + .lastReconciledStatus + "  " + .metadata.revision[0:17]'
./scripts/release-notes <stamp> <ctx> <since-revision> --first-parent          # what shipped, as reviewed
```

**A window.** One line per PR that reached `main`, scoped to the paths that reach production, then trace each line as one change.

```sh
git log --first-parent --format='%h  %cI  %s' --since=<from> --until=<to> -- apps/overlays/prod clusters/prod
git log --first-parent --format='%h  %s' --since=<from> --until=<to> --basic-regexp --grep='^Freeze-override: '
```

**Context.** Where the question is about delivery performance rather than one change, `./scripts/dora --window <span>` gives the four numbers from the same artifacts.

## 3. Write the dossier

Fixed shape, so two dossiers a year apart read the same:

```markdown
# Audit: <the question, verbatim>

- Asked: <date>  Scope: <change | PR #n | stamp on cluster | window from..to, paths>
- Answered from: git (`main` at <sha>), commit statuses, the PR record, work items, <cluster contexts>

## Controls exercised

| Control | Mechanism | Evidence | Retrieved by |
|---|---|---|---|
| every change is a PR | ruleset on main, no bypass | merge commit <sha> is a PR merge; `ruleset show` | `git log --merges`, `scripts/ruleset show` |
| every change cites a work item | `Refs:` trailer, `pr-record` check | `Refs: #n`, issue open at merge | `git log -1 --format=%B`, `gh issue view` |
| the change was reviewed and gated | required checks, reviews | check rollup, reviews on PR #m | `gh pr view --json` |
| the fleet reported the outcome | commit statuses per stamp and cluster | the status sequence | `gh api .../statuses` |
| the cluster applied it (or did not) | `lastAppliedRevision`, health gating | revision on <cluster> | `kubectl get kustomization` |

## Timeline (UTC, one source per line)

| When | What | Source |
|---|---|---|

## Findings

## Gaps
```

Findings are sentences an auditor can check against the timeline. Gaps are everything the artifacts could not answer (a metric store whose retention ended before the window, a cluster that no longer exists, a status that was never posted), stated rather than papered over.

## 4. Land it

Print the dossier. If it is to be kept, write it to `docs/audits/<YYYY-MM-DD>-<slug>.md`, stage it, and open a PR with `scripts/pr-open`, citing the audit's work item in the `Refs:` trailer: an audit answer is itself a change record, and it gets the same review as any other.

## Rules

- Never state what an artifact does not back. Quote identifiers verbatim (stamp, cluster, status context, sha).
- Never run a gate to change its outcome, and never bypass one. This skill only reads.
- No stopwatch. Every time in the dossier is a recorded timestamp with its source.
- A green status is stamp telemetry about a reconcile, not a verdict about a commit; read the sequence and the applied revision together.
- Reconcile scope is not change scope: every cluster reconciles every commit; only the paths the commit touched decide who was affected.
- Ten minutes for one change, end to end. Longer means an artifact is missing, which is a finding.
