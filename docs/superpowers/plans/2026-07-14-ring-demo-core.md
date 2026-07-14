# Ring Demo Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the local Ring Demo website and connect a real ring to mutually exclusive Flash and Vibe flows using the existing Eureka Backend and Ring Desktop.

**Architecture:** A new React/Vite client owns presentation, JWT, and calls to `/api/flash`; Ring Desktop remains the only BLE/audio/ASR/gesture owner and exposes a localhost Demo Session API plus SSE events. A lease and generation-stamped capture context prevent stale Flash/Vibe results from crossing modes.

**Tech Stack:** Python 3, Ring Desktop (rumps/Bleak/PyObjC), stdlib HTTP/SSE, React 18, TypeScript 5, Vite 5, Vitest, existing FastAPI/MySQL Backend.

## Global Constraints

- macOS only; do not add Windows behavior.
- Reuse `backend/`, its JWT API, MySQL schema, `/api/flash`, Skills, Sessions, Assets, Contacts, and Events.
- Do not add a Demo database or place LLM/ASR secrets in the browser bundle.
- Flash and Vibe are mutually exclusive; stale ASR results must be dropped by Session ID and Generation.
- Vibe supports only `com.openai.codex` and `com.alibaba.DingTalkMac` in the first Demo.
- Do not use long-press or present failure vibration.
- Preserve Ring Desktop standalone behavior when no Demo lease is active.
- Use simple React/CSS transitions; no shader, 3D engine, or heavy motion dependency.

---

## File Structure

### Ring Desktop

- Create `ring-desktop/ring_desktop/demo_session.py`: pure thread-safe Demo lease, mode, generation, capture context, and event broker.
- Create `ring-desktop/tests/test_demo_session.py`: deterministic mode/lease/generation tests.
- Modify `ring-desktop/ring_desktop/control_api.py`: Demo REST endpoints, SSE, CORS, and OPTIONS.
- Modify `ring-desktop/tests/test_control_api.py`: API and SSE contract tests.
- Modify `ring-desktop/ring_desktop/app.py`: route gestures/captures through Demo state and publish UI events.
- Expand `ring-desktop/tests/test_app.py`: pure routing/status regressions.

### Demo Web

- Create `ring-demo/package.json`, TypeScript/Vite configs, and `index.html`: standalone web workspace.
- Create `ring-demo/src/main.tsx` and `ring-demo/src/app/App.tsx`: root and routes.
- Create `ring-demo/src/styles.css`: visual system and simple animations.
- Create `ring-demo/src/lib/types.ts`: shared wire types.
- Create `ring-demo/src/lib/ring-client.ts`: localhost Ring REST/SSE client.
- Create `ring-demo/src/lib/backend-client.ts`: JWT auth and Flash API client.
- Create `ring-demo/src/state/demo-store.tsx`: Demo Session lifecycle and shared state.
- Create `ring-demo/src/components/RingConnection.tsx`: scan/connect/disconnect UI.
- Create `ring-demo/src/components/AssetCard.tsx`: known-card and generic fallback renderer.
- Create `ring-demo/src/pages/HomePage.tsx`, `SetupPage.tsx`, `FlashPage.tsx`, `VibePage.tsx`.
- Create focused `ring-demo/src/**/*.test.ts(x)` tests next to each unit.

### Documentation

- Modify `README.md`: add Ring Demo development entry after the core flow works.

---

### Task 1: Ring Desktop Demo Session State Machine

**Files:**
- Create: `ring-desktop/ring_desktop/demo_session.py`
- Create: `ring-desktop/tests/test_demo_session.py`

**Interfaces:**
- Produces: `DemoMode`, `CaptureContext`, `DemoEventBroker`, `DemoSessionController`.
- `DemoSessionController.acquire(session_id: str) -> dict`
- `DemoSessionController.heartbeat(session_id: str) -> bool`
- `DemoSessionController.set_mode(session_id: str, mode: DemoMode) -> dict`
- `DemoSessionController.release(session_id: str) -> bool`
- `DemoSessionController.tick() -> bool`
- `DemoSessionController.capture_context() -> CaptureContext`
- `DemoSessionController.accept_capture(context: CaptureContext) -> bool`
- `DemoSessionController.snapshot() -> dict`

- [ ] **Step 1: Write failing state-machine tests**

```python
from ring_desktop.demo_session import DemoMode, DemoSessionController


def test_mode_change_invalidates_capture():
    now = [10.0]
    controller = DemoSessionController(now=lambda: now[0], lease_seconds=5)
    controller.acquire("browser-1")
    controller.set_mode("browser-1", DemoMode.FLASH)
    capture = controller.capture_context()
    controller.set_mode("browser-1", DemoMode.VIBE)
    assert controller.accept_capture(capture) is False


def test_expired_lease_restores_standalone():
    now = [10.0]
    controller = DemoSessionController(now=lambda: now[0], lease_seconds=5)
    controller.acquire("browser-1")
    controller.set_mode("browser-1", DemoMode.FLASH)
    now[0] = 16.0
    assert controller.tick() is True
    assert controller.snapshot()["mode"] == "standalone"
```

- [ ] **Step 2: Run the tests and verify they fail**

Run: `cd ring-desktop && pytest -q tests/test_demo_session.py`  
Expected: FAIL because `ring_desktop.demo_session` does not exist.

- [ ] **Step 3: Implement the pure state machine and event broker**

```python
class DemoMode(str, Enum):
    STANDALONE = "standalone"
    IDLE = "idle"
    FLASH = "flash"
    VIBE = "vibe"


@dataclass(frozen=True)
class CaptureContext:
    session_id: str | None
    mode: DemoMode
    generation: int


class DemoEventBroker:
    def subscribe(self) -> queue.Queue:
        subscriber = queue.Queue(maxsize=64)
        with self._lock:
            self._subscribers.add(subscriber)
        return subscriber

    def publish(self, event: str, payload: dict) -> None:
        message = {"event": event, "data": payload}
        with self._lock:
            subscribers = tuple(self._subscribers)
        for subscriber in subscribers:
            try:
                subscriber.put_nowait(message)
            except queue.Full:
                subscriber.get_nowait()
                subscriber.put_nowait(message)


class DemoSessionController:
    def accept_capture(self, context: CaptureContext) -> bool:
        with self._lock:
            self._expire_locked()
            return context == self._capture_context_locked()
```

Use one `threading.RLock`, increment `generation` on acquire, mode change, release, and expiry, reject blank Session IDs, and publish `mode.changed` after state changes.

- [ ] **Step 4: Run state-machine tests**

Run: `cd ring-desktop && pytest -q tests/test_demo_session.py`  
Expected: PASS for acquire, heartbeat, mode validation, generation invalidation, release, expiry, event delivery, and snapshot serialization.

- [ ] **Step 5: Commit**

```bash
git add ring-desktop/ring_desktop/demo_session.py ring-desktop/tests/test_demo_session.py
git commit -m "feat(desktop): add demo mode state machine"
```

### Task 2: Local Demo REST and SSE API

**Files:**
- Modify: `ring-desktop/ring_desktop/control_api.py`
- Modify: `ring-desktop/tests/test_control_api.py`

**Interfaces:**
- Consumes: `DemoSessionController` and `DemoEventBroker` from Task 1.
- Produces: `/demo/status`, `/demo/session`, `/demo/heartbeat`, `/demo/mode`, `/demo/release`, `/demo/events`.
- Preserves: existing vibration, event, and connection endpoints.

- [ ] **Step 1: Write failing endpoint tests**

```python
def test_demo_mode_endpoint_updates_controller():
    controller = DemoSessionController(lease_seconds=30)
    server = VibrationControlServer(
        lambda _kind: True,
        demo_controller=controller,
        demo_events=controller.events,
        port=0,
    ).start()
    try:
        assert post(server, {"sessionId": "browser-1"}, "/demo/session")[0] == 200
        status, body = post(
            server,
            {"sessionId": "browser-1", "mode": "flash"},
            "/demo/mode",
        )
    finally:
        server.stop()
    assert status == 200
    assert body["mode"] == "flash"


def test_options_returns_local_cors_headers():
    request = Request(
        f"http://127.0.0.1:{server.port}/demo/status",
        method="OPTIONS",
        headers={"Origin": "http://localhost:5173"},
    )
    with urlopen(request, timeout=2) as response:
        assert response.headers["Access-Control-Allow-Origin"] == "http://localhost:5173"
```

- [ ] **Step 2: Run the API tests and verify they fail**

Run: `cd ring-desktop && pytest -q tests/test_control_api.py`  
Expected: FAIL because constructor arguments and Demo routes are missing.

- [ ] **Step 3: Add Demo routes, JSON validation, CORS, and SSE**

```python
ALLOWED_ORIGINS = {"http://localhost:5173", "http://127.0.0.1:5173"}


def _cors_origin(self) -> str | None:
    origin = self.headers.get("Origin")
    return origin if origin in ALLOWED_ORIGINS else None


def _handle_demo_mode(self):
    body = self._read_json()
    try:
        snapshot = demo_controller.set_mode(
            body.get("sessionId", ""), DemoMode(body.get("mode", ""))
        )
    except (KeyError, ValueError):
        self._json(409, {"ok": False, "error": "invalid demo session or mode"})
        return
    self._json(200, {"ok": True, **snapshot})
```

For `/demo/events`, subscribe to the broker, emit an initial `snapshot` event, write `event:` plus JSON `data:` frames, send a comment heartbeat every 10 seconds, unsubscribe on disconnect, and never bind beyond `127.0.0.1`.

- [ ] **Step 4: Run API and full Ring Desktop tests**

Run: `cd ring-desktop && pytest -q tests/test_control_api.py`  
Expected: PASS.  
Run: `cd ring-desktop && pytest -q`  
Expected: existing tests plus Demo tests PASS.

- [ ] **Step 5: Commit**

```bash
git add ring-desktop/ring_desktop/control_api.py ring-desktop/tests/test_control_api.py
git commit -m "feat(desktop): expose local demo control API"
```

### Task 3: Route Real Ring Capture Through Flash or Vibe

**Files:**
- Modify: `ring-desktop/ring_desktop/app.py`
- Modify: `ring-desktop/tests/test_app.py`

**Interfaces:**
- Consumes: Demo controller/API from Tasks 1–2.
- Produces: `recording.started`, `recording.stopped`, `asr.started`, `transcript.ready`, `active_app.changed`, and `mapping.changed` events.
- `transcript.ready.data` contains `sessionId`, `generation`, `text`, and `mode="flash"`.

- [ ] **Step 1: Write failing pure routing tests**

```python
def test_flash_forces_double_tap_voice_without_app_mapping():
    action = app.resolve_demo_action(
        mode="flash", bundle="com.apple.Safari", gesture="double", config={}
    )
    assert action == {"type": "voice"}


def test_vibe_rejects_unsupported_frontmost_app():
    action = app.resolve_demo_action(
        mode="vibe",
        bundle="com.apple.Safari",
        gesture="triple",
        config={"default": {"triple": {"type": "key", "value": "enter"}}},
    )
    assert action is None
```

- [ ] **Step 2: Run app tests and verify they fail**

Run: `cd ring-desktop && pytest -q tests/test_app.py`  
Expected: FAIL because `resolve_demo_action` is missing.

- [ ] **Step 3: Implement routing and stamped transcription**

```python
VIBE_BUNDLES = {"com.openai.codex", "com.alibaba.DingTalkMac"}


def resolve_demo_action(mode: str, bundle: str | None, gesture: str, config: dict):
    if mode == DemoMode.IDLE.value:
        return None
    if mode == DemoMode.FLASH.value:
        return {"type": "voice"} if gesture == "double" else None
    if mode == DemoMode.VIBE.value:
        if bundle not in VIBE_BUNDLES:
            return None
        return resolve_action(config, bundle, gesture)
    return resolve_action(config, bundle, gesture)
```

When recording starts, store `self._capture_context = self._demo.capture_context()`. Pass that immutable context with the ADPCM payload into the transcription thread. Before injection or publish, call `accept_capture(context)`:

```python
if not self._demo.accept_capture(context):
    log.info("discarding stale transcript generation=%s", context.generation)
    return
if context.mode is DemoMode.FLASH:
    self._demo.events.publish("transcript.ready", {
        "sessionId": context.session_id,
        "generation": context.generation,
        "mode": "flash",
        "text": text,
    })
elif context.mode in {DemoMode.VIBE, DemoMode.STANDALONE}:
    type_text(text)
```

Publish connection changes from `_on_status`; publish active App/mapping changes only when the cached bundle changes; call `self._demo.tick()` from `_refresh`; wire controller/events into `VibrationControlServer`.

- [ ] **Step 4: Run all Ring Desktop tests**

Run: `cd ring-desktop && pytest -q`  
Expected: PASS with standalone regression, Flash routing, Vibe allowlist, stale capture, and events covered.

- [ ] **Step 5: Commit**

```bash
git add ring-desktop/ring_desktop/app.py ring-desktop/tests/test_app.py
git commit -m "feat(desktop): isolate flash and vibe capture routing"
```

### Task 4: Scaffold the Demo Web and Home Page

**Files:**
- Create: `ring-demo/package.json`
- Create: `ring-demo/tsconfig.json`
- Create: `ring-demo/tsconfig.node.json`
- Create: `ring-demo/vite.config.ts`
- Create: `ring-demo/index.html`
- Create: `ring-demo/src/main.tsx`
- Create: `ring-demo/src/app/App.tsx`
- Create: `ring-demo/src/pages/HomePage.tsx`
- Create: `ring-demo/src/styles.css`
- Create: `ring-demo/src/pages/HomePage.test.tsx`

**Interfaces:**
- Produces routes `/`, `/setup`, `/flash`, `/vibe`.
- Home produces links labelled `Explore Flash` and `Explore Vibe`.

- [ ] **Step 1: Create package/config files and a failing Home test**

Use scripts `dev`, `build`, `test`, and `typecheck`. Dependencies are React, React DOM, and React Router; dev dependencies are Vite, TypeScript, Vitest, jsdom, and Testing Library.

```tsx
it("offers two large demo entries", () => {
  render(<MemoryRouter><HomePage /></MemoryRouter>);
  expect(screen.getByRole("link", { name: /explore flash/i })).toHaveAttribute("href", "/flash");
  expect(screen.getByRole("link", { name: /explore vibe/i })).toHaveAttribute("href", "/vibe");
});
```

- [ ] **Step 2: Install and verify the test fails**

Run: `cd ring-demo && npm install`  
Expected: dependencies install and `package-lock.json` is created.  
Run: `cd ring-demo && npm test -- --run`  
Expected: FAIL because `HomePage` is not implemented.

- [ ] **Step 3: Implement routes, Banner, Demo Blocks, and CSS transitions**

```tsx
export function HomePage() {
  return <main className="home">
    <section className="hero" aria-labelledby="hero-title">
      <p className="eyebrow">EUREKA RING</p>
      <h1 id="hero-title">Intelligence, within reach.</h1>
      <p>Speak an idea. Move through your tools. Feel the result.</p>
      <div className="ring-placeholder" aria-label="Ring product visual placeholder" />
    </section>
    <section className="mode-grid" aria-label="Ring demos">
      <ModeCard to="/flash" title="Flash Mode" cta="Explore Flash" />
      <ModeCard to="/vibe" title="Vibe Mode" cta="Explore Vibe" />
    </section>
  </main>;
}
```

Use one responsive column below 840px, two columns above it, visible keyboard focus, `prefers-reduced-motion`, and 180–300ms opacity/transform transitions.

- [ ] **Step 4: Verify tests and production build**

Run: `cd ring-demo && npm test -- --run && npm run typecheck && npm run build`  
Expected: PASS and `dist/` is generated.

- [ ] **Step 5: Commit**

```bash
git add ring-demo
git commit -m "feat(demo): add ring showcase home"
```

### Task 5: Add Auth, Ring Clients, and Shared Demo Session

**Files:**
- Create: `ring-demo/src/lib/types.ts`
- Create: `ring-demo/src/lib/backend-client.ts`
- Create: `ring-demo/src/lib/ring-client.ts`
- Create: `ring-demo/src/state/demo-store.tsx`
- Create: `ring-demo/src/pages/SetupPage.tsx`
- Create: `ring-demo/src/components/RingConnection.tsx`
- Create: colocated tests for each unit.

**Interfaces:**
- `BackendClient.login(email, password)`, `register`, `me`, `flash`.
- `RingClient.getConnection`, `scan`, `connect`, `disconnect`, `acquire`, `setMode`, `heartbeat`, `release`, `subscribe`.
- `useDemo()` exposes `{sessionId, ringStatus, connection, mode, activeApp, mapping, events, setMode}`.

- [ ] **Step 1: Write failing client and store tests**

```ts
it("sends voice transcript to the existing flash endpoint", async () => {
  fetchMock.mockResolvedValue(jsonResponse({ ok: true, cards: [] }));
  const client = new BackendClient("http://localhost:8000", () => "jwt");
  await client.flash("记一下产品想法");
  expect(fetchMock).toHaveBeenCalledWith(
    "http://localhost:8000/api/flash",
    expect.objectContaining({
      headers: expect.objectContaining({ Authorization: "Bearer jwt" }),
      body: JSON.stringify({ text: "记一下产品想法", source: "voice" }),
    }),
  );
});
```

- [ ] **Step 2: Run and verify failures**

Run: `cd ring-demo && npm test -- --run`  
Expected: FAIL because clients/store do not exist.

- [ ] **Step 3: Implement exact wire types and lifecycle**

```ts
export type DemoMode = "idle" | "flash" | "vibe";
export type RingEvent = {
  event: string;
  data: Record<string, unknown>;
};

export async function requestJson<T>(url: string, init?: RequestInit): Promise<T> {
  const response = await fetch(url, init);
  const body = await response.json().catch(() => ({}));
  if (!response.ok) throw new ApiError(response.status, body);
  return body as T;
}
```

Create one UUID per browser tab using `sessionStorage`, acquire on provider mount, heartbeat every 3 seconds, release with `sendBeacon`/best-effort fetch on unload, reconnect EventSource with browser defaults, and refresh `/demo/status` after SSE reconnect. Store JWT in `localStorage`; invalid/absent JWT redirects to `/setup` without putting credentials in source or env.

- [ ] **Step 4: Verify tests, types, and build**

Run: `cd ring-demo && npm test -- --run && npm run typecheck && npm run build`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ring-demo/src
git commit -m "feat(demo): connect auth and local ring session"
```

### Task 6: Complete Flash Mode End-to-End

**Files:**
- Create: `ring-demo/src/pages/FlashPage.tsx`
- Create: `ring-demo/src/pages/FlashPage.test.tsx`
- Create: `ring-demo/src/components/AssetCard.tsx`
- Create: `ring-demo/src/components/AssetCard.test.tsx`
- Modify: `ring-demo/src/styles.css`

**Interfaces:**
- Consumes `transcript.ready` events only when `mode=flash`, Session ID matches, and Generation equals the current snapshot.
- Calls `BackendClient.flash(text)` exactly once per accepted transcript.
- Renders `cards`; falls back to `derived_assets`; falls back again to a “随记” card when both are empty but `summary/reply` exists.

- [ ] **Step 1: Write failing state and rendering tests**

```tsx
it("submits one matching transcript and reveals returned cards", async () => {
  backend.flash.mockResolvedValue({
    ok: true,
    summary: "已记录 2 项",
    cards: [
      { card_type: "todo", content: "准备展会" },
      { card_type: "idea", content: "做一个戒指 Demo" },
    ],
  });
  render(<FlashPage />, { wrapper: demoWrapper("flash") });
  emitRingEvent("transcript.ready", matchingTranscript("帮我准备展会"));
  expect(await screen.findByText("准备展会")).toBeVisible();
  expect(backend.flash).toHaveBeenCalledTimes(1);
});
```

- [ ] **Step 2: Run and verify failures**

Run: `cd ring-demo && npm test -- --run src/pages/FlashPage.test.tsx src/components/AssetCard.test.tsx`  
Expected: FAIL because components do not exist.

- [ ] **Step 3: Implement the Flash reducer and page**

```ts
type FlashPhase = "disconnected" | "ready" | "listening" |
  "transcribing" | "processing" | "revealed";

type FlashState = {
  phase: FlashPhase;
  transcript: string;
  result: FlashResponse | null;
  error: string | null;
};
```

Map Ring events to phases, retain transcript on backend failure, provide a low-priority retry action, and never vibrate on error. Render known titles/fields for todo, idea, event, contact, expense, and note; every unknown shape goes through one generic renderer using `display_name`, `title`, `content`, or serialized non-secret payload fields.

- [ ] **Step 4: Verify Flash tests and build**

Run: `cd ring-demo && npm test -- --run && npm run typecheck && npm run build`  
Expected: PASS, including stale transcript rejection, duplicate event dedupe, empty ASR, backend retry, multi-card stagger classes, and generic fallback.

- [ ] **Step 5: Commit**

```bash
git add ring-demo/src
git commit -m "feat(demo): run flash pipeline from ring voice"
```

### Task 7: Complete Vibe Mode Status and App Mapping

**Files:**
- Create: `ring-demo/src/pages/VibePage.tsx`
- Create: `ring-demo/src/pages/VibePage.test.tsx`
- Modify: `ring-demo/src/styles.css`

**Interfaces:**
- Consumes `active_app.changed` and `mapping.changed`.
- Displays only Codex and DingTalk profiles; it never sends App content or business actions.

- [ ] **Step 1: Write failing Vibe tests**

```tsx
it("shows the active Codex profile", () => {
  render(<VibePage />, {
    wrapper: demoWrapper("vibe", {
      activeApp: "com.openai.codex",
      mapping: { double: "Voice", triple: "Enter", up: "Scroll up", down: "Scroll down" },
    }),
  });
  expect(screen.getByText("Codex active")).toBeVisible();
  expect(screen.getByText("Voice")).toBeVisible();
});
```

- [ ] **Step 2: Run and verify failure**

Run: `cd ring-demo && npm test -- --run src/pages/VibePage.test.tsx`  
Expected: FAIL because `VibePage` does not exist.

- [ ] **Step 3: Implement the Vibe page**

```tsx
const APP_PROFILES = {
  "com.openai.codex": { name: "Codex", state: "Codex active" },
  "com.alibaba.DingTalkMac": { name: "DingTalk", state: "DingTalk active" },
} as const;
```

Show connection status, both supported profiles, the current active profile, and serialized gesture labels. For any other Bundle ID, show “Open Codex or DingTalk to activate Ring controls.” Do not add send/success/failure state to the page.

- [ ] **Step 4: Verify all Web tests and build**

Run: `cd ring-demo && npm test -- --run && npm run typecheck && npm run build`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ring-demo/src
git commit -m "feat(demo): show live vibe app mappings"
```

### Task 8: Core Integration Verification and Documentation

**Files:**
- Modify: `README.md`
- Modify: `ring-desktop/README.md`

**Interfaces:**
- Documents the exact four-process local run: MySQL, Backend, Ring Desktop, Demo Web.
- Produces a reproducible real-ring checklist; exhibition reset remains in the separate operations plan.

- [ ] **Step 1: Add exact local run instructions**

Document:

```bash
docker compose up -d db
docker compose run --rm backend alembic upgrade head
docker compose run --rm backend python -m db.seed
docker compose up -d backend

cd ring-desktop
source .venv/bin/activate
python -m ring_desktop.app

cd ring-demo
npm install
npm run dev
```

Include first-time macOS Bluetooth/Accessibility permission, local Demo login, and `http://localhost:5173`.

- [ ] **Step 2: Run the complete automated verification**

Run: `cd ring-desktop && pytest -q`  
Expected: all tests PASS.  
Run: `cd ring-demo && npm test -- --run && npm run typecheck && npm run build`  
Expected: all tests PASS and Vite build succeeds.  
Run: `docker compose config`  
Expected: exit 0.

- [ ] **Step 3: Run the real-ring smoke test**

Verify in order: connect BCL ring; Flash double-tap start/stop; transcript appears; `/api/flash` returns real assets; existing UReka account shows them; return home; enter Vibe; Codex mapping works; DingTalk mapping works; switch during ASR and confirm no cross-mode result; close browser and confirm lease restores standalone.

- [ ] **Step 4: Commit**

```bash
git add README.md ring-desktop/README.md
git commit -m "docs(demo): document core local demo flow"
```
