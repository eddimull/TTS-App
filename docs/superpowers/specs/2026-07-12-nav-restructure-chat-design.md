# Navigation Restructure & Chat Discoverability — Design

**Date:** 2026-07-12
**Status:** Approved (user approved via visual mockup after v1.12.0 feedback: "the place to start a message with someone in your band is not obvious"; "the UI should have chat accessible at all times instead of bookings")
**Repo:** tts_bandmate only (no backend changes). Branch `feat/chat-discoverability` off main @ f744c58.

## Goal

Make chat ambient and person-centric, and reorganize navigation into a clear operations/settings split:

1. **Messages replaces Bookings in the 5-tab bar**, with a live unread badge on the tab icon.
2. **Hamburger → Operations menu** for run-the-band surfaces (Bookings, Finances, …).
3. **••• tab becomes "Settings"** — band settings & configuration only.
4. **"Message in Bandmate"** action on contact screens for any contact who is an app user.

## Tab bar (AppScaffold `_destinations`)

Dashboard · Search · **Messages** · Library · **••• Settings**

- Messages tab: chat-bubble icon + unread badge driven by `chatUnreadTotalProvider` (count, red, hidden at 0). `AppScaffold` currently renders bare `Icon`s — add a badge-capable icon slot (Stack + Positioned) for this destination.
- ••• tab: keep `CupertinoIcons.ellipsis` icon, rename label `More` → `Settings`.
- `/messages` becomes a shell (tab) route; its screen drops the back chevron when shown as a tab root. `/messages/new` and `/conversations/:id` stay pushed on top.

## Hamburger → Operations

- Hamburger button in `CupertinoSliverNavigationBar.leading` on the **Dashboard only** (slot is empty today; `+` and avatar stay trailing). **Follow-up (explicitly deferred):** hamburger on all main tab roots.
- Pushes `/operations` → new `OperationsScreen` (CupertinoPageScaffold + `NavRow` list, same pattern as today's MoreScreen), items in order:
  1. Bookings (moved from tab bar)
  2. Finances
  3. Rehearsals
  4. Personnel (owner-gated, same gating as today)
  5. Media

## ••• Settings screen

Rename/repurpose MoreScreen → SettingsScreen (per repo preference, split into two focused screens rather than parameterizing one). Items in order:

1. Switch Band (shown when >1 band, as today)
2. Band Settings (owner-gated, as today)
3. My Stats
4. Add to Calendar
5. Account (new tile; Dashboard avatar shortcut also stays)

The old "Messages" tile is gone (it's a tab now).

## Contact "Message in Bandmate"

- New action row on `ContactDetailScreen`, shown only when `contact.userId != null` (roster placeholders have no account).
- Label exactly "Message in Bandmate" — the screen already has "Send Message" which opens **SMS**; the two must not be conflatable.
- Behavior: `chatRepositoryProvider.openDm(userId)` → `context.push('/conversations/{id}', extra: {'title': name})` (reuse the pattern in `new_message_screen.dart`). No new providers.
- Surfaces everywhere `ContactDetailScreen` is opened: band members, rosters, event details.
- Event-detail `_MemberTile` primary tap stays owner sub-assignment; no new gesture added there in v1 (the tile already opens the contact screen for non-owners — that path picks up the action for free).

## Router / restore mechanics

- `_kShellPrefixes` (router.dart) and `_kRestorableShellPrefixes` (main.dart): remove `/bookings` only if it leaves the shell — it does NOT: `/bookings` stays registered inside the ShellRoute (like `/finances`, `/band-settings` today) so existing links, search results, and saved last-routes keep working; it's just no longer a tab destination. Add `/messages` and `/operations` as shell routes; `/more` renames to `/settings` with a redirect from `/more` for saved-route compatibility.
- Bookings list screen gains a back button when pushed from Operations (it's a tab-root screen today — verify its nav bar renders sensibly outside the tab; adjust if it assumed tab context).

## Migration hint

One-time dismissible hint on the Dashboard ("Bookings moved — now under ☰ Operations"), gated on a local SharedPreferences flag, removed in a later release. Copy short, dismiss persists.

## Testing

- AppScaffold: tab set/labels, unread badge renders count and hides at 0.
- Router: /messages as tab root; /more → /settings redirect; /bookings still resolves in shell; restore paths.
- OperationsScreen/SettingsScreen: item sets incl. owner-gating and single-band hiding.
- ContactDetailScreen: action visible only with userId; tap opens DM (repository stubbed); SMS row unaffected.
- Dashboard: hamburger present, pushes /operations; hint shows once and stays dismissed.
- Full suite + analyze (3 known pre-existing issues only); on-device pass.

## Deferred

- Hamburger on all main tab roots (user-requested follow-up).
- Any badge/counter on the hamburger (e.g. pending contracts).
- Web app parity (chat UI on web is still the larger phase-2 item).

## Decisions log

- Messages replaces Bookings in the tab bar (product owner).
- Hamburger = Operations (Bookings, Finances, Rehearsals, Personnel, Media); ••• = Settings (Switch Band, Band Settings, My Stats, Add to Calendar, Account).
- Hamburger Dashboard-only in v1; all-tab-roots is a follow-up.
- Pushed full-screen menus, not action sheets/drawers (Cupertino idiom + existing NavRow pattern).
- Two focused screens instead of one parameterized More screen.
