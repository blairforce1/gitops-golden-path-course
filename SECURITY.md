# Security

The scripts in this repository are designed to be copied into your own repository and run in your own shell - stage 00 does exactly that. A vulnerability here means a script or paste block that can be made to do something other than what its page says: command injection through crafted repo state, a gate that can be bypassed silently, a block whose effect exceeds its stated scope.

Report privately to **git@blairforce1.com**. Include the file, the input that triggers it, and what you observed - an errata report with discretion. No bounty; you get a fix, a credit line and a straight answer.

Not vulnerabilities: the props the course labels unsafe by design where they occur (Azurite's publicly documented dev key, the deliberately public demo image). The debt each one carries is named on the page that introduces it, along with the stage that pays it back.
