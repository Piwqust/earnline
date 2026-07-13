// A tappable money label that flips between primary and secondary currency.
// Ports Views/MoneyAmountText.swift.
import { useState } from "react";
import { useSettings, currencySettings } from "../state/settings";
import { secondaryValue } from "../domain/currency";
import { currencySymbol, formatMoney } from "../domain/money";

/** Split the (unchanged) formatted string into its currency symbol + the rest,
 *  purely for presentation — the value/formatting is never touched. */
function splitSymbol(text: string, code: string): { lead: string; core: string; trail: string } {
  const symbol = currencySymbol(code);
  if (symbol) {
    if (text.startsWith(symbol)) return { lead: symbol, core: text.slice(symbol.length), trail: "" };
    if (text.endsWith(symbol)) return { lead: "", core: text.slice(0, text.length - symbol.length), trail: symbol };
  }
  return { lead: "", core: text, trail: "" };
}

export function MoneyAmountText({
  baseAmount,
  className,
  approximate = false,
  dim = false,
}: {
  baseAmount: number;
  className?: string;
  approximate?: boolean;
  /** Step the currency symbol back from the digits (via .money__sym). */
  dim?: boolean;
}) {
  const settings = useSettings();
  const cs = currencySettings(settings);
  const [showSecondary, setShowSecondary] = useState(false);

  const value = showSecondary ? secondaryValue(baseAmount, cs) : baseAmount;
  const code = showSecondary ? settings.secondaryCurrencyCode : settings.baseCurrencyCode;
  const nextCode = showSecondary ? settings.baseCurrencyCode : settings.secondaryCurrencyCode;
  const text = formatMoney(value, code);
  const { lead, core, trail } = dim ? splitSymbol(text, code) : { lead: "", core: text, trail: "" };

  return (
    <button
      type="button"
      className={"money" + (className ? " " + className : "")}
      title={`Show ${nextCode}`}
      aria-label={`${approximate ? `${text}, approximate` : text}. Show ${nextCode}`}
      aria-pressed={showSecondary}
      onClick={(e) => {
        e.stopPropagation();
        setShowSecondary((s) => !s);
      }}
    >
      <span className="money__value">
        {lead && <span className="money__sym">{lead}</span>}
        {core}
        {trail && <span className="money__sym">{trail}</span>}
      </span>
      {approximate && (
        <span className="money__approx" aria-hidden>
          ·?
        </span>
      )}
    </button>
  );
}
