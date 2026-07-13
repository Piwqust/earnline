// Anchored menu/popover that renders into a portal so scrolling surfaces never
// clip it. Menu mode follows the ARIA menu keyboard pattern; dialog mode is for
// compact forms such as the Smart Composer options.
import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useId,
  useLayoutEffect,
  useRef,
  useState,
  type ReactNode,
} from "react";
import { createPortal } from "react-dom";
import { CloseIcon } from "../icons";
import { IconButton } from "./Button";

type Align = "left" | "right";
type Vertical = "down" | "up";
type Mode = "menu" | "dialog";

const DropdownCtx = createContext<{ close: () => void }>({ close: () => {} });

export function Dropdown({
  trigger,
  children,
  align = "right",
  vertical = "down",
  triggerClassName,
  ariaLabel,
  disabled,
  mode = "menu",
  popoverTitle,
}: {
  trigger: ReactNode;
  children: ReactNode;
  align?: Align;
  vertical?: Vertical;
  triggerClassName?: string;
  ariaLabel?: string;
  disabled?: boolean;
  mode?: Mode;
  popoverTitle?: string;
}) {
  const [open, setOpen] = useState(false);
  const triggerRef = useRef<HTMLButtonElement>(null);
  const popupRef = useRef<HTMLDivElement>(null);
  const [pos, setPos] = useState<{ top: number; left: number } | null>(null);
  const popupId = useId();

  const close = useCallback((restoreFocus = false) => {
    setOpen(false);
    setPos(null);
    if (restoreFocus) requestAnimationFrame(() => triggerRef.current?.focus({ preventScroll: true }));
  }, []);

  const place = useCallback(() => {
    const triggerElement = triggerRef.current;
    const popup = popupRef.current;
    if (!triggerElement || !popup) return;
    const rect = triggerElement.getBoundingClientRect();
    const width = popup.offsetWidth;
    const height = popup.offsetHeight;
    const gap = 6;
    const pad = 8;

    let top = vertical === "down" ? rect.bottom + gap : rect.top - gap - height;
    if (vertical === "down" && top + height > window.innerHeight - pad && rect.top - gap - height > pad) {
      top = rect.top - gap - height;
    } else if (vertical === "up" && top < pad && rect.bottom + gap + height < window.innerHeight - pad) {
      top = rect.bottom + gap;
    }

    let left = align === "left" ? rect.left : rect.right - width;
    left = Math.max(pad, Math.min(left, window.innerWidth - width - pad));
    top = Math.max(pad, Math.min(top, window.innerHeight - height - pad));
    setPos({ top, left });
  }, [align, vertical]);

  useLayoutEffect(() => {
    if (!open) return;
    place();
    const frame = requestAnimationFrame(place);
    return () => cancelAnimationFrame(frame);
  }, [open, place]);

  useEffect(() => {
    if (!open) return;
    const onPointerDown = (event: MouseEvent) => {
      const target = event.target as Node;
      if (popupRef.current?.contains(target) || triggerRef.current?.contains(target)) return;
      close(false);
    };
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        event.preventDefault();
        close(true);
      }
    };
    const onReflow = () => close(false);
    window.addEventListener("mousedown", onPointerDown);
    window.addEventListener("keydown", onKeyDown);
    window.addEventListener("scroll", onReflow, true);
    window.addEventListener("resize", onReflow);
    return () => {
      window.removeEventListener("mousedown", onPointerDown);
      window.removeEventListener("keydown", onKeyDown);
      window.removeEventListener("scroll", onReflow, true);
      window.removeEventListener("resize", onReflow);
    };
  }, [close, open]);

  useEffect(() => {
    if (!open || !pos) return;
    const popup = popupRef.current;
    if (!popup) return;
    const focusables = () =>
      Array.from(
        popup.querySelectorAll<HTMLElement>(
          mode === "menu"
            ? '[role="menuitem"]:not([disabled])'
            : 'button:not([disabled]),input:not([disabled]),select:not([disabled]),textarea:not([disabled]),[tabindex]:not([tabindex="-1"])',
        ),
      ).filter((item) => item.offsetWidth > 0 || item.offsetHeight > 0 || item === document.activeElement);
    const preferred = popup.querySelector<HTMLElement>("[data-popover-autofocus]");
    (preferred ?? focusables()[0])?.focus({ preventScroll: true });

    const onKeyDown = (event: KeyboardEvent) => {
      const list = focusables();
      if (!list.length) return;
      const index = list.indexOf(document.activeElement as HTMLElement);
      if (mode === "dialog" && event.key === "Tab") {
        const first = list[0];
        const last = list[list.length - 1];
        if (event.shiftKey && document.activeElement === first) {
          event.preventDefault();
          last.focus();
        } else if (!event.shiftKey && document.activeElement === last) {
          event.preventDefault();
          first.focus();
        }
      } else if (mode === "menu" && event.key === "ArrowDown") {
        event.preventDefault();
        list[(index + 1) % list.length]?.focus();
      } else if (mode === "menu" && event.key === "ArrowUp") {
        event.preventDefault();
        list[(index - 1 + list.length) % list.length]?.focus();
      } else if (mode === "menu" && event.key === "Home") {
        event.preventDefault();
        list[0]?.focus();
      } else if (mode === "menu" && event.key === "End") {
        event.preventDefault();
        list[list.length - 1]?.focus();
      }
    };
    popup.addEventListener("keydown", onKeyDown);
    return () => popup.removeEventListener("keydown", onKeyDown);
  }, [mode, open, pos]);

  return (
    <>
      <button
        ref={triggerRef}
        type="button"
        className={triggerClassName}
        aria-label={ariaLabel}
        aria-haspopup={mode}
        aria-expanded={open}
        aria-controls={open ? popupId : undefined}
        disabled={disabled}
        onClick={(event) => {
          event.stopPropagation();
          if (open) close(false);
          else setOpen(true);
        }}
      >
        {trigger}
      </button>
      {open &&
        createPortal(
          <DropdownCtx.Provider value={{ close: () => close(true) }}>
            <div
              id={popupId}
              ref={popupRef}
              className={"dropdown" + (mode === "dialog" ? " dropdown--dialog" : "")}
              role={mode}
              aria-label={mode === "dialog" ? popoverTitle ?? ariaLabel : undefined}
              tabIndex={mode === "dialog" ? -1 : undefined}
              style={{
                position: "fixed",
                top: pos?.top ?? -9999,
                left: pos?.left ?? -9999,
                visibility: pos ? "visible" : "hidden",
              }}
              onClick={(event) => event.stopPropagation()}
            >
              {mode === "dialog" && (
                <div className="dropdown__dialog-head">
                  <span>{popoverTitle ?? ariaLabel ?? "Options"}</span>
                  <IconButton label="Close options" size="sm" onClick={() => close(true)}>
                    <CloseIcon size={16} />
                  </IconButton>
                </div>
              )}
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
  return (
    <div className="dropdown__section" role="presentation">
      {children}
    </div>
  );
}

export function DropdownDivider() {
  return <div className="dropdown__divider" role="separator" />;
}
