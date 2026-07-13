// The main ledger — desktop app shell: topbar (tracked month + total + New),
// a sticky command-bar composer, month sections, and the right summary rail.
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import type { Entry, EntryStatus, Heading } from "../domain/types";
import { formatMoney } from "../domain/money";
import { monthNameOfDay, monthStartDayMs, todayDayMs } from "../domain/dateFormat";
import { Limits, trimmed } from "../domain/validation";
import { useClients, useDataReady, useEntries, useHeadings } from "../state/data";
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
import { LedgerSkeleton } from "./components/LedgerSkeleton";
import { Dropdown, DropdownItem } from "./components/Dropdown";
import { ConfirmDialog } from "./components/Dialog";
import { IconButton } from "./components/Button";
import { ChevronDownIcon, HeadingIcon, PanelRightIcon, PersonPlusIcon, PlusIcon, TrashIcon } from "./icons";
import { buildLedgerModel } from "./ledgerModel";

// How far below the scroll top a month divider must sit before it counts as the
// "displayed" month (clears the sticky composer).
const STICKY_OFFSET = 150;

export function LedgerView() {
  const navigate = useNavigate();
  const clients = useClients();
  const entries = useEntries();
  const headings = useHeadings();
  const dataReady = useDataReady();
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
  const [actionError, setActionError] = useState<string | null>(null);

  const scrollRef = useRef<HTMLDivElement>(null);
  const ledgerContentRef = useRef<HTMLDivElement>(null);
  const monthEls = useRef(new Map<number, HTMLElement | null>());
  const monthOffsets = useRef<Array<{ month: number; top: number }>>([]);
  const didInit = useRef(false);
  const scrollFrame = useRef<number | null>(null);

  const ledgerModel = useMemo(
    () => buildLedgerModel(clients, entries, headings, cs),
    [clients, entries, headings, settings.baseCurrencyCode, settings.rate, settings.secondaryCurrencyCode],
  );
  const months = ledgerModel.months;
  const showEmpty = clients.length === 0 && entries.length === 0 && headings.length === 0;
  const base = settings.baseCurrencyCode;

  // The "never-dead" landing target: the most recent month that actually earned
  // something, so the app never opens on a tucked-away $0.
  const firstFundedMonth = useMemo(() => {
    for (const month of months) if ((ledgerModel.byMonth.get(month)?.total ?? 0) > 0) return month;
    return months[0];
  }, [ledgerModel, months]);

  // Hero figures for the displayed month: total, line count, and the delta vs the
  // previous month that had earnings.
  const heroStats = useMemo(() => {
    const displayed = ledgerModel.byMonth.get(displayedMonth);
    const total = displayed?.total ?? 0;
    const lineCount = displayed?.lineCount ?? 0;
    const unsupportedCount = displayed?.unsupportedCount ?? 0;
    const idx = months.indexOf(displayedMonth);
    let prev: { month: number; total: number } | null = null;
    if (idx >= 0) {
      for (let i = idx + 1; i < months.length; i++) {
        const t = ledgerModel.byMonth.get(months[i])?.total ?? 0;
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
    return { total, lineCount, unsupportedCount, prev, delta };
  }, [displayedMonth, ledgerModel, months]);
  const heroEmpty = heroStats.lineCount === 0;

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

  const updateDisplayedMonthFromScroll = useCallback(() => {
    const scroller = scrollRef.current;
    const offsets = monthOffsets.current;
    if (!scroller || offsets.length === 0) return;

    const target = scroller.scrollTop + STICKY_OFFSET;
    let low = 0;
    let high = offsets.length - 1;
    let chosen = offsets[0].month;
    while (low <= high) {
      const middle = Math.floor((low + high) / 2);
      if (offsets[middle].top <= target) {
        chosen = offsets[middle].month;
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }
    setDisplayedMonth((current) => (current === chosen ? current : chosen));
  }, []);

  const measureMonthOffsets = useCallback(() => {
    const scroller = scrollRef.current;
    if (!scroller) return;
    const rootTop = scroller.getBoundingClientRect().top;
    monthOffsets.current = months
      .flatMap((month) => {
        const element = monthEls.current.get(month);
        return element
          ? [{ month, top: element.getBoundingClientRect().top - rootTop + scroller.scrollTop }]
          : [];
      })
      .sort((left, right) => left.top - right.top);
  }, [months]);

  function onScroll() {
    if (scrollFrame.current != null) return;
    scrollFrame.current = requestAnimationFrame(() => {
      scrollFrame.current = null;
      updateDisplayedMonthFromScroll();
    });
  }

  useEffect(() => {
    const scroller = scrollRef.current;
    if (!scroller || !dataReady) return;
    measureMonthOffsets();
    const observer = typeof ResizeObserver === "undefined" ? null : new ResizeObserver(measureMonthOffsets);
    observer?.observe(scroller);
    if (ledgerContentRef.current) observer?.observe(ledgerContentRef.current);
    window.addEventListener("resize", measureMonthOffsets);
    return () => {
      observer?.disconnect();
      window.removeEventListener("resize", measureMonthOffsets);
    };
  }, [dataReady, measureMonthOffsets]);

  useEffect(
    () => () => {
      if (scrollFrame.current != null) cancelAnimationFrame(scrollFrame.current);
    },
    [],
  );

  async function changeStatus(e: Entry, s: EntryStatus) {
    setActionError(null);
    try {
      await setEntryStatus(e.id, s);
      queueSync();
    } catch {
      setActionError("The line status could not be saved. Try again.");
    }
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

  if (!dataReady) return <LedgerSkeleton />;

  return (
    <div className={"ledger-layout" + (railOpen ? " has-rail" : "")}>
      <div className="ledger-main">
        <header className="topbar ledger-hero">
          <div className="ledger-hero__lead">
            <h1 className="ledger-hero__kicker">Earned in {monthNameOfDay(displayedMonth)}</h1>
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
                  {heroStats.unsupportedCount > 0 && (
                    <span className="total-incomplete">Unsupported currencies excluded</span>
                  )}
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

        {actionError && (
          <p className="ledger-feedback" role="alert">
            {actionError}
          </p>
        )}

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

              <div ref={ledgerContentRef} className="ledger-content">
                {months.map((month) => {
                  const model = ledgerModel.byMonth.get(month);
                  const blocks = model?.blocks ?? [];
                  return (
                    <section
                      key={month}
                      className="month"
                      aria-label={monthNameOfDay(month)}
                      ref={(el) => {
                        if (el) monthEls.current.set(month, el);
                        else monthEls.current.delete(month);
                      }}
                    >
                      {blocks.length === 0 ? (
                        <div className="month-empty">
                          <h2 className="month-empty__name">{monthNameOfDay(month)}</h2>
                          <span className="month-empty__rule" />
                          <span className="month-empty__hint">Nothing logged yet</span>
                        </div>
                      ) : (
                        <>
                          <MonthDivider
                            monthMs={month}
                            total={model?.total ?? 0}
                            unsupportedCount={model?.unsupportedCount ?? 0}
                          />
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
                                  total={block.total}
                                  unsupportedCount={block.unsupportedCount}
                                  onOpen={() => navigate(`/client/${block.client.id}`)}
                                  onAdd={() => setComposerClientId(block.client.id)}
                                />
                                {block.entries.map((e) => (
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
          nextSortIndex={
            (ledgerModel.byMonth.get(displayedMonth)?.blocks ?? []).reduce(
              (maximum, block) => Math.max(maximum, block.sortIndex),
              -1,
            ) + 1
          }
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
          onConfirm={confirmDeleteEntry}
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
          onConfirm={confirmDeleteHeading}
          onClose={() => setDeletingHeading(null)}
        />
      )}
    </div>
  );
}

function HeadingRow({ heading, onDelete }: { heading: Heading; onDelete: () => void }) {
  const [editing, setEditing] = useState(false);
  const [title, setTitle] = useState(heading.title);
  const [saveError, setSaveError] = useState<string | null>(null);
  const cancelCommit = useRef(false);

  useEffect(() => {
    if (!editing) setTitle(heading.title);
  }, [heading.title, editing]);

  async function commit() {
    if (cancelCommit.current) {
      cancelCommit.current = false;
      return;
    }
    const clean = trimmed(title, Limits.maxHeadingLength);
    if (clean !== "" && clean !== heading.title) {
      try {
        await updateHeading(heading.id, { title: clean });
        queueSync();
        setSaveError(null);
        setEditing(false);
      } catch {
        setSaveError("Could not save heading.");
        setEditing(true);
      }
    } else {
      setTitle(heading.title);
      setSaveError(null);
      setEditing(false);
    }
  }

  return (
    <div className="heading-row">
      {editing ? (
        <input
          className="heading-row__input"
          aria-label="Heading title"
          autoFocus
          value={title}
          onChange={(e) => {
            setTitle(e.target.value.slice(0, Limits.maxHeadingLength));
            setSaveError(null);
          }}
          onBlur={() => void commit()}
          onKeyDown={(e) => {
            if (e.key === "Enter") void commit();
            if (e.key === "Escape") {
              cancelCommit.current = true;
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
      {saveError && (
        <span className="heading-row__error" role="alert">
          {saveError}
        </span>
      )}
      <span className="heading-row__rule" />
      <IconButton label="Delete heading" size="sm" variant="danger" className="heading-row__del" onClick={onDelete}>
        <TrashIcon size={14} />
      </IconButton>
    </div>
  );
}
