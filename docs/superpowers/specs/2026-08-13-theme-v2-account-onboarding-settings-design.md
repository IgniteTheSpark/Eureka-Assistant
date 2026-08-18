# Theme V2 Account, Onboarding, and Settings Design

**Date:** 2026-08-13

**Status:** Approved in conversation; awaiting written-spec review

## 1. Goal

Complete the Theme V2 user lifecycle:

1. Create and verify an email account.
2. Offer a short, fully skippable onboarding experience that demonstrates how a user creates a personal record type and turns one real input into a structured Asset.
3. Provide a focused account settings surface entered from the UReka logo.
4. Support password recovery, password changes, selective data export, logout, and permanent account deletion.

The onboarding experience no longer represents REKA as a pet, character, egg, or other concrete avatar. REKA may remain the name of UReka's intelligence and writing voice, but Theme V2 onboarding must teach the actual product through the capture-to-structure workflow.

## 2. Product Principles

### 2.1 Demonstrate value instead of touring features

The first screen gives one concise value statement and one three-part explanation:

> Choose something you want to keep track of, say or write one real thing, and UReka will organize it for you.

The supporting sequence is:

```text
Choose what to record -> Say or write one entry -> UReka structures and saves it
```

The first screen does not explain the Library, reports, calendar, devices, every capture surface, or the complete product architecture.

### 2.2 Onboarding is optional

The user can skip from the first screen or leave at any later step. Skipping ends onboarding and opens the App. It must not become a recurring modal or a launch blocker.

The Home empty state exposes one natural entry such as “Create your first record book.” The Account page exposes “Experience onboarding again.” Neither entry is a persistent nag.

### 2.3 Users choose a concrete record type, not a broad life domain

Examples include:

- Running
- Drinking water
- Baby feeding
- Dancing

The user then chooses what they want to record within that category. For example:

| Category | Suggested fields |
|---|---|
| Running | Distance, duration, location |
| Drinking water | Amount, time, container |
| Baby feeding | Feeding method, amount, time |
| Dancing | Dance style, dance studio, duration |

The suggestions are multi-select. The user can deselect suggestions and add their own fields. At least one field is required only when they choose to create the Skill; skipping remains available.

### 2.4 Hardware improves onboarding but never gates it

- A user with a UReka card or ring may connect it and speak the first entry.
- A user without hardware, or one who does not want to connect it now, uses typed input.
- Phone microphone capture is not part of this scope.
- Both paths use the same hint, extraction, preview, correction, and confirmation experience.

### 2.5 Preview before persistence

The processing UI displays the real stages of receiving, transcribing when applicable, understanding, and structuring. It then shows an editable structured card.

The first Asset is created only after the user confirms that card. A failed extraction or abandoned preview must not create a ghost Asset.

## 3. Scope

### 3.1 Included

- Theme V2 email-and-password login and registration UI.
- Real email verification with a six-digit code.
- Aliyun DirectMail as the first production email provider.
- Provider-neutral email delivery interface and fake test provider.
- Password reset through a six-digit email code.
- Authenticated password change.
- Immediate revocation of old sessions after password change, password reset, or account deletion.
- Fully skippable Theme V2 onboarding.
- Curated onboarding category catalog.
- Custom category input.
- Three suggested fields, multi-select, and user-added fields.
- Idempotent creation of a custom UserSkill after field confirmation.
- Optional card or ring connection.
- Typed fallback when hardware is unavailable or skipped.
- Skill-grounded hint generation.
- Non-persisting onboarding extraction preview.
- Editable first-card preview.
- First Asset confirmation and Home handoff.
- Full-screen account settings entered through the top-left UReka logo.
- Selective Markdown and CSV export.
- Permanent account deletion with password reauthentication.

### 3.2 Excluded

- Pet hatching, naming, cosmetics, growth, or a concrete REKA avatar.
- Avatar, user nickname, public profile, usage achievements, or personal statistics.
- Device management inside Account settings. Device entry remains independent.
- Appearance preferences inside Account settings.
- Changing the login email.
- Phone microphone onboarding capture.
- Third-party login and Baizhi login for the independent Theme V2 service.
- A generic server-configurable onboarding workflow engine.
- Fine-grained restoration to the exact onboarding step after the App exits.
- Visual design for the category carousel, field pills, processing animation, card transition, or Home bubble. These follow in a separate visual design pass.

## 4. User Journeys

### 4.1 Registration

```text
Login page
  -> Create account
  -> Enter email, password, password confirmation
  -> Accept Terms and Privacy Policy
  -> Request six-digit email code
  -> Enter code
  -> Atomically create verified account + baseline Skills
  -> Receive UReka session token
  -> Onboarding first screen
```

The account does not exist before successful code verification. This avoids creating inactive user-owned rows and prevents an unverified account from receiving an authenticated session.

The registration verification request contains the normalized email. Password and accepted legal-version data are submitted with the final verification command and are never stored in an email challenge row.

If the App is killed before verification, the user restarts registration. Detailed registration progress recovery is unnecessary.

### 4.2 Login

```text
Email + password
  -> Validate account and password
  -> Issue token carrying current auth_version
  -> pending onboarding: open onboarding
  -> skipped/completed onboarding: open App
```

Existing Theme V2 accounts are backfilled to `skipped`, so the migration never forces current users into onboarding.

### 4.3 Forgot password

```text
Forgot password
  -> Enter email
  -> Request six-digit reset code
  -> Enter code + new password + confirmation
  -> Replace password hash and increment auth_version
  -> Return to login
```

The code-request response is identical whether or not the email exists. This prevents account enumeration.

### 4.4 Onboarding

```text
Value screen
  -> Start OR Skip
Category selection
  -> Choose curated category OR enter custom category
Field selection
  -> Select 1..N suggested fields
  -> Add 0..N custom fields
  -> Confirm Skill OR Skip
Skill creation
  -> Optional device path OR typed path
First-entry hint
  -> Speak through connected hardware OR type/edit text
Processing
  -> Receive -> Transcribe if needed -> Understand -> Structure
Editable structured card
  -> Edit and save OR retry/re-enter OR skip
Confirmed Asset
  -> Card transitions into a Home bubble
  -> Open Home with the new Asset visible
```

Browsing categories and editing fields do not write user data. Confirming the category and field definition creates the Skill. If the user skips after that point, the empty Skill remains valid and usable later.

Confirming the preview creates the first Asset and marks onboarding `completed`.

### 4.5 Onboarding exit and replay

- A deliberate Skip changes `pending` to `skipped` and opens the App.
- An unexpected exit leaves `pending`; the next authenticated launch starts again from the first onboarding screen.
- Fine-grained step state is held only in the Flutter controller's memory.
- A successful replay changes `skipped` to `completed`; leaving replay keeps the prior terminal status.
- Replaying from an already completed account leaves it `completed`.
- Replay never changes a terminal account back to `pending` and never blocks App launch.

## 5. Account and Authentication Architecture

### 5.1 UserAccount changes

Extend `theme_v2_service/app/auth/models.py::UserAccount` with:

| Field | Type | Meaning |
|---|---|---|
| `email_verified_at` | UTC datetime, non-null for new accounts | Email ownership was verified |
| `onboarding_status` | bounded string | `pending`, `skipped`, or `completed` |
| `terms_accepted_at` | UTC datetime | Acceptance time |
| `terms_version` | bounded string | Version accepted during registration |
| `auth_version` | positive integer | Session revocation epoch |
| `password_updated_at` | UTC datetime | Audit time for password mutation |

Migration behavior:

1. Add nullable columns.
2. Backfill existing accounts with `email_verified_at = created_at`, `onboarding_status = skipped`, `terms_version = legacy-pre-email-verification`, `terms_accepted_at = created_at`, and `auth_version = 1`.
3. Apply the final nullability and defaults needed for future accounts.

No nickname, avatar, appearance, device, or profile-summary fields are added.

### 5.2 EmailVerificationChallenge

Add a dedicated challenge table with these fields:

- `id`
- `purpose`: `register` or `password_reset`
- normalized `email`
- `code_digest`
- `request_ip_hash`
- `created_at`
- `sent_at`
- `expires_at`
- `consumed_at`
- `failed_attempts`
- `locked_until`
- `delivery_status`

Rules:

- Code format: six digits.
- Validity: 10 minutes.
- Resend cooldown: 60 seconds.
- Only the newest successfully sent, unconsumed challenge for an email and purpose is accepted.
- Per email: no more than one send per 60 seconds, five sends per hour, or twenty sends per day.
- Per request-IP hash: no more than twenty sends per hour or one hundred sends per day.
- Five invalid submissions lock verification for 15 minutes.
- Challenges store only an HMAC digest of the code, never the plaintext code.
- Codes, passwords, provider secrets, and full delivery payloads are not logged.
- Consumed and expired rows are deleted after a 30-day audit/abuse window.

### 5.3 Email provider boundary

Define this application-owned interface:

```text
EmailVerificationSender.send_code(email, code, purpose, expires_in)
```

Implementations:

- `AliyunDirectMailVerificationSender` for production in mainland China.
- `FakeVerificationSender` for automated tests.
- A disabled provider that fails readiness in production but allows explicit local development behavior.

Aliyun DirectMail is the initial provider because its official product supports transactional messages, verification notifications, API access, and SMTP access:

<https://www.aliyun.com/product/directmail>

The application does not expose DirectMail response payloads to the client. Provider timeouts and failures become a bounded public error that allows retry.

### 5.4 Auth version and token revocation

JWTs include the user's current `auth_version`. The authenticated dependency must:

1. Verify the token signature and expiry.
2. Load the referenced UserAccount.
3. Reject a missing account.
4. Reject a token whose version does not equal the current account `auth_version`.

This adds one authoritative account check to authenticated requests. It closes the current gap where deleting an account or changing its password would leave a signed token usable until expiry.

Password change and password reset increment `auth_version`. Authenticated password change returns a replacement token at the new version so the current device can continue while every previous token becomes invalid.

### 5.5 Auth API surface

The public route contract is:

| Method | Route | Purpose |
|---|---|---|
| `POST` | `/api/auth/verification-codes` | Request a registration or password-reset code |
| `POST` | `/api/auth/register` | Verify the registration code and atomically create the account |
| `POST` | `/api/auth/login` | Authenticate an existing account |
| `GET` | `/api/auth/me` | Read the current verified account and onboarding status |
| `POST` | `/api/auth/password-reset` | Verify the reset code and replace the password |
| `PATCH` | `/api/account/password` | Change password while authenticated |

`POST /api/auth/verification-codes` accepts `{email, purpose}`, where purpose is `register` or `password_reset`. The response contains the resend delay and expiry duration but never the code.

`POST /api/auth/register` accepts `{email, verification_code, password, terms_version, terms_accepted}`. Password confirmation is a client validation; the server receives one password and enforces 8–128 characters for new, reset, and changed passwords. Existing shorter passwords remain valid for login until changed.

`POST /api/auth/password-reset` accepts `{email, verification_code, new_password}`. `PATCH /api/account/password` accepts `{current_password, new_password}` and returns a replacement token.

Registration code request returns a clear conflict for an already registered email. Password-reset code request always returns the same public result for known and unknown addresses.

Account creation, baseline Skill provisioning, challenge consumption, legal acceptance, and initial `pending` onboarding status are committed together.

## 6. Onboarding Architecture

### 6.1 Lightweight state model

Only `pending`, `skipped`, and `completed` are durable. The service does not store a row for every screen or answer.

The Flutter controller owns:

- current screen;
- selected category;
- suggested and selected fields;
- user-added fields;
- created Skill reference;
- hardware-versus-typed path;
- generated hint;
- raw typed text or hardware recording reference;
- extracted preview payload;
- local edit state and submission idempotency key.

This state is intentionally discarded when the page is destroyed.

### 6.2 Category catalog

The curated catalog is versioned product configuration with stable category IDs. Each category includes:

- localized display label;
- concise description;
- exactly three initial field suggestions;
- field keys, labels, and value types;
- a default schema/render basis;
- hint examples.

The first release uses a compact carousel rather than an exhaustive taxonomy. Running, drinking water, baby feeding, and dancing are mandatory entries. Additional entries require product approval through the later visual/content pass; the implementation does not invent unreviewed categories.

The catalog must load without an LLM. The client bundles the current required catalog entries as a fallback so a temporary catalog request failure does not leave the onboarding screen empty.

### 6.3 Custom category and fields

For a custom category, the service asks the existing Skill Designer for three field suggestions. The onboarding-specific prompt must return a final suggestion set rather than entering the full multi-step Skill Builder interview.

Users can ignore those suggestions and type their own fields. Model unavailability must not block progress: user-added fields can be converted to conservative text fields, while recognized curated field metadata retains its numeric, duration, time, or location type.

### 6.4 Skill creation

Skill creation occurs only after field confirmation. The command contains the category and the complete selected field list.

The service creates a stable definition fingerprint from normalized category identity and normalized field definitions. A deterministic `machine_name` derived from this fingerprint preserves the existing per-user machine-name uniqueness contract. Retrying the same definition returns the existing Skill instead of creating a duplicate.

The resulting Skill includes:

- display name;
- description;
- schema;
- render specification;
- queryable fields;
- chat starters;
- enabled state.

Curated definitions are deterministic. Custom definitions may be enriched by the Skill Designer, but validation guarantees that every user-selected field remains present and no unselected field becomes required.

### 6.5 First-entry hint

The hint is grounded in the category and selected fields. It is usable as-is but editable.

Examples:

- Running: “I ran 5 kilometers along the river today and it took 32 minutes.”
- Dancing: “I practiced hip-hop at Star Dance Studio tonight for 60 minutes.”

Curated categories use deterministic examples. Custom Skills may use model-enriched hints with a deterministic fallback assembled from the field labels. Hint failure never blocks input.

### 6.6 Extraction-only preview

The current normal Capture flow gives the Agent write tools and persists records during execution. It cannot be reused unchanged because onboarding requires a preview before persistence.

Add a dedicated onboarding extraction provider that receives:

- owned `user_skill_id`;
- Skill schema and presentation metadata loaded by the server;
- source text;
- current time and timezone context.

It returns one validated payload draft and user-facing field-level warnings. It receives no write tool runtime and cannot create or update an Asset, Event, Contact, Session, or Skill.

The preview payload is returned to Flutter and held in memory. The user may edit fields, retry extraction, or replace the original input.

### 6.7 Typed path

Typed input posts the Skill ID and source text to the extraction-only preview endpoint. No Session, InputTurn, or Asset is created yet.

On final confirmation, the server atomically creates a manual/onboarding provenance turn and the Asset from the edited payload.

### 6.8 Hardware path

Hardware capture uses a short-lived, single-use onboarding capture intent:

1. Flutter requests an intent for the owned Skill.
2. The intent expires after 10 minutes and can be cancelled.
3. Flutter attaches the intent ID to the next card or ring capture submission.
4. The server validates that the intent belongs to the authenticated user and is unused.
5. The recording is marked `onboarding_preview`.
6. ASR runs normally.
7. After ASR, the pipeline stops before normal Session materialization and before `capture_process` receives Agent write tools.
8. The transcript is sent through the extraction-only preview provider.

The intent is one-shot so a later unrelated device recording cannot accidentally enter onboarding mode. Leaving onboarding disarms the client-side intent.

An unconfirmed onboarding recording is transient. On Skip it is cancelled immediately; otherwise it expires and is cleaned up within 24 hours. Cleanup removes its server record and temporary media. A confirmed recording is materialized into the normal provenance chain with the Asset.

### 6.9 Final confirmation

Final confirmation receives:

- Skill ID;
- edited payload;
- typed source text or owned onboarding recording ID;
- an idempotency key generated once for the confirmation screen.

In one transaction, the service:

1. Revalidates Skill ownership and payload compatibility.
2. Creates or materializes the input provenance.
3. Creates exactly one Asset.
4. Stores the idempotency result.
5. Changes onboarding status to `completed` when appropriate.

The response returns the canonical Asset. Flutter refreshes Home and opens it with the new Asset highlighted for the card-to-bubble handoff. The exact animation is deferred to visual design.

### 6.10 Skip

Skip changes an authenticated account from `pending` to `skipped`. It is idempotent.

- Before Skill confirmation: no Skill or Asset exists.
- After Skill confirmation: the empty Skill remains.
- After an unconfirmed capture: the transient onboarding capture is cancelled and cleaned up.
- In replay mode: Skip or close preserves the account's previous terminal status.

## 7. Flutter Structure

### 7.1 Authentication gate

The root gate resolves these states:

```text
loading
unauthenticated -> Theme V2 auth surface
authenticated + onboarding pending -> onboarding
authenticated + onboarding skipped/completed -> Theme V2 App shell
```

The auth surface contains Login, Create Account, Verify Email, Forgot Password, and Set New Password states. It uses Theme V2 foundations and does not retain the legacy login page's visual contract by accident.

### 7.2 Onboarding modules

Keep units focused:

- Onboarding controller: in-memory state and commands.
- Category repository: catalog and custom suggestions.
- Skill creation repository: confirmed definitions only.
- Device bridge: connect, arm one-shot intent, and observe capture status.
- Preview repository: typed/hardware extraction and confirmation.
- Screen widgets: product introduction, category selection, field selection, device choice, first entry, processing, preview, and success handoff.

Screen widgets do not call the API directly. The controller owns busy state, idempotency, cancellation, and error retention.

### 7.3 Hardware fallback

Every device-related onboarding screen exposes “Use text instead.” Device connection and capture timeout never trap the user. Switching to text cancels or disarms the one-shot capture intent before showing the text field.

### 7.4 Result correction

The structured preview supports:

- confirm without editing;
- edit individual values and confirm;
- rerun extraction using the retained original input;
- return to input and replace the source text;
- skip onboarding.

Validation errors attach to the relevant field. A failed submission retains all edits.

## 8. Account Settings

### 8.1 Entry and boundaries

The top-left UReka logo becomes an accessible button that opens a full-screen Account page. It has an explicit semantic label and pressed state.

The existing device entry remains independent in the top navigation. It does not move into Account settings.

The existing top-navigation day/night action remains where it is, but Account settings contains no appearance-preference section.

### 8.2 Account page contents

Only these sections are included:

#### Account

- Read-only verified email.
- Verified status.
- Change password.

#### Data

- Export data.
- Delete account.

#### Product

- Experience onboarding again.

#### About

- Terms of Service.
- Privacy Policy.
- App version.

#### Session

- Log out.

No avatar, nickname, profile summary, statistics, achievements, device list, or appearance settings appear.

### 8.3 Change password

The authenticated form requires:

- current password;
- new password;
- new-password confirmation.

Success increments `auth_version`, returns a replacement token, updates Flutter's stored token, and invalidates all other sessions.

### 8.4 Legal links and release configuration

Terms and Privacy Policy open production-configured HTTPS URLs. The registration consent names the versions being accepted.

Production readiness fails when either URL or legal version is missing. Local development may use an explicit development placeholder but must not silently ship it.

### 8.5 Logout

Logout clears the local token and every account-scoped singleton or persisted client key, then returns to Login. It does not mutate server data.

## 9. Data Export

Theme V2 adopts the mature legacy interaction and output contract instead of inventing another export format.

### 9.1 Interaction

1. Open Export Data from Account settings.
2. Load available record types and counts.
3. Select one or more types.
4. Choose Markdown or CSV.
5. Generate the file.
6. Open the operating-system share sheet.

Export is not an implicit all-data action. The user chooses types explicitly.

### 9.2 Types

- Each owned UserSkill is an Asset export type.
- Event is a separate type when present.
- Contact is a separate type when present.

Types with zero records are hidden, matching the legacy export interaction. If no exportable data exists, the page reports that clearly instead of opening an empty selector.

### 9.3 Markdown

Markdown is grouped and human-readable:

- export timestamp;
- summary counts;
- Assets grouped by Skill display name;
- Events;
- Contacts;
- readable schema labels rather than machine keys when available.

### 9.4 CSV

CSV remains a flat heterogeneous table:

```text
kind,type,title,domain,created_at,detail_json
```

Each record occupies one row. Type-specific fields live in UTF-8 JSON inside `detail_json`.

### 9.5 Delivery and isolation

- All queries are scoped to the authenticated user.
- Requested type IDs are checked against owned Skills.
- Large exports stream rather than building an unbounded response in memory.
- Suggested filename: `ureka_export_YYYYMMDD.md` or `.csv`.
- Flutter writes a temporary file and uses the existing system share dependencies.

## 10. Permanent Account Deletion

### 10.1 User interaction

Deletion requires:

1. A clear irreversible-deletion explanation.
2. A second explicit confirmation.
3. Re-entry of the current password.

Successful confirmation immediately returns the client to Login and clears all local account data.

### 10.2 Server behavior

The current Theme V2 schema does not consistently foreign-key every `user_id` to `user_accounts`. Deletion therefore cannot rely on deleting one account row and hoping database cascades cover the rest.

Implement one explicit account-deletion service that owns the deletion graph. It includes, where present:

- UserSkills and Assets;
- Events and Contacts;
- Sessions, messages, input turns, pending actions, and capture turns;
- capture recordings/files and device bindings;
- notifications and outbox records;
- reports, report runs, shares, actions, triggers, and related jobs;
- Reka nudges and rhythm profiles;
- account-scoped configuration and any other user-owned rows;
- the UserAccount row last.

Database deletion is one transaction. Any database failure rolls the entire transaction back.

External media cannot share that database transaction. Before account removal, the service writes a durable, minimal deletion work item containing the owned object keys needed for cleanup. The worker retries storage deletion until completion. The work item contains no email, password, transcript, or report content.

The token becomes unusable as soon as the account is missing, and `auth_version` protects the period before final row deletion.

### 10.3 Deletion coverage guard

Tests maintain an explicit registry of user-owned models/tables. A new model with a user-ownership field must either:

- be registered in account deletion; or
- explicitly document why it contains no deletable user data.

This turns forgotten data into a test failure.

## 11. Error Handling

### 11.1 Registration and email

- Invalid email: field-level validation before sending.
- Already registered: registration reports the conflict and offers Login.
- Send failure: no account is created; retry is available.
- Cooldown or rate limit: show a bounded retry time.
- Wrong code: show a generic invalid-code result and remaining attempts when safe.
- Expired code: offer resend.
- Duplicate verification race: exactly one account is committed.

### 11.2 Onboarding

- Catalog failure: use bundled curated fallback.
- Suggestion failure: keep category text and allow manual fields.
- Skill creation failure: retain category and selected fields.
- Device connection failure: retry or switch to text.
- Hardware capture timeout: retry or switch to text.
- ASR failure: retain capture error and allow text fallback.
- Empty transcript: request another input without calling extraction.
- Extraction failure: retain original input; no Asset exists.
- Field validation failure: retain the edited card and mark invalid fields.
- Double confirmation: return the same idempotent Asset result.

### 11.3 Export and deletion

- No exportable content: explain without creating an empty file.
- Export transport failure: retain selection and allow retry.
- Incorrect deletion password: stay signed in and do not mutate data.
- Database deletion failure: rollback fully and report that deletion did not complete.
- Media cleanup failure: keep the durable cleanup item and retry without restoring account access.

## 12. Testing Strategy

### 12.1 Backend unit and contract tests

- Code generation, HMAC comparison, expiry, consumption, lockout, cooldown, and rate limits.
- Email provider adapter and fake provider behavior.
- Registration email normalization and atomic account creation.
- Concurrent verification of the same email creates one account.
- Password-reset requests do not enumerate accounts.
- Password change/reset increments auth version.
- Old tokens fail after password change/reset.
- Existing accounts are backfilled to verified and onboarding-skipped.
- Curated catalog includes required acceptance fixtures and exactly three initial suggestions.
- Custom field fallback retains user labels.
- Equal category/field definitions resolve to one Skill.
- Extraction preview has no write tools and creates no Asset.
- Final confirmation creates one Asset under double submission.
- Skip before confirmation creates no Skill or Asset.
- Skip after Skill confirmation retains only the Skill.
- Replay does not restore the launch gate.
- Hardware onboarding mode stops before normal capture processing.
- Expired preview captures are cleaned up.
- Export type selection and Markdown/CSV serialization.
- Cross-user export IDs are rejected.
- Account deletion covers every registered user-owned table.
- Deleted accounts and old tokens cannot call authenticated APIs.

### 12.2 Flutter tests

- Login/Create/Forgot Password state transitions.
- Password confirmation and legal-consent validation.
- Six-digit code input, resend cooldown, and error retention.
- Pending versus skipped/completed root gating.
- Skip from the first onboarding screen.
- Curated category and custom-category selection.
- Suggested field multi-select and custom field addition.
- Skill creation only after confirmation.
- Device connection, failure, cancellation, and text fallback.
- Typed hint edit and submit.
- Real capture status mapping into receiving/transcribing/understanding/structuring.
- Preview edit, retry, input replacement, and idempotent confirm.
- Home handoff receives the new Asset ID.
- UReka logo opens Account settings.
- Account page contains only the approved sections.
- Change-password token replacement.
- Export type and format selection.
- Delete-account double confirmation and password entry.
- Logout clears account-scoped state.

Visual goldens are added only after the separate visual design is approved.

### 12.3 End-to-end tests

Run with fake email, fake ASR, and fake extraction providers:

1. Register, verify, skip, and enter Home without a Skill or Asset.
2. Register, choose Running, select/add fields, type a first record, edit preview, confirm, and see one Home Asset.
3. Register, choose Dancing, create a Skill, skip first capture, and enter Home with an empty Skill.
4. Run hardware onboarding preview, verify no Asset exists before confirmation, then confirm one Asset.
5. Reset password and prove the former token is invalid.
6. Export a selected subset in Markdown and CSV.
7. Delete the account and prove every user-owned row and authenticated access are gone.

Aliyun DirectMail receives a controlled staging smoke test. Real outbound email is not a dependency of the automated suite.

## 13. Release and Observability

- Production readiness checks DirectMail credentials, sender identity, legal URLs, legal version, JWT secret, and deletion-worker availability.
- Metrics count code requests, provider success/failure, verification success/failure, rate-limit rejection, onboarding start/skip/Skill-created/Asset-completed, preview failures, export completion, and account deletion completion.
- Metrics use anonymous aggregate dimensions. They do not contain email addresses, codes, passwords, transcripts, or Asset payloads.
- Logs use challenge IDs, provider request IDs, recording IDs, and user IDs only where operationally required and already authorized by existing logging policy.
- Rollout begins in staging with fake-provider E2E, then real DirectMail smoke, then a production canary account.

## 14. Success Criteria

The work is complete when:

1. A new user cannot receive an authenticated session without verifying a real email code.
2. Password recovery works without revealing whether an account exists.
3. A user can skip onboarding immediately and is not blocked or repeatedly prompted.
4. A user can create a concrete custom record type from category plus selected/custom fields.
5. Hardware is optional and typed input provides the full core experience.
6. No Asset exists before first-card confirmation.
7. Confirmation creates exactly one Asset and hands it to Home as a bubble target.
8. The UReka logo opens a focused Account page with no avatar, nickname, device settings, or appearance settings.
9. Selective Markdown and CSV export works for Theme V2 data.
10. Password changes revoke old tokens.
11. Permanent account deletion removes all user-owned database data, schedules durable media cleanup, and invalidates all tokens.
