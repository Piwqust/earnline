# Contributing to earn›line

earn›line is an **iPhone-first monorepo**. The native SwiftUI app is the
primary product surface; the web client is an optional desktop companion, and
Supabase supports private sync between them. The most important technical rule
is to keep the shared contract in lock-step without turning the companion into
a parallel product direction.

## Layout & ownership

| Path | What | Stack |
| --- | --- | --- |
| [`ios-app/`](ios-app) | **Primary iPhone app** | SwiftUI (iOS 26) · SwiftData · Supabase Swift |
| [`web/`](web) | Optional desktop companion | React · Vite · TypeScript · Dexie · supabase-js |
| [`supabase/`](supabase) | Private sync contract | Postgres schema + migrations |
| [`docs/`](docs) | Screenshots and operator documentation | — |

Review ownership is declared in [`.github/CODEOWNERS`](.github/CODEOWNERS).

## The one rule: don't break the wire format

Both apps read and write the **same** Supabase tables with an identical
convention, so a line added on the phone shows up in the browser and vice-versa.
That contract is:

- amounts as 2-decimal strings, days as `yyyy-MM-dd` (UTC), timestamps ISO-8601;
- snake_case columns, status in `{paid, inProgress, canceled}`, a `workspace_id`
  on every row;
- a deterministic ID hash shared by both clients (`DeterministicID.swift` ↔
  `deterministicId.ts`).

A change to any of these — or to anything in [`supabase/`](supabase) — must be
made in **both** apps and covered by the mirrored test cases, or the two clients
will drift out of sync.

## Working on the primary iOS app

```bash
cd ios-app
xcodegen generate        # regenerate earnline.xcodeproj
open earnline.xcodeproj
```

## Working on the optional web companion

```bash
cd web
npm install
npm run dev              # http://localhost:5173
npm test                # Vitest (parser / money / validation / wire-format parity)
npm run typecheck
npm run build
```

## CI

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs both apps on every
pull request: the **iOS** job (XcodeGen + `xcodebuild test`) and the **web** job
(Vitest + production build). Keep CI green before merging. A web-only change
still needs to preserve the iPhone-led product model; a shared sync change needs
matching coverage in both clients.
