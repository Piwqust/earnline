// Button + IconButton — the workhorse web-native controls.
import type { ButtonHTMLAttributes, ReactNode } from "react";

type Variant = "primary" | "secondary" | "ghost" | "danger";
type Size = "sm" | "md" | "lg";

export function Button({
  variant = "secondary",
  size = "md",
  full,
  leading,
  trailing,
  className,
  children,
  ...rest
}: {
  variant?: Variant;
  size?: Size;
  full?: boolean;
  leading?: ReactNode;
  trailing?: ReactNode;
} & ButtonHTMLAttributes<HTMLButtonElement>) {
  return (
    <button
      type="button"
      className={
        `btn btn--${variant} btn--${size}` + (full ? " btn--full" : "") + (className ? " " + className : "")
      }
      {...rest}
    >
      {leading && <span className="btn__icon">{leading}</span>}
      {children != null && <span>{children}</span>}
      {trailing && <span className="btn__icon">{trailing}</span>}
    </button>
  );
}

export function IconButton({
  label,
  variant = "ghost",
  size = "md",
  className,
  children,
  ...rest
}: {
  label: string;
  variant?: "ghost" | "secondary" | "danger";
  size?: Size;
} & ButtonHTMLAttributes<HTMLButtonElement>) {
  return (
    <button
      type="button"
      aria-label={label}
      title={label}
      className={`icon-btn icon-btn--${variant} icon-btn--${size}` + (className ? " " + className : "")}
      {...rest}
    >
      {children}
    </button>
  );
}
