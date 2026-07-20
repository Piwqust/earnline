// Color picker — a row of brand-palette circles.
import { useRef } from "react";

export function Swatches({
  colors,
  value,
  onChange,
}: {
  colors: string[];
  value: string;
  onChange: (hex: string) => void;
}) {
  const refs = useRef<Array<HTMLButtonElement | null>>([]);

  function move(from: number, delta: number) {
    const next = (from + delta + colors.length) % colors.length;
    onChange(colors[next]);
    requestAnimationFrame(() => refs.current[next]?.focus());
  }

  return (
    <div className="swatches" role="radiogroup" aria-label="Color">
      {colors.map((hex, index) => {
        const selected = hex === value;
        return (
          <button
            key={hex}
            ref={(node) => {
              refs.current[index] = node;
            }}
            type="button"
            role="radio"
            aria-checked={selected}
            aria-label={`Color ${hex}`}
            tabIndex={selected ? 0 : -1}
            className={"swatch" + (selected ? " is-selected" : "")}
            style={{ background: hex, color: hex }}
            onClick={() => onChange(hex)}
            onKeyDown={(event) => {
              if (event.key === "ArrowRight" || event.key === "ArrowDown") {
                event.preventDefault();
                move(index, 1);
              } else if (event.key === "ArrowLeft" || event.key === "ArrowUp") {
                event.preventDefault();
                move(index, -1);
              }
            }}
          />
        );
      })}
    </div>
  );
}
