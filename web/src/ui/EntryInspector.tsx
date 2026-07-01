// Edit an existing line in a right slide-in panel. Replaces EditEntrySheet.
import { useMemo, useState } from "react";
import type { Client, Entry, EntryStatus } from "../domain/types";
import { toBase, secondaryValue } from "../domain/currency";
import {
  centsFromNumber,
  currencySymbol,
  formatMoney,
  numberFromCents,
  parseDecimalString,
  SUPPORTED_CURRENCY_CODES,
} from "../domain/money";
import { Limits, capped, clampAmount, sanitizeAmountInput, trimmed } from "../domain/validation";
import { dayMsFromInputValue, inputValueFromDayMs } from "../domain/dateFormat";
import { useSettings, currencySettings } from "../state/settings";
import { updateEntry } from "../data/repository";
import { queueSync } from "../state/store";
import { Panel } from "./components/Panel";
import { StatusPicker } from "./components/StatusPicker";
import { Field, Select } from "./components/Field";
import { Dropdown, DropdownItem } from "./components/Dropdown";
import { ChevronDownIcon } from "./icons";

export function EntryInspector({
  entry,
  clients,
  onClose,
}: {
  entry: Entry;
  clients: Client[];
  onClose: () => void;
}) {
  const settings = useSettings();
  const cs = currencySettings(settings);

  const [amountText, setAmountText] = useState(String(numberFromCents(entry.amountCents)));
  const [project, setProject] = useState(entry.project ?? "");
  const [task, setTask] = useState(entry.task);
  const [currencyCode, setCurrencyCode] = useState(entry.currencyCode);
  const [dateMs, setDateMs] = useState(entry.date);
  const [hasHold, setHasHold] = useState(entry.holdUntil != null);
  const [holdMs, setHoldMs] = useState(entry.holdUntil ?? entry.date);
  const [status, setStatus] = useState<EntryStatus>(entry.status);
  const [clientId, setClientId] = useState(entry.clientId);

  const amountCents = useMemo(() => {
    const d = parseDecimalString(amountText);
    return d != null && d > 0 ? centsFromNumber(clampAmount(d)) : null;
  }, [amountText]);

  const canSave = amountCents != null && clientId !== "" && trimmed(task, Limits.maxTaskLength) !== "";

  const secondaryHint =
    amountCents == null
      ? "Enter an amount"
      : `≈ ${formatMoney(
          secondaryValue(toBase(numberFromCents(amountCents), currencyCode, cs), cs),
          settings.secondaryCurrencyCode,
        )}`;

  async function save() {
    if (amountCents == null) return;
    const p = trimmed(project, Limits.maxProjectLength);
    await updateEntry(entry.id, {
      amountCents,
      currencyCode,
      project: p === "" ? null : p,
      task: trimmed(task, Limits.maxTaskLength),
      date: dateMs,
      holdUntil: hasHold ? holdMs : null,
      status,
      clientId,
    });
    queueSync();
    onClose();
  }

  return (
    <Panel
      title="Edit line"
      onClose={onClose}
      footer={
        <>
          <button type="button" className="btn btn--secondary btn--md" onClick={onClose}>
            <span>Cancel</span>
          </button>
          <button
            type="button"
            className="btn btn--primary btn--md"
            disabled={!canSave}
            onClick={() => void save()}
          >
            <span>Save changes</span>
          </button>
        </>
      }
    >
      <div className="inspector-amount">
        <Dropdown
          align="left"
          ariaLabel="Currency"
          triggerClassName="cur-pill"
          trigger={
            <>
              <span>{currencyCode}</span>
              <ChevronDownIcon size={11} />
            </>
          }
        >
          {SUPPORTED_CURRENCY_CODES.map((code) => (
            <DropdownItem key={code} onClick={() => setCurrencyCode(code)}>
              <span style={{ width: 20, display: "inline-block" }}>{currencySymbol(code)}</span>
              <span>{code}</span>
            </DropdownItem>
          ))}
        </Dropdown>
        <div className="inspector-amount__row">
          <span className="inspector-amount__sym">{currencySymbol(currencyCode)}</span>
          <input
            className="inspector-amount__input tabular"
            inputMode="decimal"
            placeholder="0"
            data-autofocus
            value={amountText}
            onChange={(e) => setAmountText(sanitizeAmountInput(e.target.value))}
            style={{ width: `${Math.max(1, amountText.length || 1)}ch` }}
          />
        </div>
        <span className="inspector-amount__hint tabular">{secondaryHint}</span>
      </div>

      <Field label="Status">
        <StatusPicker value={status} onChange={setStatus} />
      </Field>

      <Field label="Project">
        <input
          className="input"
          placeholder="Project (optional)"
          value={project}
          onChange={(e) => setProject(capped(e.target.value, Limits.maxProjectLength))}
        />
      </Field>

      <Field label="Task">
        <textarea
          className="textarea"
          placeholder="What was it?"
          value={task}
          onChange={(e) => setTask(capped(e.target.value, Limits.maxTaskLength))}
        />
      </Field>

      <Field label="Client">
        <Select value={clientId} onChange={(e) => setClientId(e.target.value)}>
          {clients.map((c) => (
            <option key={c.id} value={c.id}>
              {c.name}
            </option>
          ))}
        </Select>
      </Field>

      <Field label="Date">
        <input
          className="input"
          type="date"
          value={inputValueFromDayMs(dateMs)}
          onChange={(e) => {
            const ms = dayMsFromInputValue(e.target.value);
            if (ms != null) {
              setDateMs(ms);
              if (holdMs < ms) setHoldMs(ms);
            }
          }}
        />
      </Field>

      <div className="inspector-hold">
        <label className="inspector-hold__toggle">
          <input type="checkbox" checked={hasHold} onChange={(e) => setHasHold(e.target.checked)} />
          <span>Hold until a date</span>
        </label>
        {hasHold && (
          <input
            className="input"
            type="date"
            value={inputValueFromDayMs(holdMs)}
            min={inputValueFromDayMs(dateMs)}
            onChange={(e) => {
              const ms = dayMsFromInputValue(e.target.value);
              if (ms != null) setHoldMs(Math.max(ms, dateMs));
            }}
          />
        )}
      </div>
    </Panel>
  );
}
