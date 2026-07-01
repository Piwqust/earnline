// Create a client — name + color palette, with duplicate/empty validation.
// The web-native replacement for NewClientSheet (a centered dialog, not a sheet).
import { useState } from "react";
import type { Client } from "../domain/types";
import { Limits, capped, clientNameMessage, validateClientName } from "../domain/validation";
import { createClient } from "../data/repository";
import { queueSync } from "../state/store";
import { CLIENT_PALETTE, paletteColor } from "./theme/theme";
import { Dialog } from "./components/Dialog";
import { Field } from "./components/Field";
import { Swatches } from "./components/Swatches";

export function NewClientDialog({
  existingClients,
  onClose,
  onCreated,
}: {
  existingClients: Client[];
  onClose: () => void;
  onCreated?: (client: Client) => void;
}) {
  const [name, setName] = useState("");
  const [colorHex, setColorHex] = useState(paletteColor(existingClients.length));
  const validation = validateClientName(
    name,
    existingClients.map((c) => c.name),
  );
  const valid = validation.kind === "valid";

  async function create() {
    if (validation.kind !== "valid") return;
    const client = await createClient({
      name: validation.name,
      colorHex,
      sortIndex: existingClients.length,
    });
    queueSync();
    onCreated?.(client);
    onClose();
  }

  return (
    <Dialog
      title="New client"
      onClose={onClose}
      footer={
        <>
          <button type="button" className="btn btn--secondary btn--md" onClick={onClose}>
            <span>Cancel</span>
          </button>
          <button
            type="button"
            className="btn btn--primary btn--md"
            disabled={!valid}
            onClick={() => void create()}
          >
            <span>Add client</span>
          </button>
        </>
      }
    >
      <div className="form-stack">
        <Field label="Name">
          <div className="name-field">
            <span className="name-field__dot" style={{ background: colorHex }} />
            <input
              className="input"
              data-autofocus
              placeholder="Client name"
              value={name}
              onChange={(e) => setName(capped(e.target.value, Limits.maxClientNameLength))}
              onKeyDown={(e) => {
                if (e.key === "Enter" && valid) void create();
              }}
            />
          </div>
          {!valid && name !== "" && <p className="field__error">{clientNameMessage(validation)}</p>}
        </Field>
        <Field label="Color">
          <Swatches colors={CLIENT_PALETTE} value={colorHex} onChange={setColorHex} />
        </Field>
      </div>
    </Dialog>
  );
}
