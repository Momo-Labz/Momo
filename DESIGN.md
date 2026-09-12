---
# gstack: design-md-format=spec
name: BAR BOY
description: A compact pixel-industrial command surface with hard edges, honest data, and one coral interruption signal.
colors:
  primary: "#211F1E"
  on-primary: "#F3F2F2"
  surface: "#2B2928"
  text: "#F3F2F2"
  text-muted: "#A5A09D"
  accent: "#E25C48"
  success: "#7C9A78"
  warning: "#D39A53"
  error: "#E25C48"
typography:
  display:
    fontFamily: "Menlo Bold"
    fontWeight: 700
    fontSize: "15px"
    letterSpacing: "0.06em"
  body:
    fontFamily: "SF Pro Text"
    fontSize: "11px"
    lineHeight: 1.4
  label:
    fontFamily: "Menlo Bold"
    fontSize: "9px"
    letterSpacing: "0.08em"
  mono:
    fontFamily: "Menlo"
    fontFeature: "tnum"
rounded:
  sm: "0px"
  md: "2px"
  lg: "4px"
  full: "9999px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "16px"
  lg: "24px"
  xl: "32px"
  2xl: "48px"
components:
  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.on-primary}"
    rounded: "{rounded.sm}"
  button-primary-hover:
    backgroundColor: "#343130"
  input:
    borderColor: "{colors.text-muted}"
    rounded: "{rounded.sm}"
  card:
    backgroundColor: "{colors.surface}"
    rounded: "{rounded.sm}"
  nav-link:
    textColor: "{colors.text}"
---

# BAR BOY

## Overview

**Creative North Star:** A pocket mission-control panel made by Momo Labz, where structure is visible, interruptions are rare, and every pixel earns its place.

**Product context:** A native macOS menu-bar hub and iOS companion for people running Codex, Claude, Gemini, Cursor, and Grok sessions at the same time. Its core job is to remove human-response latency, not to become another chat client.

**Mode per surface:** The compact menu popup is an Operate glance surface. The expanded desktop hub is an Operate investigation surface. The iOS companion is an Operate return queue. The desk display is a Read surface.

**Reference:** The user-supplied HeyClicky screenshot informs the top navigation, shortcut keycaps, and horizontal composition. BAR BOY keeps its own Momo Labz pixel identity, hard edges, and return-queue hierarchy.

**Key characteristics:**

- A short menu-bar mark opens a models-only strip before the full hub.
- The expanded window extends the same 430-point provider strip downward into a scrolling list grouped by provider (user revision, 2026-09-12). Session details expose capability provenance.
- Menlo labels, one-pixel rules, square surfaces, and the Momo monitor character create the 8-bit identity.
- Coral is used only for human-blocking returns and failures.
- Provider marks are recognizable without competing with the Momo Labz brand.

## Colors

**Strategy:** Restrained. Monochrome carries information density and coral is reserved for work that cannot continue without the person.

**Light or dark:** Both are system-responsive because a menu-bar utility follows the Mac's current work environment. Light mode uses paper-white space and ink surfaces; dark mode uses warm-black space and paper-white type. Dark mode is designed as its own surface treatment rather than a literal inversion.

Interactive selection uses the primary ink/paper pair. Accent never decorates neutral content. Muted text may describe provenance but never the blocking action.

## Typography

Menlo Bold is the display, navigation, label, and numeric voice because it matches the existing pixel identity and keeps columns stable. SF Pro Text is limited to short explanatory copy where native legibility matters. Type stays compact, but labels and body text differ in family, case, tracking, and size so hierarchy does not depend on weight alone.

## Layout

The menu popup is a single horizontal provider strip. The desktop window begins at 760 by 500 points and can expand. Its main grid uses a flexible work area, a one-pixel divider, and a fixed 222-point action rail. Home prioritizes the return queue, Agents prioritizes model/session density, and Tools exposes capability provenance. iOS keeps the same three information modes in a full-width tab strip.

The rhythm uses 4 and 8 point micro spacing, 16 to 18 point section gaps, and 24 to 32 point breathing room only at major boundaries.

## Elevation & Depth

Depth comes from warm neutral surface tints and one-pixel rules. There are no glow halos, glass layers, or stacked cards. The strong action is a flat inverse block.

## Shapes

Primary controls and data surfaces are square. A 2-point radius is permitted only for tiny optical corrections; the large and full radius tokens are reserved for system-owned controls and must not become the default visual language.

## Components

Primary actions invert the entire rectangular surface. Provider cards use the provider's real app icon when installed and a recognizable monochrome glyph otherwise. Urgent rows use a coral outline and tint. Selected tabs are filled rectangles. Keycaps are separate 24-point rectangular tokens. Disabled future voice actions are visibly labeled NEXT rather than appearing functional.

## Do's and Don'ts

- Do keep the compact menu popup limited to provider state and one Expand action.
- Do use coral only when an agent needs the person or has failed.
- Do preserve provider attribution and distinguish main agents from subagents.
- Do keep labels short enough to survive small menu and desk-display surfaces.
- Do let the expanded window grow horizontally.
- Don't copy HeyClicky's name, mascot, rounded-card styling, or upgrade treatment.
- Don't animate live counters, keyboard shortcuts, or polling updates.
- Don't hide unavailable usage behind invented percentages.
- Don't use nested cards, gradients, glow, or decorative dashboard metrics.
- Don't put personal prompts or provider credentials in the relay payload.

## Motion

- **Approach:** Minimal-functional, weighted toward Emil Kowalski's frequency rule and Jakub Krehel's production subtlety.
- **Easing:** Enter uses a fast native-style deceleration; exit is opacity-only; state changes use a no-bounce timing curve.
- **Duration:** Button press 80ms, Momo entrance 220ms, page transition 200ms.
- **Momo motion:** Native 13 × 14 pixel frames and holds from `../Branding/index.html`: LOOK plus two WALK cycles in the dashboard and compact strip; a 300ms-per-pose wave in Quick Ask. Frames switch without interpolation. Reduce Motion, inactive scenes, and static previews use the resting pose. Tasks cancel when the view disappears. This supersedes the original entrance-only treatment at the user’s request (2026-09-12).

## Decisions Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-09-10 | Use a compact models-only popup plus an expandable three-tab hub | It keeps the menu interaction fast while preserving a serious workspace for agents and tools. |
| 2026-09-10 | Keep provider marks monochrome and subordinate to Momo Labz | Providers remain recognizable without turning the product into a logo collage. |
| 2026-09-10 | Use one-shot Momo motion and no looping attention animation | It adds identity without making a frequently used productivity tool tiring. |
