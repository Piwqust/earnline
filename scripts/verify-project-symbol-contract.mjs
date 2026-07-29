import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

const root = process.cwd();
const symbols = JSON.parse(await readFile(resolve(root, "supabase/contract/project-symbols.json"), "utf8"));
if (!Array.isArray(symbols) || symbols.length === 0 || symbols.some((value) => typeof value !== "string")) {
  throw new Error("supabase/contract/project-symbols.json must contain a non-empty string array.");
}
if (new Set(symbols).size !== symbols.length) throw new Error("Project symbol contract contains duplicates.");

const swift = await readFile(resolve(root, "ios-app/earnline/Models/SyncState.swift"), "utf8");
const enumBody = swift.match(/enum ProjectSymbol:[\s\S]*?\n\s*var id:/)?.[0] ?? "";
const swiftSymbols = [...enumBody.matchAll(/^\s*case\s+\w+(?:\s*=\s*"([^"]+)")?/gm)]
  .map((match) => match[1] ?? match[0].replace(/^\s*case\s+/, "").trim());

function sameSet(actual, expected, label) {
  const missing = expected.filter((value) => !actual.includes(value));
  const extra = actual.filter((value) => !expected.includes(value));
  if (missing.length || extra.length || new Set(actual).size !== actual.length) {
    throw new Error(`${label} diverges from the canonical project-symbol contract. Missing: ${missing.join(", ") || "none"}; extra: ${extra.join(", ") || "none"}.`);
  }
}

sameSet(swiftSymbols, symbols, "Swift ProjectSymbol");

const edge = await readFile(resolve(root, "supabase/functions/earnline-sync/index.ts"), "utf8");
if (!edge.includes('import projectSymbols from "../../contract/project-symbols.json"')) {
  throw new Error("The Edge function must import the canonical project-symbol contract.");
}

const migration = await readFile(resolve(root, "supabase/migrations/20260729100000_harden_sync_invariants.sql"), "utf8");
const missingFromSQL = symbols.filter((symbol) => !migration.includes(`'${symbol}'`));
if (missingFromSQL.length) {
  throw new Error(`The database symbol constraint is missing: ${missingFromSQL.join(", ")}.`);
}

console.log(`Project symbol contract verified (${symbols.length} symbols).`);
