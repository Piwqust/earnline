// A client group header in the ledger: colored tag (→ detail) + rolled-up total
// + an inline "+ Line" that targets the composer at this client.
import type { Client } from "../domain/types";
import { MoneyAmountText } from "./MoneyAmountText";
import { ClientTag } from "./components/ClientTag";
import { PlusIcon } from "./icons";

export function ClientChip({
  client,
  total,
  onOpen,
  onAdd,
  unsupportedCount = 0,
}: {
  client: Client;
  total: number;
  onOpen: () => void;
  onAdd: () => void;
  unsupportedCount?: number;
}) {
  return (
    <div className="client-group__head">
      <ClientTag name={client.name} color={client.colorHex} size="md" onClick={onOpen} />
      <MoneyAmountText baseAmount={total} className="client-group__total tabular" />
      {unsupportedCount > 0 && (
        <span className="client-group__incomplete" title="Unsupported currencies are excluded from this total">
          incomplete
        </span>
      )}
      <span className="u-spacer" />
      <button type="button" className="client-group__add" onClick={onAdd} aria-label={`Add a line for ${client.name}`}>
        <PlusIcon size={15} />
        <span>Line</span>
      </button>
    </div>
  );
}
