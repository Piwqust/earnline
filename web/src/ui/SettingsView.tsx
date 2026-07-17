import { useEffect, useRef, useState } from "react";
import { useLiveQuery } from "dexie-react-hooks";
import { needsSync } from "../domain/types";
import { canConvert, secondaryValue, validExchangeRate } from "../domain/currency";
import { formatMoney, SUPPORTED_CURRENCY_CODES, currencySymbol } from "../domain/money";
import { dottedInstant } from "../domain/dateFormat";
import { exportDatabase, getDatabase, importDatabase, useDatabaseGeneration } from "../data/db";
import { useClients, useEntries, useHeadings } from "../state/data";
import {
  currencySettings,
  isSyncConfigured,
  setSettings,
  useSettings,
  useSettingsPersistenceError,
} from "../state/settings";
import { queueSync, syncController, useSyncStatus } from "../state/store";
import { importBundledLedger } from "../data/sampleLedger";
import { Card } from "./components/Card";
import { Select } from "./components/Field";
import { Button } from "./components/Button";
import { SyncIcon } from "./icons";
import { AccountDevicesPanel } from "../auth/AuthGate";

function downloadBackup(value: unknown): void {
  const blob = new Blob([JSON.stringify(value, null, 2)], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = `earnline-backup-${new Date().toISOString().slice(0, 10)}.json`;
  link.click();
  URL.revokeObjectURL(url);
}

export function SettingsView() {
  const settings = useSettings();
  const persistenceError = useSettingsPersistenceError();
  const status = useSyncStatus();
  const cs = currencySettings(settings);
  const clients = useClients();
  const entries = useEntries();
  const headings = useHeadings();
  const databaseGeneration = useDatabaseGeneration();
  const tombstoneCount = useLiveQuery(() => getDatabase().tombstones.count(), [databaseGeneration], 0);
  const [importing, setImporting] = useState(false);
  const [rateDraft, setRateDraft] = useState(String(settings.rate));
  const [localMessage, setLocalMessage] = useState<string | null>(null);
  const [localError, setLocalError] = useState<string | null>(null);
  const restoreInput = useRef<HTMLInputElement>(null);

  useEffect(() => setRateDraft(String(settings.rate)), [settings.rate]);

  const pending = clients.filter(needsSync).length + entries.filter(needsSync).length +
    headings.filter(needsSync).length + tombstoneCount;
  const unsupportedCount = entries.filter((entry) => !canConvert(entry.currencyCode, cs)).length;
  const secondaryOptions = SUPPORTED_CURRENCY_CODES.filter((code) => code !== settings.baseCurrencyCode);
  const syncConfigured = isSyncConfigured(settings);

  async function importSample(): Promise<void> {
    setImporting(true);
    setLocalError(null);
    try {
      const inserted = await importBundledLedger();
      setLocalMessage(inserted > 0 ? `Imported ${inserted} sample records.` : "Sample ledger is already imported.");
      if (inserted > 0) queueSync();
    } catch (error) {
      setLocalError(error instanceof Error ? error.message : "Sample import failed.");
    } finally {
      setImporting(false);
    }
  }

  function commitRate(): void {
    const parsed = Number(rateDraft.replace(",", "."));
    if (!Number.isFinite(parsed) || parsed <= 0) {
      setRateDraft(String(settings.rate));
      setLocalError("Exchange rate must be greater than zero.");
      return;
    }
    setSettings({ rate: validExchangeRate(parsed) });
    setLocalError(null);
  }

  async function restore(file: File | undefined): Promise<void> {
    if (!file) return;
    setLocalError(null);
    try {
      const result = await importDatabase(JSON.parse(await file.text()));
      setLocalMessage(`Restored ${result.clients + result.entries + result.headings} records. They are waiting to sync.`);
      queueSync();
    } catch (error) {
      setLocalError(error instanceof Error ? error.message : "Backup restore failed.");
    } finally {
      if (restoreInput.current) restoreInput.current.value = "";
    }
  }

  return (
    <div className="page">
      <header className="topbar">
        <h1 className="topbar__title">Settings</h1>
      </header>

      <div className="page__body settings">
        {(persistenceError || localError) && (
          <p className="settings-note settings-note--error" role="alert">{persistenceError || localError}</p>
        )}
        {localMessage && <p className="settings-note" role="status">{localMessage}</p>}

        <AccountDevicesPanel />

        <section className="settings-group" aria-labelledby="appearance-heading">
          <h2 className="settings-group__title" id="appearance-heading">Appearance</h2>
          <Card className="settings-card">
            <div className="setting-row">
              <span className="setting-row__label">Theme</span>
              <div className="segmented" role="group" aria-label="Theme">
                {(["light", "dark", "auto"] as const).map((theme) => (
                  <button key={theme} type="button"
                    className={"segmented__opt" + (settings.theme === theme ? " is-active" : "")}
                    aria-pressed={settings.theme === theme} onClick={() => setSettings({ theme })}>
                    {theme === "light" ? "Light" : theme === "dark" ? "Dark" : "Auto"}
                  </button>
                ))}
              </div>
            </div>
          </Card>
          <p className="settings-note">Auto follows your system appearance.</p>
        </section>

        <section className="settings-group" aria-labelledby="currency-heading">
          <h2 className="settings-group__title" id="currency-heading">Currency</h2>
          <Card className="settings-card">
            <div className="setting-row">
              <label className="setting-row__label" htmlFor="base-currency">Primary</label>
              <Select id="base-currency" aria-label="Primary currency" value={settings.baseCurrencyCode}
                onChange={(event) => setSettings({ baseCurrencyCode: event.target.value })}>
                {SUPPORTED_CURRENCY_CODES.map((code) => <option key={code} value={code}>{code} · {currencySymbol(code)}</option>)}
              </Select>
            </div>
            <div className="setting-row">
              <label className="setting-row__label" htmlFor="secondary-currency">Secondary</label>
              <Select id="secondary-currency" aria-label="Secondary currency" value={settings.secondaryCurrencyCode}
                onChange={(event) => setSettings({ secondaryCurrencyCode: event.target.value })}>
                {secondaryOptions.map((code) => <option key={code} value={code}>{code} · {currencySymbol(code)}</option>)}
              </Select>
            </div>
          </Card>
          {unsupportedCount > 0 && (
            <p className="settings-note settings-note--warn" role="status">
              {unsupportedCount} unsupported-currency {unsupportedCount === 1 ? "line is" : "lines are"} excluded from converted totals.
            </p>
          )}
        </section>

        <section className="settings-group" aria-labelledby="rate-heading">
          <h2 className="settings-group__title" id="rate-heading">Exchange rate</h2>
          <Card className="settings-card">
            <div className="setting-row">
              <label className="setting-row__label" htmlFor="exchange-rate">1 {settings.baseCurrencyCode} equals</label>
              <div className="rate-input">
                <input id="exchange-rate" className="input tabular" type="text" inputMode="decimal"
                  value={rateDraft} aria-describedby="rate-example"
                  onChange={(event) => setRateDraft(event.target.value)} onBlur={commitRate}
                  onKeyDown={(event) => { if (event.key === "Enter") event.currentTarget.blur(); }} />
                <span className="rate-input__code">{settings.secondaryCurrencyCode}</span>
              </div>
            </div>
          </Card>
          <p className="settings-note" id="rate-example">
            Example: {formatMoney(100, settings.baseCurrencyCode)} = {formatMoney(secondaryValue(100, cs), settings.secondaryCurrencyCode)}
          </p>
        </section>

        <section className="settings-group" aria-labelledby="sync-heading">
          <h2 className="settings-group__title" id="sync-heading">Sync</h2>
          <Card className="settings-card">
            <div className="setting-row"><span className="setting-row__label">Connection</span>
              <span className="setting-row__value">{status.connection === "polling" ? "Secure polling" : status.connection}</span></div>
            <div className="setting-row"><span className="setting-row__label">Status</span>
              <span className="setting-row__value" role="status" aria-live="polite">{status.message}</span></div>
            <div className="setting-row"><span className="setting-row__label">Pending</span>
              <span className="setting-row__value tabular">{pending}</span></div>
            {status.lastSyncAt != null && <div className="setting-row"><span className="setting-row__label">Last sync</span>
              <span className="setting-row__value tabular">{dottedInstant(status.lastSyncAt)}</span></div>}
          </Card>
          {status.error && <p className="settings-note settings-note--error" role="alert">{status.error}</p>}
          {status.retryAt != null && <p className="settings-note">Retry scheduled for {dottedInstant(status.retryAt)}.</p>}
          {status.conflictCount > 0 && (
            <div className="settings-actions" role="group" aria-label="Resolve sync conflict">
              <Button variant="secondary" onClick={() => void syncController.useCloudConflictChanges()}>Use cloud changes</Button>
              <Button variant="secondary" onClick={() => void syncController.keepLocalConflictChanges()}>Keep browser changes</Button>
            </div>
          )}
          <div className="settings-actions">
            <Button variant="secondary" leading={<SyncIcon size={15} className={status.isSyncing ? "is-spinning" : undefined} />}
              disabled={status.isSyncing || !syncConfigured} onClick={() => void syncController.syncNow()}>
              {status.isSyncing ? "Syncing…" : "Sync now"}
            </Button>
          </div>
        </section>

        <section className="settings-group" aria-labelledby="data-heading">
          <h2 className="settings-group__title" id="data-heading">Data and recovery</h2>
          <div className="settings-actions">
            <Button variant="secondary" disabled={importing} onClick={() => void importSample()}>
              {importing ? "Importing…" : "Import sample ledger"}
            </Button>
            <Button variant="secondary" onClick={() => void exportDatabase().then(downloadBackup).catch((error: unknown) =>
              setLocalError(error instanceof Error ? error.message : "Backup export failed."))}>Export backup</Button>
            <Button variant="secondary" onClick={() => restoreInput.current?.click()}>Restore backup</Button>
            <input ref={restoreInput} hidden type="file" accept="application/json,.json" aria-label="Choose Earnline backup"
              onChange={(event) => void restore(event.target.files?.[0])} />
          </div>
          {status.storagePersistent === false && <p className="settings-note settings-note--warn">
            This browser did not grant durable storage. Export backups regularly.
          </p>}
        </section>

        <section className="settings-group" aria-labelledby="about-heading">
          <h2 className="settings-group__title" id="about-heading">About</h2>
          <Card className="settings-card">
            <div className="setting-row"><span className="setting-row__label">Version</span><span className="setting-row__value">0.1.0</span></div>
            <div className="setting-row"><span className="setting-row__label">Built with</span><span className="setting-row__value">React · Vite · TypeScript</span></div>
          </Card>
        </section>
      </div>
    </div>
  );
}
