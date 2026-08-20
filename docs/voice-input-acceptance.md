# App-wide Voice Input Acceptance

Date: 2026-08-20
Branch: `codex/skill-dither-report-revamp`

## Automated acceptance

- Backend configuration, Qwen provider, and WebSocket gateway suites pass.
- The App owns exactly one real `VoiceInputService` through the root
  `VoiceInputHost`; Session, report, Skill, ordinary fields, and Reka bind to
  the shared coordinator.
- Starting a newer target invalidates and restores the previous target before
  cleanup, without exposing a microphone-conflict error.
- Page disposal, App backgrounding, logout/auth identity changes, provider
  failure, and late events are covered by deterministic lifecycle tests.
- Ordinary fields keep final text editable and do not auto-submit.
- Reka preserves provisional text, release-to-send, slide-up cancel, a
  60-second limit, and at-most-once Flash submission.
- Same-user backend sessions replace one another with exact lease ownership;
  different users remain independent. Startup, finalization, and cleanup are
  bounded, and cumulative PCM bytes are capped by the selected mode.
- Infrastructure code does not log transcript/audio bodies, retain audio, or
  retry provider submissions automatically.

Fresh commands:

```text
python -m scripts.test_asr_config                         PASS
python -m scripts.test_qwen_streaming_asr                PASS
python -m scripts.test_asr_stream_gateway                PASS
flutter test test/voice_input                            41 passed
flutter test test/theme_v2/session test/theme_v2/report \
  test/theme_v2/library test/theme_v2/home               500 passed
flutter analyze lib test/voice_input test/theme_v2       No issues found
flutter build apk --debug \
  --dart-define=API_BASE=http://127.0.0.1:8200            PASS
```

The rebuilt backend was started with the untracked root `.env` explicitly
supplied to Docker Compose. A credential-safe, authenticated smoke connection
through `ws://127.0.0.1:8200/api/asr/stream` reached `ready` from Alibaba Qwen
and then cancelled without sending audio. The proxy and both backend health
endpoints were healthy.

## Android device

- Device: SM F9660, Android 16 / API 36, arm64.
- Installed artifact:
  `mobile/build/app/outputs/flutter-apk/app-debug.apk`.
- ADB reverse: `tcp:8200` to `tcp:8200`.
- Package launched: `com.eureka.mindapp`.
- Visual check: the newly built login screen is visible; the removed legacy
  floating Reka is absent.
- Device radios and network settings were not changed.

## Manual spoken acceptance still required

The fresh install is currently at the login screen, and speaking cannot be
simulated honestly. After signing in, verify these items with real speech:

1. Session start/stop leaves editable final text.
2. Session to report to Skill switches targets without restarting the App.
3. Session to Reka slide-up cancel to Session remains reusable.
4. Leaving a connecting/listening page allows another field to start.
5. A real network/provider interruption restores the exact original text and
   typing remains usable.

Different-user isolation and deliberately stalled first-user behavior are
covered deterministically in the backend gateway suite; no second physical
login was created because the product allows one device per account.
