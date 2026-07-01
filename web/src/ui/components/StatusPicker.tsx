// Three tinted status pills (paid / in progress / canceled). Selected = solid
// tint + white; otherwise tint text on a faint tint wash.
import type { EntryStatus } from "../../domain/types";
import { STATUS_ORDER, statusTitle } from "../../domain/types";
import { STATUS_COLOR } from "../theme/theme";
import { StatusIcon } from "../icons";

export function StatusPicker({
  value,
  onChange,
}: {
  value: EntryStatus;
  onChange: (s: EntryStatus) => void;
}) {
  return (
    <div className="status-picker" role="radiogroup" aria-label="Status">
      {STATUS_ORDER.map((s) => {
        const selected = s === value;
        return (
          <button
            key={s}
            type="button"
            role="radio"
            aria-checked={selected}
            className={"status-picker__opt" + (selected ? " is-selected" : "")}
            style={{ ["--st" as string]: STATUS_COLOR[s] } as React.CSSProperties}
            onClick={() => onChange(s)}
          >
            <StatusIcon status={s} size={15} />
            <span>{statusTitle(s)}</span>
          </button>
        );
      })}
    </div>
  );
}
