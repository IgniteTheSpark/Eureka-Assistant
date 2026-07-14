import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { ApiError, BackendClient } from "./backend-client";

const jsonResponse = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

describe("BackendClient", () => {
  const fetchMock = vi.fn<typeof fetch>();

  beforeEach(() => {
    vi.stubGlobal("fetch", fetchMock);
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    fetchMock.mockReset();
  });

  it.each(["login", "register"] as const)(
    "posts credentials to the %s endpoint",
    async (action) => {
      fetchMock.mockResolvedValue(
        jsonResponse({ ok: true, token: "jwt", user: { id: "1", email: "a@b.co" } }),
      );
      const client = new BackendClient("http://localhost:8000", () => null);

      await client[action]("a@b.co", "secret1");

      expect(fetchMock).toHaveBeenCalledWith(
        `http://localhost:8000/api/auth/${action}`,
        expect.objectContaining({
          method: "POST",
          body: JSON.stringify({ email: "a@b.co", password: "secret1" }),
        }),
      );
    },
  );

  it("authenticates the current-user request", async () => {
    fetchMock.mockResolvedValue(
      jsonResponse({ ok: true, user: { id: "1", email: "a@b.co" } }),
    );
    const client = new BackendClient("http://localhost:8000/", () => "jwt");

    await client.me();

    expect(fetchMock).toHaveBeenCalledWith(
      "http://localhost:8000/api/auth/me",
      expect.objectContaining({
        headers: expect.objectContaining({ Authorization: "Bearer jwt" }),
      }),
    );
  });

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

  it("throws a status-aware error for non-JSON API failures", async () => {
    fetchMock.mockResolvedValue(new Response("bad gateway", { status: 502 }));
    const client = new BackendClient("http://localhost:8000", () => null);

    const error = await client.login("a@b.co", "secret1").catch((reason) => reason);
    expect(error).toBeInstanceOf(ApiError);
    expect(error).toMatchObject({ status: 502, body: {} });
  });
});
