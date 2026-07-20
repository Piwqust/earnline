// Labeled field wrapper + a styled native <select>. Plain inputs use the
// `.input` / `.textarea` classes directly.
import {
  cloneElement,
  isValidElement,
  useId,
  type ReactElement,
  type ReactNode,
  type SelectHTMLAttributes,
} from "react";
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
  const generatedId = useId();
  const controlId = htmlFor ?? generatedId;
  const canReceiveId =
    isValidElement(children) &&
    (children.type === "input" || children.type === "textarea" || children.type === "select" || children.type === Select);
  const control = canReceiveId
    ? cloneElement(children as ReactElement<{ id?: string }>, { id: children.props.id ?? controlId })
    : children;
  const labelIsForControl = htmlFor != null || canReceiveId;

  return (
    <div className="field">
      {label && labelIsForControl && (
        <label className="field__label" htmlFor={controlId}>
          {label}
        </label>
      )}
      {label && !labelIsForControl && <span className="field__label">{label}</span>}
      {control}
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
