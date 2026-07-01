// A small tinted status pill (icon + label) for read-only contexts.
import type { EntryStatus } from "../../domain/types";
import { statusTitle } from "../../domain/types";
import { STATUS_COLOR } from "../theme/theme";
import { StatusIcon } from "../icons";

export function StatusBadge({ status, size = "md" }: { status: EntryStatus; size?: "sm" | "md" }) {
  return (
    <span
      className={`status-badge status-badge--${size}`}
      style={{ ["--st" as string]: STATUS_COLOR[status] } as React.CSSProperties}
    >
      <StatusIcon status={status} size={size === "sm" ? 12 : 14} />
      <span>{statusTitle(status)}</span>
    </span>
  );
}
