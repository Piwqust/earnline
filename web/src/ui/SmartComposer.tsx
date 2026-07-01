// The persistent command bar — pick a client, type a line as live pills, commit.
// Keeps the structured-field logic of the old composer; restyled for desktop and
// given a leading client selector so it can live at the top of the ledger.
import { useEffect, useMemo, useRef, useState } from "react";
import type { Client, EntryStatus } from "../domain/types";
import { STATUS_ORDER, statusTitle } from "../domain/types";
import {
  centsFromNumber,
  currencySymbol,
  parseDecimalString,
  SUPPORTED_CURRENCY_CODES,
} from "../domain/money";
import { Limits, capped, clampAmount, sanitizeAmountInput, trimmed } from "../domain/validation";
import { dayMsFromInputValue, inputValueFromDayMs, todayDayMs } from "../domain/dateFormat";
import { useSettings } from "../state/settings";
import { useEntries } from "../state/data";
import { createEntry } from "../data/repository";
import { queueSync } from "../state/store";
import { STATUS_COLOR } from "./theme/theme";
import { ClientTag } from "./components/ClientTag";
import { Dropdown, DropdownItem, DropdownSection, DropdownDivider } from "./components/Dropdown";
import {
  ArrowUpIcon,
  CalendarIcon,
  ChevronDownIcon,
  CloseIcon,
  PlusIcon,
  StatusIcon,
} from "./icons";

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

  const [amountText, setAmountText] = useState("");
  const [project, setProject] = useState("");
  const [task, setTask] = useState("");
  const [entryDateMs, setEntryDateMs] = useState(todayDayMs());
  const [holdUntilMs, setHoldUntilMs] = useState<number | null>(null);
  const [status, setStatus] = useState<EntryStatus>("paid");
  const [currencyCode, setCurrencyCode] = useState(settings.baseCurrencyCode);

  const amountRef = useRef<HTMLInputElement>(null);
  const projectRef = useRef<HTMLInputElement>(null);
  const taskRef = useRef<HTMLInputElement>(null);

  const currentClient = clients.find((c) => c.id === clientId) ?? clients[0] ?? null;

  // Focus the amount field when the target client changes (e.g. via "+ Line").
  useEffect(() => {
    if (currentClient) amountRef.current?.focus({ preventScroll: true });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [clientId]);

  const amountCents = useMemo(() => {
    const d = parseDecimalString(amountText);
    if (d == null || d <= 0) return null;
    return centsFromNumber(clampAmount(d));
  }, [amountText]);

  const canCommit = amountCents != null && trimmed(task, Limits.maxTaskLength) !== "";

  const existingProjects = useMemo(() => {
    const seen = new Set<string>();
    const result: string[] = [];
    for (const e of [...allEntries].sort((a, b) => b.createdAt - a.createdAt)) {
      const raw = (e.project ?? "").trim();
      if (raw === "") continue;
      if (!seen.has(raw.toLowerCase())) {
        seen.add(raw.toLowerCase());
        result.push(raw);
      }
      if (result.length >= 12) break;
    }
    return result;
  }, [allEntries]);

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
    if (amountCents == null) {
      amountRef.current?.focus();
      return;
    }
    const cleanTask = trimmed(task, Limits.maxTaskLength);
    if (cleanTask === "") {
      taskRef.current?.focus();
      return;
    }
    const cleanProject = trimmed(project, Limits.maxProjectLength);
    const clientEntries = allEntries.filter((e) => e.clientId === currentClient!.id);
    const minIndex = clientEntries.length ? Math.min(...clientEntries.map((e) => e.sortIndex)) : 0;

    await createEntry({
      clientId: currentClient!.id,
      amountCents,
      currencyCode,
      project: cleanProject === "" ? null : cleanProject,
      task: cleanTask,
      date: entryDateMs,
      holdUntil: holdUntilMs,
      status,
      sortIndex: minIndex - 1,
    });
    queueSync();

    setAmountText("");
    setProject("");
    setTask("");
    setHoldUntilMs(null);
    setStatus("paid");
    setEntryDateMs(todayDayMs());
    setCurrencyCode(settings.baseCurrencyCode);
    amountRef.current?.focus();
  }

  return (
    <div className="composer">
      <div className="composer__fields">
        {/* client selector */}
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

        {/* amount */}
        <div className="cpill cpill--amount">
          <Dropdown
            ariaLabel="Currency"
            align="left"
            triggerClassName="cpill__currency"
            trigger={currencySymbol(currencyCode)}
          >
            {SUPPORTED_CURRENCY_CODES.map((code) => (
              <DropdownItem key={code} onClick={() => setCurrencyCode(code)}>
                <span style={{ width: 20, display: "inline-block" }}>{currencySymbol(code)}</span>
                <span>{code}</span>
              </DropdownItem>
            ))}
          </Dropdown>
          <input
            ref={amountRef}
            className="cpill__input tabular"
            inputMode="decimal"
            placeholder="100"
            value={amountText}
            style={{ width: `${Math.max(3, amountText.length || 3)}ch` }}
            onChange={(e) => setAmountText(sanitizeAmountInput(e.target.value))}
            onKeyDown={(e) => {
              if (e.key === "Enter") {
                e.preventDefault();
                projectRef.current?.focus();
              }
            }}
          />
        </div>

        {/* project */}
        <div className="cpill">
          <input
            ref={projectRef}
            className="cpill__input"
            placeholder="Project"
            value={project}
            style={{ width: `${Math.max(6, project.length || 7)}ch` }}
            onChange={(e) => setProject(capped(e.target.value, Limits.maxProjectLength))}
            onKeyDown={(e) => {
              if (e.key === "Enter") {
                e.preventDefault();
                taskRef.current?.focus();
              }
            }}
          />
          {existingProjects.length > 0 && (
            <Dropdown ariaLabel="Pick a project" triggerClassName="cpill__chev" trigger={<ChevronDownIcon size={11} />}>
              <DropdownSection>Recent projects</DropdownSection>
              {existingProjects.map((name) => (
                <DropdownItem
                  key={name}
                  onClick={() => {
                    setProject(name);
                    taskRef.current?.focus();
                  }}
                >
                  <span>{name}</span>
                </DropdownItem>
              ))}
            </Dropdown>
          )}
        </div>

        {/* status */}
        <Dropdown
          ariaLabel="Status"
          triggerClassName="cpill cpill--status"
          trigger={
            <span className="cpill--status__inner" style={{ ["--st" as string]: STATUS_COLOR[status] } as React.CSSProperties}>
              <StatusIcon status={status} size={14} />
              <span>{statusTitle(status)}</span>
              <ChevronDownIcon size={10} />
            </span>
          }
        >
          {STATUS_ORDER.map((s) => (
            <DropdownItem key={s} onClick={() => setStatus(s)}>
              <StatusIcon status={s} size={16} />
              <span>{statusTitle(s)}</span>
            </DropdownItem>
          ))}
        </Dropdown>

        <span className="composer__grow" />

        {/* dates */}
        <label className="cpill cpill--date">
          <CalendarIcon size={13} />
          <input
            type="date"
            value={inputValueFromDayMs(entryDateMs)}
            onChange={(e) => {
              const ms = dayMsFromInputValue(e.target.value);
              if (ms != null) {
                setEntryDateMs(ms);
                if (holdUntilMs != null && holdUntilMs < ms) setHoldUntilMs(ms);
              }
            }}
          />
        </label>
        {holdUntilMs == null ? (
          <button type="button" className="cpill cpill--ghost" onClick={() => setHoldUntilMs(entryDateMs)}>
            <CalendarIcon size={13} />
            <span>Hold</span>
          </button>
        ) : (
          <span className="cpill cpill--date">
            <span className="cpill__lead">Hold</span>
            <input
              type="date"
              value={inputValueFromDayMs(holdUntilMs)}
              min={inputValueFromDayMs(entryDateMs)}
              onChange={(e) => {
                const ms = dayMsFromInputValue(e.target.value);
                if (ms != null) setHoldUntilMs(Math.max(ms, entryDateMs));
              }}
            />
            <button type="button" aria-label="Clear hold" className="cpill__clear" onClick={() => setHoldUntilMs(null)}>
              <CloseIcon size={12} />
            </button>
          </span>
        )}
      </div>

      <div className="composer__submit-row">
        <input
          ref={taskRef}
          className="composer__task"
          placeholder="What was it? (e.g. 2 screens for the landing page)"
          value={task}
          onChange={(e) => setTask(capped(e.target.value, Limits.maxTaskLength))}
          onKeyDown={(e) => {
            if (e.key === "Enter") {
              e.preventDefault();
              void commit();
            }
          }}
        />
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
    </div>
  );
}
