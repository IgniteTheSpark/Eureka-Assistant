import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { RingClient } from "./ring-client";

const jsonResponse = (body: unknown) =>
  new Response(JSON.stringify(body), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });

class FakeEventSource {
  static instances: FakeEventSource[] = [];
  readonly listeners = new Map<string, EventListener[]>();
  onopen: ((event: Event) => void) | null = null;
  closed = false;

  constructor(readonly url: string) {
    FakeEventSource.instances.push(this);
  }

  addEventListener(type: string, listener: EventListener) {
    this.listeners.set(type, [...(this.listeners.get(type) ?? []), listener]);
  }

  emit(type: string, data: unknown) {
    const event = new MessageEvent(type, { data: JSON.stringify(data) });
    for (const listener of this.listeners.get(type) ?? []) listener(event);
  }

  close() {
    this.closed = true;
  }
}

describe("RingClient", () => {
  const fetchMock = vi.fn<typeof fetch>();

  beforeEach(() => {
    FakeEventSource.instances = [];
    vi.stubGlobal("fetch", fetchMock);
    vi.stubGlobal("EventSource", FakeEventSource);
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    fetchMock.mockReset();
  });

  it("uses the localhost connection control endpoints", async () => {
    fetchMock.mockResolvedValue(jsonResponse({ ok: true }));
    const client = new RingClient("http://127.0.0.1:17863/");

    await client.getConnection();
    await client.scan();
    await client.connect({ address: "ring-id", name: "BCL60392D5" });
    await client.disconnect();

    expect(fetchMock.mock.calls.map(([url]) => url)).toEqual([
      "http://127.0.0.1:17863/connection",
      "http://127.0.0.1:17863/connection/scan",
      "http://127.0.0.1:17863/connection/connect",
      "http://127.0.0.1:17863/connection/disconnect",
    ]);
    expect(fetchMock.mock.calls[2]?.[1]).toEqual(
      expect.objectContaining({
        method: "POST",
        body: JSON.stringify({ address: "ring-id", name: "BCL60392D5" }),
      }),
    );
  });

  it("sends the browser session to every lease command", async () => {
    fetchMock.mockResolvedValue(jsonResponse({ mode: "idle" }));
    const client = new RingClient("http://127.0.0.1:17863");

    await client.acquire("tab-1");
    await client.setMode("tab-1", "flash");
    await client.heartbeat("tab-1");
    await client.release("tab-1");

    expect(fetchMock.mock.calls.map(([url, init]) => [url, init?.body])).toEqual([
      ["http://127.0.0.1:17863/demo/session", JSON.stringify({ sessionId: "tab-1" })],
      [
        "http://127.0.0.1:17863/demo/mode",
        JSON.stringify({ sessionId: "tab-1", mode: "flash" }),
      ],
      ["http://127.0.0.1:17863/demo/heartbeat", JSON.stringify({ sessionId: "tab-1" })],
      ["http://127.0.0.1:17863/demo/release", JSON.stringify({ sessionId: "tab-1" })],
    ]);
  });

  it("uses native EventSource reconnection and parses named ring events", () => {
    const client = new RingClient("http://127.0.0.1:17863");
    const onEvent = vi.fn();
    const onReconnect = vi.fn();

    const unsubscribe = client.subscribe(onEvent, onReconnect);
    const source = FakeEventSource.instances[0];
    source?.onopen?.(new Event("open"));
    source?.emit("connection.changed", { connected: true });

    expect(source?.url).toBe("http://127.0.0.1:17863/demo/events");
    expect(onReconnect).toHaveBeenCalledOnce();
    expect(onEvent).toHaveBeenCalledWith({
      event: "connection.changed",
      data: { connected: true },
    });

    unsubscribe();
    expect(source?.closed).toBe(true);
  });
});
