// Three tinted status pills (paid / in progress / canceled). Selected = solid
// tint + white; otherwise tint text on a faint tint wash.
import { useRef } from "react";
import type { EntryStatus } from "../../domain/types";
import { STATUS_ORDER, statusTitle } from "../../domain/types";
import { readableForeground, STATUS_COLOR, STATUS_TEXT_COLOR } from "../theme/theme";
import { StatusIcon } from "../icons";

export function StatusPicker({
  value,
  onChange,
}: {
  value: EntryStatus;
  onChange: (s: EntryStatus) => void;
}) {
  const refs = useRef<Array<HTMLButtonElement | null>>([]);

  function move(from: number, delta: number) {
    const next = (from + delta + STATUS_ORDER.length) % STATUS_ORDER.length;
    onChange(STATUS_ORDER[next]);
    requestAnimationFrame(() => refs.current[next]?.focus());
  }

  return (
    <div className="status-picker" role="radiogroup" aria-label="Status">
      {STATUS_ORDER.map((s) => {
        const selected = s === value;
        return (
          <button
            key={s}
            ref={(node) => {
              refs.current[STATUS_ORDER.indexOf(s)] = node;
            }}
            type="button"
            role="radio"
            aria-checked={selected}
            tabIndex={selected ? 0 : -1}
            className={"status-picker__opt" + (selected ? " is-selected" : "")}
            style={
              {
                ["--st" as string]: STATUS_COLOR[s],
                ["--st-text" as string]: STATUS_TEXT_COLOR[s],
                ["--st-on" as string]: readableForeground(STATUS_COLOR[s]),
              } as React.CSSProperties
            }
            onClick={() => onChange(s)}
            onKeyDown={(event) => {
              const index = STATUS_ORDER.indexOf(s);
              if (event.key === "ArrowRight" || event.key === "ArrowDown") {
                event.preventDefault();
                move(index, 1);
              } else if (event.key === "ArrowLeft" || event.key === "ArrowUp") {
                event.preventDefault();
                move(index, -1);
              }
            }}
          >
            <StatusIcon status={s} size={15} />
            <span>{statusTitle(s)}</span>
          </button>
        );
      })}
    </div>
  );
}
