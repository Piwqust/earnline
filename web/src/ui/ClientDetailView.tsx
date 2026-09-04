// Per-client page: hero total, by-status / by-project breakdowns, all lines,
// rename + recolor. Lives inside the app shell (sidebar persists).
import { useEffect, useId, useMemo, useRef, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import type { Client, Entry, EntryStatus } from "../domain/types";
import { Limits, capped, clientNameMessage, validateClientName } from "../domain/validation";
import { useClient, useClients, useDataReady, useEntries } from "../state/data";
import { useSettings, currencySettings } from "../state/settings";
import { deleteClient, deleteEntry, setEntryStatus, updateClient } from "../data/repository";
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
import { Button, IconButton } from "./components/Button";
import { ConfirmDialog } from "./components/Dialog";
import { BackIcon, TrashIcon } from "./icons";
import { buildClientDetailModel } from "./ledgerModel";

export function ClientDetailView() {
  const { id } = useParams();
  const navigate = useNavigate();
  const client = useClient(id);
  const dataReady = useDataReady();

  if (!dataReady) {
    return (
      <div className="page detail-loading" role="status" aria-live="polite">
        <h1 className="u-sr">Client details</h1>
        <span>Loading client…</span>
      </div>
    );
  }

  if (!client) {
    return (
      <div className="page">
        <header className="topbar">
          <IconButton label="Back" onClick={() => navigate("/")}>
            <BackIcon />
          </IconButton>
          <h1 className="topbar__title">Client</h1>
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
  const cs = useMemo(() => currencySettings(settings), [settings]);
  const [editing, setEditing] = useState<Entry | null>(null);
  const [deleting, setDeleting] = useState<Entry | null>(null);
  const [deletingClient, setDeletingClient] = useState(false);
  const [name, setName] = useState(client.name);
  const [nameError, setNameError] = useState<string | null>(null);
  const [savingName, setSavingName] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);
  const cancelNameCommit = useRef(false);
  const nameId = useId();
  const nameErrorId = useId();

  const model = useMemo(
    () => buildClientDetailModel(client.id, entries, cs),
    [client.id, cs, entries],
  );
  const list = model.entries;
  const totalAll = model.total;
  const projects = model.projects;
  const showProjects = projects.length > 1 || (projects[0]?.name ?? "—") !== "—";
  const realProjectCount = projects.filter((p) => p.name !== "—").length;
  const statusRows = model.statuses;
  const unsupportedCount = model.unsupportedCount;

  useEffect(() => {
    const frame = requestAnimationFrame(() => setName(client.name));
    return () => cancelAnimationFrame(frame);
  }, [client.name]);

  async function commitName() {
    if (cancelNameCommit.current) {
      cancelNameCommit.current = false;
      return;
    }
    const validation = validateClientName(
      name,
      clients.filter((item) => item.id !== client.id).map((item) => item.name),
    );
    if (validation.kind !== "valid") {
      setNameError(clientNameMessage(validation));
      return;
    }
    setName(validation.name);
    setNameError(null);
    if (validation.name === client.name) return;
    setSavingName(true);
    try {
      await updateClient(client.id, { name: validation.name });
      queueSync();
    } catch {
      setNameError("The name could not be saved. Try again.");
    } finally {
      setSavingName(false);
    }
  }
  async function recolor(hex: string) {
    setActionError(null);
    try {
      await updateClient(client.id, { colorHex: hex });
      queueSync();
    } catch {
      setActionError("The client color could not be saved. Try again.");
    }
  }
  async function changeStatus(e: Entry, s: EntryStatus) {
    setActionError(null);
    try {
      await setEntryStatus(e.id, s);
      queueSync();
    } catch {
      setActionError("The line status could not be saved. Try again.");
    }
  }
  async function confirmDelete() {
    if (!deleting) return;
    await deleteEntry(deleting.id);
    queueSync();
  }
  async function confirmDeleteClient() {
    await deleteClient(client.id);
    queueSync();
    onBack();
  }

  return (
    <div className="page">
      <header className="topbar">
        <IconButton label="Back to ledger" onClick={onBack}>
          <BackIcon />
        </IconButton>
        <h1 className="topbar__title">{client.name}</h1>
      </header>

      <div className="page__body detail">
        {actionError && (
          <p className="settings-note settings-note--error" role="alert">
            {actionError}
          </p>
        )}
        <div className="detail-hero">
          <ClientTag name={client.name} color={client.colorHex} size="lg" />
          <MoneyAmountText baseAmount={totalAll} className="detail-hero__amount tabular" />
          <div className="detail-hero__meta">
            <span>Earned all time</span>
            <span className="detail-hero__dot" aria-hidden>
              ·
            </span>
            <span>
              {list.length} {list.length === 1 ? "line" : "lines"}
            </span>
            {realProjectCount > 0 && (
              <>
                <span className="detail-hero__dot" aria-hidden>
                  ·
                </span>
                <span>
                  {realProjectCount} {realProjectCount === 1 ? "project" : "projects"}
                </span>
              </>
            )}
            {unsupportedCount > 0 && (
              <span className="total-incomplete">
                {unsupportedCount} unsupported {unsupportedCount === 1 ? "currency is" : "currencies are"} excluded
              </span>
            )}
          </div>
        </div>

        <div className="detail-grid">
          <Card className="detail-card">
            <h2 className="detail-card__title">By status</h2>
            {statusRows.map((r) => (
              <div className="detail-line" key={r.status}>
                <StatusBadge status={r.status} />
                <span className="detail-line__count">{r.count}</span>
                <MoneyAmountText baseAmount={r.sum} className="detail-line__amount tabular" />
              </div>
            ))}
          </Card>

          {showProjects && (
            <Card className="detail-card">
              <h2 className="detail-card__title">By project</h2>
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
          <h2 className="detail-card__title">Lines</h2>
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
          <h2 className="detail-card__title">Client</h2>
          <Field label="Name" htmlFor={nameId}>
            <input
              id={nameId}
              className="input"
              value={name}
              disabled={savingName}
              aria-invalid={nameError != null}
              aria-describedby={nameError ? nameErrorId : undefined}
              onChange={(event) => {
                setName(capped(event.target.value, Limits.maxClientNameLength));
                setNameError(null);
              }}
              onBlur={() => void commitName()}
              onKeyDown={(event) => {
                if (event.key === "Enter") event.currentTarget.blur();
                if (event.key === "Escape") {
                  cancelNameCommit.current = true;
                  setName(client.name);
                  setNameError(null);
                  event.currentTarget.blur();
                }
              }}
            />
            {nameError && (
              <p id={nameErrorId} className="field__error" role="alert">
                {nameError}
              </p>
            )}
          </Field>
          <div className="detail-color">
            <span className="field__label">Color</span>
            <Swatches colors={CLIENT_PALETTE} value={client.colorHex} onChange={(hex) => void recolor(hex)} />
          </div>
          <div className="detail-danger">
            <Button variant="danger" leading={<TrashIcon size={15} />} onClick={() => setDeletingClient(true)}>
              Delete client
            </Button>
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
          onConfirm={confirmDelete}
          onClose={() => setDeleting(null)}
        />
      )}
      {deletingClient && (
        <ConfirmDialog
          title="Delete client?"
          message={
            <>
              This permanently removes <strong>{client.name}</strong> and {list.length} associated{" "}
              {list.length === 1 ? "line" : "lines"}.
            </>
          }
          confirmLabel="Delete client"
          onConfirm={confirmDeleteClient}
          onClose={() => setDeletingClient(false)}
        />
      )}
    </div>
  );
}
