import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { Field, Select } from "./Field";

describe("Field", () => {
  it("associates generated labels with native inputs", () => {
    render(
      <Field label="Project">
        <input />
      </Field>,
    );

    expect(screen.getByLabelText("Project")).toHaveAttribute("id");
  });

  it("associates generated labels with the styled native select", () => {
    render(
      <Field label="Currency">
        <Select defaultValue="USD">
          <option value="USD">USD</option>
          <option value="RUB">RUB</option>
        </Select>
      </Field>,
    );

    expect(screen.getByRole("combobox", { name: "Currency" })).toHaveValue("USD");
  });
});
