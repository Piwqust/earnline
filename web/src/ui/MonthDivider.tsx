// Month separator with its subtotal. Ports Views/MonthDivider.swift.
import { monthNameOfDay } from "../domain/dateFormat";
import { MoneyAmountText } from "./MoneyAmountText";

export function MonthDivider({
  monthMs,
  total,
  unsupportedCount = 0,
}: {
  monthMs: number;
  total: number;
  unsupportedCount?: number;
}) {
  return (
    <div className="month-divider">
      <h2 className="month-divider__title">{monthNameOfDay(monthMs)}</h2>
      <span className="month-divider__rule" />
      {unsupportedCount > 0 && (
        <span className="month-divider__incomplete" title="Unsupported currencies are excluded from this total">
          Total incomplete
        </span>
      )}
      <MoneyAmountText baseAmount={total} className="month-divider__total tabular" />
    </div>
  );
}
