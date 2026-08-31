---
name: declare-freeze
description: >-
  Declare, shorten or inspect a change freeze as a calendar entry in git (freezes.yaml), checked against the existing calendar and landed by PR. Use when asked to freeze a tenant, a rung or a wave over a window, to lift a freeze early, or to say what is frozen now. Never suspends a reconciler.
---

# declare-freeze

A freeze is a calendar entry in `freezes.yaml`, enforced at merge time by `freeze-gate`, and it lapses with no action. It is never `flux suspend`: that stops drift correction too, never expires, and leaves no record.

## 1. What is frozen now

```sh
./scripts/freeze-gate --calendar
```

Print it for the asker before changing anything.

## 2. Shape the entry

Every field is mandatory:

| Field | Rule |
|---|---|
| `id` | kebab-case, who and when: `acme-eoy-2026` |
| `scope` | a list of path prefixes: a tenant leaf (`apps/tenants/acme/prod/`), a rung (`apps/overlays/prod/`), or a wave's bindings; never a cluster-side object |
| `from`, `to` | inclusive whole days, UTC; `to` is required, a freeze has an end |
| `reason` | the customer or business commitment, in one sentence |
| `ticket` | the work item or contract reference |
| `contact` | a team address, never a person's |

Check the window for conflicts before writing it: a scheduled wave or a planned promotion inside the window is stated in the PR body, not discovered at merge.

```sh
./scripts/freeze-gate --at <each planning date> origin/main HEAD
```

## 3. Land it

Edit `freezes.yaml` with yq (it carries lists; keep the tool's style), then:

```sh
git add freezes.yaml
./scripts/pr-open policy/<issue>/freeze-<id> "policy(<scope>): freeze <from> to <to>" <<'EOF'
## What is moving
A freeze entry: <id>, <scope>, <from> to <to>.

## Why now
<reason, verbatim from the asker; the ticket>

## Evidence
`freeze-gate --calendar` before: <output>. Conflicts inside the window: <none, or the wave/promotion named>.

## If it is wrong
Shorten `to` by PR. Never delete the entry: the record of the freeze is the point.

Refs: #<issue>
EOF
```

Lifting early is a PR that moves `to` earlier. Deleting an entry is refused.

## Rules

- No open-ended windows. A freeze nobody lifted is the real failure.
- Scope is a path. If the ask is "stop the cluster changing", explain why the calendar is the tool and offer it.
- Crossing a freeze is a `Freeze-override:` trailer on the crossing PR, citing the incident; it is loud and permanent, and this skill never adds one.
- The skill never merges.
