// The collapsible right rail. A month-independent anchor (all-time earned + a
// recent-months trend) keeps it alive even on an empty month; below it, the
// per-month status breakdown and this-month's top clients. Not the iOS Insights.
import { useMemo } from "react";
import { Link } from "react-router-dom";
import { STATUS_ORDER, statusTitle, isIncludedInEarnedTotals } from "../../domain/types";
import { convertToBase } from "../../domain/currency";
import { numberFromCents, formatMoney } from "../../domain/money";
import { monthNameOfDay, monthStartDayMs, sameMonthDay, todayDayMs } from "../../domain/dateFormat";
import { useClients, useEntries } from "../../state/data";
import { useSettings, currencySettings } from "../../state/settings";
import { STATUS_COLOR } from "../theme/theme";
import { StatusIcon } from "../icons";

export function RightRail({ monthMs }: { monthMs: number }) {
  const clients = useClients();
  const entries = useEntries();
  const settings = useSettings();
  const cs = currencySettings(settings);
  const base = settings.baseCurrencyCode;

  const { allTime, allTimeUnsupported, trend, rows, grand, earned, hasMonthData, monthUnsupported, topClients } =
    useMemo(() => {
      const monthTotals = new Map<number, number>();
      const months = new Set<number>();
      months.add(monthStartDayMs(todayDayMs()));
      const statusRows = new Map(STATUS_ORDER.map((status) => [status, { status, count: 0, sum: 0 }]));
      const clientTotals = new Map<string, number>();
      let allTime = 0;
      let allTimeUnsupported = 0;
      let monthUnsupported = 0;
      let hasMonthData = false;

      for (const entry of entries) {
        const entryMonth = monthStartDayMs(entry.date);
        months.add(entryMonth);
        const inMonth = sameMonthDay(entry.date, monthMs);
        const converted = convertToBase(numberFromCents(entry.amountCents), entry.currencyCode, cs);
        if (inMonth) {
          hasMonthData = true;
          const row = statusRows.get(entry.status)!;
          row.count += 1;
          if (converted != null) row.sum += converted;
        }
        if (!isIncludedInEarnedTotals(entry.status)) continue;
        if (converted == null) {
          allTimeUnsupported += 1;
          if (inMonth) monthUnsupported += 1;
          continue;
        }
        allTime += converted;
        monthTotals.set(entryMonth, (monthTotals.get(entryMonth) ?? 0) + converted);
        if (inMonth) {
          clientTotals.set(entry.clientId, (clientTotals.get(entry.clientId) ?? 0) + converted);
        }
      }

      const trend = [...months]
        .sort((left, right) => right - left)
        .slice(0, 6)
        .reverse()
        .map((month) => ({ month, value: monthTotals.get(month) ?? 0 }));
      const rows = STATUS_ORDER.map((status) => statusRows.get(status)!);
      const grand = rows.reduce((sum, row) => sum + row.sum, 0);
      const earned = rows
        .filter((row) => isIncludedInEarnedTotals(row.status))
        .reduce((sum, row) => sum + row.sum, 0);
      const topClients = clients
        .map((client) => ({ client, total: clientTotals.get(client.id) ?? 0 }))
        .filter((item) => item.total > 0)
        .sort((left, right) => right.total - left.total)
        .slice(0, 5);
      return {
        allTime,
        allTimeUnsupported,
        trend,
        rows,
        grand,
        earned,
        hasMonthData,
        monthUnsupported,
        topClients,
      };
    }, [clients, entries, monthMs, settings.baseCurrencyCode, settings.rate, settings.secondaryCurrencyCode]);
  const trendMax = Math.max(1, ...trend.map((item) => item.value));

  const monthLabel = monthNameOfDay(monthMs);
  const visibleRows = rows.filter((r) => r.count > 0);

  return (
    <aside className="rail" aria-label="Summary">
      <section className="rail-card rail-trend-card">
        <h2 className="rail-card__title">Earned, all time</h2>
        <div className="rail-trend__figure tabular">{formatMoney(allTime, base)}</div>
        {allTimeUnsupported > 0 && <p className="rail-card__warning">Unsupported currencies excluded</p>}
        <div className="rail-trend" role="list" aria-label="Recent earnings by month">
          {trend.map((t) => (
            <div
              className="rail-trend__col"
              key={t.month}
              role="listitem"
              title={`${monthNameOfDay(t.month)} · ${formatMoney(t.value, base)}`}
            >
              <span className="u-sr">
                {monthNameOfDay(t.month)}: {formatMoney(t.value, base)}
              </span>
              <div className="rail-trend__track" aria-hidden>
                <div
                  className={"rail-trend__bar" + (sameMonthDay(t.month, monthMs) ? " is-current" : "")}
                  style={{ ["--bar-scale" as string]: Math.max(0.04, t.value / trendMax) } as React.CSSProperties}
                />
              </div>
              <span className="rail-trend__label" aria-hidden>
                {monthNameOfDay(t.month).slice(0, 3)}
              </span>
            </div>
          ))}
        </div>
      </section>

      {hasMonthData ? (
        <section className="rail-card">
          <h2 className="rail-card__title">{monthLabel} · by status</h2>
          <div className="rail-stats">
            {visibleRows.map((r) => (
              <div className="rail-stat" key={r.status}>
                <div className="rail-stat__top">
                  <StatusIcon status={r.status} size={13} />
                  <span className="rail-stat__label">{statusTitle(r.status)}</span>
                  <span className="rail-stat__count">{r.count}</span>
                  <span className="rail-stat__val tabular">{formatMoney(r.sum, base)}</span>
                </div>
                <div className="rail-stat__track">
                  <span
                    className="rail-stat__fill"
                    style={{
                      ["--fill-scale" as string]: grand > 0 ? Math.max(0.02, Math.abs(r.sum) / grand) : 0,
                      background: STATUS_COLOR[r.status],
                    }}
                  />
                </div>
              </div>
            ))}
          </div>
          <div className="rail-card__foot">
            <span>Earned</span>
            <strong className="tabular">{formatMoney(earned, base)}</strong>
          </div>
          {monthUnsupported > 0 && <p className="rail-card__warning">Total incomplete</p>}
        </section>
      ) : (
        <p className="rail__hint">Nothing in {monthLabel} yet — the total above is all-time.</p>
      )}

      {topClients.length > 0 && (
        <section className="rail-card">
          <h2 className="rail-card__title">{monthLabel} · top clients</h2>
          <div className="rail-clients">
            {topClients.map(({ client, total }) => (
              <Link key={client.id} to={`/client/${client.id}`} className="rail-client">
                <span className="rail-client__dot" style={{ background: client.colorHex }} />
                <span className="rail-client__name">{client.name}</span>
                <span className="rail-client__total tabular">{formatMoney(total, base)}</span>
              </Link>
            ))}
          </div>
        </section>
      )}
    </aside>
  );
}
