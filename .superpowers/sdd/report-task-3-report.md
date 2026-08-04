# Theme V2 Report App Layer — Task 3 report

## Scope and audit result

Only the Task 3 report run/controller/create-sheet sources and their approved
tests were inspected or changed. Task 4/5 files and unrelated dirty worktree
changes were not touched.

| Specification | Implementation / verification |
| --- | --- |
| Manual creation posts only `origin` and `intent` | `startUserInitiated` trims and rejects blank input, then posts exactly `{"origin":"user_initiated","intent":"..."}` to `/api/report-generation-runs`; the returned run is applied. |
| Blank submit, keyboard submit, and recoverable failure | The sheet disables blank submit; `onSubmitted` invokes the same submit path; request failures leave the controller/field mounted and the entered text intact for retry. |
| Successful creation enters the run page | `showReportCreateSheet` returns the run ID and the existing report-container success path pushes `ReportRunPage(runId: ...)`; the new widget test exercises the sheet through the actual container button and verifies the run-page route. |
| Generic copy | Run page defaults now say `报告` / `生成`, while `plan_options[].title` remains the displayed option title. |
| Cancel active runs | The controller permits the service's active states (`planning`, `awaiting_selection`, `generating`, `failed`), posts `/api/report-generation-runs/{id}/cancel`, applies the response, and the run page pops back to the originating report container on `cancelled`. Completed runs do not make a cancel request. |

The service defines `failed` as active/retryable, so it intentionally remains
cancellable; terminal completed/cancelled/expired states do not.

## RED / GREEN record

The assigned source files already contained an uncommitted implementation when
the task began. I first ran the focused existing suite; it passed. I then added
the missing acceptance coverage before relying on the implementation:

1. `keyboard submission opens the created report run` initially exposed that
   `pumpAndSettle` is invalid for a planning run because intentional polling and
   the progress indicator never settle. This was a test-harness RED, not a
   product-behaviour failure.
2. Replaced settling with explicit route/async frame advancement. GREEN: the
   test observes the exact POST, the subsequent run GET, and `ReportRunPage`.
3. Added tests for an active cancellation returning to its container and a
   terminal run making no cancel POST. GREEN: both pass against the controller
   and route behaviour.

No extra production change was warranted after the audit: the pre-existing
Task 3 source implementation satisfies the specified behaviours. The new tests
close the prior coverage gaps around real sheet-to-run navigation, keyboard
submission, return-on-cancel, and terminal-state guarding.

## Test evidence

Executed from `mobile/`:

```text
flutter test test/theme_v2/report/report_notification_target_test.dart \
  test/theme_v2/report/report_create_sheet_test.dart \
  test/theme_v2/report/report_run_page_test.dart \
  test/theme_v2/report/report_run_controller_test.dart
```

Result: PASS (all focused report tests; 14 tests after the added coverage).

`git diff --check` also passed for every allowed Task 3 source/test file.

## Self-review

- Verified the manual request body equality, rather than only checking the
  endpoint.
- Verified the sheet through `ReportContainerPage`, so the success route is not
  a callback-only unit assertion.
- Verified the cancellation endpoint, response transition, and visible return
  to the prior report-container route.
- Kept backend option titles intact and confirmed no legacy `会前调研` copy in
  the run-page generic-copy test.
- Did not stage or modify the unrelated dirty `report_notification_target.dart`
  or any Task 4/5 file.

## Commit

Commit message: `feat(report): add manual report creation and cancellation`.

## Concerns

None. The actual report-container navigation is an existing Task 2 file and
was deliberately not modified; it was exercised read-only through the Task 3
create-sheet test.
