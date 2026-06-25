# Guided payout-config UX redesign

**Date:** 2026-06-25
**Status:** Design — pending review
**Type:** UX redesign of the payout-flow node config form (mobile)

## Problem

The node config form (`lib/features/finances/payout_editor/config/node_config_form.dart`)
is functional but reads like a raw data dump: uppercase section headers
(`SOURCE` / `INCOMING ALLOCATION` / `DISTRIBUTION`) over bare `label: value`
rows with dropdowns. "Incoming allocation → Type → Remainder" tells the user
nothing about *what taking the remainder does*. The three payoutGroup sections
are the conceptually hardest part of the whole feature and have no explanatory
scaffolding. Users can't tell what their choices mean.

## Goal

Replace the raw form with a **guided, plain-language config** that explains each
choice, consistent across all node types, with a live payout preview.

## Design

### Shared shell (every node type)

A common config-screen structure so all node types feel consistent:

1. **Tab chips** at the top (1 or more steps depending on type), tappable for
   free movement — not a linear wizard. Save is always available in the nav bar.
2. **Question heading + subtitle** per step — e.g. "Who gets paid?" /
   "Choose where this group's people come from." — instead of a bare section label.
3. **Described option cards** instead of dropdowns: each choice is a tappable
   card with an icon, a title, and a one-line plain-English description of what it
   does. The selected card is highlighted with a checkmark. (Replaces `_EnumField`
   for the primary choices; secondary numeric/text inputs stay as fields.)
4. **Worked-example hints** inline — e.g. "Incoming $1,500 → this group takes
   $1,500 (the remainder)" and "$1,500 ÷ 3 people = $500 each".
5. **Pinned live-preview bar** at the bottom showing that node's computed result
   (members / amount / per-person), refreshed as the user edits. Driven by the
   `node_values` we already fetch via the preview API.

### Per-type step layout

- **payoutGroup** → **3 tabs**:
  - **Recipients** — "Who gets paid?": source type as option cards
    (Roster / All members / Specific people / Payment group / Role slots), plus
    the source-specific config (roster role filter, allMembers toggles, specific-
    member picker, role slots) under the chosen source. Preview: "pays N people".
  - **Take** — "How much does this group take?": incomingAllocationType as cards
    (Remainder / Percentage / Fixed) + the value field when not remainder.
    Preview: "this group gets $X".
  - **Split** — "How is it split?": distributionMode as cards (Equally /
    By percentage / Fixed per member / Tiered / Weighted) + the mode-specific
    editor (fixed-amount field, per-member allocations list, tier table).
    Overrides (respect custom payouts, minimum payout) live here too.
    Preview: "each member gets $X".
- **income** → **1 tab** ("Income"): label + amount, in the same style.
- **bandCut** → **1 tab** ("The cut"): cut type as cards
  (Percentage / Fixed / Tiered) + value or tier table. Preview: "takes $X, $Y to members".
- **conditional** → **1 tab** ("Condition"): condition summary + type/operator/
  value, TRUE/FALSE explained. (Backend doesn't branch yet — note it.)

Simple types get the consistent shell (tab chip + question + described cards +
preview) but no padded extra steps.

## Components

New, focused widgets (keep `node_config_form.dart` from ballooning):

- `GuidedConfigScaffold` — the shell: nav bar (title + Save/Delete), tab chips,
  the active step's body, and the pinned preview bar. Takes a list of steps and
  the current node's preview values.
- `ConfigStep` — a (title, question, subtitle, builder) describing one tab.
- `OptionCard` / `OptionCardGroup` — the described, tappable single-select cards
  (icon + title + description + checkmark) replacing `_EnumField` for primary choices.
- `PreviewBar` — the pinned bottom bar; formats label + value from `node_values`.
- `_payoutGroupSteps()` / `_incomeStep()` / `_bandCutStep()` / `_conditionalStep()`
  — build the `ConfigStep` lists per type.

Reused as-is inside the new structure: `_NumberField`, `_TextField`,
`_ToggleField` (secondary inputs), and the nested-list editors
(`TierConfigField`, `MemberAllocationsField`, `RoleSlotsField`,
`SpecificMembersField`, `RosterRoleFilterField`). The friendly-label maps
(`PayoutNodeOptions.labelFor`) feed the option-card titles. The
descriptions/icons are a new static map keyed by (field, value).

## Data flow

- The form still edits the node's `data` map in place and calls `onChanged`
  (host repaints + persists) — unchanged contract.
- The preview bar reads the per-node values the editor already fetches
  (`_nodeValues[node.id]`). The form receives the current node's values (or a
  callback to read them) so the preview + worked examples reflect real numbers.
  When values are absent (preview not yet loaded / amount 0), the preview bar
  shows a neutral placeholder rather than stale numbers.

## Out of scope / non-goals

- No change to what gets saved (`data` keys are identical — this is presentation).
- No change to the backend or the calc.
- Not a linear wizard — tabs are freely navigable (editing convenience).
- Conditional branching still isn't evaluated by the backend; the UI just
  explains TRUE/FALSE, same as today.

## Testing

**Widget tests** (new — `test/features/finances/payout_config_form_test.dart`),
pumping the form for a given node `data` and asserting behaviour via the
`onChanged` callback and rendered text:

- **Option-card → data key**: for each primary choice, tapping an `OptionCard`
  writes the expected `data` key/value (e.g. tapping "Fixed amount" sets
  `incomingAllocationType: 'fixed'`; tapping a distribution mode sets
  `distributionMode`; tapping a bandCut type sets `cutType`). This is the core
  regression guard — it's the wiring most likely to break in the rewrite.
- **Tabs**: payoutGroup renders 3 tab chips (Recipients/Take/Split) and tapping
  a chip swaps the visible question; simple types render a single tab.
- **Conditional fields**: mode-specific inputs appear/hide correctly — fixed
  distribution shows the per-member amount field (not the allocations list);
  non-remainder "Take" shows the value field; tiered shows the tier editor.
- **Preview bar**: given `node_values`, the bar shows the formatted figure;
  given none, it shows the neutral placeholder (not stale numbers).

Tests drive the widget through `WidgetTester` (tap + pump) and assert on the
captured `onChanged` data and on-screen text — no backend or golden images.

The adapter/merge suite is unaffected (no data-shape change) and must stay green.

## Risks

- **Scope**: this is a substantial rewrite of `node_config_form.dart`. Mitigation:
  extract the shell/cards into separate widgets so the per-type step builders stay
  small and readable.
- **Vertical space**: option cards are taller than dropdown rows. The body
  scrolls; the preview bar stays pinned. Watch for cramped layouts on small phones.
