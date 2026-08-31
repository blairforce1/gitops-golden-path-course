---
name: course-voice
description: The writing rules for this course's prose (stages, checkpoints, appendices, README, rules). Use whenever writing or editing any .md file in this repo, and when asked to review course text for voice or style.
---

# Course voice

The course reads as a finished, published artifact, written in plain technical English. These rules apply to every .md file except STATUS.md (the maintainers' ledger).

## Plainness (the useful half of ASD-STE100)

1. **The ordinary word.** use, not utilize; many, not numerous; because, not due to the fact that; boring or plain, not degenerate. A domain term beats a plain-English paraphrase, but jargon invented to sound technical is banned.
2. **One idea per sentence.** If the reader must backtrack to parse a sentence, split it or drop a clause.
3. **Active voice.** Name the actor: "the controller decrypts", not "is decrypted". Passive only when the actor is unknown or truly does not matter.
4. **One name per thing.** The vocabulary table in rules.md is the register. Never cycle synonyms for a coined term.
5. **Name the mechanism, not the feeling.** "the gate exits non-zero", not "the gate keeps you safe". If a sentence cannot be restated as a fact, instruction, or number, cut it.

## Hard bans

6. **No em dashes (`—`).** Restructure with a comma, a period, a colon before a list or example, or parentheses that were already there. In code-block comments and expected-output lines, the separator is ` - ` (space hyphen space). Numeric ranges keep the en dash (`stages 02–04`); arrows (`→`) stay.
7. **No process narration.** Never "found in verification", "found the hard way", "run 1", "verified on vX.Y", dates of testing, or what earlier versions got wrong. State the behaviour as a fact. Evidence observed during a run is fine when stated as observation ("Observed: ...").
8. **No chatty idioms.** "File that away", "I hope this helps", "Let's dive in". Say "Remember this for later" or nothing.
9. **No flow-style YAML in authored examples** (rule 3.4). `{}`/`[]` only for genuinely empty collections or where flow is a tool's own syntax, called out where it occurs.

## What never changes in a style edit

- Commands, YAML, expected output, and commit/PR-title strings inside code fences (except an em dash in a comment, which becomes ` - `).
- Markdown headings, unless every referrer to the heading's anchor is updated in the same change.
- Counted claims ("the nine deciding rules"), stage numbers, work-item numbers, link targets.
- The coined vocabulary: stamp, binding, class, rung, release channel, wave, era, IOU, gate.

## Enforcement

- `vale .` from the repo root lints the bans (config in `.vale.ini`, rules in `.vale/styles/Course/`).
- `tools/docs-gate` validates links, anchors, counts, and work-item citations; `scripts/commit-gate --docs $(git ls-files '*.md')` holds every commit string in the text to the convention it teaches. Run both before pushing any docs change.
