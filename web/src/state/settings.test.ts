import { beforeEach, describe, expect, it, vi } from "vitest";

describe("settings — workspace profile dirty tracking", () => {
  beforeEach(() => {
    const values = new Map<string, string>();
    vi.stubGlobal("localStorage", {
      getItem: (key: string) => values.get(key) ?? null,
      setItem: (key: string, value: string) => values.set(key, value),
      removeItem: (key: string) => values.delete(key),
      clear: () => values.clear(),
      key: (index: number) => [...values.keys()][index] ?? null,
      get length() { return values.size; },
    });
    vi.resetModules();
  });

  it("queues local currency edits but accepts a pulled profile as clean", async () => {
    const { getSettings, setSettings } = await import("./settings");

    expect(getSettings().profileNeedsSync).toBe(false);
    setSettings({ rate: 89.125 });
    expect(getSettings().profileNeedsSync).toBe(true);

    setSettings({
      baseCurrencyCode: "EUR",
      secondaryCurrencyCode: "GBP",
      rate: 0.86,
      profileNeedsSync: false,
    });
    expect(getSettings()).toMatchObject({
      baseCurrencyCode: "EUR",
      secondaryCurrencyCode: "GBP",
      rate: 0.86,
      profileNeedsSync: false,
    });
  });

  it("keeps connection edits as a draft until explicit apply", async () => {
    const { connectionDraft, getSettings, isSyncConfigured } = await import("./settings");
    const draft = connectionDraft();
    draft.endpoint = "https://sync.example.test";
    draft.capability = "a".repeat(48);
    expect(getSettings().syncEndpoint).toBe("");
    expect(isSyncConfigured()).toBe(false);
  });

  it("requires a validated opaque scope before enabling sync", async () => {
    const { getSettings, isSyncConfigured, setSettings } = await import("./settings");
    setSettings({ syncMode: "proxy", syncEndpoint: "https://sync.example.test", syncCapability: "a".repeat(48) });
    expect(isSyncConfigured()).toBe(false);
    setSettings({ connectionScope: "a".repeat(32) });
    expect(isSyncConfigured(getSettings())).toBe(true);
  });

  it("invalidates validation when live connection fields change", async () => {
    const { getSettings, isSyncConfigured, setSettings } = await import("./settings");
    setSettings({
      syncMode: "proxy",
      syncEndpoint: "https://sync.example.test",
      syncCapability: "a".repeat(48),
      connectionScope: "b".repeat(32),
    });
    expect(isSyncConfigured()).toBe(true);
    setSettings({ syncEndpoint: "https://other.example.test" });
    expect(getSettings().connectionScope).toBe("");
    expect(isSyncConfigured()).toBe(false);
  });

  it("rejects endpoint credentials even after an opaque scope was supplied", async () => {
    const { getSettings, isSyncConfigured, setSettings } = await import("./settings");
    setSettings({
      syncMode: "proxy",
      syncEndpoint: "https://user:secret@sync.example.test",
      syncCapability: "a".repeat(48),
      connectionScope: "b".repeat(32),
    });
    expect(isSyncConfigured(getSettings())).toBe(false);
  });

  it("surfaces localStorage persistence failures", async () => {
    const { getSettingsPersistenceError, setSettings } = await import("./settings");
    localStorage.setItem = () => { throw new Error("quota"); };
    expect(setSettings({ theme: "dark" })).toBe(false);
    expect(getSettingsPersistenceError()).toContain("could not be saved");
  });

  it("surfaces settings load failures instead of silently resetting", async () => {
    localStorage.getItem = () => { throw new Error("blocked"); };
    const { getSettingsPersistenceError } = await import("./settings");
    expect(getSettingsPersistenceError()).toContain("could not be loaded");
  });
});
