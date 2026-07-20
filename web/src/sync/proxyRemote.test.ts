import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { ProxyRemote } from "./proxyRemote";

const { getSession } = vi.hoisted(() => ({ getSession: vi.fn() }));
vi.mock("./supabaseClient", () => ({
  configuredSupabase: () => ({ auth: { getSession } }),
}));

afterEach(() => vi.unstubAllGlobals());
beforeEach(() => {
  getSession.mockClear();
  getSession.mockResolvedValue({ data: { session: { access_token: "test-access-token" } } });
});

describe("secure proxy transport", () => {
  it("sends the Supabase bearer token and accepts an opaque scope", async () => {
    const fetchMock = vi.fn(async (_url: string, init?: RequestInit) => {
      expect(init?.headers).toMatchObject({ authorization: "Bearer test-access-token" });
      expect(JSON.parse(String(init?.body))).toEqual({ action: "validate" });
      return new Response(JSON.stringify({ data: { scope: "opaque-workspace-scope", transport: "proxy" } }), {
        status: 200, headers: { "content-type": "application/json" },
      });
    });
    vi.stubGlobal("fetch", fetchMock);
    const remote = new ProxyRemote("https://sync.example.test");
    await expect(remote.validate()).resolves.toMatchObject({
      scope: expect.stringMatching(/^[a-f0-9]{32}$/),
      transport: "proxy",
    });
  });

  it("binds the local database scope to the validated endpoint", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => new Response(JSON.stringify({
      data: { scope: "same-opaque-workspace-scope", transport: "proxy" },
    }), { status: 200, headers: { "content-type": "application/json" } })));
    const first = await new ProxyRemote("https://one.example.test/sync").validate();
    const repeat = await new ProxyRemote("https://one.example.test/sync/").validate();
    const second = await new ProxyRemote("https://two.example.test/sync").validate();
    expect(first.scope).toBe(repeat.scope);
    expect(first.scope).not.toBe(second.scope);
  });

  it("does not expose server error details for rejected sessions", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => new Response(JSON.stringify({ error: "sensitive detail" }), {
      status: 401, headers: { "content-type": "application/json" },
    })));
    const remote = new ProxyRemote("https://sync.example.test");
    await expect(remote.validate()).rejects.toThrow("not authorized");
    await expect(remote.validate()).rejects.not.toThrow("sensitive detail");
  });

  it("coalesces concurrent row reads into one Edge Function invocation", async () => {
    const fetchMock = vi.fn(async (_url: string, init?: RequestInit) => {
      const body = JSON.parse(String(init?.body)) as { action: string; requests: Array<{ action: string; table: string }> };
      expect(body.action).toBe("batch");
      expect(body.requests.map((request) => request.table)).toEqual([
        "earnline_clients",
        "earnline_headings",
        "earnline_entries",
      ]);
      return new Response(JSON.stringify({ data: [[], [], []] }), {
        status: 200, headers: { "content-type": "application/json" },
      });
    });
    vi.stubGlobal("fetch", fetchMock);
    const remote = new ProxyRemote("https://sync.example.test");
    await Promise.all([
      remote.fetchPage("earnline_clients", "updated_at", null, 0, 1000),
      remote.fetchPage("earnline_headings", "updated_at", null, 0, 1000),
      remote.fetchPage("earnline_entries", "updated_at", null, 0, 1000),
    ]);
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(getSession).toHaveBeenCalledTimes(1);
  });
});
