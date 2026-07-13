// Centered modal dialog — used sparingly (new client, headings, confirm).
import { useId, useRef, useState, type ReactNode } from "react";
import { createPortal } from "react-dom";
import { IconButton } from "./Button";
import { useOverlay } from "./useOverlay";
import { CloseIcon } from "../icons";

export function Dialog({
  title,
  description,
  onClose,
  footer,
  size = "md",
  children,
}: {
  title: string;
  description?: ReactNode;
  onClose: () => void;
  footer?: ReactNode;
  size?: "sm" | "md";
  children: ReactNode;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const titleId = useId();
  const descriptionId = useId();
  useOverlay(onClose, ref);

  return createPortal(
    <div className="scrim" onMouseDown={onClose}>
      <div
        ref={ref}
        className={`dialog dialog--${size}`}
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
        aria-describedby={description ? descriptionId : undefined}
        tabIndex={-1}
        onMouseDown={(e) => e.stopPropagation()}
      >
        <header className="dialog__head">
          <h2 id={titleId} className="dialog__title">
            {title}
          </h2>
          <IconButton label="Close" onClick={onClose}>
            <CloseIcon size={18} />
          </IconButton>
        </header>
        {description && (
          <p id={descriptionId} className="dialog__desc">
            {description}
          </p>
        )}
        <div className="dialog__body">{children}</div>
        {footer && <footer className="dialog__foot">{footer}</footer>}
      </div>
    </div>,
    document.body,
  );
}

// Lightweight confirm built on Dialog — replaces window.confirm.
export function ConfirmDialog({
  title,
  message,
  confirmLabel = "Delete",
  destructive = true,
  onConfirm,
  onClose,
}: {
  title: string;
  message: ReactNode;
  confirmLabel?: string;
  destructive?: boolean;
  onConfirm: () => void | Promise<void>;
  onClose: () => void;
}) {
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function confirm() {
    setPending(true);
    setError(null);
    try {
      await onConfirm();
      onClose();
    } catch {
      setError("The change could not be completed. Try again.");
    } finally {
      setPending(false);
    }
  }

  return (
    <Dialog
      title={title}
      size="sm"
      onClose={onClose}
      footer={
        <>
          <button type="button" className="btn btn--secondary btn--md" disabled={pending} onClick={onClose}>
            <span>Cancel</span>
          </button>
          <button
            type="button"
            data-autofocus
            className={`btn ${destructive ? "btn--danger" : "btn--primary"} btn--md`}
            disabled={pending}
            onClick={() => void confirm()}
          >
            <span>{pending ? "Working…" : confirmLabel}</span>
          </button>
        </>
      }
    >
      <p className="dialog__message">{message}</p>
      {error && (
        <p className="field__error" role="alert">
          {error}
        </p>
      )}
    </Dialog>
  );
}
