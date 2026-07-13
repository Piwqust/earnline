import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { AppShell } from "./AppShell";

vi.mock("../../state/data", () => ({
  useClients: () => [],
  useEntries: () => [],
}));

vi.mock("../../state/settings", () => ({
  useSettings: () => ({
    theme: "light",
    baseCurrencyCode: "USD",
    secondaryCurrencyCode: "RUB",
    rate: 83,
  }),
  setSettings: vi.fn(),
  currencySettings: (settings: unknown) => settings,
}));

vi.mock("../../state/store", () => ({
  useSyncStatus: () => ({ isSyncing: false, message: "Local only", error: null }),
}));

function installNarrowViewport() {
  Object.defineProperty(window, "matchMedia", {
    configurable: true,
    value: vi.fn().mockImplementation((query: string) => ({
      matches: query === "(max-width: 859px)",
      media: query,
      onchange: null,
      addEventListener: vi.fn(),
      removeEventListener: vi.fn(),
      addListener: vi.fn(),
      removeListener: vi.fn(),
      dispatchEvent: vi.fn(),
    })),
  });
  Object.defineProperty(HTMLElement.prototype, "offsetWidth", { configurable: true, get: () => 10 });
  Object.defineProperty(HTMLElement.prototype, "offsetHeight", { configurable: true, get: () => 10 });
}

function renderShell() {
  return render(
    <MemoryRouter
      initialEntries={["/"]}
      future={{ v7_startTransition: true, v7_relativeSplatPath: true }}
    >
      <Routes>
        <Route element={<AppShell />}>
          <Route index element={<h1>Ledger content</h1>} />
        </Route>
      </Routes>
    </MemoryRouter>,
  );
}

describe("AppShell mobile navigation", () => {
  beforeEach(() => installNarrowViewport());

  it("keeps the closed drawer inert and restores focus after Escape", async () => {
    const user = userEvent.setup();
    renderShell();

    const sidebar = document.getElementById("primary-sidebar") as HTMLElement;
    const main = document.getElementById("main-content") as HTMLElement;
    const openButton = screen.getByRole("button", { name: "Open navigation" });

    await waitFor(() => expect(sidebar.inert).toBe(true));
    expect(sidebar).toHaveAttribute("aria-hidden", "true");
    expect(document.querySelector(".shell__scrim")).not.toBeInTheDocument();

    await user.click(openButton);

    await waitFor(() => expect(sidebar).toHaveAttribute("role", "dialog"));
    expect(sidebar).toHaveAttribute("aria-modal", "true");
    expect(sidebar).not.toHaveAttribute("aria-hidden");
    expect(sidebar.inert).toBe(false);
    expect(main.inert).toBe(true);
    expect(sidebar.contains(document.activeElement)).toBe(true);
    expect(screen.getByRole("button", { name: "Close navigation" })).toBeInTheDocument();
    expect(document.querySelector(".shell__scrim")).toHaveAttribute("aria-hidden", "true");

    await user.keyboard("{Escape}");

    await waitFor(() => expect(sidebar).toHaveAttribute("aria-hidden", "true"));
    expect(sidebar.inert).toBe(true);
    expect(main.inert).toBe(false);
    expect(document.querySelector(".shell__scrim")).not.toBeInTheDocument();
    await waitFor(() => expect(openButton).toHaveFocus());
  });
});
