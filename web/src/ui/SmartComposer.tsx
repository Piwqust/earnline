// The notepad composer — one plain line, like typing into Notes. Type
// "+240 Acme: 2 screens hold 25.07" and press Return. Status, income date and
// currency live behind a single unobtrusive options icon on the right; the note
// itself is parsed with the shared LineParser so web and iOS read alike.
import { useEffect, useMemo, useRef, useState } from "react";
import type { Client, EntryStatus } from "../domain/types";
import { STATUS_ORDER, statusTitle } from "../domain/types";
import { parseLine } from "../domain/lineParser";
import { centsFromNumber, currencySymbol, SUPPORTED_CURRENCY_CODES } from "../domain/money";
import { Limits, clampAmount, trimmed } from "../domain/validation";
import { dayMsFromInputValue, inputValueFromDayMs, todayDayMs } from "../domain/dateFormat";
import { useSettings } from "../state/settings";
import { useEntries } from "../state/data";
import { createEntry } from "../data/repository";
import { queueSync } from "../state/store";
import { ClientTag } from "./components/ClientTag";
import { Dropdown, DropdownItem, DropdownSection, DropdownDivider } from "./components/Dropdown";
import { Select } from "./components/Field";
import { ArrowUpIcon, ChevronDownIcon, PlusIcon, SlidersIcon, StatusIcon } from "./icons";

export function SmartComposer({
  clients,
  clientId,
  onClientChange,
  onNewClient,
}: {
  clients: Client[];
  clientId: string | null;
  onClientChange: (id: string) => void;
  onNewClient: () => void;
}) {
  const settings = useSettings();
  const allEntries = useEntries();

  const [noteText, setNoteText] = useState("");
  const [entryDateMs, setEntryDateMs] = useState(todayDayMs());
  const [statusPick, setStatusPick] = useState<EntryStatus>("paid");
  const [currencyPick, setCurrencyPick] = useState(settings.baseCurrencyCode);

  const noteRef = useRef<HTMLInputElement>(null);
  const currentClient = clients.find((c) => c.id === clientId) ?? clients[0] ?? null;

  // Focus the note when the target client changes (e.g. via a client's "+ Line").
  useEffect(() => {
    if (currentClient) noteRef.current?.focus({ preventScroll: true });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [clientId]);

  // Everything is derived from the single note; the icon just tweaks the rest.
  const parsed = useMemo(() => parseLine(noteText, currencyPick), [noteText, currencyPick]);
  const amount = parsed.amount != null ? clampAmount(parsed.amount) : null;
  const code = parsed.currencyCode;
  const cleanTask = trimmed(parsed.task, Limits.maxTaskLength);
  const status: EntryStatus = parsed.status ?? statusPick;
  const canCommit = amount != null && amount > 0 && cleanTask !== "";
  const optionsSet =
    status !== "paid" || entryDateMs !== todayDayMs() || code !== settings.baseCurrencyCode;

  if (!currentClient) {
    return (
      <div className="composer composer--empty">
        <span className="composer__empty-text">Add a client to start logging income.</span>
        <button type="button" className="btn btn--primary btn--sm" onClick={onNewClient}>
          <span className="btn__icon">
            <PlusIcon size={14} />
          </span>
          <span>New client</span>
        </button>
      </div>
    );
  }

  async function commit() {
    if (!currentClient || amount == null || amount <= 0 || cleanTask === "") {
      noteRef.current?.focus();
      return;
    }
    const cleanProject = parsed.project ? trimmed(parsed.project, Limits.maxProjectLength) : "";
    const clientEntries = allEntries.filter((e) => e.clientId === currentClient.id);
    const minIndex = clientEntries.length ? Math.min(...clientEntries.map((e) => e.sortIndex)) : 0;

    await createEntry({
      clientId: currentClient.id,
      amountCents: centsFromNumber(amount),
      currencyCode: code,
      project: cleanProject === "" ? null : cleanProject,
      task: cleanTask,
      date: entryDateMs,
      holdUntil: parsed.holdUntil ?? null,
      status,
      sortIndex: minIndex - 1,
    });
    queueSync();

    setNoteText("");
    setStatusPick("paid");
    setCurrencyPick(settings.baseCurrencyCode);
    setEntryDateMs(todayDayMs());
    noteRef.current?.focus();
  }

  return (
    <div className="composer composer--smart">
      <Dropdown
        ariaLabel="Choose client"
        align="left"
        triggerClassName="composer__client"
        trigger={
          <>
            <ClientTag name={currentClient.name} color={currentClient.colorHex} size="sm" />
            <ChevronDownIcon size={11} />
          </>
        }
      >
        <DropdownSection>Add income to</DropdownSection>
        {clients.map((c) => (
          <DropdownItem key={c.id} onClick={() => onClientChange(c.id)}>
            <span className="dot" style={{ background: c.colorHex }} />
            <span>{c.name}</span>
          </DropdownItem>
        ))}
        <DropdownDivider />
        <DropdownItem onClick={onNewClient}>
          <PlusIcon size={15} />
          <span>New client</span>
        </DropdownItem>
      </Dropdown>

      <span className="composer__sep" />

      <input
        ref={noteRef}
        className="composer__note"
        placeholder="+240 Acme : 2 screens"
        value={noteText}
        aria-label="Write an income line"
        autoComplete="off"
        spellCheck={false}
        onChange={(e) => setNoteText(e.target.value.slice(0, 240))}
        onKeyDown={(e) => {
          if (e.key === "Enter") {
            e.preventDefault();
            void commit();
          }
        }}
      />

      <Dropdown
        ariaLabel="Line options — status, date, currency"
        triggerClassName={"composer__opts-btn" + (optionsSet ? " is-set" : "")}
        trigger={
          <>
            <SlidersIcon size={17} />
            {optionsSet && <span className="composer__opts-dot" aria-hidden />}
          </>
        }
      >
        <div className="composer-opts">
          <div className="composer-opts__row">
            <span className="composer-opts__label">Status</span>
            <div className="composer-opts__seg" role="group" aria-label="Status">
              {STATUS_ORDER.map((s) => (
                <button
                  key={s}
                  type="button"
                  className={"composer-opts__seg-opt" + (status === s ? " is-active" : "")}
                  aria-pressed={status === s}
                  aria-label={statusTitle(s)}
                  title={statusTitle(s)}
                  onClick={() => setStatusPick(s)}
                >
                  <StatusIcon status={s} size={15} />
                </button>
              ))}
            </div>
          </div>

          <div className="composer-opts__row">
            <span className="composer-opts__label">Date</span>
            <input
              type="date"
              className="composer-opts__date"
              aria-label="Income date"
              value={inputValueFromDayMs(entryDateMs)}
              onChange={(e) => {
                const ms = dayMsFromInputValue(e.target.value);
                if (ms != null) setEntryDateMs(ms);
              }}
            />
          </div>

          <div className="composer-opts__row">
            <span className="composer-opts__label">Currency</span>
            <Select value={code} onChange={(e) => setCurrencyPick(e.target.value)}>
              {SUPPORTED_CURRENCY_CODES.map((c) => (
                <option key={c} value={c}>
                  {currencySymbol(c)} · {c}
                </option>
              ))}
            </Select>
          </div>

          <p className="composer-opts__tip">
            <b>+240 Acme : 2 screens</b> — amount, project : task. Add <b>hold 25.07</b>, or lead with
            ✅ ⌛ ❌ to set status.
          </p>
        </div>
      </Dropdown>

      <button
        type="button"
        className="composer__submit"
        disabled={!canCommit}
        onClick={() => void commit()}
        aria-label="Add line"
      >
        <ArrowUpIcon size={16} />
      </button>
    </div>
  );
}
