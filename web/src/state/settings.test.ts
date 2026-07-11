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
});
