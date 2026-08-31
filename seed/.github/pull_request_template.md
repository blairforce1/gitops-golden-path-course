<!-- Title: obeys the commit convention exactly - it becomes the merge commit's subject.
     e.g.  promote(app-prod): app 0.1.4      pin(platform): traefik 41.3.0      access(prod): add jo to recipients -->

## What is moving

<!-- The change in one or two lines. Which rung, which stamp, which version. -->

## Why now

<!-- The reason, not the diff. The diff already says what. -->

## Evidence

<!-- What justified this: the source commit's green context, slo-gate output and window, the rendered diff comment, a freeze calendar check. Paste the lines, not a summary of them. -->

## If it is wrong

<!-- Revert this merge - or, if the title carries `!`, the Roll-forward: trailer below says what to do instead. -->

<!-- Trailers go last, one per line, and travel into the merge commit:
Refs: #            (required - the work item this change advances; Closes: only when this PR is the whole item)
Roll-forward:      (required when the title carries `!`)
Freeze-override:   (only when deliberately merging inside a freeze window; say why) -->
