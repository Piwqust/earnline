// The client's colored name capsule (white text on the client color).
import type { ReactNode } from "react";

export function ClientTag({
  name,
  color,
  size = "md",
  onClick,
  title,
  trailing,
}: {
  name: string;
  color: string;
  size?: "sm" | "md" | "lg";
  onClick?: () => void;
  title?: string;
  trailing?: ReactNode;
}) {
  const className = `client-tag client-tag--${size}` + (onClick ? " is-button" : "");
  const style = { background: color } as React.CSSProperties;
  const inner = (
    <>
      <span className="client-tag__name">{name}</span>
      {trailing}
    </>
  );
  if (onClick) {
    return (
      <button type="button" className={className} style={style} onClick={onClick} title={title ?? name}>
        {inner}
      </button>
    );
  }
  return (
    <span className={className} style={style} title={title ?? name}>
      {inner}
    </span>
  );
}
