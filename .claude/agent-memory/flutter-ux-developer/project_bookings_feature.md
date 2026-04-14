---
name: Bookings Feature — Full Implementation
description: Architecture and patterns for the complete bookings feature (detail hub, form, contacts, payments, contract, history screens)
type: project
---

The bookings feature was fully implemented with read+write parity. Key non-obvious facts:

**Route ordering**: GoRouter matches in declaration order. `/bookings/:bandId/new` must be declared before `/bookings/:bandId/:id` to prevent "new" being captured as the `:id` param.

**Async context safety**: `_confirmCancel` and `_confirmDelete` on the detail screen use `this.context` (state-level) rather than accepting `BuildContext` as a parameter — this avoids `use_build_context_synchronously` lint violations when calling dialogs after awaits with `mounted` guards.

**BookingDetail extended fields**: `contractOption`, `contract` (BookingContract), and `payments` (List<BookingPayment>) were added in this implementation. The API returns them alongside the existing fields.

**BookingContact extended fields**: `bcId` (pivot row id, required for update/remove), `contactId`, `isPrimary` were added.

**Widget conventions**:
- `BookingSectionTile` in `lib/features/bookings/widgets/` — reusable hub row with icon/title/subtitle/badge/chevron
- `PaymentTypePicker` in `lib/features/bookings/widgets/` — wraps `CupertinoPicker` with `paymentTypes` const list
- `_PickerSheet` (private to booking_form_screen.dart) — reusable 300px bottom sheet with Done button for modal pickers

**Contact add flow**: "Add Contact" pushes a full `CupertinoPageRoute` (`_AddContactScreen`) rather than using a modal popup, because the screen needs search + results list + inline create form — too complex for a bottom sheet.

**Venue selection UX (booking_form_screen.dart)**: Redesigned to integrated map-first pattern:
- `VenueDetails` model (in `venue_search_service.dart`) carries `lat`/`lng` alongside name/address; `fetchDetails()` uses `PlaceField.Location` to retrieve them.
- `_VenueSearchSheet` splits vertically: results list on top, animated `_MapPreviewPane` at bottom. Single tap highlights + fetches details + shows static map preview. Second tap or "Select" button confirms.
- Back in the form, the selected venue renders as `_VenuePreviewCard`: a `ClipRRect` card with `_StaticMapThumbnail` (Google Static Maps API via `CachedNetworkImage`) stacked above address text + icon buttons (map/change/clear).
- Static map URL pattern: `https://maps.googleapis.com/maps/api/staticmap?center=LAT,LNG&zoom=15&size=600x180&scale=2&markers=color:red%7CLAT,LNG&key=KEY`
- All map UI degrades gracefully when `AppConfig.googlePlacesApiKey.isEmpty` or on Linux (NoOp service has no coordinates).
- No new packages required — uses `cached_network_image` (already in project) for image tiles.

**Bookings list screen redesign (bookings_screen.dart)**:
- `BandBookingsParams` gained a nullable `year` field (also in `hashCode`/`==`). The repository passes it as `?year=YYYY` to the API.
- The API controller (`BookingsController::index`) needs `'year' => 'nullable|integer|min:2000|max:2100'` added to `validate()` and a `whereYear('date', $year)` clause in the query builder.
- List is grouped by month using a sealed `_ListItem` union (`_HeaderItem` / `_CardItem`). A single `SliverList` renders both header rows and cards from a flat list — no nested slivers.
- Year stepper is a `_YearStepper` widget: two `CupertinoButton` chevrons + fixed-width `80px` year label. `_minYear = 2000` (const), `_maxYear = DateTime.now().year + 3` (static final).
- The 48px left icon column was removed. Replaced by a `3px` accent bar (`Container(width: 3)`) whose color mirrors `StatusChip` status colors. `IntrinsicHeight` + `CrossAxisAlignment.stretch` makes the bar span the full card height.
- Date format changed from `'EEEE, MMMM d'` (no year, bug) to `'EEE, MMM d, yyyy'` (unambiguous). Existing `toAmPm()` utility is still used for time.
- Disclosure chevron (`CupertinoIcons.chevron_right`, size 14, `tertiaryLabel`) added to card trailing edge.
- Location icon (`CupertinoIcons.location`, size 11) prefixes the venue name row.
- Desktop/web: `LayoutBuilder` wraps `CustomScrollView` in `SizedBox(maxWidth: 700)`.

**Why:** User feedback that flat list with no year context is ambiguous for bookings 2+ years out; loading all bookings at once is wasteful.
**How to apply:** When touching bookings screens, check that `bcId` is present before calling remove/update contact. The `bookingDetailProvider` is the single source of truth — always invalidate it after mutations. The `VenueSearchService.fetchAddress()` method no longer exists — it was replaced by `fetchDetails()`; update any call sites accordingly.
