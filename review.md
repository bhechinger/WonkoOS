Start a fresh agent session with a new context containing only these
repository instructions and the current branch or pull-request diff against
its base. Have that agent perform an adversarial review that actively tries
to falsify the change's correctness. Do not reuse the implementation
session or its context. Assess:

   - bugs;
   - security;
   - code quality;
   - DRY violations; and
   - removable complexity.

Synthesize and deduplicate their findings. Report only actionable issues
with severity, file/line, and rationale. Address all issues raised by this
review before continuing to the Greptile review.
