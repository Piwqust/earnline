// Month separator with its subtotal. Ports Views/MonthDivider.swift.
import { monthNameOfDay } from "../domain/dateFormat";
import { MoneyAmountText } from "./MoneyAmountText";

export function MonthDivider({ monthMs, total }: { monthMs: number; total: number }) {
  return (
    <div className="month-divider">
      <span className="month-divider__title">{monthNameOfDay(monthMs)}</span>
      <span className="month-divider__rule" />
      <MoneyAmountText baseAmount={total} className="month-divider__total tabular" />
    </div>
  );
}
