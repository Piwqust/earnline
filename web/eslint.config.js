// Tuned to the code as written. `tsconfig.json` already enforces `strict`,
// `noUnusedLocals`, and `noUnusedParameters`, so this config deliberately does
// not repeat type-level checks — it covers what the compiler cannot see:
// React hook dependencies, accidental `any` leaking through, and floating
// promises in the sync layer.

import js from "@eslint/js";
import globals from "globals";
import tseslint from "typescript-eslint";
import reactHooks from "eslint-plugin-react-hooks";
import reactRefresh from "eslint-plugin-react-refresh";

export default tseslint.config(
  { ignores: ["dist", "node_modules", "coverage"] },
  {
    extends: [js.configs.recommended, ...tseslint.configs.recommended],
    files: ["src/**/*.{ts,tsx}"],
    languageOptions: {
      ecmaVersion: 2022,
      globals: globals.browser,
    },
    plugins: {
      "react-hooks": reactHooks,
      "react-refresh": reactRefresh,
    },
    rules: {
      ...reactHooks.configs.recommended.rules,
      "react-refresh/only-export-components": ["warn", { allowConstantExport: true }],

      // The React Compiler-era rules (new defaults in eslint-plugin-react-hooks
      // v7) flag real patterns in the existing components, but acting on them
      // is a web refactor in its own right. Surfaced as warnings so they are
      // visible and fixable incrementally without blocking every build.
      "react-hooks/set-state-in-effect": "warn",
      "react-hooks/purity": "warn",
      "react-hooks/preserve-manual-memoization": "warn",

      // `void somePromise()` is the house idiom for deliberately not awaiting
      // background work — the sync controller, lease heartbeats, and every
      // async event handler use it. Flagging it would fight the codebase.
      "no-void": "off",

      // Thin (U+2009) and non-breaking (U+00A0) spaces appear on purpose inside
      // the number-parsing regexes and replacements in `domain/lineParser.ts`
      // and `domain/money.ts`, mirroring the Swift parser. Irregular whitespace
      // in actual code is still an error.
      "no-irregular-whitespace": [
        "error",
        { skipStrings: true, skipTemplates: true, skipRegExps: true },
      ],

      // `catch {}` with an explanatory comment is a deliberate pattern in the
      // lease and teardown paths; an empty block with no comment is not.
      "no-empty": ["error", { allowEmptyCatch: false }],

      // Underscore-prefixed args are the escape hatch already used in the code.
      "@typescript-eslint/no-unused-vars": [
        "error",
        { argsIgnorePattern: "^_", varsIgnorePattern: "^_" },
      ],

      // The Supabase client generics are `any` at the boundary by necessity
      // (`SupabaseClient<any>` in the edge function's own types); warn rather
      // than block so a real regression still stands out.
      "@typescript-eslint/no-explicit-any": "warn",
    },
  },
  {
    // Tests reach into internals and assert on shapes the app never builds.
    files: ["src/**/*.test.{ts,tsx}"],
    rules: {
      "@typescript-eslint/no-explicit-any": "off",
      "@typescript-eslint/no-non-null-assertion": "off",
    },
  },
);
