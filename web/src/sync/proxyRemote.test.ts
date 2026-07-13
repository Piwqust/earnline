import { afterEach, describe, expect, it, vi } from "vitest";
import { ProxyRemote } from "./proxyRemote";

afterEach(() => vi.unstubAllGlobals());

describe("secure proxy transport", () => {
  it("sends the capability only in a dedicated header and accepts opaque scope", async () => {
    const fetchMock = vi.fn(async (_url: string, init?: RequestInit) => {
      expect(init?.headers).toMatchObject({ "x-earnline-capability": "x".repeat(32) });
      expect(JSON.parse(String(init?.body))).toEqual({ action: "validate" });
      return new Response(JSON.stringify({ data: { scope: "opaque-workspace-scope", transport: "proxy" } }), {
        status: 200, headers: { "content-type": "application/json" },
      });
    });
    vi.stubGlobal("fetch", fetchMock);
    const remote = new ProxyRemote("https://sync.example.test", "x".repeat(32));
    await expect(remote.validate()).resolves.toMatchObject({
      scope: expect.stringMatching(/^[a-f0-9]{32}$/),
      transport: "proxy",
    });
  });

  it("binds the local database scope to the validated endpoint", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => new Response(JSON.stringify({
      data: { scope: "same-opaque-workspace-scope", transport: "proxy" },
    }), { status: 200, headers: { "content-type": "application/json" } })));
    const first = await new ProxyRemote("https://one.example.test/sync", "x".repeat(32)).validate();
    const repeat = await new ProxyRemote("https://one.example.test/sync/", "x".repeat(32)).validate();
    const second = await new ProxyRemote("https://two.example.test/sync", "x".repeat(32)).validate();
    expect(first.scope).toBe(repeat.scope);
    expect(first.scope).not.toBe(second.scope);
  });

  it("does not expose server error details for rejected capabilities", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => new Response(JSON.stringify({ error: "sensitive detail" }), {
      status: 401, headers: { "content-type": "application/json" },
    })));
    const remote = new ProxyRemote("https://sync.example.test", "x".repeat(32));
    await expect(remote.validate()).rejects.toThrow("connection code was rejected");
    await expect(remote.validate()).rejects.not.toThrow("sensitive detail");
  });
});
