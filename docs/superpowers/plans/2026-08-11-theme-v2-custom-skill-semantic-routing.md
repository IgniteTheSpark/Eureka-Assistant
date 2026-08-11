# Theme V2 Custom Skill Semantic Routing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add scope confirmation and hidden semantic routing profiles to custom Skill creation, then verify natural Chinese routing with live DeepSeek.

**Architecture:** Keep routing metadata inside the existing Skill JSON Schema as normalized `x-routing`, so no database migration is needed. The designer may return one compact scope-and-content confirmation group before a draft; the Flutter controller keeps it in the existing Describe stage and silently carries the generated profile into Skill creation. The capture dispatcher consumes a readable profile and the live evaluator asserts exact structured routes.

**Tech Stack:** Python 3, FastAPI, Pydantic, LiteLLM/DeepSeek, pytest; Flutter/Dart, flutter_test.

## Global Constraints

- Build and test only Theme V2.
- Do not add a database table or expose routing keys in user-facing UI.
- Custom capture fields remain optional.
- Event/Expense/Contact semantics outrank custom Skills. A clearly completed
  historical record may correct a model-misclassified Todo; reminders and future
  actions remain Todo.
- Tests must distinguish structural fake-provider stress from live semantic behavior.

---

### Task 1: Skill designer response contract

**Files:**
- Modify: `theme_v2_service/app/domains/assets/skill_design.py`
- Modify: `theme_v2_service/app/domains/assets/api.py`
- Test: `theme_v2_service/tests/unit/test_skill_design.py`
- Test: `theme_v2_service/tests/contract/test_asset_api.py`

**Interfaces:**
- Consumes: `SkillDraftRequest(description, answers)`.
- Produces: `design_skill_step(description, answers) -> {"questions": [...]}` or `{"draft": {..., "routing_profile": {...}}}`.

- [x] Write failing normalization tests for the bounded scope-and-content confirmation group and a normalized routing profile.
- [x] Run the focused tests and verify they fail because the step/profile contract does not exist.
- [x] Implement provider prompting, response parsing, clarification validation, and routing-profile normalization.
- [x] Update the API to return the designer step without mislabeling questions as a draft.
- [x] Run unit and contract tests to green.

### Task 2: Hidden routing persistence and readable Dispatcher catalog

**Files:**
- Modify: `mobile/lib/theme_v2/library/create_skill/skill_wizard_controller.dart`
- Modify: `theme_v2_service/app/domains/capture/skill_factory.py`
- Test: `mobile/test/theme_v2/library/create_skill/skill_wizard_controller_test.dart`
- Test: `theme_v2_service/tests/unit/test_flash_dispatcher.py`

**Interfaces:**
- Consumes: draft `routing_profile`.
- Produces: schema root `x-routing` and readable `_custom_skill_hint(...)` content.

- [x] Write failing Dart test proving `routing_profile` becomes hidden `x-routing` on confirm.
- [x] Write failing Python test proving aliases, inclusions, exclusions, and examples appear readably in the Dispatcher catalog.
- [x] Run both tests and verify the expected failures.
- [x] Extend repository conversion and controller confirmation without adding visible routing fields.
- [x] Replace opaque custom-schema serialization with bounded localized routing and field summaries.
- [x] Run focused tests to green.

### Task 3: Wizard intent-confirmation interaction

**Files:**
- Modify: `mobile/lib/theme_v2/library/create_skill/theme_v2_skill_wizard.dart`
- Test: `mobile/test/theme_v2/library/create_skill/theme_v2_skill_wizard_test.dart`

**Interfaces:**
- Consumes: `SkillWizardQuestion` from the existing controller.
- Produces: a Describe-stage scope confirmation with clear button/copy behavior.

- [x] Write a failing widget test that checks scope copy and confirms routing metadata remains invisible.
- [x] Run the widget test and verify the failure is caused by current generic copy.
- [x] Update Describe copy, clarification presentation, and primary action copy while preserving the three-stage flow.
- [x] Run controller, widget, and golden-adjacent tests to green.

### Task 4: Live DeepSeek semantic behavior suite

**Files:**
- Create: `theme_v2_service/scripts/eval_capture_semantic_routing.py`
- Create: `theme_v2_service/tests/evals/capture_semantic_cases.py`
- Modify: `theme_v2_service/scripts/smoke_flash_provider.py`

**Interfaces:**
- Consumes: configured capture model/API key and isolated custom Skill catalog.
- Produces: per-case expected/actual structured route report and non-zero exit on mismatch.

- [x] Encode the reviewed natural-language matrix with exact expected operation, machine name, and excluded routes.
- [x] Add a testable pure assertion layer so evaluator failures identify the utterance and mismatch.
- [x] Seed water, running, dance, and tennis profiles rather than baseline Skills only.
- [x] Invoke the real dispatcher through the configured LiteLLM/DeepSeek provider with deterministic temperature.
- [x] Run the live suite for three repetitions and preserve the summarized pass/fail output.

### Task 5: Regression verification

**Files:**
- Test only the files changed by Tasks 1–4 plus existing capture parity suites.

**Interfaces:**
- Consumes: completed designer, Wizard, catalog, and evaluator changes.
- Produces: verified Theme V2 implementation ready for connected-device acceptance.

- [x] Run Python skill-design, API-contract, dispatcher, normalizer, parity, and multi-intent tests.
- [x] Run Dart controller and widget tests.
- [x] Run formatter/analyzer on changed files.
- [x] Review `git diff` to ensure unrelated dirty mobile changes were not modified or staged.
- [x] Report the exact live DeepSeek failures, if any, instead of weakening expected routes.

## Final verification — 2026-08-11

- Backend: `707 passed`.
- Flutter: `867 passed`; changed files format clean and analyzer clean.
- Live DeepSeek capture routing: `69/69` across three repetitions.
- Live DeepSeek Skill designer: `3/3`.
- Full Flash provider persistence smoke: expense, water, running, and Q&A all passed with isolated cleanup.
