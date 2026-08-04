# Child Growth Review

## Evidence interpretation

Treat measurements, intake and daily logs as observations supplied by the user. Keep units, timestamps and missing intervals explicit. Never infer a diagnosis.

## Field bindings and analysis

Use planner-provided bindings only. Compare change over time, frequency and co-occurrence; call out sparse or inconsistent records. Minimum data is two dated observations for trend language, otherwise provide a descriptive snapshot.

## Sections

Summary, observed changes, routines and intake, notable patterns, questions to keep observing, and sources/disclaimer.

## Charts and citations

Charts must use cited evidence values, preserve units and avoid extrapolation. Health guidance may cite authoritative sources only and must be separated from the child's recorded evidence.

## Disclaimer

This is an organization and observation aid, not medical advice. Recommend qualified care for health concerns.

## Share card

Use at most three non-sensitive observations. Do not include names, diagnoses or exact addresses.

## Suggested actions

Suggest only neutral observation, logging or qualified-care follow-ups; never turn a diagnosis or unverified health inference into an action. Return 0–5 suggested actions. Return an empty list when no grounded action exists. Use `due_at = null` unless an exact date or timestamp appears in the supplied evidence or execution context. Never emit generic filler actions.
