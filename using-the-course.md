# Using the course - read before stage 00

[Walkthrough index](README.md) · [The GitOps rules](rules.md)

[The GitOps rules](rules.md) are what the *platform* is built to obey. This page is the set of rules the *course* obeys: how a stage is shaped, what the course seeds into your repo, what it deliberately never names, and the idioms its paste blocks use. None of it is GitOps; all of it is what lets a reader tell a broken page from a hard idea, and it is short enough to read once.

---

## 1. Three repositories, and what the course seeds

The **config repo** (`gitops-golden-path`) is the one you build: what runs where, a standard root-level GitOps repo from its first commit, tagged at every stage and act boundary. The **app repo** (`gitops-golden-path-app`) is the prop: a deliberately boring .NET API with one Azurite dependency, whose only job is to be deployed. This repo is the **course**: the walkthrough, the appendices, and `seed/`, a literal image of the config repo at day zero. [Rule 1.1](rules.md#11-two-repositories-one-job-each) says why the first two are separate; this section says what crosses the line between them and the course.

The config repo is created at [stage 00 step 1](act-1/stage-00.md#1-the-config-repo---create-it-and-seed-it-from-the-course) and seeded **once** from the course, because a real platform repo *keeps* its gates, checkpoints and drills, and stage 01 already needs `cluster-up`. The seed is the `seed/` folder, copied whole - every path in it already sits where it will live in your repo: `scripts/`, `decisions/` (the platform's decision log: why each rule exists and what it rejected, yours to extend, see [decisions/](seed/decisions/README.md)), `.claude/skills/` (the operating skills, which ask the repo a question and write the answer as a document; a skill never bypasses a gate, see [the skills appendix](appendices/operating-skills.md)), `env.sh`, `.gitattributes`, `.gitmessage`, `.github/pull_request_template.md`. The same step seeds the **backlog**: `tools/seed-backlog`, course-side, reads the README's act tables and creates a milestone per act and an issue per stage and checkpoint, in course order, so issue numbers are identical for every reader ([rule 2.5](rules.md#25-every-change-has-a-work-item-the-trailer-is-the-reason)). Pulled a course update mid-walkthrough? `tools/seed-backlog --verify <owner>/<repo>` compares your seeded backlog against the updated roster and names any number that drifted. Run it before trusting a citation. After that the config repo is your own work: nothing course-shaped lands in it again, and nothing it needs lives only here ([take it to production](appendices/take-it-to-production.md) says which parts are the platform and which are the course). The app repo is created at stage 00 step 3, and stage 01's plain manifests live there as `deploy/`, the app team's kubectl folder, where deployment YAML really lives before a config repo exists. They stay until stage 02 lifts them out and retires the copy.

## 2. How a stage reads

Each stage document has the same shape:

- **Where you are.** Which repo, directory and branch the stage operates in (`main` unless it says otherwise - check before pasting anything), and the **starting state** it assumes. At act granularity the starting state is executable: `act-N-drill` rebuilds it.
- **Goal.** One sentence.
- **Steps.** Small, numbered, copy-pasteable.
- **Stop & measure.** The checkpoint: measurable outcomes with concrete verification and expected output. Do not proceed past a failing checkpoint. **From stage 02 on, mechanical checks are a `scripts/checkpoint-NN` script**: every check prints `PASS`/`FAIL` plus what it means, the script exits non-zero on failure, and CI runs the identical file. Bare unlabeled command output is banned at checkpoints. Live/observational checks (does the app answer, does the portal agree) stay as listed items. The last item is always the stage tag, and the closing of the stage's work item with it (§5).
- **Audit artifacts produced.** What durable, queryable evidence this stage added. This accretes stage by stage; by the end the point is made: *audit and compliance are built in; it's harder NOT to do it.* Stage 01 deliberately produces none; that absence is the lesson.
- **AI enhancement** (only where an operating skill applies). Four short parts: **how** the skill helps at this stage, **why** it is a skill and not a script (the judgment it adds), **where** in the stage it fits, and **what you verify** by hand afterwards. A skill reads, sequences and writes; it never replaces a gate, never merges, and never touches a cluster as a fix. Do the stage by hand first; the skill is for the second time and every time after.
- **Troubleshooting.** Symptom → likely cause → fix, for everything that can plausibly have gone wrong by this checkpoint.
- **What you learned, and what's next.** The stage's takeaways in two or three sentences, what's still deliberately missing, and the hook into the next stage.
- **End state.** Declared explicitly, with the commands to reach it. No stage may leave the reader guessing what should be running.

Acts close with an **act checkpoint** that exercises everything in the act end to end, beginning with a rebuild-from-nothing ([rule 5.2](rules.md#52-the-cluster-is-derivable-from-git---and-every-act-proves-it)).

## 3. How the text is written

- **Prop files vs lesson files.** *Everything* arrives as paste-ready blocks or tooling commands. Typing YAML is not a lesson under any approach. Prop files (the app, Dockerfiles, CI workflows) are pasted or generated without ceremony. Lesson files (manifests, kustomizations, Flux CRs) are pasted **and then read**: the walkthrough points at what matters in them, and the stop-and-measure asserts on their rendered effect.
- **Navigation.** Every stage links to the previous stage and the index directly under its title, and closes with a **Next:** link. Acts chain through their checkpoint pages, so the whole walkthrough reads front to back without returning to the index.
- **Repetition over reference.** Verification blocks are repeated in full at every point of use: a paste-able block beats a pointer to an earlier page, every time. Prose may reference; commands never do.
- **Gates and actions never share a block.** Every code block must be safe to paste whole. A check whose output a human must read goes in its own block *before* the block that acts on it. Otherwise paste-the-block runs the action before anyone reads the gate. The commonest instance: `gh pr diff` ends a block and `gh pr merge` starts the next one - a block that prints the diff and merges in the same breath has already decided.
- **Typed commands live in fenced blocks.** Anything the reader is expected to type or paste is a fenced ` ```sh ` block - the rendered page gives every block a copy button, and an inline command has none. Inline code in prose *names* a command, flag or file; it never issues one.
- **One command per line.** `&&` joins commands only when the join is load-bearing, never for brevity. The two load-bearing cases: a later command that must not run if an earlier one fails (a pasted block keeps executing after a failure, so `&&` is the only brake it has - the tag-push-close and merge-switch-pull chains are this case), and a subshell scoping a `cd`. Everything else is one command, one line, so a reader can see where each step starts. A load-bearing chain of three or more still writes one command per line: each line ends in a continuation backslash and the next line opens with `&&`, so the brake sits in the left margin. A two-command chain may stay on one line.
- **A comment must fit the screen.** GitHub renders a code block at roughly 110 monospace columns; anything past that hides behind a horizontal scrollbar nobody drags. A trailing comment that would push its line past that budget moves to its own line *above* the command it explains, and a long standalone comment wraps. Quoted expected output (`# →` lines, and their deep-indented continuations) is exempt: output is reproduced faithfully, even long. A long command is sometimes unavoidable; an invisible comment never is.
- **The voice.** Plain technical English: the ordinary word, one idea per sentence, active voice, one name per thing. No em dashes; a code comment's separator is ` - `. `vale .` from the repo root lints the bans (`.vale.ini`).
- **Asides are quote blocks.** A paragraph-length aside (a rationale, a wart stated honestly, a refinement a real fleet would make) renders as a `>` note, never as a paragraph wrapped in parentheses. Parentheses stay inside sentences.
- **Terminology reminders.** The course coins a few terms: *stamp*, *binding*, *class*, *rung*, *release channel*, *wave*, *era*, *IOU*, *gate*. [The vocabulary table](rules.md#vocabulary) is their canonical mapping. Every page re-states a term's mapping at its first use, in one clause: a reader landing mid-course on any page must never need a different page to decode a sentence.
- **Cross-references.** A stage lives in three registers: its file, its README row, and its neighbours' nav and Next lines. A counted claim ("the nine deciding rules") is a promise about a table somewhere else. Move one, move all; `tools/docs-gate` notices when you didn't, and `commit-gate --docs` holds every commit string in the text to the convention it teaches.

## 4. Identity: the tutorial names no accounts

**The rule.** Docs and scripts contain no GitHub owner, repo name, or registry path specific to any instance. Identity derives at runtime, three ways: paste blocks `source ./env.sh` (repo root; derives owner, repos and image from the `gh` login and the git remote; the committed file stores nothing); `gh api` calls use gh's native `{owner}/{repo}` placeholders; scripts derive via `gh repo view` from the remote. Expected outputs write `<owner>` where identity would appear.

**Why.** The course must work for any fork without a find-and-replace, and a find-and-replace is how a private name leaks into a public repo. Files the walkthrough *creates* (overlay pins, Provider addresses) legitimately carry the instance's real identity: that is their job; the tutorial that creates them stays fork-agnostic.

**Where.** `env.sh` is explained at stage 00 step 2; every later paste block that needs identity starts with `source ./env.sh`.

## 5. Tags at every boundary

**The rule.** The config repo is tagged at the end of every stage (`stage-07`) and every act (`act-2`), by the reader, as the last step of the stage's stop-and-measure. The same line closes the stage's issue (`gh issue close <n>`): the tag is the verification, the issue is the work item.

**Why.** "Your tree should now match `stage-07`" and `git diff stage-06..stage-07 --stat` are only real if the tags exist, and `act-N-drill` rebuilds *to* a tag. A course that says "at this point your repo looks like this" without a tag is describing, not asserting. The tag is a save point, and `act-N-drill` is the proof you can load it.

**Where.** Every stage's stop-and-measure from stage 02 on; every act checkpoint's pass criteria.

## 6. Command idiom: `docker`, fully-qualified images, `:ro,z`

**The rule.** Container commands are written as `docker` (the majority idiom); podman users install the docker shim once (stage 00 shows how: a real shim, never a shell alias, which dies in scripts). **Image references are always fully qualified** (`docker.io/openpolicyagent/conftest:…`, never the short form). Bind mounts into filter containers are always `:ro,z`. Anything started with `&` gets a readiness loop before first use and an explicit stop after last use, **by PID (`PF=$!` … `kill $PF`), never by job number**.

**Why.** Each one was written against a real failure. Podman enforces short-name resolution and wants to *ask* which registry you meant, which dies with `cannot prompt without a TTY` the moment stdin carries piped input, while real docker silently assumes `docker.io`. So the unqualified form works for exactly the users who didn't need the shim. SELinux-enforcing hosts deny containers access to unlabeled host dirs with a bare `permission denied`; `z` fixes it and is a no-op elsewhere. Job control exists only in interactive shells, so `kill %1` breaks the moment a block is pasted into a script. And it misleads when a *previous* port-forward still holds the port. A leaked port-forward is silent and looks exactly like a working one.

**Where.** Stage 00 (the shim), stage 02 (first filter container), stage 03 (first port-forward); `scripts/cluster-up` detects docker-that-is-podman for kind, the one tool that must know the truth.

---

## Quick reference

| § | Convention | One line | Enforced by |
|---|---|---|---|
| 1 | Three repos | the course seeds the config repo once; nothing course-shaped lands in it again | layout |
| 1 | The backlog | every stage is a seeded issue; every PR cites one; the milestone bar is "where am I" | `seed-backlog`, `issue-gate`, `pr-record` check |
| 2 | Stage shape | where you are, goal, steps, stop-and-measure, artifacts, troubleshooting, end state | `tools/docs-gate` (nav, Next) |
| 3 | The text | paste-safe blocks; repeat, don't reference; gates and actions never share a block; typed commands in fenced blocks, one per line unless `&&` is the brake; a long comment sits above its command | `docs-gate`, `commit-gate --docs` |
| 4 | Identity | the tutorial names no accounts | `env.sh`, `{owner}/{repo}` |
| 5 | Tags | `stage-NN` and `act-N` at every boundary | stop-and-measure |
| 6 | Command idiom | `docker`; fully-qualified images; `:ro,z`; kill by PID | review |

---

**Next:** [The GitOps rules](rules.md)
