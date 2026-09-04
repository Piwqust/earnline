// Persistent desktop shell with an accessible off-canvas navigation drawer on
// narrow screens.
import { Suspense, useCallback, useEffect, useRef, useState } from "react";
import { Outlet, useLocation } from "react-router-dom";
import { Sidebar, Wordmark } from "./Sidebar";
import { IconButton } from "./Button";
import { MenuIcon } from "../icons";

const NARROW_QUERY = "(max-width: 859px)";
const FOCUSABLE =
  'a[href],button:not([disabled]),input:not([disabled]),textarea:not([disabled]),select:not([disabled]),[tabindex]:not([tabindex="-1"])';

function routeName(pathname: string): string {
  if (pathname === "/settings") return "Settings";
  if (pathname.startsWith("/client/")) return "Client details";
  return "Ledger";
}

export function AppShell() {
  const [navOpen, setNavOpen] = useState(false);
  const [isNarrow, setIsNarrow] = useState(() =>
    typeof window !== "undefined" ? window.matchMedia(NARROW_QUERY).matches : false,
  );
  const { pathname } = useLocation();
  const currentRouteName = routeName(pathname);
  const previousPath = useRef(pathname);
  const menuButtonRef = useRef<HTMLButtonElement>(null);
  const sidebarRef = useRef<HTMLElement>(null);
  const mobileBarRef = useRef<HTMLElement>(null);
  const mainRef = useRef<HTMLElement>(null);
  const restoreMenuFocus = useRef(false);

  const closeNavigation = useCallback((restoreFocus: boolean) => {
    restoreMenuFocus.current = restoreFocus;
    if (restoreFocus) {
      if (mobileBarRef.current) mobileBarRef.current.inert = false;
      menuButtonRef.current?.focus({ preventScroll: true });
      if (document.activeElement === menuButtonRef.current) restoreMenuFocus.current = false;
    }
    setNavOpen(false);
  }, []);

  useEffect(() => {
    const media = window.matchMedia(NARROW_QUERY);
    const update = () => {
      setIsNarrow(media.matches);
      if (!media.matches) setNavOpen(false);
    };
    update();
    media.addEventListener("change", update);
    return () => media.removeEventListener("change", update);
  }, []);

  useEffect(() => {
    const backgroundIsInert = isNarrow && navOpen;
    const main = mainRef.current;
    const mobileBar = mobileBarRef.current;
    if (main) main.inert = backgroundIsInert;
    if (mobileBar) mobileBar.inert = backgroundIsInert;
    return () => {
      if (main) main.inert = false;
      if (mobileBar) mobileBar.inert = false;
    };
  }, [isNarrow, navOpen]);

  useEffect(() => {
    if (navOpen || !restoreMenuFocus.current) return;
    restoreMenuFocus.current = false;
    const frame = requestAnimationFrame(() => menuButtonRef.current?.focus({ preventScroll: true }));
    return () => cancelAnimationFrame(frame);
  }, [navOpen]);

  useEffect(() => {
    document.title = `${currentRouteName} · earn›line`;
    if (previousPath.current === pathname) return;
    previousPath.current = pathname;
    const frame = requestAnimationFrame(() => {
      setNavOpen(false);
      mainRef.current?.focus({ preventScroll: true });
    });
    return () => cancelAnimationFrame(frame);
  }, [currentRouteName, pathname]);

  useEffect(() => {
    if (!isNarrow || !navOpen) return;
    const sidebar = sidebarRef.current;
    if (!sidebar) return;
    const focusables = () =>
      Array.from(sidebar.querySelectorAll<HTMLElement>(FOCUSABLE)).filter(
        (item) => item.offsetWidth > 0 || item.offsetHeight > 0,
      );
    focusables()[0]?.focus({ preventScroll: true });

    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        event.preventDefault();
        closeNavigation(true);
        return;
      }
      if (event.key !== "Tab") return;
      const list = focusables();
      if (!list.length) return;
      const first = list[0];
      const last = list[list.length - 1];
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    };
    document.addEventListener("keydown", onKeyDown, true);
    return () => document.removeEventListener("keydown", onKeyDown, true);
  }, [closeNavigation, isNarrow, navOpen]);

  const mobileHidden = isNarrow && !navOpen;

  return (
    <div className={"shell" + (navOpen ? " is-nav-open" : "")}>
      <a className="skip-link" href="#main-content">
        Skip to content
      </a>

      <header ref={mobileBarRef} className="shell__mobilebar">
        <IconButton
          ref={menuButtonRef}
          label="Open navigation"
          aria-controls="primary-sidebar"
          aria-expanded={navOpen}
          onClick={() => setNavOpen(true)}
        >
          <MenuIcon />
        </IconButton>
        <Wordmark />
      </header>

      <Sidebar
        ref={sidebarRef}
        mobileHidden={mobileHidden}
        mobileDialog={isNarrow && navOpen}
        onRequestClose={() => closeNavigation(true)}
      />

      {isNarrow && navOpen && (
        <div
          aria-hidden="true"
          className="shell__scrim"
          onClick={() => closeNavigation(true)}
        />
      )}

      <p className="u-sr" aria-live="polite" aria-atomic="true">
        {currentRouteName} page
      </p>

      <main id="main-content" ref={mainRef} className="shell__main" tabIndex={-1}>
        <Suspense
          fallback={
            <div className="route-loading" role="status" aria-live="polite">
              <h1 className="u-sr">{currentRouteName}</h1>
              <span className="route-loading__bar" aria-hidden />
              <span>Loading view…</span>
            </div>
          }
        >
          <Outlet />
        </Suspense>
      </main>
    </div>
  );
}
