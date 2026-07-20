import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import type { Entry } from "../domain/types";
import { EntryRow } from "./EntryRow";

vi.mock("../state/settings", () => ({
  useSettings: () => ({
    theme: "light",
    baseCurrencyCode: "USD",
    secondaryCurrencyCode: "RUB",
    rate: 83,
  }),
  currencySettings: (settings: unknown) => settings,
}));

const entry: Entry = {
  id: "entry-1",
  clientId: "client-1",
  amountCents: 24000,
  currencyCode: "USD",
  project: "Acme",
  task: "Test task",
  date: Date.UTC(2026, 6, 12),
  holdUntil: null,
  status: "paid",
  sortIndex: 0,
  createdAt: 1,
  syncState: "synced",
};

describe("EntryRow", () => {
  it("uses a native row button with Enter and Space behavior and no nested controls", async () => {
    const user = userEvent.setup();
    const onEdit = vi.fn();
    const { container } = render(
      <EntryRow entry={entry} onSetStatus={vi.fn()} onEdit={onEdit} onDelete={vi.fn()} />,
    );
    const rowButton = screen.getByRole("button", { name: /^Edit Acme: Test task,/ });

    expect(rowButton.tagName).toBe("BUTTON");
    expect(rowButton.querySelector("button")).toBeNull();
    expect(container.querySelector('[role="button"]')).toBeNull();

    rowButton.focus();
    await user.keyboard(" ");
    expect(onEdit).toHaveBeenCalledTimes(1);

    onEdit.mockClear();
    rowButton.focus();
    await user.keyboard("{Enter}");
    expect(onEdit).toHaveBeenCalledTimes(1);
  });
});
