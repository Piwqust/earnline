import type { EntryStatus } from "../../domain/types";

// Design tokens lifted from the earn›line Figma (Theme.swift).
export const BLUE = "#0088FF";
export const PURPLE = "#7B00FF";

export const STATUS_COLOR: Record<EntryStatus, string> = {
  paid: "#8E8E93", // gray — already paid, unremarkable
  inProgress: "#FF8A00", // orange — in progress
  canceled: "#FF3B30", // red — canceled
};

export const STATUS_TEXT_COLOR: Record<EntryStatus, string> = {
  paid: "var(--paid-text)",
  inProgress: "var(--progress-text)",
  canceled: "var(--canceled-text)",
};

const LIGHT_FOREGROUND = "#f9fbff";
const DARK_FOREGROUND = "#101217";

function channel(value: string): number {
  const normalized = Number.parseInt(value, 16) / 255;
  return normalized <= 0.04045 ? normalized / 12.92 : ((normalized + 0.055) / 1.055) ** 2.4;
}

function luminance(hex: string): number | null {
  const match = /^#([0-9a-f]{6})$/i.exec(hex.trim());
  if (!match) return null;
  const value = match[1];
  return channel(value.slice(0, 2)) * 0.2126 + channel(value.slice(2, 4)) * 0.7152 + channel(value.slice(4, 6)) * 0.0722;
}

/** Pick a stable AA foreground for arbitrary user/client colors. */
export function readableForeground(background: string): string {
  const backgroundLuminance = luminance(background);
  if (backgroundLuminance == null) return LIGHT_FOREGROUND;
  const lightLuminance = luminance(LIGHT_FOREGROUND) ?? 1;
  const darkLuminance = luminance(DARK_FOREGROUND) ?? 0;
  const lightContrast = (lightLuminance + 0.05) / (backgroundLuminance + 0.05);
  const darkContrast = (backgroundLuminance + 0.05) / (darkLuminance + 0.05);
  return darkContrast >= lightContrast ? DARK_FOREGROUND : LIGHT_FOREGROUND;
}

/** Calm palette offered when creating new clients. */
export const CLIENT_PALETTE: string[] = [
  "#0088FF", // blue
  "#7B00FF", // purple
  "#FF7A45", // coral
  "#16B364", // green
  "#E8467C", // pink
  "#0FB5BA", // teal
  "#F5A623", // amber
  "#6E56CF", // indigo
];

export function paletteColor(index: number): string {
  return CLIENT_PALETTE[index % CLIENT_PALETTE.length];
}
