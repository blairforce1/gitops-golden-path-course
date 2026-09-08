# The operating skills

Claude Code skills for operating the config repo: what an operations team used to call runbooks, the written procedure for a task that recurs, with one difference that matters. A runbook was read by a person and followed by hand, so it drifted from the scripts it named and was skipped under pressure; a skill is read by the assistant, runs the same scripts in the same order every time, and stops at the human's line (the merge, the tag, the revocation). They live in the course at `seed/.claude/skills/<name>/` and land in your repo at that same `.claude/skills/` path when stage 00 copies the seed, beside the scripts, and a real platform repo keeps them: they are how an operator asks the repo a question and gets a document back, rather than a pile of query output.

**The boundary.** A script is a gate: it turns one class of evidence into a `PASS`/`FAIL` verdict and an exit code ([rule 5.9](../rules.md#59-gates-not-checks---and-ci-is-a-backstop-that-never-fires)). A skill adds what a script cannot: choosing which artifacts answer a question, sequencing the queries, reading the result, and writing the artefact a person asked for. A skill never bypasses a gate and never changes a gate's outcome; where a skill's work must land in the repo, it lands by PR like everything else.

| Skill | What it produces | First used |
|---|---|---|
| `audit-evidence` | An audit dossier for a change, a PR, a stamp or a window, from durable artifacts only: the question, the controls exercised, a timeline, findings, gaps | [Act III checkpoint](../act-3/act-checkpoint.md), drill 4 |
| `promote` | A promotion PR on both signatures (the lower rung's green context, a clean SLO window), the calendar and the reach checked, the body a deployment record | [stage 07](../act-2/stage-07.md) |
| `fleet-triage` | The four-layer diagnosis of a red or stuck stamp from its identifier, the applied revision and the status sequence read together, the fix named as a PR | [stage 04](../act-1/stage-04.md), [stage 09](../act-3/stage-09.md) |
| `rotate-secret` | A class key, a value or a recipient rotated in two phases with the provider revocation recorded and the roll-forward trailer written | [stage 17](../act-5/stage-17.md) |
| `onboard-tenant` | A tenant as a replica: leaf per rung, stamp per cluster, secret boundary, owners, the SLO dimension, one PR with the isolation proofs | [stage 22](../act-6/stage-22.md) |
| `declare-freeze` | A freeze or lift as a calendar entry, checked against the existing calendar, landed by PR | [stage 27](../act-6/stage-27.md) |
| `break-glass` | A production fix under incident conditions: declared, the narrowest bypass, the controls restored and proved, the change reconciled by PR | the break-glass drill (after Act VI) |
| `run-drill` | A rebuild drill or a game day run against what exists, with the numbers from artifacts and the evidence pack on the work item | every act checkpoint |

Skills are markdown (`SKILL.md` with a name and a description in front matter, then the procedure). Read one the way you would read a runbook; the commands in it are the same ones the stages teach. Where a skill applies, the stage carries an **AI enhancement** section ([using the course §2](../using-the-course.md#2-how-a-stage-reads)): how the skill helps, why it is a skill rather than a script, where in the stage it fits, and what you verify by hand afterwards.
