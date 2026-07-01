// Shown when the ledger is completely empty.
import { ReceiptIcon } from "./icons";

export function EmptyStateView({ onStart }: { onStart: () => void }) {
  return (
    <div className="empty">
      <div className="empty__glyph">
        <ReceiptIcon size={26} />
      </div>
      <h2 className="empty__title">Start your ledger</h2>
      <p className="empty__text">
        Jot income the way you would type it in Notes. earn›line totals it up by month, client,
        and status.
      </p>
      <div className="empty__example tabular">
        <span className="empty__example-amt">+$240</span>
        <span className="empty__example-sep">·</span>
        <span>Acme</span>
        <span className="empty__example-sep">·</span>
        <span className="empty__example-task">2 screens</span>
      </div>
      <button type="button" className="btn btn--primary btn--lg" onClick={onStart}>
        <span>Add your first client</span>
      </button>
    </div>
  );
}
