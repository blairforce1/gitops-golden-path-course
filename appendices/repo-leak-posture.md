# Appendix - Assume the clone leaks

[Walkthrough index](../README.md) · Companions: [06 - Secrets](../act-2/stage-06.md) · [stage 21 - Path protection](../act-5/stage-21.md)

A config repo is the fleet's blueprint, so the instinct is to protect it by keeping it private. Private is worth having. It is also the weakest control in the stack, because of what a repo *is*: every person with read access holds a complete, offline, permanent copy the moment they clone, as does every person who *used to* have access, every laptop that has ever been compromised, every CI runner that has ever checked it out, and every backup of all of those. There is no revocation for a clone. A leaving employee doesn't need to exfiltrate anything; they already have it.

So the posture is not "keep it secret". It is:

> **Secrecy of the repo is a delay, not a control. Design so that a full clone is worth nothing on its own.**

That is a testable property, and this appendix is the test. It is also why most of the hardening people associate with *public* repos belongs in private ones too: the threat model barely changes, only the number of adversaries and the time to first attempt.

## The invariant

**Reading the repo must not grant access to anything.** Read it as a question about each file: *if an attacker held this, what could they do that they could not do before?* Three answers, and only the first is acceptable.

| Answer | Verdict |
|---|---|
| "Nothing: it's a pointer, a pin, or ciphertext they can't decrypt" | Correct |
| "They'd learn something useful" (topology, versions, names, who approves what) | Acceptable, but it sets your patch cadence and anonymisation requirements |
| "They could authenticate as something" | **A bug.** Fix it before anything else here matters |

## Applies regardless of visibility

These are the ones worth folding in now, private repo or not.

| Control | Why it survives the "but we're private" objection |
|---|---|
| **No file is a capability** | No bearer tokens, long-lived cloud keys, kubeconfigs or webhook URLs with secrets in the query string. This course's IOU pattern exists for this reason: the one irreducible token is ciphertext, and everything cloud-shaped becomes federation in stages 12–14 |
| **Ciphertext is durable, not immortal** | Every historical value stays in history forever ([stage 06](../act-2/stage-06.md) states this at the point of creation). An age key leaked in three years decrypts what you encrypted today. Consequences: rotate **on a schedule**, not on incident ([stage 17](../act-5/stage-17.md)); revoke old values at the *provider*, never just commit a new one; and a secret ever committed in plaintext is compromised even after the "fix" commit: rotate it, don't just delete it |
| **Federation conditions are the real perimeter** | Workload identity removes the secret, so what the repo publishes is the *trust policy's shape*. Pin the subject to repo **and** branch **and** environment: no `repo:org/*`, no bare-branch wildcards. Knowing your conditions must not be sufficient to satisfy them, because a leaked repo tells an attacker exactly what to imitate |
| **Actions pinned by commit SHA** | A moving tag is a supply-chain write path into a runner that holds cloud identity. This is the same "pins, not floating refs" rule the render chain already runs on |
| **Least-privilege workflow permissions, OIDC over stored secrets** | A leaked repo shows which workflows hold which permissions, and a stored secret is a capability that outlives its context, where an OIDC token is minted per run and dies with it |
| **CODEOWNERS carries teams, not personal emails** | The file publishes who can approve changes to `base/` and prod. That's a target list for phishing the exact person whose approval matters ([stage 21](../act-5/stage-21.md)) |
| **Tenant anonymisation** | Customer names in folder names, hostnames and namespaces convert a security incident into a contractual one. Nothing about a private repo prevents this from being read by someone who shouldn't, **but this one has a real cost on the other side of the ledger, so it gets its own section below rather than a verdict here** |
| **Patch cadence beats inventory secrecy** | The repo is a complete version inventory *and*, through git history, a public record of how long you take to patch. You cannot hide it from someone with a clone, so the only real answer is to shorten it: the ladder ([stage 16](../act-4/stage-16.md)) and automated entry-rung bumps ([stage 14](../act-4/stage-14.md)) are security controls, not just convenience |
| **Detection lives on the resource side** | You cannot alert on someone reading a repo they have access to. You *can* alert on identity use from an unexpected source, at an unexpected time, from an unexpected workflow, cloud-side, where the capability actually is |

### Tenant names: the one control with a genuine cost

Every other row above is close to free. This one isn't, and treating it as free is how you end up with a repo nobody can navigate during the incident it was hardened for.

**The case for names.** Named folders are *self-describing under pressure*. An outage is exactly when cognitive load is highest and improvisation is most dangerous, and `clusters/prod/northwind/` answers "am I about to touch the right customer?" with no lookup, no second screen, no chance of fixing the wrong tenant because two IDs differ in one digit. Anonymised identifiers push that translation into a mapping table you must consult *precisely when you least want to*, and having seen both, the named layout is materially nicer to work in.

**The case against is not really about attackers.** The mapping table exists somewhere regardless: a runbook, a CMDB, someone's spreadsheet. So anonymisation usually *moves* the disclosure rather than removing it, and only helps if that mapping is genuinely better protected than the repo. Worse, it is often theatre: if you terminate TLS with publicly-issued certificates per tenant hostname, **those hostnames are already public in Certificate Transparency logs**, searchable by anyone, forever. Anonymising the folder while publishing the SAN is a control that costs your responders real time and buys an attacker's afternoon nothing. What the case *is* really about: contractual and regulatory obligations (many customer agreements forbid naming the customer at all), and sectors where the client list is itself commercially sensitive.

**Scale decides it, and the pets-versus-cattle instinct is exactly the right one.** At five customers, names are navigation and everyone knows all of them anyway. At five hundred, nobody can hold the list in their head, tooling does every lookup regardless, and named folders stop being navigation and become an unbounded, unreviewed disclosure surface with no operational upside left to defend. The transition is the same one that happened to servers: you name pets, you number cattle. The mistake is not choosing wrongly, it is failing to notice the moment you crossed over.

A workable middle, if you're near that line:

- **Identify by stable ID, label for humans.** The folder and resource names are IDs; a `metadata.annotations` or a comment carries the display name. Grep still finds either, and the disclosure surface is bounded to files a reader has to open rather than a directory listing.
- **Then make translation one keystroke.** If responders have to consult a spreadsheet to resolve an ID, you have not anonymised; you have added a step to every incident. Dashboard variables, a `tenant` lookup in the CLI, ID-to-name in the alert payload. Budget for this or keep the names.
- **Anonymise at the boundary, not in the workspace.** Screenshots, public repos, vendor tickets and conference talks are where names leak in practice, and those are cheap to scrub. Internal navigation is where names pay.

The decision rule, stated so a future reader can apply it rather than re-argue it: **use names while every reader of this repo is already inside the same confidentiality boundary as the customer relationship, and the list is small enough that a human is the lookup. Switch to IDs when either stops being true**, and expect the second one to stop first.

### Whichever you choose, make the identifier the *same string* everywhere

The naming decision above is only half the operational cost. The other half is whether the identifier you picked survives the trip from an alert back to the config that caused it. If the dashboard says one thing, the namespace says another and the folder says a third, you have built a translation step into every incident, and anonymisation makes it worse, because now the translation is also the thing you were trying to hide.

The chain has to hold end to end, and in this course it deliberately does:

| Where the identifier appears | Example |
|---|---|
| folder in git | `clusters/prod/prod-01/` |
| cluster / kube context | `kind-ggp-prod-01` |
| stamp (Flux `Kustomization`) | `app-prod` |
| commit status context | `kustomization/app-prod/prod-01` |
| metric labels | `gotk_resource_info{name="app-prod", cluster="prod-01"}` |
| resource file name | `app-prod.kustomization.yaml` ([file naming convention](../README.md)) |

That is why `<metadata.name>.<kind>.yaml` is a convention rather than a preference: an alert names a resource, and the resource name **is** the filename, so the path from "what is paging me" to "which file did this" is a `grep` with no lookup table in between. [Stage 09](../act-3/stage-09.md) leans on the same property in reverse: the dashboard names the stamp *and* the cluster, so triage starts on the right cluster instead of three of them.

Two rules that keep it true:

- **Alert payloads carry the identifiers, not just the symptom.** Cluster, namespace, stamp: in the notification body, not only on a dashboard the responder has to go and find. An alert that says "availability breached" without saying where costs the first five minutes of every incident.
- **Anonymise the whole chain or none of it.** Half-anonymised is the worst outcome available: the responder pays the translation cost *and* the name is still in the metric labels, the certificate, or the alert text. If you switch to IDs, switch everywhere in one change, and check the observability side explicitly: labels and dashboard variables are where the old names survive longest.

The test, worth running once on a real alert: **from the notification alone, can you name the file to open?** If it takes a lookup, the identifiers aren't lined up yet, and that gap will be found at 3am, by whoever is least equipped to close it.

## Only matters if the repo is public

Kept separate on purpose, because these are the ones that genuinely change with visibility, and because a private repo that adopts everything above has already done the hard part.

- **Fork PRs from strangers**: `pull_request_target` and workflows that check out and execute PR code become remote code execution with your repo's identity.
- **Self-hosted runners**: never on a public repo. A fork PR is an execution request on your hardware.
- **Time to first attempt**: public repos are scanned continuously. Private ones give you the luxury of a mistake being found by you first, which is a scheduling advantage, not a security property.

## What a leaked clone does *not* give

Worth stating, because over-estimating the damage leads to the wrong response (panic re-keying of things that were never at risk, while the actual capability sits unrotated).

- **No inbound path to a cluster.** Flux pulls; nothing in the repo lets anyone push to your API servers. There is no credential in the repo that reaches a cluster: the deploy key lives *in* the cluster, and it is read-only besides ([stage 14](../act-4/stage-14.md) widens exactly one, deliberately).
- **No decryption.** sops ciphertext without an age key is inert, and CI proves it daily: every render and policy check in this course runs **keyless** ([stage 11](../act-4/stage-11.md)).
- **No approval.** Read access is not write access; the promotion ladder and path protection are enforced by the forge, not by obscurity.

## Where the irreducible secrets should live

Most secrets dissolve, per [stage 06](../act-2/stage-06.md)'s taxonomy, and stages 31–35 replace cloud credentials with federation outright, which is the only real win available: **the best secret is the one that no longer exists.** What survives is genuinely irreducible: third-party API keys, SMTP passwords, payment-provider keys. For those, encrypted-in-git was the right answer for a *laptop-scale* fleet and stops being the right answer at team scale, for the reason this appendix started with: the ciphertext is in every clone, forever, and its safety rests entirely on a key you cannot un-leak.

The target shape, in four decisions:

**Reference, don't store.** The secret lives in a vault (Key Vault, or your cloud's equivalent); git holds a *pointer*. The consuming cluster resolves it, an `ExternalSecret` (External Secrets Operator) or a Secrets Store CSI mount, so what a repo leak yields is the *name of a secret*, not its value. This is the same move the render rule makes everywhere else: git holds intent, the cluster holds the thing.

**Fetch with an identity, not another secret.** The obvious trap is a vault credential in git to fetch the secrets from git: the chicken-and-egg that made people give up on vaults. Workload identity dissolves it: the pod federates to a cloud identity, the vault authorises that identity, and there is no bootstrap secret anywhere. If your vault integration needs a stored credential to start, the architecture has a hole in exactly the place it claims to fix.

**Put the vault on a private network.** Private endpoint on the VNet, `publicNetworkAccess` disabled, private DNS zone so the in-cluster resolver reaches it. Then a stolen identity is not enough: the caller must also be *inside*, which converts a credential-theft incident into a credential-theft-plus-network-position incident. Two useful consequences: the blast radius of a leaked token collapses to whatever can already route to the VNet, and **CI cannot reach the vault at all**, which costs nothing here, because every gate in this course is deliberately keyless ([stage 11](../act-4/stage-11.md)) and renders ciphertext without decrypting it.

**Pin the version in the URI, and know what you are trading.** Vault secret identifiers are versioned (`.../secrets/<name>/<version>`); `ExternalSecret`'s `remoteRef.version` selects one. This is the decision worth thinking about rather than defaulting:

| | Unversioned (latest) | Versioned (pinned) |
|---|---|---|
| Rotating a value | no commit, no deploy: change it in the vault | a reviewed one-line PR per environment |
| Git as the record | shows *that* a secret is referenced | shows **which value each environment runs**, and when it changed |
| Emergency rotation | immediate, fleet-wide | as fast as a merge: slower, but attributable |
| Rebuilding an old commit | gets today's value | gets the value that commit ran: DR is reproducible |
| Ladder | secrets bypass promotion entirely | a secret change climbs dev→prod like any other change, soaking on the way |

The pinned column is the same argument the whole course makes about pins, applied to secrets: **an unversioned reference is a floating tag**, and floating tags are exactly what the render rule, the version ladder and the promotion ladder each exist to eliminate. It also restores the property encrypted-in-git had and referencing quietly took away: a rotation is a *visible diff with an author*, not an invisible change of state in a system nobody reviews. Pinning is only safe because the vault keeps old versions: enable soft-delete and purge protection, or a pin becomes a dangling reference and rebuilding last month's commit fails.

The honest cost: emergency rotation now needs a merge on every rung, and a forgotten pin means a rotated secret that nothing picked up. Mitigate by pinning *and* alerting on drift, the vault's current version versus what git pins, so "we rotated and prod never took it" is a monitored condition rather than a discovery. And stage 19's Reloader stays load-bearing either way: a changed Secret still has to reach running pods.

### The decay rule, and why rollback is the wrong reflex

Pinning raises the question everyone asks second: *how long do we keep old versions, in case we need to go back?* The answer is smaller than it looks, because **a secret is the one artifact in the repo whose old versions decay.** An image tag from last year still runs; a chart version still installs; a manifest is a pure value. A credential is a *pointer to state you don't own*, and [stage 17](../act-5/stage-17.md)'s rule, rotation means revoking at the provider, guarantees that a properly rotated value is dead the moment it is superseded. Revert to it and you get an address with nothing behind it: a green reconcile onto a credential that opens nothing.

> **For secrets, roll forward. Never back. A revert must not drag credentials backwards with it.**

Three consequences worth writing down before you need them:

- **The rollback horizon is the overlap window, not the retention setting.** Inside [stage 17](../act-5/stage-17.md)'s deliberate both-values-valid interval, going back works. Outside it, the pointer is dead regardless of what the vault still stores, and every old value you keep *working* past that point is simply an unrevoked credential with a longer name. Set retention to overlap plus a margin and stop.
- **Make dead-ness queryable.** Set an expiry on the superseded version at rotation time, so "is this pin still good" is a vault query rather than someone's memory, which is also what lets drift be classified automatically: current, behind-but-valid, or a dead pointer already deployed.
- **A revert carries code back and credentials forward, in one commit** (`git revert -n`, restore the secret paths from `HEAD`, commit once), so no window exists where a cluster points at a dead value.

[stage 20](../act-5/stage-20.md) rehearses all of this, including the part that makes it dangerous: **the wrong revert succeeds.** Nothing errors, nothing goes red, the fleet converges happily onto a dead credential: stage 09's *converged is not working* in a new costume. It ships `scripts/revert-gate`, which reads paths only (no key material, so it runs anywhere CI runs) and exits non-zero when a change moves secret material, printing the roll-forward recipe.

## The five-minute audit

Run this thinking, not a script, when a repo's access list changes, or when someone leaves:

1. Does any tracked file grant access if read? (If yes, stop and fix that.)
2. Has any secret **ever** been committed in plaintext? Rotate at the provider. The history is out.
3. Are federation subject conditions pinned to repo + branch + environment, with no wildcards?
4. Are the age keys older than your rotation interval? An offboarding is a rotation trigger, not a formality ([stage 18](../act-5/stage-18.md) ends in [stage 17](../act-5/stage-17.md) for exactly this reason).
5. Would the version inventory embarrass you? That's the patch-cadence conversation, and it is the one an attacker with a clone is actually reading.
