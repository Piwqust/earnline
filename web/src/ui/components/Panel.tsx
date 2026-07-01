// Right slide-in inspector panel — the web-native replacement for bottom sheets.
// Non-blocking-feeling editor that keeps the ledger visible behind a light scrim.
import { useRef, type ReactNode } from "react";
import { createPortal } from "react-dom";
import { IconButton } from "./Button";
import { useOverlay } from "./useOverlay";
import { CloseIcon } from "../icons";

export function Panel({
  title,
  subtitle,
  onClose,
  footer,
  children,
}: {
  title: string;
  subtitle?: ReactNode;
  onClose: () => void;
  footer?: ReactNode;
  children: ReactNode;
}) {
  const ref = useRef<HTMLElement>(null);
  useOverlay(onClose, ref);

  return createPortal(
    <div className="panel-scrim" onMouseDown={onClose}>
      <aside
        ref={ref}
        className="panel"
        role="dialog"
        aria-modal="true"
        aria-label={title}
        tabIndex={-1}
        onMouseDown={(e) => e.stopPropagation()}
      >
        <header className="panel__head">
          <div className="panel__heading">
            <h2 className="panel__title">{title}</h2>
            {subtitle && <p className="panel__subtitle">{subtitle}</p>}
          </div>
          <IconButton label="Close" onClick={onClose}>
            <CloseIcon size={18} />
          </IconButton>
        </header>
        <div className="panel__body">{children}</div>
        {footer && <footer className="panel__foot">{footer}</footer>}
      </aside>
    </div>,
    document.body,
  );
}
