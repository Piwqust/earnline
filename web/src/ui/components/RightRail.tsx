// The collapsible right rail: month roll-ups re-presented from existing
// selectors (status breakdown + top clients). Not the iOS Insights screen.
import { useMemo } from "react";
import { Link } from "react-router-dom";
import { STATUS_ORDER, statusTitle, isIncludedInEarnedTotals } from "../../domain/types";
import { toBase } from "../../domain/currency";
import { numberFromCents, formatMoney } from "../../domain/money";
import { sameMonthDay, monthNameOfDay } from "../../domain/dateFormat";
import { clientsWithEntries, totalOf } from "../../domain/totals";
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

  const { rows, grand, earned } = useMemo(() => {
    const monthEntries = entries.filter((e) => sameMonthDay(e.date, monthMs));
    const rows = STATUS_ORDER.map((s) => {
      const list = monthEntries.filter((e) => e.status === s);
      const sum = list.reduce((a, e) => a + toBase(numberFromCents(e.amountCents), e.currencyCode, cs), 0);
      return { status: s, count: list.length, sum };
    });
    const grand = rows.reduce((a, r) => a + r.sum, 0);
    const earned = rows.filter((r) => isIncludedInEarnedTotals(r.status)).reduce((a, r) => a + r.sum, 0);
    return { rows, grand, earned };
  }, [entries, monthMs, cs]);

  const topClients = useMemo(
    () =>
      clientsWithEntries(clients, entries, monthMs)
        .map((c) => ({ client: c, total: totalOf(c.id, entries, monthMs, cs) }))
        .filter((x) => x.total > 0)
        .sort((a, b) => b.total - a.total)
        .slice(0, 6),
    [clients, entries, monthMs, cs],
  );

  const hasData = grand !== 0 || topClients.length > 0;

  return (
    <aside className="rail" aria-label="Month summary">
      <div className="rail__head">{monthNameOfDay(monthMs)}</div>

      {!hasData ? (
        <p className="rail__empty">No income recorded this month yet.</p>
      ) : (
        <>
          <section className="rail-card">
            <h3 className="rail-card__title">By status</h3>
            <div className="rail-stats">
              {rows.map((r) => (
                <div className="rail-stat" key={r.status}>
                  <div className="rail-stat__top">
                    <StatusIcon status={r.status} size={13} />
                    <span className="rail-stat__label">{statusTitle(r.status)}</span>
                    {r.count > 0 && <span className="rail-stat__count">{r.count}</span>}
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

          {topClients.length > 0 && (
            <section className="rail-card">
              <h3 className="rail-card__title">Top clients</h3>
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
        </>
      )}
    </aside>
  );
}
