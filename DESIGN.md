---
name: "earn›line"
description: "A calm, precise iPhone-first income ledger with an optional web companion."
colors:
  accent-blue: "#0088FF"
  accent-blue-pressed: "#0072E0"
  canvas-light: "#F2F2F7"
  surface-light: "#FFFFFF"
  ink-light: "#1A1A1A"
  canvas-dark: "#0C0C0F"
  surface-dark: "#1C1C1E"
  ink-dark: "#F2F2F4"
  paid: "#8E8E93"
  progress: "#FF8A00"
  canceled: "#FF3B30"
typography:
  display:
    fontFamily: "SF Pro Display, Inter Variable, -apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "46px"
    fontWeight: 700
    lineHeight: 1.05
    letterSpacing: "-0.025em"
  headline:
    fontFamily: "SF Pro Display, Inter Variable, -apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "24px"
    fontWeight: 650
    lineHeight: 1.15
    letterSpacing: "-0.015em"
  title:
    fontFamily: "SF Pro Text, Inter Variable, -apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "17px"
    fontWeight: 600
    lineHeight: 1.25
  body:
    fontFamily: "SF Pro Text, Inter Variable, -apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "16px"
    fontWeight: 400
    lineHeight: 1.4
  label:
    fontFamily: "SF Pro Text, Inter Variable, -apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "13px"
    fontWeight: 550
    lineHeight: 1.25
rounded:
  control: "12px"
  panel: "20px"
  sheet: "26px"
  pill: "999px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "24px"
  xxl: "32px"
components:
  button-primary:
    backgroundColor: "{colors.accent-blue}"
    textColor: "{colors.surface-light}"
    typography: "{typography.title}"
    rounded: "{rounded.control}"
    padding: "12px 18px"
    height: "44px"
  button-primary-active:
    backgroundColor: "{colors.accent-blue-pressed}"
    textColor: "{colors.surface-light}"
    typography: "{typography.title}"
    rounded: "{rounded.control}"
    padding: "12px 18px"
    height: "44px"
  icon-button:
    backgroundColor: "{colors.surface-light}"
    textColor: "{colors.ink-light}"
    rounded: "{rounded.pill}"
    size: "44px"
  field:
    backgroundColor: "{colors.surface-light}"
    textColor: "{colors.ink-light}"
    typography: "{typography.body}"
    rounded: "{rounded.control}"
    padding: "12px 14px"
    height: "44px"
  client-chip:
    textColor: "{colors.surface-light}"
    typography: "{typography.label}"
    rounded: "{rounded.pill}"
    padding: "6px 12px"
---

# Design System: earn›line

## Overview

**Creative North Star: "Quiet Ledger"**

Earnline should feel like a carefully kept working notebook: immediate enough for a ten-second entry, structured enough to trust at a glance, and quiet enough to revisit many times a day. The interface serves the ledger rather than performing around it. Numbers, client names, work descriptions, and status carry the hierarchy; chrome recedes until it is needed.

iOS and web share product semantics, color roles, typographic character, and component discipline, but each platform stays native. The native iPhone app is the primary product experience: it sets everyday interaction priority and release quality. The web is an optional desktop companion with a sidebar, ledger, and summary rail; it supports the iPhone workflow rather than setting a parallel direction. Neither platform imitates the other mechanically.

**Key Characteristics:**

- Calm, precise, contemporary, and trustworthy.
- Restrained color with one blue interaction accent.
- Dense but breathable ledger rows, not dashboard tiles.
- Familiar platform controls with explicit states and generous targets.
- Motion limited to state feedback, reveal, and spatial continuity.

**The Content-First Rule.** Every decorative decision must make the ledger easier to scan or operate. If it does neither, remove it.

**The Platform-Native Rule.** Share meaning and tokens across platforms, never platform-inappropriate layout or controls.

## Colors

The palette uses cool, slightly blue-tinted neutrals so the interface feels crisp without becoming sterile. The accent is deliberately rare.

### Primary

- **Signal Blue:** the sole default interaction accent. Use it for the primary action, focus, current selection, and active navigation.

### Secondary

- **Client Identity Colors:** user-selected colors distinguish clients in compact tags and markers. They never become large page backgrounds or utility-icon colors.

### Neutral

- **Quiet Canvas:** the app background and outer chrome layer.
- **Paper Surface:** the main content, fields, and structurally elevated panels.
- **Cool Ink:** primary text; use opacity or the neutral ladder for secondary labels and metadata.
- **Hairline:** low-contrast separators establish grouping without turning every region into a card.

### Semantic

- **Paid Gray:** completed income, intentionally unremarkable.
- **Progress Orange:** active work that needs attention.
- **Canceled Red:** exclusion or destructive meaning only.

**The Ten-Percent Accent Rule.** Signal Blue occupies no more than roughly 10% of a screen. Its scarcity makes actions legible.

**The Meaningful Color Rule.** Client color identifies a client; status color communicates status; blue communicates interaction. Never swap these roles for decoration.

## Typography

**Display Font:** SF Pro Display on iOS; Inter Variable with the system stack on the web.

**Body Font:** SF Pro Text on iOS; Inter Variable with the system stack on the web.

**Label/Mono Font:** SF Mono only for technical identifiers or fixed-width diagnostics in developer-only surfaces.

**Character:** A single modern sans-serif voice keeps the product native and numerically clear. Hierarchy comes from scale, weight, alignment, and spacing, not from ornamental font changes.

### Hierarchy

- **Display** (700, 46 px, 1.05): a single high-value total or insight, never a grid of competing hero metrics.
- **Headline** (650, 24 px, 1.15): screen and major-section titles.
- **Title** (600, 17 px, 1.25): client names, grouped totals, row-leading values, and prominent controls.
- **Body** (400, 16 px, 1.4): work descriptions, settings values, instructions, and form input.
- **Label** (550, 13 px, 1.25): dates, statuses, field labels, and compact supporting metadata.

**The Numeric Scan Rule.** Use tabular figures for aligned totals and repeated monetary values. Amount, description, and date must form stable scan columns.

**The Dynamic Type Rule.** iOS text scales through semantic metrics. At accessibility sizes, reflow or hide secondary content before shrinking, clipping, or reducing the target below 44 pt.

## Elevation

Earnline is flat by default. Structure comes from surface tone, spacing, alignment, and hairlines. Shadows are reserved for transient layers such as menus, dialogs, panels, and web overlays. iOS uses Liquid Glass only for functional navigation and control chrome; content cards use solid or standard material surfaces.

### Shadow Vocabulary

- **Low Ambient:** the web's subtle resting shadow for floating controls and the composer; it must never look like a dark outline.
- **Medium Lift:** hover or temporary raised state on an interactive panel.
- **Overlay Lift:** dialogs, dropdowns, and inspectors only.

**The Flat-by-Default Rule.** A resting content surface has no decorative shadow. If every region appears elevated, hierarchy has failed.

**The Functional Glass Rule.** Liquid Glass belongs to toolbars, navigation, menus, and transient controls. It is prohibited on summary cards, ledger rows, and content containers.

## Components

### Buttons

- **Shape:** compact rounded rectangle on the web (12 px); native concentric shape on iOS. Every frequent action has a minimum 44 pt target.
- **Primary:** Signal Blue with high-contrast foreground. Only one primary emphasis per local decision area.
- **Hover / Focus:** web hover changes tone without bouncing; focus uses a visible blue ring. iOS uses native pressed and accessibility behavior.
- **Secondary / Ghost / Danger:** secondary uses a neutral surface and hairline; ghost is reserved for low-priority chrome; danger is red only for destructive confirmation.

### Chips

- **Style:** client chips use the client's identity color with compact high-contrast text. Status is not encoded as a client-style chip.
- **State:** selected client state can add emphasis or a checkmark; inactive utility chips stay neutral.

### Cards / Containers

- **Corner Style:** 20 px for web panels and 26 pt for iOS sheets where concentric geometry is appropriate.
- **Background:** solid Paper Surface over Quiet Canvas.
- **Shadow Strategy:** flat for content; overlay lift only for transient layers.
- **Border:** one subtle hairline when separation cannot be achieved with spacing or tone.
- **Internal Padding:** 16–24 px depending on density; nested cards are prohibited.

### Inputs / Fields

- **Style:** solid or gently sunken neutral surface, 12 px corner radius on web, native SwiftUI field treatment on iOS, and a minimum 44 pt target.
- **Focus:** visible Signal Blue focus ring on web; native focus and keyboard behavior on iOS.
- **Error / Disabled:** error includes text or iconography in addition to color; disabled controls remain legible and visibly noninteractive.

### Navigation

- **iOS:** use native navigation, sheets, searchable behavior, menus, and predictable action placement. A first tap must reveal and focus search.
- **Web:** persistent sidebar on desktop, off-canvas navigation on narrow screens, with clear selected state and keyboard reachability.
- **Utility actions:** one monochrome SF Symbol or coherent web icon family; no generic colored settings glyphs.

### Ledger Row

- **Hierarchy:** amount first, project/task second, date and hold metadata third, status last.
- **Behavior:** the full row remains scannable; edit/delete gestures or controls are discoverable and preserved through refactors.
- **State:** canceled rows are visibly excluded without becoming illegible; unsupported conversions explain why a total is incomplete.

### Smart Composer

- **Character:** one direct writing surface, closer to Notes than an enterprise form.
- **Behavior:** parse progressively, keep optional status/date/currency controls secondary, preserve keyboard flow, and surface validation without clearing the user's text.

## Do's and Don'ts

### Do

- **Do** put everyday actions within immediate reach and keep advanced controls intentionally recessed.
- **Do** use one coherent monochrome icon language for utility actions.
- **Do** prefer familiar iOS behavior and web-native controls over decorative novelty.
- **Do** verify 44 pt targets, Dynamic Type, VoiceOver, keyboard focus, Reduce Motion, dark mode, empty, loading, error, offline, and long-content states.
- **Do** compare before/after screenshots at the same simulator or viewport for every visual change.
- **Do** let amount, description, client, date, and status define the ledger's visual rhythm.

### Don't

- **Don't** use generic colored settings glyphs.
- **Don't** turn settings or the ledger into a dense developer dashboard or enterprise admin console.
- **Don't** use tiny floating controls or unexplained toolbar actions.
- **Don't** use Liquid Glass, blur, or glassmorphism as a decorative content-card treatment.
- **Don't** build repeated hero-metric cards, identical card grids, nested cards, gradient text, or colored side-stripe accents.
- **Don't** rely on color alone for status, error, selection, or destructive meaning.
- **Don't** introduce one-off colors, radii, shadows, icons, or control styles outside the shared token and component vocabulary.
