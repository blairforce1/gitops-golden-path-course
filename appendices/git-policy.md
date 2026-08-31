# The git policy - how a change enters the record

[← walkthrough index](../README.md)

[The commit convention](commit-convention.md) says what a commit's subject must look like. This page
says what git and GitHub must be configured to do so those subjects survive the trip to `main`,
because a convention that the merge button quietly rewrites is not a convention.

## Merge commit only

**Squash and rebase merges are disabled. Every PR lands as a merge commit.**

This is not a taste argument. In a config repo the PR *is* the unit of review: it carries the
approvals, the rendered diff ([stage 12](../act-4/stage-12.md)), the status checks, the
SLO evidence a promotion was gated on. A merge commit is the only merge strategy that puts a durable
pointer to that PR in the history: `%p` gives you both parents, `git log --first-parent` gives you
the PR-level view of what shipped, and the full log still gives you the change-level view. Squash
throws the second away and rebase throws the first.

Three consequences follow, and each removes work rather than adding it:

- **Branch commits actually land.** The walkthrough has four flows where the commit's `-m` and the
  PR's `--title` differ ([stage 13](../act-4/stage-13.md),
  [stage 16](../act-4/stage-16.md)). Under squash, the `-m` text is a fiction that
  never reaches `main`, a latent bug in every one. Under merge, both strings are real and both are
  queryable.
- **No lookup has to tolerate a rewritten subject.** Squash appends ` (#N)` and, depending on
  settings, concatenates every branch commit message into the body. The checkpoint's `rung-time`
  lookups currently work only because a squashed subject *happened* to stay byte-identical to the
  branch commit's. That is an accident; merge-only makes it a property.
- **`lastAppliedRevision` resolves to a commit that still exists.** A cluster records the sha it
  applied. Rebase and squash both rewrite shas, so a revision a cluster reported an hour ago can
  become unreachable, which breaks the per-cluster release-note range
  ([stage 26](../act-6/stage-26.md)) at exactly the moment you need it.

Set it. These are plain repository settings and, unlike branch protection, they are **free on
private repositories**:

```sh
gh api -X PATCH "repos/{owner}/{repo}" \
  -F allow_merge_commit=true -F allow_squash_merge=false -F allow_rebase_merge=false \
  -f merge_commit_title=PR_TITLE -f merge_commit_message=PR_BODY \
  -F delete_branch_on_merge=true \
  --jq '"merge: \(.allow_merge_commit)  squash: \(.allow_squash_merge)  rebase: \(.allow_rebase_merge)  subject: \(.merge_commit_title)"'
```

**The two `merge_commit_*` flags are the load-bearing half.** GitHub's default merge subject is
`Merge pull request #1 from owner/branch`: the PR title lands on line 3, so the *merge commit
itself* violates the convention no matter how carefully the PR was titled. `PR_TITLE` makes the
subject the pull request title alone (GitHub's own wording: "just the pull request title"; unlike
squash, the number is not appended), and `PR_BODY` carries the body down with it, trailers included.
With both set, the merge commit is a conforming commit and `Closes: #142` still auto-closes.

That makes **the PR title a first-class artifact**: it is the subject that reaches `main`, so
`commit-gate` lints it as a PR check, not as a courtesy.

## Protection is the other half

Settings decide the *shape* of a merge; branch protection decides whether a merge can be
*skipped* at all. That is set on the same day as the settings: a ruleset on `main` at stage 00,
requiring a PR and blocking force-push, with no bypass actors ([rule 1.3](../rules.md#13-protection-from-day-zero-nothing-reaches-main-except-a-merged-pr)).
It grows from there: CI becomes a required check at [stage 08](../act-3/stage-08.md), code-owner review
and the path gate join at [stage 21](../act-5/stage-21.md). Two rules are worth restating because
they are what makes merge-only meaningful rather than decorative: **linear history must stay off**
(it forbids merge commits, which is the opposite of this policy), and **CODEOWNERS is path-scoped**,
so `base/`, `clusters/`, prod overlays and the gates themselves demand review the promotion ladder
cannot enforce on its own. Rulesets on a private repository need a paid plan; the README says so
before stage 00.

## Trailers, and the template that makes them habitual

Trailers are the reference slot ([convention → trailers](commit-convention.md#trailers-carry-the-references)):
`Closes:` for what a change finishes, `Refs:` for what it touches, both multi-value. They are worth a
commit template, because the discipline that survives is the one you don't have to remember:

```sh
cat > .gitmessage <<'EOF'

# <type>(<scope>): <description>          # <=72 chars, imperative, no trailing period
#
#   domain    pin promote bind rotate access policy break
#   standard  feat fix docs refactor test ci chore revert
#   scope     the BLAST RADIUS - stamp | cluster | class | tree
#             see appendices/commit-convention.md in the course repo
#
# Why, not what. The diff already says what.
#
# Closes: #142
# Refs: #98, #131
EOF
git config commit.template .gitmessage
git add .gitmessage && git commit -m "policy(scripts): commit template carries the vocabulary"
```

The template is committed (it is repo policy, not a personal preference) but the `git config` line
is local: git deliberately will not let a repository set your editor behaviour on clone, and it is
right not to. Say so in the README, or new clones silently lose it.

Two smaller settings worth the same treatment:

```sh
git config --local user.name  "$(git config user.name)"   # pin identity per-repo: a correct global
git config --local user.email "$(git config user.email)"  # config is silently overridable elsewhere
git config --local pull.rebase false                       # merges here too - see above
```

## What this buys, concretely

| Question | The query it becomes |
|---|---|
| What shipped to prod between two revisions? | `git log --first-parent <old>..<new>`: PR-level, one line per merge |
| Which of those were promotions vs. pins? | `--basic-regexp --grep='^promote('` on the same range |
| Every policy change this quarter? | `git log --since=... --basic-regexp --grep='^policy'` |
| What did issue #142 actually change, and where did it land? | `--grep='^Closes: #142'` on the body, then the merge commit's first parent |
| Release notes, per cluster | the cluster's `lastAppliedRevision` as the range → git-cliff ([stage 26](../act-6/stage-26.md)) |

None of these are possible against prose subjects and squashed history. That is the argument.
