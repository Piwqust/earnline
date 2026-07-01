// Labeled field wrapper + a styled native <select>. Plain inputs use the
// `.input` / `.textarea` classes directly.
import { useId, type ReactNode, type SelectHTMLAttributes } from "react";
import { ChevronDownIcon } from "../icons";

export function Field({
  label,
  hint,
  htmlFor,
  children,
}: {
  label?: ReactNode;
  hint?: ReactNode;
  htmlFor?: string;
  children: ReactNode;
}) {
  return (
    <div className="field">
      {label && (
        <label className="field__label" htmlFor={htmlFor}>
          {label}
        </label>
      )}
      {children}
      {hint && <p className="field__hint">{hint}</p>}
    </div>
  );
}

export function Select({
  className,
  children,
  ...rest
}: SelectHTMLAttributes<HTMLSelectElement>) {
  const id = useId();
  return (
    <span className={"select-wrap" + (className ? " " + className : "")}>
      <select id={id} className="select" {...rest}>
        {children}
      </select>
      <span className="select__chev" aria-hidden>
        <ChevronDownIcon size={13} />
      </span>
    </span>
  );
}
