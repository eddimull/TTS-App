# Release Notes

## 1.1.1

_Released 2026-06-20_

### ✨ New Features

#### Personnel management
- Added a new **Personnel** area for managing your band's people:
  - **Members & rosters** — view band members, browse rosters, and manage roles.
  - **Substitutes** — invite subs, manage substitute lists, and maintain per-role call lists for filling open spots.

#### Stats: earned vs. upcoming earnings
- The Stats screen now distinguishes **earned** income from **upcoming** (booked-but-not-yet-played) income.
- **Earnings by Year** bar chart stacks upcoming earnings (in gray) on top of earned earnings.
- The earnings **donut chart** shows lighter-hue upcoming slices per band alongside earned amounts.
- Year headers display a compact inline summary of bookings, earned, and upcoming totals.
- Bookings with no date yet (TBD) are now handled correctly in the stats views.

#### Contact actions
- Event contacts now support quick actions — **call, text, or email** a contact directly from the contact detail screen.
- Email and phone details are now exposed for band members and substitutes.

### 🐛 Fixes & polish
- Keep the first non-empty band name when building the band breakdown.
- Defensive handling so the stacked-bar base rod renders transparently.
- Addressed multiple rounds of code-review feedback across the stats UI, personnel, and contact detail screens.

### 🧪 Tests
- Added test coverage for personnel models and providers, substitute models, stats breakdown/repository logic, contact detail navigation, and band settings models.
