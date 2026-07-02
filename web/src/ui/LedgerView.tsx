// The main ledger — desktop app shell: topbar (tracked month + total + New),
// a sticky command-bar composer, month sections, and the right summary rail.
import { useEffect, useMemo, useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import type { Client, Entry, EntryStatus, Heading } from "../domain/types";
import { clientsWithEntries, entriesOf, monthTotal, monthsWithData, totalOf } from "../domain/totals";
import { formatMoney } from "../domain/money";
import { monthNameOfDay, monthStartDayMs, sameMonthDay, todayDayMs } from "../domain/dateFormat";
import { Limits, trimmed } from "../domain/validation";
import { useClients, useEntries, useHeadings } from "../state/data";
import { useSettings, currencySettings } from "../state/settings";
import {
  deleteEntry,
  deleteHeading,
  setEntryStatus,
  updateHeading,
} from "../data/repository";
import { queueSync } from "../state/store";
import { MonthDivider } from "./MonthDivider";
import { ClientChip } from "./ClientChip";
import { EntryRow } from "./EntryRow";
import { SmartComposer } from "./SmartComposer";
import { EmptyStateView } from "./EmptyStateView";
import { NewClientDialog } from "./NewClientDialog";
import { HeadingDialog } from "./HeadingDialog";
import { EntryInspector } from "./EntryInspector";
import { MoneyAmountText } from "./MoneyAmountText";
import { RightRail } from "./components/RightRail";
import { Dropdown, DropdownItem } from "./components/Dropdown";
import { ConfirmDialog } from "./components/Dialog";
import { IconButton } from "./components/Button";
import { ChevronDownIcon, HeadingIcon, PanelRightIcon, PersonPlusIcon, PlusIcon, TrashIcon } from "./icons";

type Block =
  | { kind: "heading"; heading: Heading; sortIndex: number; createdAt: number }
  | { kind: "client"; client: Client; sortIndex: number; createdAt: number };

// How far below the scroll top a month divider must sit before it counts as the
// "displayed" month (clears the sticky composer).
const STICKY_OFFSET = 150;

export function LedgerView() {
  const navigate = useNavigate();
  const clients = useClients();
  const entries = useEntries();
  const headings = useHeadings();
  const settings = useSettings();
  const cs = currencySettings(settings);

  const [composerClientId, setComposerClientId] = useState<string | null>(null);
  const [showNewClient, setShowNewClient] = useState(false);
  const [editingEntry, setEditingEntry] = useState<Entry | null>(null);
  const [deletingEntry, setDeletingEntry] = useState<Entry | null>(null);
  const [headingDraft, setHeadingDraft] = useState<{ heading: Heading | null } | null>(null);
  const [deletingHeading, setDeletingHeading] = useState<Heading | null>(null);
  const [railOpen, setRailOpen] = useState(true);
  const [displayedMonth, setDisplayedMonth] = useState(() => monthStartDayMs(todayDayMs()));

  const scrollRef = useRef<HTMLDivElement>(null);
  const monthEls = useRef(new Map<number, HTMLElement | null>());
  const didInit = useRef(false);

  const months = useMemo(() => monthsWithData(entries), [entries]);
  const showEmpty = clients.length === 0 && entries.length === 0 && headings.length === 0;
  const base = settings.baseCurrencyCode;

  // The "never-dead" landing target: the most recent month that actually earned
  // something, so the app never opens on a tucked-away $0.
  const firstFundedMonth = useMemo(() => {
    for (const m of months) if (monthTotal(clients, entries, m, cs) > 0) return m;
    return months[0];
  }, [months, clients, entries, cs]);

  // Hero figures for the displayed month: total, line count, and the delta vs the
  // previous month that had earnings.
  const heroStats = useMemo(() => {
    const total = monthTotal(clients, entries, displayedMonth, cs);
    const lineCount = entries.filter((e) => sameMonthDay(e.date, displayedMonth)).length;
    const idx = months.indexOf(displayedMonth);
    let prev: { month: number; total: number } | null = null;
    if (idx >= 0) {
      for (let i = idx + 1; i < months.length; i++) {
        const t = monthTotal(clients, entries, months[i], cs);
        if (t > 0) {
          prev = { month: months[i], total: t };
          break;
        }
      }
    }
    // A calm month-over-month read. Huge swings (a quiet month → a big invoice)
    // collapse into a "×N" multiplier instead of a four-digit percentage.
    let delta: { dir: "up" | "down"; label: string } | null = null;
    if (prev && prev.total > 0) {
      const ref = monthNameOfDay(prev.month);
      const ratio = total / prev.total;
      if (ratio >= 1) {
        const pct = Math.round((ratio - 1) * 100);
        delta = { dir: "up", label: pct >= 1000 ? `${Math.round(ratio)}× vs ${ref}` : `${pct}% vs ${ref}` };
      } else {
        delta = { dir: "down", label: `${Math.round((1 - ratio) * 100)}% vs ${ref}` };
      }
    }
    return { total, lineCount, prev, delta };
  }, [clients, entries, displayedMonth, months, cs]);
  const heroEmpty = heroStats.total === 0;

  // Keep the composer aimed at a valid (most-recent) client.
  useEffect(() => {
    if (clients.length === 0) {
      if (composerClientId !== null) setComposerClientId(null);
      return;
    }
    if (composerClientId == null || !clients.some((c) => c.id === composerClientId)) {
      const recent = [...clients].sort((a, b) => b.createdAt - a.createdAt)[0];
      setComposerClientId(recent.id);
    }
  }, [clients, composerClientId]);

  // Land on the most recent funded month once data has loaded (once only, so it
  // never fights the scroll spy afterwards).
  useEffect(() => {
    if (didInit.current) return;
    if (clients.length === 0 && entries.length === 0) return;
    didInit.current = true;
    setDisplayedMonth(firstFundedMonth);
  }, [clients.length, entries.length, firstFundedMonth]);

  useEffect(() => {
    if (months.length && !months.includes(displayedMonth)) setDisplayedMonth(firstFundedMonth);
  }, [months, displayedMonth, firstFundedMonth]);

  function blocksIn(month: number): Block[] {
    const hs: Block[] = headings
      .filter((h) => sameMonthDay(h.date, month))
      .map((h) => ({ kind: "heading", heading: h, sortIndex: h.sortIndex, createdAt: h.createdAt }));
    const cls = clientsWithEntries(clients, entries, month);
    const cb: Block[] = cls.map((c) => ({ kind: "client", client: c, sortIndex: c.sortIndex, createdAt: c.createdAt }));
    return [...hs, ...cb].sort((a, b) =>
      a.sortIndex === b.sortIndex ? a.createdAt - b.createdAt : a.sortIndex - b.sortIndex,
    );
  }

  function onScroll() {
    const sc = scrollRef.current;
    if (!sc) return;
    const top = sc.getBoundingClientRect().top;
    let chosen: number | undefined;
    for (const m of months) {
      const el = monthEls.current.get(m);
      if (el && el.getBoundingClientRect().top - top <= STICKY_OFFSET) chosen = m;
    }
    if (chosen == null) chosen = months[0];
    if (chosen != null && chosen !== displayedMonth) setDisplayedMonth(chosen);
  }

  async function changeStatus(e: Entry, s: EntryStatus) {
    await setEntryStatus(e.id, s);
    queueSync();
  }
  async function confirmDeleteEntry() {
    if (!deletingEntry) return;
    await deleteEntry(deletingEntry.id);
    queueSync();
  }
  async function confirmDeleteHeading() {
    if (!deletingHeading) return;
    await deleteHeading(deletingHeading.id);
    queueSync();
  }

  return (
    <div className={"ledger-layout" + (railOpen ? " has-rail" : "")}>
      <div className="ledger-main">
        <header className="topbar ledger-hero">
          <div className="ledger-hero__lead">
            <span className="ledger-hero__kicker">Earned in {monthNameOfDay(displayedMonth)}</span>
            {heroEmpty ? (
              <div className="ledger-hero__emptyline">
                <span className="ledger-hero__prompt">Nothing logged yet</span>
                {heroStats.prev && (
                  <span className="ledger-hero__ref">
                    {monthNameOfDay(heroStats.prev.month)} brought in{" "}
                    <span className="tabular">{formatMoney(heroStats.prev.total, base)}</span>
                  </span>
                )}
              </div>
            ) : (
              <>
                <MoneyAmountText baseAmount={heroStats.total} className="ledger-hero__total tabular" />
                <div className="ledger-hero__context">
                  {heroStats.delta && (
                    <span className={"ledger-hero__delta is-" + heroStats.delta.dir}>
                      {heroStats.delta.dir === "up" ? "▲" : "▼"} {heroStats.delta.label}
                    </span>
                  )}
                  {heroStats.delta && (
                    <span className="ledger-hero__dot" aria-hidden>
                      ·
                    </span>
                  )}
                  <span className="ledger-hero__lines">
                    {heroStats.lineCount} {heroStats.lineCount === 1 ? "line" : "lines"}
                  </span>
                </div>
              </>
            )}
          </div>
          <div className="ledger-hero__actions">
            <Dropdown
              ariaLabel="Add"
              triggerClassName="btn btn--primary btn--md ledger-hero__new"
              trigger={
                <>
                  <PlusIcon size={15} />
                  <span>New</span>
                  <ChevronDownIcon size={12} />
                </>
              }
            >
              <DropdownItem onClick={() => setShowNewClient(true)}>
                <PersonPlusIcon size={16} />
                <span>New client</span>
              </DropdownItem>
              <DropdownItem onClick={() => setHeadingDraft({ heading: null })}>
                <HeadingIcon size={16} />
                <span>New heading</span>
              </DropdownItem>
            </Dropdown>
            <IconButton
              label={railOpen ? "Hide summary" : "Show summary"}
              className={"ledger-hero__railtoggle" + (railOpen ? " is-active" : "")}
              onClick={() => setRailOpen((o) => !o)}
            >
              <PanelRightIcon />
            </IconButton>
          </div>
        </header>

        <div className="ledger-scroll" ref={scrollRef} onScroll={onScroll}>
          {showEmpty ? (
            <EmptyStateView onStart={() => setShowNewClient(true)} />
          ) : (
            <>
              <div className="composer-wrap">
                <SmartComposer
                  clients={clients}
                  clientId={composerClientId}
                  onClientChange={setComposerClientId}
                  onNewClient={() => setShowNewClient(true)}
                />
              </div>

              <div className="ledger-content">
                {months.map((month) => {
                  const blocks = blocksIn(month);
                  return (
                    <section
                      key={month}
                      className="month"
                      ref={(el) => {
                        monthEls.current.set(month, el);
                      }}
                    >
                      {blocks.length === 0 ? (
                        <div className="month-empty">
                          <span className="month-empty__name">{monthNameOfDay(month)}</span>
                          <span className="month-empty__rule" />
                          <span className="month-empty__hint">Nothing logged yet</span>
                        </div>
                      ) : (
                        <>
                          <MonthDivider monthMs={month} total={monthTotal(clients, entries, month, cs)} />
                          {blocks.map((block) =>
                            block.kind === "heading" ? (
                              <HeadingRow
                                key={"h-" + block.heading.id}
                                heading={block.heading}
                                onDelete={() => setDeletingHeading(block.heading)}
                              />
                            ) : (
                              <div key={"c-" + block.client.id} className="client-group">
                                <ClientChip
                                  client={block.client}
                                  total={totalOf(block.client.id, entries, month, cs)}
                                  onOpen={() => navigate(`/client/${block.client.id}`)}
                                  onAdd={() => setComposerClientId(block.client.id)}
                                />
                                {entriesOf(block.client.id, entries, month).map((e) => (
                                  <EntryRow
                                    key={e.id}
                                    entry={e}
                                    onSetStatus={(s) => void changeStatus(e, s)}
                                    onEdit={() => setEditingEntry(e)}
                                    onDelete={() => setDeletingEntry(e)}
                                  />
                                ))}
                              </div>
                            ),
                          )}
                        </>
                      )}
                    </section>
                  );
                })}
              </div>
            </>
          )}
        </div>
      </div>

      {railOpen && <RightRail monthMs={displayedMonth} />}

      {showNewClient && (
        <NewClientDialog
          existingClients={clients}
          onClose={() => setShowNewClient(false)}
          onCreated={(c) => setComposerClientId(c.id)}
        />
      )}
      {headingDraft && (
        <HeadingDialog
          heading={headingDraft.heading}
          monthMs={displayedMonth}
          nextSortIndex={blocksIn(displayedMonth).reduce((m, b) => Math.max(m, b.sortIndex), -1) + 1}
          onClose={() => setHeadingDraft(null)}
        />
      )}
      {editingEntry && (
        <EntryInspector entry={editingEntry} clients={clients} onClose={() => setEditingEntry(null)} />
      )}
      {deletingEntry && (
        <ConfirmDialog
          title="Delete line?"
          message={
            <>
              This permanently removes <strong>{deletingEntry.task || "this line"}</strong> from the ledger.
            </>
          }
          confirmLabel="Delete line"
          onConfirm={() => void confirmDeleteEntry()}
          onClose={() => setDeletingEntry(null)}
        />
      )}
      {deletingHeading && (
        <ConfirmDialog
          title="Delete heading?"
          message={
            <>
              Delete the heading <strong>{deletingHeading.title || "Untitled"}</strong>? Lines underneath it stay.
            </>
          }
          confirmLabel="Delete heading"
          onConfirm={() => void confirmDeleteHeading()}
          onClose={() => setDeletingHeading(null)}
        />
      )}
    </div>
  );
}

function HeadingRow({ heading, onDelete }: { heading: Heading; onDelete: () => void }) {
  const [editing, setEditing] = useState(false);
  const [title, setTitle] = useState(heading.title);

  useEffect(() => {
    if (!editing) setTitle(heading.title);
  }, [heading.title, editing]);

  async function commit() {
    const clean = trimmed(title, Limits.maxHeadingLength);
    setEditing(false);
    if (clean !== "" && clean !== heading.title) {
      await updateHeading(heading.id, { title: clean });
      queueSync();
    } else {
      setTitle(heading.title);
    }
  }

  return (
    <div className="heading-row">
      {editing ? (
        <input
          className="heading-row__input"
          autoFocus
          value={title}
          onChange={(e) => setTitle(e.target.value.slice(0, Limits.maxHeadingLength))}
          onBlur={() => void commit()}
          onKeyDown={(e) => {
            if (e.key === "Enter") void commit();
            if (e.key === "Escape") {
              setTitle(heading.title);
              setEditing(false);
            }
          }}
        />
      ) : (
        <button type="button" className="heading-row__title" title="Rename heading" onClick={() => setEditing(true)}>
          {heading.title || "Untitled"}
        </button>
      )}
      <span className="heading-row__rule" />
      <IconButton label="Delete heading" size="sm" variant="danger" className="heading-row__del" onClick={onDelete}>
        <TrashIcon size={14} />
      </IconButton>
    </div>
  );
}
