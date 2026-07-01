// Persistent left navigation: brand, primary nav, the client list, sync status.
import { useState } from "react";
import { NavLink } from "react-router-dom";
import { clientTotalAll } from "../../domain/totals";
import { formatMoney } from "../../domain/money";
import { useClients, useEntries } from "../../state/data";
import { useSettings, currencySettings } from "../../state/settings";
import { useSyncStatus } from "../../state/store";
import { NewClientDialog } from "../NewClientDialog";
import { IconButton } from "./Button";
import { GearIcon, PlusIcon, ReceiptIcon, SyncIcon } from "../icons";

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

export function Sidebar() {
  const clients = useClients();
  const entries = useEntries();
  const settings = useSettings();
  const cs = currencySettings(settings);
  const sync = useSyncStatus();
  const [newClient, setNewClient] = useState(false);

  const sorted = [...clients].sort((a, b) => a.sortIndex - b.sortIndex);

  return (
    <aside className="sidebar">
      <div className="sidebar__brand">
        <Wordmark />
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
                  {formatMoney(clientTotalAll(c.id, entries, cs), settings.baseCurrencyCode)}
                </span>
              </NavLink>
            ))
          )}
        </div>
      </div>

      <NavLink to="/settings" className="sidebar__sync" title="Sync settings">
        <SyncIcon size={15} className={sync.isSyncing ? "is-spinning" : undefined} />
        <span className="sidebar__sync-msg">{sync.message}</span>
        {sync.error && <span className="sidebar__sync-dot" aria-hidden />}
      </NavLink>

      {newClient && (
        <NewClientDialog existingClients={clients} onClose={() => setNewClient(false)} />
      )}
    </aside>
  );
}
