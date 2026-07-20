// Button + IconButton — the workhorse web-native controls.
import { forwardRef, type ButtonHTMLAttributes, type ReactNode } from "react";

type Variant = "primary" | "secondary" | "ghost" | "danger";
type Size = "sm" | "md" | "lg";

export const Button = forwardRef<
  HTMLButtonElement,
  {
    variant?: Variant;
    size?: Size;
    full?: boolean;
    leading?: ReactNode;
    trailing?: ReactNode;
  } & ButtonHTMLAttributes<HTMLButtonElement>
>(function Button(
  { variant = "secondary", size = "md", full, leading, trailing, className, children, ...rest },
  ref,
) {
  return (
    <button
      ref={ref}
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
});

export const IconButton = forwardRef<
  HTMLButtonElement,
  {
    label: string;
    variant?: "ghost" | "secondary" | "danger";
    size?: Size;
  } & ButtonHTMLAttributes<HTMLButtonElement>
>(function IconButton({ label, variant = "ghost", size = "md", className, children, ...rest }, ref) {
  return (
    <button
      ref={ref}
      type="button"
      aria-label={label}
      title={label}
      className={`icon-btn icon-btn--${variant} icon-btn--${size}` + (className ? " " + className : "")}
      {...rest}
    >
      {children}
    </button>
  );
});
