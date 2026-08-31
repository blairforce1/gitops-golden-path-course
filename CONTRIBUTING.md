# Contributing

This course is a finished artifact with one voice, and its contribution lane is deliberately narrow. Here is what fits where.

## Errata: the most valuable thing you can send

You walked a stage and a step did not do what the page said. Open an issue with the errata template: the stage and step, what you ran, the full output, what the page claims. Every stage of this course was verified by walking it; your failed paste is the signal that something drifted, and it is exactly how the course was debugged in the first place.

## Small fixes: PRs welcome

Typos, dead links, a command that lost a flag. Every PR faces the same gates the author does:

```sh
tools/docs-gate
vale .
seed/scripts/commit-gate --docs
```

Commits are Conventional Commits (`type(scope): description`); the PR title becomes the merge commit's subject. The house text rules are in [using-the-course.md §3](using-the-course.md#3-how-the-text-is-written) - plain English, no em dashes, paste-safe blocks - and `vale` enforces most of them mechanically.

## Content and design changes: issues, not PRs

The course's structure, voice and technical decisions carry a decision-record trail ([decisions/](seed/decisions/README.md)) and a verification ledger ([STATUS.md](STATUS.md)). A rewrite, however good, cannot be merged unwalked. Propose the change in an issue; if it is taken, it gets built, walked and recorded like everything else, with credit.

## Licensing of contributions

Inbound equals outbound (GitHub Terms of Service, section D.6): code contributions land under [MIT](LICENSE-code), prose contributions under [CC BY-SA 4.0](LICENSE-docs), per the split in [LICENSE](LICENSE). No CLA.
