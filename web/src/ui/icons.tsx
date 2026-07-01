// Minimal inline SVG icons mirroring the SF Symbols used on iOS.
import type { EntryStatus } from "../domain/types";
import { STATUS_COLOR } from "./theme/theme";

type IconProps = { size?: number; className?: string; strokeWidth?: number };

function svgProps(size: number, className?: string) {
  return {
    width: size,
    height: size,
    viewBox: "0 0 24 24",
    fill: "none",
    xmlns: "http://www.w3.org/2000/svg",
    className,
    "aria-hidden": true,
  } as const;
}

export function PlusIcon({ size = 16, className, strokeWidth = 2 }: IconProps) {
  return (
    <svg {...svgProps(size, className)}>
      <path d="M12 5v14M5 12h14" stroke="currentColor" strokeWidth={strokeWidth} strokeLinecap="round" />
    </svg>
  );
}

export function ChevronDownIcon({ size = 12, className, strokeWidth = 2.2 }: IconProps) {
  return (
    <svg {...svgProps(size, className)}>
      <path d="M6 9l6 6 6-6" stroke="currentColor" strokeWidth={strokeWidth} strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

export function ArrowUpIcon({ size = 16, className, strokeWidth = 2.4 }: IconProps) {
  return (
    <svg {...svgProps(size, className)}>
      <path d="M12 19V5M6 11l6-6 6 6" stroke="currentColor" strokeWidth={strokeWidth} strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

export function ReturnIcon({ size = 12, className, strokeWidth = 2 }: IconProps) {
  return (
    <svg {...svgProps(size, className)}>
      <path d="M4 7v4a3 3 0 003 3h11M14 10l4 4-4 4" stroke="currentColor" strokeWidth={strokeWidth} strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

export function CalendarIcon({ size = 14, className, strokeWidth = 1.8 }: IconProps) {
  return (
    <svg {...svgProps(size, className)}>
      <rect x="3.5" y="5" width="17" height="15" rx="3" stroke="currentColor" strokeWidth={strokeWidth} />
      <path d="M3.5 9.5h17M8 3.5v3M16 3.5v3" stroke="currentColor" strokeWidth={strokeWidth} strokeLinecap="round" />
    </svg>
  );
}

export function GearIcon({ size = 18, className, strokeWidth = 1.7 }: IconProps) {
  return (
    <svg {...svgProps(size, className)}>
      <circle cx="12" cy="12" r="3.2" stroke="currentColor" strokeWidth={strokeWidth} />
      <path
        d="M12 2.8v2.4M12 18.8v2.4M21.2 12h-2.4M5.2 12H2.8M18.5 5.5l-1.7 1.7M7.2 16.8l-1.7 1.7M18.5 18.5l-1.7-1.7M7.2 7.2L5.5 5.5"
        stroke="currentColor"
        strokeWidth={strokeWidth}
        strokeLinecap="round"
      />
    </svg>
  );
}

export function TrashIcon({ size = 16, className, strokeWidth = 1.8 }: IconProps) {
  return (
    <svg {...svgProps(size, className)}>
      <path
        d="M4 7h16M9 7V5a2 2 0 012-2h2a2 2 0 012 2v2M6 7l1 13a2 2 0 002 2h6a2 2 0 002-2l1-13"
        stroke="currentColor"
        strokeWidth={strokeWidth}
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

export function PencilIcon({ size = 16, className, strokeWidth = 1.8 }: IconProps) {
  return (
    <svg {...svgProps(size, className)}>
      <path
        d="M4 20h4L18.5 9.5a2.1 2.1 0 00-3-3L5 17v3z"
        stroke="currentColor"
        strokeWidth={strokeWidth}
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

export function PersonPlusIcon({ size = 16, className, strokeWidth = 1.8 }: IconProps) {
  return (
    <svg {...svgProps(size, className)}>
      <circle cx="9" cy="8" r="3.4" stroke="currentColor" strokeWidth={strokeWidth} />
      <path d="M3.5 20a5.5 5.5 0 0111 0M17 8v6M14 11h6" stroke="currentColor" strokeWidth={strokeWidth} strokeLinecap="round" />
    </svg>
  );
}

export function HeadingIcon({ size = 16, className, strokeWidth = 1.8 }: IconProps) {
  return (
    <svg {...svgProps(size, className)}>
      <path d="M4 6h16M4 11h16M4 16h10" stroke="currentColor" strokeWidth={strokeWidth} strokeLinecap="round" />
    </svg>
  );
}

export function DollarIcon({ size = 16, className, strokeWidth = 1.8 }: IconProps) {
  return (
    <svg {...svgProps(size, className)}>
      <path
        d="M12 3v18M16 7.5C16 5.6 14.2 4.5 12 4.5S8 5.6 8 7.5s1.8 2.6 4 3.2 4 1.3 4 3.3-1.8 3-4 3-4-1.1-4-3"
        stroke="currentColor"
        strokeWidth={strokeWidth}
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

export function CloseIcon({ size = 18, className, strokeWidth = 2 }: IconProps) {
  return (
    <svg {...svgProps(size, className)}>
      <path d="M6 6l12 12M18 6L6 18" stroke="currentColor" strokeWidth={strokeWidth} strokeLinecap="round" />
    </svg>
  );
}

export function BackIcon({ size = 20, className, strokeWidth = 2 }: IconProps) {
  return (
    <svg {...svgProps(size, className)}>
      <path d="M15 5l-7 7 7 7" stroke="currentColor" strokeWidth={strokeWidth} strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

export function ReceiptIcon({ size = 16, className, strokeWidth = 1.8 }: IconProps) {
  return (
    <svg {...svgProps(size, className)}>
      <path
        d="M6 3h12v17l-2.5-1.6L13 20l-2.5-1.6L8 20l-2-1.6V3z"
        stroke="currentColor"
        strokeWidth={strokeWidth}
        strokeLinejoin="round"
      />
      <path d="M9 8h6M9 12h4" stroke="currentColor" strokeWidth={strokeWidth} strokeLinecap="round" />
    </svg>
  );
}

export function UsersIcon({ size = 16, className, strokeWidth = 1.8 }: IconProps) {
  return (
    <svg {...svgProps(size, className)}>
      <circle cx="9" cy="8" r="3.2" stroke="currentColor" strokeWidth={strokeWidth} />
      <path d="M3.5 19.5a5.5 5.5 0 0111 0" stroke="currentColor" strokeWidth={strokeWidth} strokeLinecap="round" />
      <path
        d="M16 5.3a3.2 3.2 0 010 5.4M16.8 14.8a5.2 5.2 0 013.7 4.7"
        stroke="currentColor"
        strokeWidth={strokeWidth}
        strokeLinecap="round"
      />
    </svg>
  );
}

export function SyncIcon({ size = 16, className, strokeWidth = 1.8 }: IconProps) {
  return (
    <svg {...svgProps(size, className)}>
      <path d="M3.5 12a8.5 8.5 0 0114.9-5.5" stroke="currentColor" strokeWidth={strokeWidth} strokeLinecap="round" />
      <path d="M18.6 3.6v3.4h-3.4" stroke="currentColor" strokeWidth={strokeWidth} strokeLinecap="round" strokeLinejoin="round" />
      <path d="M20.5 12a8.5 8.5 0 01-14.9 5.5" stroke="currentColor" strokeWidth={strokeWidth} strokeLinecap="round" />
      <path d="M5.4 20.4V17h3.4" stroke="currentColor" strokeWidth={strokeWidth} strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

export function ChevronRightIcon({ size = 14, className, strokeWidth = 2 }: IconProps) {
  return (
    <svg {...svgProps(size, className)}>
      <path d="M9 5l7 7-7 7" stroke="currentColor" strokeWidth={strokeWidth} strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

export function PanelRightIcon({ size = 18, className, strokeWidth = 1.8 }: IconProps) {
  return (
    <svg {...svgProps(size, className)}>
      <rect x="3.5" y="5" width="17" height="14" rx="2.6" stroke="currentColor" strokeWidth={strokeWidth} />
      <path d="M14.5 5v14" stroke="currentColor" strokeWidth={strokeWidth} />
    </svg>
  );
}

export function SearchIcon({ size = 16, className, strokeWidth = 1.9 }: IconProps) {
  return (
    <svg {...svgProps(size, className)}>
      <circle cx="11" cy="11" r="6.5" stroke="currentColor" strokeWidth={strokeWidth} />
      <path d="M16 16l4 4" stroke="currentColor" strokeWidth={strokeWidth} strokeLinecap="round" />
    </svg>
  );
}

export function MoreIcon({ size = 18, className }: IconProps) {
  return (
    <svg {...svgProps(size, className)}>
      <circle cx="5" cy="12" r="1.6" fill="currentColor" />
      <circle cx="12" cy="12" r="1.6" fill="currentColor" />
      <circle cx="19" cy="12" r="1.6" fill="currentColor" />
    </svg>
  );
}

export function MenuIcon({ size = 20, className, strokeWidth = 2 }: IconProps) {
  return (
    <svg {...svgProps(size, className)}>
      <path d="M4 7h16M4 12h16M4 17h16" stroke="currentColor" strokeWidth={strokeWidth} strokeLinecap="round" />
    </svg>
  );
}

/** Filled status dot (checkmark / clock / xmark), tinted by status. */
export function StatusIcon({ status, size = 16 }: { status: EntryStatus; size?: number }) {
  const color = STATUS_COLOR[status];
  return (
    <svg {...svgProps(size)}>
      <circle cx="12" cy="12" r="9" fill={color} />
      {status === "paid" && (
        <path d="M8 12.3l2.6 2.6L16 9.5" stroke="#fff" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" />
      )}
      {status === "inProgress" && (
        <path d="M12 7.6V12l3 1.8" stroke="#fff" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" />
      )}
      {status === "canceled" && (
        <path d="M9 9l6 6M15 9l-6 6" stroke="#fff" strokeWidth={2} strokeLinecap="round" />
      )}
    </svg>
  );
}
