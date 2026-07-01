// A tappable money label that flips between primary and secondary currency.
// Ports Views/MoneyAmountText.swift.
import { useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { useSettings, currencySettings } from "../state/settings";
import { secondaryValue } from "../domain/currency";
import { formatMoney } from "../domain/money";

export function MoneyAmountText({
  baseAmount,
  className,
  approximate = false,
}: {
  baseAmount: number;
  className?: string;
  approximate?: boolean;
}) {
  const settings = useSettings();
  const cs = currencySettings(settings);
  const [showSecondary, setShowSecondary] = useState(false);

  const value = showSecondary ? secondaryValue(baseAmount, cs) : baseAmount;
  const code = showSecondary ? settings.secondaryCurrencyCode : settings.baseCurrencyCode;
  const nextCode = showSecondary ? settings.baseCurrencyCode : settings.secondaryCurrencyCode;
  const text = formatMoney(value, code);

  return (
    <button
      type="button"
      className={"money" + (className ? " " + className : "")}
      title={`Tap to show ${nextCode}`}
      aria-label={approximate ? `${text}, approximate` : text}
      onClick={(e) => {
        e.stopPropagation();
        setShowSecondary((s) => !s);
      }}
    >
      <AnimatePresence mode="popLayout" initial={false}>
        <motion.span
          key={text}
          initial={{ opacity: 0, y: 8 }}
          animate={{ opacity: 1, y: 0 }}
          exit={{ opacity: 0, y: -8 }}
          transition={{ duration: 0.22, ease: [0.2, 0.8, 0.2, 1] }}
        >
          {text}
        </motion.span>
      </AnimatePresence>
      {approximate && <span className="money__approx">·?</span>}
    </button>
  );
}
