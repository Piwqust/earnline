// Per-client page: hero total, by-status / by-project breakdowns, all lines,
// rename + recolor. Lives inside the app shell (sidebar persists).
import { useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import type { Client, Entry, EntryStatus } from "../domain/types";
import { STATUS_ORDER } from "../domain/types";
import { clientEntries, clientTotalAll, projectTotals, statusTotal } from "../domain/totals";
import { Limits, capped } from "../domain/validation";
import { useClient, useClients, useEntries } from "../state/data";
import { useSettings, currencySettings } from "../state/settings";
import { deleteEntry, setEntryStatus, updateClient } from "../data/repository";
import { queueSync } from "../state/store";
import { CLIENT_PALETTE } from "./theme/theme";
import { MoneyAmountText } from "./MoneyAmountText";
import { EntryRow } from "./EntryRow";
import { EntryInspector } from "./EntryInspector";
import { Card } from "./components/Card";
import { ClientTag } from "./components/ClientTag";
import { StatusBadge } from "./components/StatusBadge";
import { Field } from "./components/Field";
import { Swatches } from "./components/Swatches";
import { IconButton } from "./components/Button";
import { ConfirmDialog } from "./components/Dialog";
import { BackIcon } from "./icons";

export function ClientDetailView() {
  const { id } = useParams();
  const navigate = useNavigate();
  const client = useClient(id);

  if (!client) {
    return (
      <div className="page">
        <header className="topbar">
          <IconButton label="Back" onClick={() => navigate("/")}>
            <BackIcon />
          </IconButton>
          <span className="topbar__title">Client</span>
        </header>
        <div className="page__body">
          <p className="detail-missing">This client no longer exists.</p>
        </div>
      </div>
    );
  }

  return <ClientDetailBody key={client.id} client={client} onBack={() => navigate("/")} />;
}

function ClientDetailBody({ client, onBack }: { client: Client; onBack: () => void }) {
  const clients = useClients();
  const entries = useEntries();
  const settings = useSettings();
  const cs = currencySettings(settings);
  const [editing, setEditing] = useState<Entry | null>(null);
  const [deleting, setDeleting] = useState<Entry | null>(null);
  const [name, setName] = useState(client.name);

  const list = [...clientEntries(client.id, entries)].sort((a, b) => b.date - a.date);
  const totalAll = clientTotalAll(client.id, entries, cs);
  const projects = projectTotals(client.id, entries, cs);
  const showProjects = projects.length > 1 || (projects[0]?.name ?? "—") !== "—";

  async function changeName(v: string) {
    const capped2 = capped(v, Limits.maxClientNameLength);
    setName(capped2);
    await updateClient(client.id, { name: capped2 });
    queueSync();
  }
  async function recolor(hex: string) {
    await updateClient(client.id, { colorHex: hex });
    queueSync();
  }
  async function changeStatus(e: Entry, s: EntryStatus) {
    await setEntryStatus(e.id, s);
    queueSync();
  }
  async function confirmDelete() {
    if (!deleting) return;
    await deleteEntry(deleting.id);
    queueSync();
  }

  return (
    <div className="page">
      <header className="topbar">
        <IconButton label="Back to ledger" onClick={onBack}>
          <BackIcon />
        </IconButton>
        <span className="topbar__title">{client.name}</span>
      </header>

      <div className="page__body detail">
        <div className="detail-hero">
          <ClientTag name={client.name} color={client.colorHex} size="lg" />
          <div className="detail-hero__total">
            <span className="detail-hero__label">Earned, all time</span>
            <MoneyAmountText baseAmount={totalAll} className="detail-hero__amount tabular" />
          </div>
        </div>

        <div className="detail-grid">
          <Card className="detail-card">
            <h3 className="detail-card__title">By status</h3>
            {STATUS_ORDER.map((s) => {
              const t = statusTotal(client.id, entries, s, cs);
              return (
                <div className="detail-line" key={s}>
                  <StatusBadge status={s} />
                  <span className="detail-line__count">{t.count}</span>
                  <MoneyAmountText baseAmount={t.sum} className="detail-line__amount tabular" />
                </div>
              );
            })}
          </Card>

          {showProjects && (
            <Card className="detail-card">
              <h3 className="detail-card__title">By project</h3>
              {projects.map((p) => (
                <div className="detail-line" key={p.name}>
                  <span className="detail-line__name">{p.name}</span>
                  <MoneyAmountText baseAmount={p.sum} className="detail-line__amount tabular" />
                </div>
              ))}
            </Card>
          )}
        </div>

        <Card className="detail-card">
          <h3 className="detail-card__title">Lines</h3>
          {list.length === 0 ? (
            <p className="detail-empty">No lines yet.</p>
          ) : (
            <div className="detail-lines">
              {list.map((e) => (
                <EntryRow
                  key={e.id}
                  entry={e}
                  onSetStatus={(s) => void changeStatus(e, s)}
                  onEdit={() => setEditing(e)}
                  onDelete={() => setDeleting(e)}
                />
              ))}
            </div>
          )}
        </Card>

        <Card className="detail-card">
          <h3 className="detail-card__title">Client</h3>
          <Field label="Name">
            <input
              className="input"
              value={name}
              onChange={(e) => void changeName(e.target.value)}
            />
          </Field>
          <div className="detail-color">
            <span className="field__label">Color</span>
            <Swatches colors={CLIENT_PALETTE} value={client.colorHex} onChange={(hex) => void recolor(hex)} />
          </div>
        </Card>
      </div>

      {editing && <EntryInspector entry={editing} clients={clients} onClose={() => setEditing(null)} />}
      {deleting && (
        <ConfirmDialog
          title="Delete line?"
          message={
            <>
              This permanently removes <strong>{deleting.task || "this line"}</strong> from the ledger.
            </>
          }
          confirmLabel="Delete line"
          onConfirm={() => void confirmDelete()}
          onClose={() => setDeleting(null)}
        />
      )}
    </div>
  );
}
