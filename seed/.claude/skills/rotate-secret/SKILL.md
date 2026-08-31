---
name: rotate-secret
description: >-
  Rotate a class key, a stored secret value, or a recipient (a person's access) in two phases, overlap then retire, with the revocation step at the provider and the roll-forward trailer, landed as PRs. Use when asked to rotate a key or a value, to remove a person's access, or after a suspected leak. Never commits a new value without a revocation plan.
---

# rotate-secret

Three rotations share one shape: overlap, then retire, then prove. What differs is what gets revoked. A rotation without revocation is theatre, because git history keeps every old ciphertext forever.

## 1. Which rotation

| Ask | Rotation | Revocation |
|---|---|---|
| "rotate the <class> key" | the class's age key | none at a provider; the old key is retired and kept, renamed |
| "rotate the <value>" | a stored secret value | **the old value revoked at the provider** before the commit |
| "<person> has left", "a laptop is lost" | a recipient | every value that recipient could read, per the row above |
| a suspected clone leak | all of the above, at once, in this order: recipient, class keys, deploy key, the robot's token | as above |

Local decrypt is needed for re-wrapping: `export SOPS_AGE_KEY_FILE=<operator keyfile>` holding the current private keys.

## 2. Class key: overlap, re-wrap, retire, prove

```sh
age-keygen -o <keys>/<class>.agekey.new
# overlap: the clusters of that class hold both identities
kubectl --context <ctx> -n flux-system delete secret sops-age
kubectl --context <ctx> -n flux-system create secret generic sops-age --from-file=age.agekey=<combined keyfile>
# policy first, then every file the class rule owns
NEW=$(age-keygen -y <keys>/<class>.agekey.new) yq -i '(.creation_rules[] | select(.path_regex | test("<class>")) | .age) = strenv(NEW)' .sops.yaml
for f in $(git ls-files '*/<class>/secrets/*.yaml'); do sops updatekeys -y "$f"; done
```

Land the re-wrap as `rotate(<class>): re-wrap to the new class key` by `pr-open`. After the fleet reconciles green, retire: the cluster secret carries the new identity only, the old keyfile is renamed `retired-<date>` and kept. Prove both directions: the old key decrypts nothing at `HEAD`; the new key decrypts everything the rule owns.

## 3. A value: revoke, then commit

1. Mint the new value at the provider **and revoke the old one there**. Record the revocation (console, API call, timestamp) in the PR body; the skill cannot do this step and says so.
2. `sops set <file> '["stringData"]["<KEY>"]' '"<new value>"'` (the only legal edit of ciphertext).
3. `./scripts/revert-gate origin/main HEAD` before pushing.
4. `./scripts/pr-open rotate/<issue>/<scope> "rotate(<scope>)!: <what> after <why>"` with a `Roll-forward:` trailer that is a recipe, not a warning: what to do instead of reverting.
5. Rollout: committed encrypted resources do not re-roll pods; Reloader does where the workload opts in. Confirm the rollout or say it is pending.

## 4. A recipient

Remove the key from `.sops.yaml` (`access(tree): remove <name> as a recipient`), `sops updatekeys` over every file the rules own, then rotate every value that recipient could have read, per section 3. Removing a recipient stops future reads; it does not un-read the past.

## Rules

- Never commit a new value without the provider revocation recorded.
- The class ladder applies: platform, then dev, then prod; never prod first.
- Two phases or an outage: both identities live during the overlap.
- Never delete history to hide ciphertext; assume the clone leaked.
- The skill never merges; each PR is read and merged by a person, and the retire step waits for green.
