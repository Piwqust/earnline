// Create a client — name + color palette, with duplicate/empty validation.
// The web-native replacement for NewClientSheet (a centered dialog, not a sheet).
import { useId, useState } from "react";
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
  const [isCreating, setIsCreating] = useState(false);
  const [createError, setCreateError] = useState<string | null>(null);
  const nameId = useId();
  const nameErrorId = useId();
  const validation = validateClientName(
    name,
    existingClients.map((c) => c.name),
  );
  const valid = validation.kind === "valid";

  async function create() {
    if (validation.kind !== "valid") return;
    setIsCreating(true);
    setCreateError(null);
    try {
      const client = await createClient({
        name: validation.name,
        colorHex,
        sortIndex: existingClients.length,
      });
      queueSync();
      onCreated?.(client);
      onClose();
    } catch {
      setCreateError("The client could not be added. Your name is still here.");
    } finally {
      setIsCreating(false);
    }
  }

  return (
    <Dialog
      title="New client"
      onClose={onClose}
      footer={
        <>
          <button type="button" className="btn btn--secondary btn--md" disabled={isCreating} onClick={onClose}>
            <span>Cancel</span>
          </button>
          <button
            type="button"
            className="btn btn--primary btn--md"
            disabled={!valid || isCreating}
            onClick={() => void create()}
          >
            <span>{isCreating ? "Adding…" : "Add client"}</span>
          </button>
        </>
      }
    >
      <div className="form-stack">
        <Field label="Name" htmlFor={nameId}>
          <div className="name-field">
            <span className="name-field__dot" style={{ background: colorHex }} />
            <input
              id={nameId}
              className="input"
              data-autofocus
              placeholder="Client name"
              value={name}
              required
              aria-invalid={name !== "" && !valid}
              aria-describedby={name !== "" && !valid ? nameErrorId : undefined}
              onChange={(e) => {
                setName(capped(e.target.value, Limits.maxClientNameLength));
                setCreateError(null);
              }}
              onKeyDown={(e) => {
                if (e.key === "Enter" && valid) void create();
              }}
            />
          </div>
          {!valid && name !== "" && (
            <p id={nameErrorId} className="field__error" role="alert">
              {clientNameMessage(validation)}
            </p>
          )}
        </Field>
        <Field label="Color">
          <Swatches colors={CLIENT_PALETTE} value={colorHex} onChange={setColorHex} />
        </Field>
        {createError && (
          <p className="field__error" role="alert">
            {createError}
          </p>
        )}
      </div>
    </Dialog>
  );
}
