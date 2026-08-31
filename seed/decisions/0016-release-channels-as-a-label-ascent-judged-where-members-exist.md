# 0016. Release channels are a label on the binding; ascent is judged where members exist

- **Status:** accepted
- **Date:** 2026-08-26
- **Deciders:** blairforce1, with Claude Code
- **Supersedes:** none

## Context

Two promotion axes exist and must not be conflated: class promotion (platform, infrastructure and cluster changes climbing platform → dev → prod) and app release exposure (which tenants see a release first). A previous fleet ran rings named dev/canary/latest/stable, mirroring cluster areas; canary auto-advance burned the team and canary was abandoned, so customers' `latest` stamps became the first production exposure, and `latest` degenerated into a micro-version of `stable`, with stamps scattered across many versions instead of controlled waves. Tenants also built their own ring semantics inside whatever ring they were given. A ring named `dev` beside a class named `dev` rebuilds the ambiguity the split exists to kill. Five exposure tiers with two of them empty would deadlock a gate that treats no traffic as a failure.

## Decision

An app release climbs **release channels**: engineering → internal → pilot → early-access → ga, declared as a `platform.example.com/release-channel` label on the binding, orthogonal to class. The `release` label names the version a stamp carries; the channel is the schedule that decides when it moves. Three rules a gate can refuse: every app binding carries exactly one channel label from the registry; a channel moves only forward and only to what the next-faster channel is serving after a clean soak window; a fast-channel binding on a prod-class cluster is a declared exception with an expiry. The corollary: an empty channel is legal, its pointer follows its faster neighbour, and ascent evidence comes from the nearest populated faster channel, the gate naming whose soak window it judged. GA is partitioned into named **waves**, a `wave` label beside the channel, advanced one batched PR at a time with soak between; a customer freeze holds their wave. Enforcement is a named deliverable (`channel-gate`) that ships with the stage that introduces channels; until then the app rides the class ladder as one implicit channel.

## Considered options

- **Annotations as the authority.** Not render-resolvable and not bulk-operable; annotations remain fine as non-selecting metadata.
- **A shared per-channel pointer file or component.** Structurally wrong for GA, which needs partial advancement by wave; the one-pointer idea is what OCI channel tags already do properly, for fast channels only.
- **Channels as folders.** Schedule never encodes as taxonomy ([0015](0015-bindings-live-in-the-cluster-folder.md)).
- **Version-named tiers (dev/latest/stable).** The names that degenerated; exposure-named tiers say what a tier is for.
- **Pod-level canary (Flagger).** A different layer: which request hits the new version, not which stamp gets the release. Deliberately out of scope.

## Consequences

- Easier: membership change is a one-line diff on the binding; `kubectl get kustomizations -l release-channel=internal` is the tier; halt a wave by not merging, or by suspend-by-label on fast channels; the dogfood tenant is `internal` on a prod-class cluster, which proves the axes independent.
- Harder: channels need a version ledger or channel-tag history for the ascent gate to judge against; the detective controls (version-spread metric, support-window sweep) sit beside the preventive gates.
- Harder: at course scale only three tiers are populated; the design has to be honest about empty tiers rather than hide them.
- Follow-up: wave and ascent PRs are opened by a scheduled robot when the soak clock expires and merged by humans at the exposed end ([0017](0017-automation-writes-only-at-the-entry-rung.md)); fast channels later convert to signed OCI channel tags ([0036](0036-signed-oci-config-artifacts-are-the-release-destination.md)).

## Where it is taught or enforced

Rule 5.13 and the vocabulary entries `release channel` and `wave`; stage 22 (the canary tenant), stages 28–29; `channel-gate` (ships with stage 28); the `PolicyException` pattern from stage 30 for placement exceptions.
