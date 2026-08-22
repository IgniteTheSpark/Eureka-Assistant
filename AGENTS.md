# Repository agent constraints

## Verification scope

- For ordinary bug fixes and focused product changes, default to targeted verification only:
  1. the regression test that reproduces the reported problem;
  2. tests directly affected by the changed behavior;
  3. a small number of adjacent, credible risk cases;
  4. targeted static analysis and diff checks for changed files.
- Do not run repository-wide audits, full backend suites, full Flutter suites, or unrelated-module reviews merely "for safety."
- Record unrelated findings for follow-up instead of expanding the current task without authorization.
- Full-suite verification is allowed only when:
  - the user explicitly requests it;
  - the branch is being prepared for merge or release;
  - the change affects migrations, shared infrastructure, or a genuinely cross-cutting contract whose impact cannot be bounded with focused tests.
- Before starting any full-suite verification, explain why it is necessary, estimate the time and execution cost, and obtain user confirmation.
- A focused regression suite, directly affected tests, targeted analysis, and diff checks are the default completion evidence for scoped fixes.
