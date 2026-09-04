// Persistent left navigation: brand, primary nav, the client list, sync status.
import { forwardRef, useEffect, useImperativeHandle, useMemo, useRef, useState } from "react";
import { NavLink } from "react-router-dom";
import { convertToBase } from "../../domain/currency";
import { formatMoney, numberFromCents } from "../../domain/money";
import { isIncludedInEarnedTotals } from "../../domain/types";
import { useClients, useEntries } from "../../state/data";
import { useSettings, setSettings, currencySettings } from "../../state/settings";
import { useSyncStatus } from "../../state/store";
import { NewClientDialog } from "../NewClientDialog";
import { IconButton } from "./Button";
import { CloseIcon, GearIcon, MoonIcon, PlusIcon, ReceiptIcon, SunIcon, SyncIcon } from "../icons";

export function Wordmark() {
  return (
    <NavLink to="/" className="wordmark" aria-label="earn›line — open ledger">
      earn<span className="wordmark__sep">›</span>line
    </NavLink>
  );
}

const navItemClass = ({ isActive }: { isActive: boolean }) =>
  "sidebar__nav-item" + (isActive ? " is-active" : "");

const clientLinkClass = ({ isActive }: { isActive: boolean }) =>
  "sidebar__client" + (isActive ? " is-active" : "");

export const Sidebar = forwardRef<
  HTMLElement,
  { mobileHidden?: boolean; mobileDialog?: boolean; onRequestClose?: () => void }
>(function Sidebar(
  { mobileHidden = false, mobileDialog = false, onRequestClose },
  ref,
) {
  const clients = useClients();
  const entries = useEntries();
  const settings = useSettings();
  const cs = useMemo(() => currencySettings(settings), [settings]);
  const sync = useSyncStatus();
  const [newClient, setNewClient] = useState(false);
  const localRef = useRef<HTMLElement>(null);
  const [systemDark, setSystemDark] = useState(() =>
    typeof window !== "undefined" && window.matchMedia("(prefers-color-scheme: dark)").matches,
  );

  useEffect(() => {
    const media = window.matchMedia("(prefers-color-scheme: dark)");
    const update = () => setSystemDark(media.matches);
    update();
    media.addEventListener("change", update);
    return () => media.removeEventListener("change", update);
  }, []);

  useImperativeHandle(ref, () => localRef.current as HTMLElement);

  useEffect(() => {
    if (localRef.current) localRef.current.inert = mobileHidden;
  }, [mobileHidden]);

  const sorted = [...clients].sort((a, b) => a.sortIndex - b.sortIndex);
  const clientTotals = useMemo(() => {
    const totals = new Map(clients.map((client) => [client.id, 0]));
    for (const entry of entries) {
      if (!isIncludedInEarnedTotals(entry.status)) continue;
      const converted = convertToBase(numberFromCents(entry.amountCents), entry.currencyCode, cs);
      if (converted == null || !totals.has(entry.clientId)) continue;
      totals.set(entry.clientId, (totals.get(entry.clientId) ?? 0) + converted);
    }
    return totals;
  }, [clients, cs, entries]);

  const resolvedDark =
    settings.theme === "dark" ||
    (settings.theme === "auto" &&
      typeof window !== "undefined" &&
      systemDark);

  return (
    <aside
      ref={localRef}
      id="primary-sidebar"
      className="sidebar"
      role={mobileDialog ? "dialog" : undefined}
      aria-modal={mobileDialog ? true : undefined}
      aria-label={mobileDialog ? "Navigation" : undefined}
      aria-hidden={mobileHidden ? true : undefined}
    >
      <div className="sidebar__brand">
        <Wordmark />
        {mobileDialog && onRequestClose && (
          <IconButton label="Close navigation" className="sidebar__close" onClick={onRequestClose}>
            <CloseIcon size={18} />
          </IconButton>
        )}
      </div>

      <nav className="sidebar__nav" aria-label="Primary">
        <NavLink to="/" end className={navItemClass}>
          <ReceiptIcon size={17} />
          <span>Ledger</span>
        </NavLink>
        <NavLink to="/settings" className={navItemClass}>
          <GearIcon size={17} />
          <span>Settings</span>
        </NavLink>
      </nav>

      <div className="sidebar__section">
        <div className="sidebar__section-head">
          <span>Clients</span>
          <IconButton label="New client" size="sm" onClick={() => setNewClient(true)}>
            <PlusIcon size={15} />
          </IconButton>
        </div>
        <div className="sidebar__clients">
          {sorted.length === 0 ? (
            <p className="sidebar__empty">No clients yet. Add one to start a line.</p>
          ) : (
            sorted.map((c) => (
              <NavLink key={c.id} to={`/client/${c.id}`} className={clientLinkClass}>
                <span className="sidebar__dot" style={{ background: c.colorHex }} />
                <span className="sidebar__client-name">{c.name}</span>
                <span className="sidebar__client-total tabular">
                  {formatMoney(clientTotals.get(c.id) ?? 0, settings.baseCurrencyCode)}
                </span>
              </NavLink>
            ))
          )}
        </div>
      </div>

      <div className="sidebar__foot">
        <NavLink to="/settings" className="sidebar__sync" title="Sync settings">
          <SyncIcon size={15} className={sync.isSyncing ? "is-spinning" : undefined} />
          <span className="sidebar__sync-msg">{sync.message}</span>
          {sync.error && <span className="sidebar__sync-dot" aria-hidden />}
        </NavLink>
        <button
          type="button"
          className="sidebar__theme"
          onClick={() => setSettings({ theme: resolvedDark ? "light" : "dark" })}
          title={`Switch to ${resolvedDark ? "light" : "dark"} mode`}
          aria-label={`Switch to ${resolvedDark ? "light" : "dark"} mode`}
        >
          {resolvedDark ? <SunIcon size={16} /> : <MoonIcon size={15} />}
        </button>
      </div>

      {newClient && (
        <NewClientDialog existingClients={clients} onClose={() => setNewClient(false)} />
      )}
    </aside>
  );
});
