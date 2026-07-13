export function LedgerSkeleton() {
  return (
    <div className="ledger-skeleton" role="status" aria-live="polite" aria-label="Loading ledger">
      <h1 className="u-sr">Ledger</h1>
      <div className="ledger-skeleton__hero" aria-hidden>
        <span />
        <strong />
        <span />
      </div>
      <div className="ledger-skeleton__composer" aria-hidden />
      <div className="ledger-skeleton__rows" aria-hidden>
        {Array.from({ length: 6 }, (_, index) => (
          <span key={index} />
        ))}
      </div>
    </div>
  );
}
