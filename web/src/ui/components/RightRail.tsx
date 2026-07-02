// The collapsible right rail. A month-independent anchor (all-time earned + a
// recent-months trend) keeps it alive even on an empty month; below it, the
// per-month status breakdown and this-month's top clients. Not the iOS Insights.
import { useMemo } from "react";
import { Link } from "react-router-dom";
import { STATUS_ORDER, statusTitle, isIncludedInEarnedTotals } from "../../domain/types";
import { toBase } from "../../domain/currency";
import { numberFromCents, formatMoney } from "../../domain/money";
import { sameMonthDay, monthNameOfDay } from "../../domain/dateFormat";
import { clientsWithEntries, clientTotalAll, monthTotal, monthsWithData, totalOf } from "../../domain/totals";
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

  // Month-independent anchor: all-time earned + the last six months as bars.
  const { allTime, trend } = useMemo(() => {
    const allTime = clients.reduce((a, c) => a + clientTotalAll(c.id, entries, cs), 0);
    const recent = monthsWithData(entries).slice(0, 6).reverse();
    const trend = recent.map((m) => ({ month: m, value: monthTotal(clients, entries, m, cs) }));
    return { allTime, trend };
  }, [clients, entries, cs]);
  const trendMax = Math.max(1, ...trend.map((t) => t.value));

  const { rows, grand, earned, hasMonthData } = useMemo(() => {
    const monthEntries = entries.filter((e) => sameMonthDay(e.date, monthMs));
    const rows = STATUS_ORDER.map((s) => {
      const list = monthEntries.filter((e) => e.status === s);
      const sum = list.reduce((a, e) => a + toBase(numberFromCents(e.amountCents), e.currencyCode, cs), 0);
      return { status: s, count: list.length, sum };
    });
    const grand = rows.reduce((a, r) => a + r.sum, 0);
    const earned = rows.filter((r) => isIncludedInEarnedTotals(r.status)).reduce((a, r) => a + r.sum, 0);
    return { rows, grand, earned, hasMonthData: monthEntries.length > 0 };
  }, [entries, monthMs, cs]);

  const topClients = useMemo(
    () =>
      clientsWithEntries(clients, entries, monthMs)
        .map((c) => ({ client: c, total: totalOf(c.id, entries, monthMs, cs) }))
        .filter((x) => x.total > 0)
        .sort((a, b) => b.total - a.total)
        .slice(0, 5),
    [clients, entries, monthMs, cs],
  );

  const monthLabel = monthNameOfDay(monthMs);
  const visibleRows = rows.filter((r) => r.count > 0);

  return (
    <aside className="rail" aria-label="Summary">
      <section className="rail-card rail-trend-card">
        <h3 className="rail-card__title">Earned, all time</h3>
        <div className="rail-trend__figure tabular">{formatMoney(allTime, base)}</div>
        <div className="rail-trend" aria-hidden>
          {trend.map((t) => (
            <div
              className="rail-trend__col"
              key={t.month}
              title={`${monthNameOfDay(t.month)} · ${formatMoney(t.value, base)}`}
            >
              <div className="rail-trend__track">
                <div
                  className={"rail-trend__bar" + (sameMonthDay(t.month, monthMs) ? " is-current" : "")}
                  style={{ height: `${Math.max(4, (t.value / trendMax) * 100)}%` }}
                />
              </div>
              <span className="rail-trend__label">{monthNameOfDay(t.month).slice(0, 3)}</span>
            </div>
          ))}
        </div>
      </section>

      {hasMonthData ? (
        <section className="rail-card">
          <h3 className="rail-card__title">{monthLabel} · by status</h3>
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
                      width: `${grand > 0 ? Math.max(2, (Math.abs(r.sum) / grand) * 100) : 0}%`,
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
        </section>
      ) : (
        <p className="rail__hint">Nothing in {monthLabel} yet — the total above is all-time.</p>
      )}

      {topClients.length > 0 && (
        <section className="rail-card">
          <h3 className="rail-card__title">{monthLabel} · top clients</h3>
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
