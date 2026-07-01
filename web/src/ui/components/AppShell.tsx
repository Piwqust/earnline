// The persistent app shell: sidebar + routed main area, with a responsive
// off-canvas drawer for narrow screens.
import { useEffect, useState } from "react";
import { Outlet, useLocation } from "react-router-dom";
import { Sidebar, Wordmark } from "./Sidebar";
import { IconButton } from "./Button";
import { MenuIcon } from "../icons";

export function AppShell() {
  const [navOpen, setNavOpen] = useState(false);
  const { pathname } = useLocation();

  // Close the mobile drawer whenever the route changes.
  useEffect(() => {
    setNavOpen(false);
  }, [pathname]);

  return (
    <div className={"shell" + (navOpen ? " is-nav-open" : "")}>
      <header className="shell__mobilebar">
        <IconButton label="Open navigation" onClick={() => setNavOpen(true)}>
          <MenuIcon />
        </IconButton>
        <Wordmark />
      </header>

      <Sidebar />

      <button
        type="button"
        aria-label="Close navigation"
        tabIndex={navOpen ? 0 : -1}
        className="shell__scrim"
        onClick={() => setNavOpen(false)}
      />

      <main className="shell__main">
        <Outlet />
      </main>
    </div>
  );
}
