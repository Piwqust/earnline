// Anchored dropdown menu — the web-native replacement for the iOS-style Menu.
// Renders into a portal with fixed positioning (so it never clips inside the
// scrolling ledger), flips near viewport edges, and supports keyboard nav.
import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
  type ReactNode,
} from "react";
import { createPortal } from "react-dom";

type Align = "left" | "right";
type Vertical = "down" | "up";

const DropdownCtx = createContext<{ close: () => void }>({ close: () => {} });

export function Dropdown({
  trigger,
  children,
  align = "right",
  vertical = "down",
  triggerClassName,
  ariaLabel,
  disabled,
}: {
  trigger: ReactNode;
  children: ReactNode;
  align?: Align;
  vertical?: Vertical;
  triggerClassName?: string;
  ariaLabel?: string;
  disabled?: boolean;
}) {
  const [open, setOpen] = useState(false);
  const triggerRef = useRef<HTMLButtonElement>(null);
  const menuRef = useRef<HTMLDivElement>(null);
  const [pos, setPos] = useState<{ top: number; left: number } | null>(null);

  const place = useCallback(() => {
    const t = triggerRef.current;
    const m = menuRef.current;
    if (!t || !m) return;
    const r = t.getBoundingClientRect();
    const mw = m.offsetWidth;
    const mh = m.offsetHeight;
    const gap = 6;
    const pad = 8;

    let top = vertical === "down" ? r.bottom + gap : r.top - gap - mh;
    if (vertical === "down" && top + mh > window.innerHeight - pad && r.top - gap - mh > pad) {
      top = r.top - gap - mh;
    } else if (vertical === "up" && top < pad && r.bottom + gap + mh < window.innerHeight - pad) {
      top = r.bottom + gap;
    }

    let left = align === "left" ? r.left : r.right - mw;
    left = Math.max(pad, Math.min(left, window.innerWidth - mw - pad));
    top = Math.max(pad, Math.min(top, window.innerHeight - mh - pad));
    setPos({ top, left });
  }, [align, vertical]);

  useLayoutEffect(() => {
    if (!open) return;
    place();
    const id = requestAnimationFrame(place);
    return () => cancelAnimationFrame(id);
  }, [open, place]);

  useEffect(() => {
    if (!open) return;
    const onDown = (e: MouseEvent) => {
      const target = e.target as Node;
      if (menuRef.current?.contains(target) || triggerRef.current?.contains(target)) return;
      setOpen(false);
    };
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        setOpen(false);
        triggerRef.current?.focus();
      }
    };
    const onReflow = () => setOpen(false);
    window.addEventListener("mousedown", onDown);
    window.addEventListener("keydown", onKey);
    window.addEventListener("scroll", onReflow, true);
    window.addEventListener("resize", onReflow);
    return () => {
      window.removeEventListener("mousedown", onDown);
      window.removeEventListener("keydown", onKey);
      window.removeEventListener("scroll", onReflow, true);
      window.removeEventListener("resize", onReflow);
    };
  }, [open]);

  // Roving focus inside the open menu.
  useEffect(() => {
    if (!open || !pos) return;
    const m = menuRef.current;
    if (!m) return;
    const items = () => Array.from(m.querySelectorAll<HTMLElement>('[role="menuitem"]:not([disabled])'));
    items()[0]?.focus({ preventScroll: true });
    const onKey = (e: KeyboardEvent) => {
      const list = items();
      if (!list.length) return;
      const idx = list.indexOf(document.activeElement as HTMLElement);
      if (e.key === "ArrowDown") {
        e.preventDefault();
        list[(idx + 1) % list.length]?.focus();
      } else if (e.key === "ArrowUp") {
        e.preventDefault();
        list[(idx - 1 + list.length) % list.length]?.focus();
      } else if (e.key === "Home") {
        e.preventDefault();
        list[0]?.focus();
      } else if (e.key === "End") {
        e.preventDefault();
        list[list.length - 1]?.focus();
      }
    };
    m.addEventListener("keydown", onKey);
    return () => m.removeEventListener("keydown", onKey);
  }, [open, pos]);

  return (
    <>
      <button
        ref={triggerRef}
        type="button"
        className={triggerClassName}
        aria-label={ariaLabel}
        aria-haspopup="menu"
        aria-expanded={open}
        disabled={disabled}
        onClick={(e) => {
          e.stopPropagation();
          setOpen((o) => !o);
        }}
      >
        {trigger}
      </button>
      {open &&
        createPortal(
          <DropdownCtx.Provider value={{ close: () => setOpen(false) }}>
            <div
              ref={menuRef}
              className="dropdown"
              role="menu"
              style={{
                position: "fixed",
                top: pos?.top ?? -9999,
                left: pos?.left ?? -9999,
                visibility: pos ? "visible" : "hidden",
              }}
              onClick={(e) => e.stopPropagation()}
            >
              {children}
            </div>
          </DropdownCtx.Provider>,
          document.body,
        )}
    </>
  );
}

export function DropdownItem({
  children,
  onClick,
  destructive,
  disabled,
}: {
  children: ReactNode;
  onClick: () => void;
  destructive?: boolean;
  disabled?: boolean;
}) {
  const { close } = useContext(DropdownCtx);
  return (
    <button
      type="button"
      role="menuitem"
      disabled={disabled}
      className={"dropdown__item" + (destructive ? " is-destructive" : "")}
      onClick={() => {
        onClick();
        close();
      }}
    >
      {children}
    </button>
  );
}

export function DropdownSection({ children }: { children: ReactNode }) {
  return <div className="dropdown__section">{children}</div>;
}

export function DropdownDivider() {
  return <div className="dropdown__divider" role="separator" />;
}
