// Settings — a real page (not a sheet): currency, exchange rate, Supabase
// config, sync status, sample import, about. All sync wiring is reused as-is.
import { useState } from "react";
import { useLiveQuery } from "dexie-react-hooks";
import { needsSync } from "../domain/types";
import { canConvert } from "../domain/currency";
import { formatMoney, SUPPORTED_CURRENCY_CODES, currencySymbol } from "../domain/money";
import { secondaryValue } from "../domain/currency";
import { dottedInstant } from "../domain/dateFormat";
import { db } from "../data/db";
import { useClients, useEntries, useHeadings } from "../state/data";
import { useSettings, setSettings, currencySettings, isSupabaseConfigured } from "../state/settings";
import { syncController, useSyncStatus, queueSync } from "../state/store";
import { importBundledLedger } from "../data/sampleLedger";
import { Card } from "./components/Card";
import { Field, Select } from "./components/Field";
import { Button } from "./components/Button";
import { SyncIcon } from "./icons";

export function SettingsView() {
  const settings = useSettings();
  const status = useSyncStatus();
  const cs = currencySettings(settings);
  const clients = useClients();
  const entries = useEntries();
  const headings = useHeadings();
  const tombstoneCount = useLiveQuery(() => db.tombstones.count(), [], 0);
  const [importing, setImporting] = useState(false);

  const pending =
    clients.filter(needsSync).length +
    entries.filter(needsSync).length +
    headings.filter(needsSync).length +
    tombstoneCount;
  const unsupportedCount = entries.filter((e) => !canConvert(e.currencyCode, cs)).length;
  const configured = isSupabaseConfigured(settings);
  const secondaryOptions = SUPPORTED_CURRENCY_CODES.filter((c) => c !== settings.baseCurrencyCode);

  async function importSample() {
    setImporting(true);
    try {
      const inserted = await importBundledLedger();
      if (inserted > 0) queueSync();
    } finally {
      setImporting(false);
    }
  }

  return (
    <div className="page">
      <header className="topbar">
        <span className="topbar__title">Settings</span>
      </header>

      <div className="page__body settings">
        <section className="settings-group">
          <h2 className="settings-group__title">Currency</h2>
          <Card className="settings-card">
            <div className="setting-row">
              <span className="setting-row__label">Primary</span>
              <Select
                value={settings.baseCurrencyCode}
                onChange={(e) => setSettings({ baseCurrencyCode: e.target.value })}
              >
                {SUPPORTED_CURRENCY_CODES.map((c) => (
                  <option key={c} value={c}>
                    {c} · {currencySymbol(c)}
                  </option>
                ))}
              </Select>
            </div>
            <div className="setting-row">
              <span className="setting-row__label">Secondary</span>
              <Select
                value={settings.secondaryCurrencyCode}
                onChange={(e) => setSettings({ secondaryCurrencyCode: e.target.value })}
              >
                {secondaryOptions.map((c) => (
                  <option key={c} value={c}>
                    {c} · {currencySymbol(c)}
                  </option>
                ))}
              </Select>
            </div>
          </Card>
          {unsupportedCount > 0 && (
            <p className="settings-note settings-note--warn">
              {unsupportedCount} line{unsupportedCount === 1 ? "" : "s"} in an unsupported currency,
              counted at par (1:1).
            </p>
          )}
        </section>

        <section className="settings-group">
          <h2 className="settings-group__title">Exchange rate</h2>
          <Card className="settings-card">
            <div className="setting-row">
              <span className="setting-row__label">1 {settings.baseCurrencyCode} equals</span>
              <div className="rate-input">
                <input
                  className="input tabular"
                  type="number"
                  inputMode="decimal"
                  value={settings.rate}
                  onChange={(e) => setSettings({ rate: Number(e.target.value) })}
                />
                <span className="rate-input__code">{settings.secondaryCurrencyCode}</span>
              </div>
            </div>
          </Card>
          <p className="settings-note">
            Example: {formatMoney(100, settings.baseCurrencyCode)} ={" "}
            {formatMoney(secondaryValue(100, cs), settings.secondaryCurrencyCode)}
          </p>
        </section>

        <section className="settings-group">
          <h2 className="settings-group__title">Supabase</h2>
          <Card className="settings-card settings-card--stack">
            <Field label="Project URL">
              <input
                className="input"
                placeholder="https://your-project.supabase.co"
                autoCapitalize="off"
                autoCorrect="off"
                spellCheck={false}
                value={settings.supabaseUrl}
                onChange={(e) => setSettings({ supabaseUrl: e.target.value })}
              />
            </Field>
            <Field label="Publishable key">
              <input
                className="input"
                placeholder="anon / publishable key"
                autoCapitalize="off"
                autoCorrect="off"
                spellCheck={false}
                value={settings.supabaseKey}
                onChange={(e) => setSettings({ supabaseKey: e.target.value })}
              />
            </Field>
            <Field label="Workspace ID">
              <input
                className="input"
                placeholder="your-workspace-id"
                autoCapitalize="off"
                autoCorrect="off"
                spellCheck={false}
                value={settings.workspaceId}
                onChange={(e) => setSettings({ workspaceId: e.target.value })}
              />
            </Field>
          </Card>
          <p className="settings-note">
            Personal no-login sync uses this publishable key. Never paste a service_role key.
          </p>
        </section>

        <section className="settings-group">
          <h2 className="settings-group__title">Sync</h2>
          <Card className="settings-card">
            <div className="setting-row">
              <span className="setting-row__label">Workspace</span>
              <span className="setting-row__value">
                {settings.workspaceId === "" ? "Not set" : settings.workspaceId}
              </span>
            </div>
            <div className="setting-row">
              <span className="setting-row__label">Status</span>
              <span className="setting-row__value">{status.message}</span>
            </div>
            <div className="setting-row">
              <span className="setting-row__label">Pending</span>
              <span className="setting-row__value tabular">{pending}</span>
            </div>
            {settings.lastSyncAt != null && (
              <div className="setting-row">
                <span className="setting-row__label">Last sync</span>
                <span className="setting-row__value tabular">{dottedInstant(settings.lastSyncAt)}</span>
              </div>
            )}
          </Card>
          {status.error && <p className="settings-note settings-note--error">{status.error}</p>}
          <div className="settings-actions">
            <Button
              variant="secondary"
              leading={<SyncIcon size={15} className={status.isSyncing ? "is-spinning" : undefined} />}
              disabled={status.isSyncing || !configured}
              onClick={() => void syncController.syncNow()}
            >
              {status.isSyncing ? "Syncing…" : "Sync now"}
            </Button>
            <Button variant="secondary" disabled={importing} onClick={() => void importSample()}>
              {importing ? "Importing…" : "Import sample ledger"}
            </Button>
          </div>
        </section>

        <section className="settings-group">
          <h2 className="settings-group__title">About</h2>
          <Card className="settings-card">
            <div className="setting-row">
              <span className="setting-row__label">Version</span>
              <span className="setting-row__value">0.1.0</span>
            </div>
            <div className="setting-row">
              <span className="setting-row__label">Built with</span>
              <span className="setting-row__value">React · Vite · TypeScript</span>
            </div>
          </Card>
        </section>
      </div>
    </div>
  );
}
