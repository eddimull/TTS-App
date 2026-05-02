# Dashboard Calendar — Band-Aware Markers + Floating Filter — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the dashboard calendar's generic blue dot with band-avatar markers that encode event type and booking confirmation, and add a floating filter button + sheet that narrows the calendar by band and event type.

**Architecture:** A new `BandAvatar` shared widget (extracted from the existing private `_Avatar` in `BandIdentityChip`, switched to `cached_network_image`) is reused by a new per-day `CalendarDayMarkers` widget that draws 1, 2, or "+N" avatars with type/status-coded rings. A new in-memory `Notifier` provider (`calendarFilterProvider`) holds `hiddenBandIds` + `hiddenEventTypes`; the dashboard applies it as an additional filter on the existing event stream. A new `CalendarFilterButton` overlays the dashboard scaffold via `Stack`/`Positioned`, opens `CalendarFilterSheet` (a Cupertino modal popup) for live-update toggling.

**Tech Stack:** Flutter / Cupertino, Riverpod v2 (`Notifier`), `table_calendar`, `cached_network_image: ^3.3.1`.

**Spec:** `docs/superpowers/specs/2026-05-02-dashboard-calendar-markers-design.md`

---

## File map

### New files

- `lib/shared/widgets/band_avatar.dart` — public `BandAvatar` widget with `.forBand` / `.forUser` named constructors, backed by `CachedNetworkImage`.
- `lib/shared/utils/booking_confirmation.dart` — `BookingConfirmation` enum + `bookingConfirmationFromStatus` helper.
- `lib/features/dashboard/providers/calendar_filter_provider.dart` — `CalendarFilterState` + `CalendarFilterNotifier` + `calendarFilterProvider`.
- `lib/features/dashboard/widgets/calendar_event_marker.dart` — `CalendarEventMarker` (single avatar + ring), `CalendarDayMarkers` (1 / 2 / "+N" composer), `DashedCircleBorderPainter`.
- `lib/features/dashboard/widgets/calendar_filter_button.dart` — floating button with badge.
- `lib/features/dashboard/widgets/calendar_filter_sheet.dart` — modal popup contents.
- `test/widgets/band_avatar_test.dart`
- `test/utils/booking_confirmation_test.dart`
- `test/features/dashboard/calendar_filter_provider_test.dart`
- `test/widgets/calendar_event_marker_test.dart`
- `test/widgets/calendar_filter_button_test.dart`
- `test/widgets/calendar_filter_sheet_test.dart`
- `test/widgets/dashboard_calendar_filter_integration_test.dart`

### Modified files

- `lib/shared/widgets/band_identity_chip.dart` — drops the private `_Avatar`, uses `BandAvatar.forBand` / `BandAvatar.forUser`.
- `lib/features/dashboard/screens/dashboard_screen.dart` — wraps body in `Stack` + filter button, watches `calendarFilterProvider`, passes `Map<DateTime, List<EventSummary>>` into `_CalendarSection`, swaps `TableCalendar<Object>` → `<EventSummary>` with custom `markerBuilder`, removes `markerDecoration` from `CalendarStyle`, adds filter-aware empty state.

---

## Task 1: Booking-confirmation helper

**Files:**
- Create: `lib/shared/utils/booking_confirmation.dart`
- Test: `test/utils/booking_confirmation_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/utils/booking_confirmation_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/shared/utils/booking_confirmation.dart';

void main() {
  group('bookingConfirmationFromStatus', () {
    test('returns confirmed for "confirmed"', () {
      expect(bookingConfirmationFromStatus('confirmed'),
          BookingConfirmation.confirmed);
    });

    test('returns confirmed for "Confirmed" (case-insensitive)', () {
      expect(bookingConfirmationFromStatus('Confirmed'),
          BookingConfirmation.confirmed);
    });

    test('returns confirmed for "booked"', () {
      expect(bookingConfirmationFromStatus('booked'),
          BookingConfirmation.confirmed);
    });

    test('returns confirmed for "accepted"', () {
      expect(bookingConfirmationFromStatus('accepted'),
          BookingConfirmation.confirmed);
    });

    test('returns cancelled for "cancelled"', () {
      expect(bookingConfirmationFromStatus('cancelled'),
          BookingConfirmation.cancelled);
    });

    test('returns cancelled for "canceled" (US spelling)', () {
      expect(bookingConfirmationFromStatus('canceled'),
          BookingConfirmation.cancelled);
    });

    test('returns cancelled for any string containing "cancel"', () {
      expect(bookingConfirmationFromStatus('Cancellation pending'),
          BookingConfirmation.cancelled);
    });

    test('returns pending for "pending"', () {
      expect(bookingConfirmationFromStatus('pending'),
          BookingConfirmation.pending);
    });

    test('returns pending for null', () {
      expect(bookingConfirmationFromStatus(null), BookingConfirmation.pending);
    });

    test('returns pending for unknown strings', () {
      expect(bookingConfirmationFromStatus('foobar'),
          BookingConfirmation.pending);
    });

    test('returns pending for empty string', () {
      expect(bookingConfirmationFromStatus(''), BookingConfirmation.pending);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/utils/booking_confirmation_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:tts_bandmate/shared/utils/booking_confirmation.dart'`.

- [ ] **Step 3: Implement the helper**

Create `lib/shared/utils/booking_confirmation.dart`:

```dart
enum BookingConfirmation { confirmed, pending, cancelled }

/// Normalises the free-form `status` string from the API into one of three
/// rendering buckets used by the dashboard calendar markers.
///
/// - Anything containing "cancel" (case-insensitive) → cancelled.
/// - "confirmed", "booked", or "accepted" → confirmed.
/// - Everything else (including null and empty) → pending.
BookingConfirmation bookingConfirmationFromStatus(String? status) {
  final s = (status ?? '').toLowerCase().trim();
  if (s.contains('cancel')) return BookingConfirmation.cancelled;
  if (s == 'confirmed' || s == 'booked' || s == 'accepted') {
    return BookingConfirmation.confirmed;
  }
  return BookingConfirmation.pending;
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/utils/booking_confirmation_test.dart`
Expected: All 11 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/shared/utils/booking_confirmation.dart test/utils/booking_confirmation_test.dart
git commit -m "feat(shared): add booking-confirmation status helper"
```

---

## Task 2: `BandAvatar` shared widget

**Files:**
- Create: `lib/shared/widgets/band_avatar.dart`
- Test: `test/widgets/band_avatar_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/widgets/band_avatar_test.dart`:

```dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/shared/widgets/band_avatar.dart';

Widget _wrap(Widget child) => CupertinoApp(home: Center(child: child));

void main() {
  group('BandAvatar.forBand', () {
    testWidgets('renders fallback initial when logoUrl is null', (tester) async {
      const band = BandSummary(
        id: 1,
        name: 'The Stooges',
        isOwner: true,
      );

      await tester.pumpWidget(_wrap(const BandAvatar.forBand(band: band)));

      expect(find.text('T'), findsOneWidget);
      expect(find.byType(CachedNetworkImage), findsNothing);
    });

    testWidgets('uses CachedNetworkImage when logoUrl is present',
        (tester) async {
      const band = BandSummary(
        id: 2,
        name: 'Anything',
        isOwner: false,
        logoUrl: 'https://example.com/logo.png',
      );

      await tester.pumpWidget(_wrap(const BandAvatar.forBand(band: band)));

      expect(find.byType(CachedNetworkImage), findsOneWidget);
      expect(find.text('A'), findsNothing);
    });

    testWidgets('uppercases the initial', (tester) async {
      const band = BandSummary(id: 3, name: 'awesome band', isOwner: false);

      await tester.pumpWidget(_wrap(const BandAvatar.forBand(band: band)));

      expect(find.text('A'), findsOneWidget);
    });

    testWidgets('renders "?" for empty band name', (tester) async {
      const band = BandSummary(id: 4, name: '', isOwner: false);

      await tester.pumpWidget(_wrap(const BandAvatar.forBand(band: band)));

      expect(find.text('?'), findsOneWidget);
    });

    testWidgets('respects size param', (tester) async {
      const band = BandSummary(id: 5, name: 'Big', isOwner: false);

      await tester.pumpWidget(_wrap(
          const BandAvatar.forBand(band: band, size: 40)));

      final container = tester.widget<Container>(find.byType(Container).first);
      final box = container.constraints?.biggest;
      // The widget pins width and height directly on the Container.
      expect(tester.getSize(find.byType(Container).first),
          const Size(40, 40));
    });
  });

  group('BandAvatar.forUser', () {
    testWidgets('renders user initial when imageUrl is null', (tester) async {
      await tester.pumpWidget(_wrap(
          const BandAvatar.forUser(imageUrl: null, name: 'Eddie')));

      expect(find.text('E'), findsOneWidget);
      expect(find.byType(CachedNetworkImage), findsNothing);
    });

    testWidgets('uses CachedNetworkImage when imageUrl is present',
        (tester) async {
      await tester.pumpWidget(_wrap(
          const BandAvatar.forUser(
        imageUrl: 'https://example.com/me.png',
        name: 'Eddie',
      )));

      expect(find.byType(CachedNetworkImage), findsOneWidget);
    });

    testWidgets('falls back to "?" for empty user name', (tester) async {
      await tester.pumpWidget(_wrap(
          const BandAvatar.forUser(imageUrl: null, name: '')));

      expect(find.text('?'), findsOneWidget);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/widgets/band_avatar_test.dart`
Expected: FAIL — package URI doesn't resolve.

- [ ] **Step 3: Implement `BandAvatar`**

Create `lib/shared/widgets/band_avatar.dart`:

```dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import '../../features/auth/data/models/band_summary.dart';

/// A circular band/user avatar with a colored fallback for null images.
///
/// - `BandAvatar.forBand` renders a [BandSummary]'s logo, falling back to the
///   first letter of the band's name on a tinted blue circle.
/// - `BandAvatar.forUser` renders a user's avatar with the same fallback
///   behavior. The auth lookup happens in the caller (this widget is not a
///   `ConsumerWidget`).
class BandAvatar extends StatelessWidget {
  const BandAvatar.forBand({
    super.key,
    required BandSummary band,
    this.size = 18,
  })  : _imageUrl = band.logoUrl,
        _name = band.name;

  const BandAvatar.forUser({
    super.key,
    required String? imageUrl,
    required String name,
    this.size = 18,
  })  : _imageUrl = imageUrl,
        _name = name;

  final String? _imageUrl;
  final String _name;

  /// Avatar diameter in logical pixels.
  final double size;

  static String _initial(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return trimmed.substring(0, 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final fallbackBg = CupertinoColors.systemBlue
        .resolveFrom(context)
        .withValues(alpha: 0.15);
    final fallbackFg = CupertinoColors.systemBlue.resolveFrom(context);

    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fallbackBg,
      ),
      child: _imageUrl != null && _imageUrl!.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: _imageUrl!,
              fit: BoxFit.cover,
              placeholder: (_, __) => const SizedBox.shrink(),
              errorWidget: (_, __, ___) => Center(
                child: Text(
                  _initial(_name),
                  style: TextStyle(
                    fontSize: size * 0.55,
                    fontWeight: FontWeight.w600,
                    color: fallbackFg,
                  ),
                ),
              ),
            )
          : Center(
              child: Text(
                _initial(_name),
                style: TextStyle(
                  fontSize: size * 0.55,
                  fontWeight: FontWeight.w600,
                  color: fallbackFg,
                ),
              ),
            ),
    );
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/widgets/band_avatar_test.dart`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/shared/widgets/band_avatar.dart test/widgets/band_avatar_test.dart
git commit -m "feat(shared): add BandAvatar widget with cached image"
```

---

## Task 3: Migrate `BandIdentityChip` to `BandAvatar`

**Files:**
- Modify: `lib/shared/widgets/band_identity_chip.dart`

- [ ] **Step 1: Replace the private `_Avatar` with `BandAvatar`**

Replace the entire contents of `lib/shared/widgets/band_identity_chip.dart` with:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/auth/data/models/band_summary.dart';
import '../../features/auth/providers/auth_provider.dart';
import 'band_avatar.dart';

/// A horizontal `[avatar] [label]` row identifying a band — or, for personal
/// bands, the authenticated user.
///
/// Used on Dashboard cards, Bookings tab cards, and the booking-detail
/// header. Personal bands always render the user's avatar + the literal
/// label "Personal" (the band wrapper is hidden from the user).
class BandIdentityChip extends ConsumerWidget {
  const BandIdentityChip({
    super.key,
    required this.band,
    this.size = 18,
    this.textStyle,
  });

  final BandSummary band;

  /// Avatar diameter in logical pixels. Default is compact for cards.
  final double size;

  /// Optional text style override for the label.
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (band.isPersonal) {
      final auth = ref.watch(authProvider).value;
      final user = (auth is AuthAuthenticated) ? auth.user : null;
      return _ChipRow(
        avatar: BandAvatar.forUser(
          imageUrl: user?.avatarUrl,
          name: user?.name ?? 'You',
          size: size,
        ),
        label: 'Personal',
        textStyle: textStyle,
      );
    }
    return _ChipRow(
      avatar: BandAvatar.forBand(band: band, size: size),
      label: band.name,
      textStyle: textStyle,
    );
  }
}

class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.avatar, required this.label, this.textStyle});
  final Widget avatar;
  final String label;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        avatar,
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textStyle ??
                TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                ),
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: Run the existing chip-related tests to verify no regression**

Run: `flutter test test/widgets/event_card_test.dart`
Expected: All tests PASS (the band-identity-chip tests at the bottom of that file should still find "The Rocking Eds" and "Personal" labels).

- [ ] **Step 3: Run all tests**

Run: `flutter test`
Expected: All previously-passing tests still PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/shared/widgets/band_identity_chip.dart
git commit -m "refactor(shared): use BandAvatar in BandIdentityChip"
```

---

## Task 4: `CalendarFilterState` + provider

**Files:**
- Create: `lib/features/dashboard/providers/calendar_filter_provider.dart`
- Test: `test/features/dashboard/calendar_filter_provider_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/dashboard/calendar_filter_provider_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/dashboard/providers/calendar_filter_provider.dart';
import 'package:tts_bandmate/features/events/data/models/event_summary.dart';

EventSummary _event({
  required int bandId,
  required String source,
  String key = 'evt',
}) =>
    EventSummary(
      key: key,
      title: 't',
      date: '2026-05-02',
      eventSource: source,
      band: BandSummary(id: bandId, name: 'B$bandId', isOwner: false),
    );

void main() {
  group('CalendarFilterState', () {
    test('default state is not active and visible to all events', () {
      const state = CalendarFilterState();
      expect(state.isActive, false);
      expect(state.activeCount, 0);
      expect(state.isEventVisible(_event(bandId: 1, source: 'booking')), true);
    });

    test('hidden band id hides matching event', () {
      const state = CalendarFilterState(hiddenBandIds: {7});
      expect(state.isEventVisible(_event(bandId: 7, source: 'booking')), false);
      expect(state.isEventVisible(_event(bandId: 8, source: 'booking')), true);
    });

    test('hidden event type hides matching event regardless of band', () {
      const state =
          CalendarFilterState(hiddenEventTypes: {'rehearsal'});
      expect(state.isEventVisible(_event(bandId: 1, source: 'rehearsal')),
          false);
      expect(state.isEventVisible(_event(bandId: 1, source: 'booking')), true);
    });

    test('event without band is unaffected by hiddenBandIds', () {
      final eventWithoutBand = EventSummary(
        key: 'k',
        title: 't',
        date: '2026-05-02',
        eventSource: 'booking',
      );
      const state = CalendarFilterState(hiddenBandIds: {7});
      expect(state.isEventVisible(eventWithoutBand), true);
    });

    test('activeCount sums hidden bands + hidden types', () {
      const state = CalendarFilterState(
        hiddenBandIds: {1, 2},
        hiddenEventTypes: {'rehearsal'},
      );
      expect(state.activeCount, 3);
      expect(state.isActive, true);
    });
  });

  group('CalendarFilterNotifier', () {
    test('toggleBand adds and removes a band id', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(calendarFilterProvider.notifier);

      notifier.toggleBand(5);
      expect(container.read(calendarFilterProvider).hiddenBandIds, {5});

      notifier.toggleBand(5);
      expect(container.read(calendarFilterProvider).hiddenBandIds, isEmpty);
    });

    test('toggleEventType adds and removes a source', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(calendarFilterProvider.notifier);

      notifier.toggleEventType('rehearsal');
      expect(container.read(calendarFilterProvider).hiddenEventTypes,
          {'rehearsal'});

      notifier.toggleEventType('rehearsal');
      expect(container.read(calendarFilterProvider).hiddenEventTypes,
          isEmpty);
    });

    test('clear resets state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(calendarFilterProvider.notifier);
      notifier.toggleBand(1);
      notifier.toggleEventType('booking');
      expect(container.read(calendarFilterProvider).isActive, true);

      notifier.clear();
      expect(container.read(calendarFilterProvider).isActive, false);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/dashboard/calendar_filter_provider_test.dart`
Expected: FAIL — package URI for `calendar_filter_provider.dart` doesn't exist.

- [ ] **Step 3: Implement the provider**

Create `lib/features/dashboard/providers/calendar_filter_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../events/data/models/event_summary.dart';

/// In-memory filter state for the dashboard calendar.
///
/// Bands and event types are stored as *hidden* sets — the default state hides
/// nothing. Resets on app restart (no persistence).
class CalendarFilterState {
  const CalendarFilterState({
    this.hiddenBandIds = const {},
    this.hiddenEventTypes = const {},
  });

  /// Band ids the user has chosen to hide.
  final Set<int> hiddenBandIds;

  /// Event sources the user has chosen to hide. Values are
  /// `'booking'`, `'rehearsal'`, or `'band_event'`.
  final Set<String> hiddenEventTypes;

  bool get isActive =>
      hiddenBandIds.isNotEmpty || hiddenEventTypes.isNotEmpty;

  int get activeCount => hiddenBandIds.length + hiddenEventTypes.length;

  bool isEventVisible(EventSummary event) {
    final band = event.band;
    if (band != null && hiddenBandIds.contains(band.id)) return false;
    if (hiddenEventTypes.contains(event.eventSource)) return false;
    return true;
  }

  CalendarFilterState copyWith({
    Set<int>? hiddenBandIds,
    Set<String>? hiddenEventTypes,
  }) =>
      CalendarFilterState(
        hiddenBandIds: hiddenBandIds ?? this.hiddenBandIds,
        hiddenEventTypes: hiddenEventTypes ?? this.hiddenEventTypes,
      );
}

class CalendarFilterNotifier extends Notifier<CalendarFilterState> {
  @override
  CalendarFilterState build() => const CalendarFilterState();

  void toggleBand(int bandId) {
    final next = Set<int>.from(state.hiddenBandIds);
    if (!next.add(bandId)) next.remove(bandId);
    state = state.copyWith(hiddenBandIds: next);
  }

  void toggleEventType(String source) {
    final next = Set<String>.from(state.hiddenEventTypes);
    if (!next.add(source)) next.remove(source);
    state = state.copyWith(hiddenEventTypes: next);
  }

  void clear() => state = const CalendarFilterState();
}

final calendarFilterProvider =
    NotifierProvider<CalendarFilterNotifier, CalendarFilterState>(
  CalendarFilterNotifier.new,
);
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/dashboard/calendar_filter_provider_test.dart`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/dashboard/providers/calendar_filter_provider.dart test/features/dashboard/calendar_filter_provider_test.dart
git commit -m "feat(dashboard): add calendar filter provider"
```

---

## Task 5: `CalendarEventMarker` + `CalendarDayMarkers` + dashed ring painter

**Files:**
- Create: `lib/features/dashboard/widgets/calendar_event_marker.dart`
- Test: `test/widgets/calendar_event_marker_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/widgets/calendar_event_marker_test.dart`:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/dashboard/widgets/calendar_event_marker.dart';
import 'package:tts_bandmate/features/events/data/models/event_summary.dart';
import 'package:tts_bandmate/shared/widgets/band_avatar.dart';

EventSummary _evt({
  String key = 'k',
  String source = 'booking',
  String? status = 'confirmed',
  String? time,
  int bandId = 1,
  String bandName = 'Band',
}) =>
    EventSummary(
      key: key,
      title: 't',
      date: '2026-05-02',
      time: time,
      eventSource: source,
      status: status,
      band: BandSummary(id: bandId, name: bandName, isOwner: false),
    );

Widget _wrap(Widget child) => CupertinoApp(home: Center(child: child));

void main() {
  group('CalendarDayMarkers', () {
    testWidgets('renders one BandAvatar for one event', (tester) async {
      await tester.pumpWidget(_wrap(
          CalendarDayMarkers(events: [_evt()])));

      expect(find.byType(BandAvatar), findsOneWidget);
      expect(find.textContaining('+'), findsNothing);
    });

    testWidgets('renders two BandAvatars for two events', (tester) async {
      await tester.pumpWidget(_wrap(CalendarDayMarkers(events: [
        _evt(key: 'a', bandId: 1, bandName: 'A'),
        _evt(key: 'b', bandId: 2, bandName: 'B'),
      ])));

      expect(find.byType(BandAvatar), findsNWidgets(2));
      expect(find.textContaining('+'), findsNothing);
    });

    testWidgets('renders one avatar + "+N" pill for three events',
        (tester) async {
      await tester.pumpWidget(_wrap(CalendarDayMarkers(events: [
        _evt(key: 'a', bandId: 1, bandName: 'A'),
        _evt(key: 'b', bandId: 2, bandName: 'B'),
        _evt(key: 'c', bandId: 3, bandName: 'C'),
      ])));

      expect(find.byType(BandAvatar), findsOneWidget);
      expect(find.text('+2'), findsOneWidget);
    });

    testWidgets('renders one avatar + "+N" pill for five events',
        (tester) async {
      await tester.pumpWidget(_wrap(CalendarDayMarkers(events: [
        for (var i = 0; i < 5; i++)
          _evt(key: 'k$i', bandId: i, bandName: 'B$i'),
      ])));

      expect(find.byType(BandAvatar), findsOneWidget);
      expect(find.text('+4'), findsOneWidget);
    });

    testWidgets('renders nothing for empty events list', (tester) async {
      await tester.pumpWidget(_wrap(const CalendarDayMarkers(events: [])));

      expect(find.byType(BandAvatar), findsNothing);
      expect(find.textContaining('+'), findsNothing);
    });

    testWidgets('orders by event time, nulls last', (tester) async {
      // Three events: '20:00', null, '08:00'.
      // Rendered order should be: '08:00', '20:00', then null (in "+N").
      // With two avatars before "+N", the visible avatars should be the two
      // with times — in time order — and the null event lives in the +1 pill.
      await tester.pumpWidget(_wrap(CalendarDayMarkers(events: [
        _evt(key: 'late', time: '20:00', bandId: 1, bandName: 'Late'),
        _evt(key: 'no-time', time: null, bandId: 2, bandName: 'NoTime'),
        _evt(key: 'early', time: '08:00', bandId: 3, bandName: 'Early'),
      ])));

      // 3 events → 1 avatar + "+2" pill. Avatar must be the earliest-time one.
      expect(find.byType(BandAvatar), findsOneWidget);
      expect(find.text('+2'), findsOneWidget);
      // The avatar shown is the "Early" band's first letter ("E").
      expect(find.text('E'), findsOneWidget);
    });
  });

  group('CalendarEventMarker', () {
    testWidgets('renders a BandAvatar', (tester) async {
      await tester.pumpWidget(_wrap(CalendarEventMarker(event: _evt())));
      expect(find.byType(BandAvatar), findsOneWidget);
    });

    testWidgets('uses CustomPaint for dashed ring when booking is pending',
        (tester) async {
      await tester.pumpWidget(_wrap(
          CalendarEventMarker(event: _evt(status: 'pending'))));

      // The dashed ring is drawn via a CustomPaint with our painter.
      expect(find.byType(CustomPaint), findsWidgets);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/widgets/calendar_event_marker_test.dart`
Expected: FAIL — package URI for `calendar_event_marker.dart` doesn't resolve.

- [ ] **Step 3: Implement marker widgets + painter**

Create `lib/features/dashboard/widgets/calendar_event_marker.dart`:

```dart
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import '../../../shared/utils/booking_confirmation.dart';
import '../../../shared/widgets/band_avatar.dart';
import '../../events/data/models/event_summary.dart';

/// Single-event marker: a small `BandAvatar` with a colored ring whose color
/// and style encode the event source and (for bookings) confirmation status.
class CalendarEventMarker extends StatelessWidget {
  const CalendarEventMarker({
    super.key,
    required this.event,
    this.size = 18,
  });

  final EventSummary event;
  final double size;

  @override
  Widget build(BuildContext context) {
    final spec = _ringSpec(context, event);

    final avatarOpacity = spec.fadeAvatar ? 0.4 : 1.0;
    final avatar = event.band != null
        ? BandAvatar.forBand(band: event.band!, size: size)
        : SizedBox(width: size, height: size);

    final ringPainter = spec.dashed
        ? DashedCircleBorderPainter(color: spec.color, strokeWidth: 2)
        : _SolidCircleBorderPainter(color: spec.color, strokeWidth: 2);

    final semanticsLabel = _semanticsLabel(event);

    return Semantics(
      label: semanticsLabel,
      child: SizedBox(
        width: size + 4,
        height: size + 4,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size(size + 4, size + 4),
              painter: ringPainter,
            ),
            Opacity(opacity: avatarOpacity, child: avatar),
          ],
        ),
      ),
    );
  }
}

/// Composes 1, 2, or "+N" markers for a single calendar day.
class CalendarDayMarkers extends StatelessWidget {
  const CalendarDayMarkers({
    super.key,
    required this.events,
    this.avatarSize = 14,
  });

  final List<EventSummary> events;

  /// Diameter of each avatar inside the day cell (kept small so two fit
  /// comfortably).
  final double avatarSize;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) return const SizedBox.shrink();

    // Sort by time (earliest first). Null times go last; ties preserve order.
    final sorted = [...events];
    sorted.sort((a, b) {
      final at = a.time;
      final bt = b.time;
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return at.compareTo(bt);
    });

    if (sorted.length == 1) {
      return CalendarEventMarker(event: sorted.first, size: avatarSize);
    }

    if (sorted.length == 2) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CalendarEventMarker(event: sorted[0], size: avatarSize),
          Transform.translate(
            offset: const Offset(-2, 0),
            child: CalendarEventMarker(event: sorted[1], size: avatarSize),
          ),
        ],
      );
    }

    // 3+ events → first avatar + "+N" pill.
    final overflow = sorted.length - 1;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CalendarEventMarker(event: sorted[0], size: avatarSize),
        const SizedBox(width: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: CupertinoColors.systemGrey5.resolveFrom(context),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '+$overflow',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: CupertinoColors.label.resolveFrom(context),
            ),
          ),
        ),
      ],
    );
  }
}

class _RingSpec {
  const _RingSpec({
    required this.color,
    required this.dashed,
    required this.fadeAvatar,
  });
  final Color color;
  final bool dashed;
  final bool fadeAvatar;
}

_RingSpec _ringSpec(BuildContext ctx, EventSummary e) {
  if (e.eventSource == 'rehearsal' || e.eventSource == 'rehearsal_schedule') {
    return _RingSpec(
      color: CupertinoColors.systemBlue.resolveFrom(ctx),
      dashed: false,
      fadeAvatar: false,
    );
  }
  if (e.eventSource == 'booking') {
    final c = bookingConfirmationFromStatus(e.status);
    switch (c) {
      case BookingConfirmation.cancelled:
        return _RingSpec(
          color: CupertinoColors.systemRed.resolveFrom(ctx),
          dashed: false,
          fadeAvatar: true,
        );
      case BookingConfirmation.pending:
        return _RingSpec(
          color: CupertinoColors.systemGreen.resolveFrom(ctx),
          dashed: true,
          fadeAvatar: false,
        );
      case BookingConfirmation.confirmed:
        return _RingSpec(
          color: CupertinoColors.systemGreen.resolveFrom(ctx),
          dashed: false,
          fadeAvatar: false,
        );
    }
  }
  // band_event and any other source.
  return _RingSpec(
    color: CupertinoColors.systemGrey.resolveFrom(ctx),
    dashed: false,
    fadeAvatar: false,
  );
}

String _semanticsLabel(EventSummary e) {
  final bandName = e.band?.name ?? 'Event';
  final type = switch (e.eventSource) {
    'rehearsal' || 'rehearsal_schedule' => 'rehearsal',
    'booking' => 'performance',
    _ => 'event',
  };
  if (e.eventSource == 'booking') {
    final c = bookingConfirmationFromStatus(e.status);
    final statusWord = switch (c) {
      BookingConfirmation.confirmed => 'confirmed',
      BookingConfirmation.pending => 'pending',
      BookingConfirmation.cancelled => 'cancelled',
    };
    return '$bandName $type, $statusWord';
  }
  return '$bandName $type';
}

/// Strokes a circle inscribed in the painter's bounds.
class _SolidCircleBorderPainter extends CustomPainter {
  _SolidCircleBorderPainter({required this.color, required this.strokeWidth});
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    canvas.drawCircle(size.center(Offset.zero), radius, paint);
  }

  @override
  bool shouldRepaint(_SolidCircleBorderPainter old) =>
      old.color != color || old.strokeWidth != strokeWidth;
}

/// Strokes a dashed circle inscribed in the painter's bounds.
class DashedCircleBorderPainter extends CustomPainter {
  DashedCircleBorderPainter({
    required this.color,
    required this.strokeWidth,
    this.dash = 4,
    this.gap = 3,
  });

  final Color color;
  final double strokeWidth;
  final double dash;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final center = size.center(Offset.zero);

    final circumference = 2 * math.pi * radius;
    final segment = dash + gap;
    final segments = (circumference / segment).floor();
    if (segments == 0) return;

    final stepRad = (2 * math.pi) / segments;
    final dashRad = stepRad * (dash / segment);

    for (var i = 0; i < segments; i++) {
      final start = i * stepRad;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        dashRad,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(DashedCircleBorderPainter old) =>
      old.color != color ||
      old.strokeWidth != strokeWidth ||
      old.dash != dash ||
      old.gap != gap;
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/widgets/calendar_event_marker_test.dart`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/dashboard/widgets/calendar_event_marker.dart test/widgets/calendar_event_marker_test.dart
git commit -m "feat(dashboard): add band-avatar calendar markers with status rings"
```

---

## Task 6: `CalendarFilterButton` (floating button + badge)

**Files:**
- Create: `lib/features/dashboard/widgets/calendar_filter_button.dart`
- Test: `test/widgets/calendar_filter_button_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/widgets/calendar_filter_button_test.dart`:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/dashboard/providers/calendar_filter_provider.dart';
import 'package:tts_bandmate/features/dashboard/widgets/calendar_filter_button.dart';

Widget _wrap(Widget child) => ProviderScope(
      child: CupertinoApp(home: Center(child: child)),
    );

void main() {
  group('CalendarFilterButton', () {
    testWidgets('renders without badge when no filters active',
        (tester) async {
      await tester.pumpWidget(_wrap(
          CalendarFilterButton(onPressed: () {})));

      expect(find.byIcon(CupertinoIcons.line_horizontal_3_decrease),
          findsOneWidget);
      // No badge text when count == 0.
      expect(find.text('1'), findsNothing);
      expect(find.text('2'), findsNothing);
    });

    testWidgets('renders badge with count when filters active',
        (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(calendarFilterProvider.notifier);
      notifier.toggleBand(1);
      notifier.toggleEventType('rehearsal');

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: CupertinoApp(
          home: Center(child: CalendarFilterButton(onPressed: () {})),
        ),
      ));

      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('caps badge text at 9+', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(calendarFilterProvider.notifier);
      for (var i = 0; i < 10; i++) {
        notifier.toggleBand(i);
      }

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: CupertinoApp(
          home: Center(child: CalendarFilterButton(onPressed: () {})),
        ),
      ));

      expect(find.text('9+'), findsOneWidget);
    });

    testWidgets('invokes onPressed when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(
          CalendarFilterButton(onPressed: () => tapped = true)));

      await tester.tap(find.byType(CalendarFilterButton));
      expect(tapped, true);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/widgets/calendar_filter_button_test.dart`
Expected: FAIL — package URI for `calendar_filter_button.dart` doesn't resolve.

- [ ] **Step 3: Implement the button**

Create `lib/features/dashboard/widgets/calendar_filter_button.dart`:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/calendar_filter_provider.dart';

/// Floating circular button used to open the calendar filter sheet.
///
/// Renders a small red badge with the active-filter count when any filter is
/// active. When inactive, the icon sits on a `tertiarySystemBackground` fill;
/// when active, the fill flips to `systemBlue` and the icon to white.
class CalendarFilterButton extends ConsumerWidget {
  const CalendarFilterButton({
    super.key,
    required this.onPressed,
    this.size = 48,
  });

  final VoidCallback onPressed;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(calendarFilterProvider);
    final isActive = filter.isActive;
    final count = filter.activeCount;

    final fill = isActive
        ? CupertinoColors.systemBlue.resolveFrom(context)
        : CupertinoColors.tertiarySystemBackground.resolveFrom(context);
    final iconColor = isActive
        ? CupertinoColors.white
        : CupertinoColors.systemBlue.resolveFrom(context);

    return Semantics(
      label: 'Filter calendar',
      hint: isActive ? '$count filters active' : 'No filters active',
      button: true,
      child: SizedBox(
        width: size + 8,
        height: size + 8,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: onPressed,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  margin: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: fill,
                    shape: BoxShape.circle,
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    CupertinoIcons.line_horizontal_3_decrease,
                    color: iconColor,
                    size: 22,
                  ),
                ),
              ),
            ),
            if (count > 0)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  width: 18,
                  height: 18,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemRed.resolveFrom(context),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: CupertinoColors.systemBackground.resolveFrom(
                          context),
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    count > 9 ? '9+' : '$count',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: CupertinoColors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/widgets/calendar_filter_button_test.dart`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/dashboard/widgets/calendar_filter_button.dart test/widgets/calendar_filter_button_test.dart
git commit -m "feat(dashboard): add floating CalendarFilterButton with badge"
```

---

## Task 7: `CalendarFilterSheet` (modal popup)

**Files:**
- Create: `lib/features/dashboard/widgets/calendar_filter_sheet.dart`
- Test: `test/widgets/calendar_filter_sheet_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/widgets/calendar_filter_sheet_test.dart`:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/dashboard/providers/calendar_filter_provider.dart';
import 'package:tts_bandmate/features/dashboard/widgets/calendar_filter_sheet.dart';

const _bandA = BandSummary(id: 1, name: 'Alpha', isOwner: true);
const _bandB = BandSummary(id: 2, name: 'Bravo', isOwner: false);

Widget _hostWith(ProviderContainer container) =>
    UncontrolledProviderScope(
      container: container,
      child: CupertinoApp(
        home: CupertinoPageScaffold(
          child: CalendarFilterSheet(bands: [_bandA, _bandB]),
        ),
      ),
    );

void main() {
  group('CalendarFilterSheet', () {
    testWidgets('renders all bands and three event-type switches',
        (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_hostWith(container));
      await tester.pumpAndSettle();

      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Bravo'), findsOneWidget);
      expect(find.text('Performances'), findsOneWidget);
      expect(find.text('Rehearsals'), findsOneWidget);
      expect(find.text('Other Events'), findsOneWidget);
    });

    testWidgets('hides Clear All when no filters active', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_hostWith(container));
      await tester.pumpAndSettle();

      expect(find.text('Clear All'), findsNothing);
    });

    testWidgets('shows Clear All when filters active and clears on tap',
        (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(calendarFilterProvider.notifier).toggleBand(1);

      await tester.pumpWidget(_hostWith(container));
      await tester.pumpAndSettle();

      expect(find.text('Clear All'), findsOneWidget);

      await tester.tap(find.text('Clear All'));
      await tester.pumpAndSettle();

      expect(container.read(calendarFilterProvider).isActive, false);
      expect(find.text('Clear All'), findsNothing);
    });

    testWidgets('tapping a band chip toggles its hidden state',
        (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_hostWith(container));
      await tester.pumpAndSettle();

      // Initially nothing hidden.
      expect(container.read(calendarFilterProvider).hiddenBandIds, isEmpty);

      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();

      expect(container.read(calendarFilterProvider).hiddenBandIds, {1});

      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();

      expect(container.read(calendarFilterProvider).hiddenBandIds, isEmpty);
    });

    testWidgets('toggling Performances switch hides booking source',
        (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_hostWith(container));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(Row, 'Performances')
          .evaluate()
          .isNotEmpty
          ? find.byType(CupertinoSwitch).first
          : find.byType(CupertinoSwitch).first);
      await tester.pumpAndSettle();

      expect(container.read(calendarFilterProvider).hiddenEventTypes,
          contains('booking'));
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/widgets/calendar_filter_sheet_test.dart`
Expected: FAIL — package URI for `calendar_filter_sheet.dart` doesn't resolve.

- [ ] **Step 3: Implement the sheet**

Create `lib/features/dashboard/widgets/calendar_filter_sheet.dart`:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/models/band_summary.dart';
import '../../../shared/widgets/band_avatar.dart';
import '../providers/calendar_filter_provider.dart';

/// Modal popup contents for filtering the dashboard calendar.
///
/// Lives inside `showCupertinoModalPopup` — this widget paints the sheet body
/// (drag handle, header, sections, padding). Live-updates the filter provider
/// on every interaction.
class CalendarFilterSheet extends ConsumerWidget {
  const CalendarFilterSheet({super.key, required this.bands});

  final List<BandSummary> bands;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(calendarFilterProvider);
    final notifier = ref.read(calendarFilterProvider.notifier);

    return Container(
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground.resolveFrom(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            _DragHandle(),
            const SizedBox(height: 8),
            _Header(
              isActive: filter.isActive,
              onClear: () {
                HapticFeedback.selectionClick();
                notifier.clear();
              },
            ),
            const SizedBox(height: 8),
            _SectionLabel(label: 'BANDS'),
            const SizedBox(height: 8),
            _BandsRow(
              bands: bands,
              hiddenBandIds: filter.hiddenBandIds,
              onToggle: (id) {
                HapticFeedback.selectionClick();
                notifier.toggleBand(id);
              },
            ),
            const SizedBox(height: 16),
            _SectionLabel(label: 'EVENT TYPES'),
            _EventTypeSwitch(
              label: 'Performances',
              source: 'booking',
              hidden: filter.hiddenEventTypes.contains('booking'),
              onToggle: () {
                HapticFeedback.selectionClick();
                notifier.toggleEventType('booking');
              },
            ),
            _EventTypeSwitch(
              label: 'Rehearsals',
              source: 'rehearsal',
              hidden: filter.hiddenEventTypes.contains('rehearsal'),
              onToggle: () {
                HapticFeedback.selectionClick();
                notifier.toggleEventType('rehearsal');
              },
            ),
            _EventTypeSwitch(
              label: 'Other Events',
              source: 'band_event',
              hidden: filter.hiddenEventTypes.contains('band_event'),
              onToggle: () {
                HapticFeedback.selectionClick();
                notifier.toggleEventType('band_event');
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _DragHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: CupertinoColors.systemGrey4.resolveFrom(context),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.isActive, required this.onClear});
  final bool isActive;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Center(
            child: Text(
              'Filter',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
          ),
          if (isActive)
            Align(
              alignment: Alignment.centerRight,
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: onClear,
                child: Text(
                  'Clear All',
                  style: TextStyle(
                    color: CupertinoColors.systemRed.resolveFrom(context),
                    fontSize: 15,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
          ),
        ),
      ),
    );
  }
}

class _BandsRow extends StatelessWidget {
  const _BandsRow({
    required this.bands,
    required this.hiddenBandIds,
    required this.onToggle,
  });

  final List<BandSummary> bands;
  final Set<int> hiddenBandIds;
  final void Function(int bandId) onToggle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 80,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: bands.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final band = bands[i];
          final isVisible = !hiddenBandIds.contains(band.id);
          return GestureDetector(
            onTap: () => onToggle(band.id),
            behavior: HitTestBehavior.opaque,
            child: Semantics(
              label: band.name,
              selected: isVisible,
              button: true,
              child: SizedBox(
                width: 64,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Opacity(
                      opacity: isVisible ? 1.0 : 0.4,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isVisible
                                ? CupertinoColors.systemBlue
                                    .resolveFrom(context)
                                : CupertinoColors.systemGrey5
                                    .resolveFrom(context),
                            width: 2,
                          ),
                        ),
                        padding: const EdgeInsets.all(2),
                        child: BandAvatar.forBand(band: band, size: 36),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Opacity(
                      opacity: isVisible ? 1.0 : 0.4,
                      child: Text(
                        band.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _EventTypeSwitch extends StatelessWidget {
  const _EventTypeSwitch({
    required this.label,
    required this.source,
    required this.hidden,
    required this.onToggle,
  });

  final String label;
  final String source;
  final bool hidden;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 15)),
          ),
          CupertinoSwitch(
            value: !hidden,
            onChanged: (_) => onToggle(),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/widgets/calendar_filter_sheet_test.dart`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/dashboard/widgets/calendar_filter_sheet.dart test/widgets/calendar_filter_sheet_test.dart
git commit -m "feat(dashboard): add CalendarFilterSheet with live-update toggles"
```

---

## Task 8: Wire markers + filter button into the dashboard

**Files:**
- Modify: `lib/features/dashboard/screens/dashboard_screen.dart`
- Test: `test/widgets/dashboard_calendar_filter_integration_test.dart`

This task changes `_DashboardContent` and `_CalendarSection` to:
- Watch `calendarFilterProvider` and apply `isEventVisible` on top of the existing month/day filtering.
- Hand a `Map<DateTime, List<EventSummary>>` to `_CalendarSection` so the calendar's `markerBuilder` can render `CalendarDayMarkers`.
- Swap `TableCalendar<Object>` → `<EventSummary>`.
- Drop the global `markerDecoration` from `CalendarStyle`.
- Wrap the scaffold body in a `Stack` and overlay `CalendarFilterButton` bottom-right; tapping opens `showCupertinoModalPopup` with `CalendarFilterSheet`.
- Show a filter-aware empty state with an inline "Clear filters" button when filters are active and the result is empty.

- [ ] **Step 1: Write the failing integration test**

Create `test/widgets/dashboard_calendar_filter_integration_test.dart`:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Material;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/auth/data/models/auth_user.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/auth/providers/auth_provider.dart';
import 'package:tts_bandmate/features/dashboard/providers/calendar_filter_provider.dart';
import 'package:tts_bandmate/features/dashboard/providers/dashboard_provider.dart';
import 'package:tts_bandmate/features/dashboard/screens/dashboard_screen.dart';
import 'package:tts_bandmate/features/events/data/models/event_summary.dart';

class _FixedAuthNotifier extends AuthNotifier {
  _FixedAuthNotifier(this._fixed);
  final AuthState _fixed;
  @override
  Future<AuthState> build() async => _fixed;
}

class _FixedDashboardNotifier extends DashboardNotifier {
  _FixedDashboardNotifier(this._state);
  final DashboardState _state;
  @override
  Future<DashboardState> build() async => _state;
  @override
  Future<void> refresh() async {}
}

void main() {
  const bandA = BandSummary(id: 1, name: 'Alpha', isOwner: true);
  const bandB = BandSummary(id: 2, name: 'Bravo', isOwner: false);

  EventSummary evt({
    required String key,
    required String date,
    required BandSummary band,
    String source = 'booking',
    String? status = 'confirmed',
  }) =>
      EventSummary(
        key: key,
        title: '$key title',
        date: date,
        eventSource: source,
        status: status,
        band: band,
      );

  Widget host({required List<EventSummary> events}) {
    return ProviderScope(
      overrides: [
        authProvider.overrideWith(() => _FixedAuthNotifier(
              AuthAuthenticated(
                user: const AuthUser(id: 1, name: 'Eddie', email: 'e@e.com'),
                bands: [bandA, bandB],
              ),
            )),
        dashboardProvider.overrideWith(() => _FixedDashboardNotifier(
              DashboardState(events: events, currentEvent: null),
            )),
      ],
      child: const CupertinoApp(home: Material(child: DashboardScreen())),
    );
  }

  testWidgets('hiding a band hides its event from the events list',
      (tester) async {
    final events = [
      evt(key: 'a', date: '2026-05-10', band: bandA),
      evt(key: 'b', date: '2026-05-11', band: bandB),
    ];

    await tester.pumpWidget(host(events: events));
    await tester.pumpAndSettle();

    expect(find.text('a title'), findsOneWidget);
    expect(find.text('b title'), findsOneWidget);

    // Hide band B by mutating the provider directly (faster than driving the
    // sheet UI here — the sheet is covered by its own widget test).
    final container = ProviderScope.containerOf(
      tester.element(find.byType(DashboardScreen)),
    );
    container.read(calendarFilterProvider.notifier).toggleBand(2);
    await tester.pumpAndSettle();

    expect(find.text('a title'), findsOneWidget);
    expect(find.text('b title'), findsNothing);
  });

  testWidgets('filter-aware empty state shows Clear filters button',
      (tester) async {
    final events = [evt(key: 'a', date: '2026-05-10', band: bandA)];

    await tester.pumpWidget(host(events: events));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(DashboardScreen)),
    );
    container.read(calendarFilterProvider.notifier).toggleBand(1);
    await tester.pumpAndSettle();

    expect(find.text('No events match your filters'), findsOneWidget);
    expect(find.text('Clear filters'), findsOneWidget);

    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();

    expect(container.read(calendarFilterProvider).isActive, false);
    expect(find.text('a title'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/widgets/dashboard_calendar_filter_integration_test.dart`
Expected: FAIL — current dashboard renders both events and has no filter wiring or filter-aware empty state.

- [ ] **Step 3: Replace the dashboard screen**

Replace the entire contents of `lib/features/dashboard/screens/dashboard_screen.dart` with:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Material, Theme, ThemeData;
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/providers/selected_band_provider.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/error_view.dart';
import '../../bookings/widgets/create_booking_sheet.dart';
import '../../events/data/models/event_summary.dart';
import '../providers/calendar_filter_provider.dart';
import '../providers/dashboard_provider.dart';
import '../widgets/calendar_event_marker.dart';
import '../widgets/calendar_filter_button.dart';
import '../widgets/calendar_filter_sheet.dart';
import '../widgets/event_card.dart';
import '../widgets/live_now_card.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  @override
  Widget build(BuildContext context) {
    final authAsync = ref.watch(authProvider);
    final authState = authAsync.value;
    final bandAsync = ref.watch(selectedBandProvider);
    final bandId = bandAsync.value;

    final userName =
        authState is AuthAuthenticated ? authState.user.name : 'there';

    final bandName = () {
      if (authState is! AuthAuthenticated || bandId == null) return 'Your Band';
      try {
        return authState.bands.firstWhere((b) => b.id == bandId).name;
      } catch (_) {
        return 'Your Band';
      }
    }();

    final dashboardAsync = ref.watch(dashboardProvider);

    return CupertinoPageScaffold(
      child: Stack(
        children: [
          CustomScrollView(
            slivers: [
              CupertinoSliverRefreshControl(
                onRefresh: () => ref.read(dashboardProvider.notifier).refresh(),
              ),
              CupertinoSliverNavigationBar(
                largeTitle: Text(bandName),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () async {
                        await showCupertinoModalPopup<void>(
                          context: context,
                          builder: (sheetContext) => CreateBookingSheet(
                            onBandSelected: (bandId) {
                              Navigator.of(sheetContext).pop();
                              context.push('/bookings/$bandId/new');
                            },
                          ),
                        );
                      },
                      child: const Icon(CupertinoIcons.add),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () => _showLogoutDialog(context),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: const BoxDecoration(
                          color: CupertinoColors.systemBlue,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            userName.isNotEmpty
                                ? userName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              color: CupertinoColors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              dashboardAsync.when(
                loading: () => const SliverFillRemaining(
                  child: Center(child: CupertinoActivityIndicator()),
                ),
                error: (e, _) => SliverFillRemaining(
                  child: ErrorView(
                    message: ErrorView.friendlyMessage(e),
                    onRetry: () =>
                        ref.read(dashboardProvider.notifier).refresh(),
                  ),
                ),
                data: (state) => _DashboardContent(
                  events: state.events,
                  currentEvent: state.currentEvent,
                  focusedDay: _focusedDay,
                  selectedDay: _selectedDay,
                  onDaySelected: (selected, focused) {
                    setState(() {
                      _selectedDay =
                          isSameDay(_selectedDay, selected) ? null : selected;
                      _focusedDay = focused;
                    });
                  },
                  onPageChanged: (focused) {
                    setState(() {
                      _focusedDay = focused;
                      _selectedDay = null;
                    });
                  },
                ),
              ),
            ],
          ),
          // Floating filter button — sits above the bottom tab bar.
          Positioned(
            right: 16,
            bottom: 16 + MediaQuery.of(context).padding.bottom,
            child: CalendarFilterButton(
              onPressed: () => _openFilterSheet(context),
            ),
          ),
        ],
      ),
    );
  }

  void _openFilterSheet(BuildContext context) {
    final auth = ref.read(authProvider).value;
    final bands = (auth is AuthAuthenticated) ? auth.bands : const [];
    showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => CalendarFilterSheet(bands: bands),
    );
  }

  Future<void> _showLogoutDialog(BuildContext context) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Log out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref.read(authProvider.notifier).logout();
    }
  }
}

class _DashboardContent extends ConsumerStatefulWidget {
  const _DashboardContent({
    required this.events,
    required this.currentEvent,
    required this.focusedDay,
    required this.selectedDay,
    required this.onDaySelected,
    required this.onPageChanged,
  });

  final List<EventSummary> events;
  final EventSummary? currentEvent;
  final DateTime focusedDay;
  final DateTime? selectedDay;
  final void Function(DateTime selected, DateTime focused) onDaySelected;
  final void Function(DateTime focusedDay) onPageChanged;

  @override
  ConsumerState<_DashboardContent> createState() =>
      _DashboardContentState();
}

class _DashboardContentState extends ConsumerState<_DashboardContent> {
  int _slideDirection = 1;

  @override
  void didUpdateWidget(_DashboardContent old) {
    super.didUpdateWidget(old);
    final oldMonth = DateTime(old.focusedDay.year, old.focusedDay.month);
    final newMonth = DateTime(widget.focusedDay.year, widget.focusedDay.month);
    if (oldMonth != newMonth) {
      _slideDirection = newMonth.isAfter(oldMonth) ? 1 : -1;
    }
  }

  DateTime _normalise(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  List<EventSummary> _filterByDayOrMonth(List<EventSummary> events) {
    final focusedDay = widget.focusedDay;
    final selectedDay = widget.selectedDay;
    if (selectedDay != null) {
      final dayEvents =
          events.where((e) => isSameDay(e.parsedDate, selectedDay)).toList();
      if (dayEvents.isNotEmpty) return dayEvents;
      final later = events
          .where((e) => !e.parsedDate.isBefore(selectedDay))
          .toList()
        ..sort((a, b) => a.parsedDate.compareTo(b.parsedDate));
      return later.take(1).toList();
    }
    final monthStart = DateTime(focusedDay.year, focusedDay.month, 1);
    final monthEnd = DateTime(focusedDay.year, focusedDay.month + 1, 1);
    return events
        .where(
          (e) =>
              !e.parsedDate.isBefore(monthStart) &&
              e.parsedDate.isBefore(monthEnd),
        )
        .toList()
      ..sort((a, b) => a.parsedDate.compareTo(b.parsedDate));
  }

  @override
  Widget build(BuildContext context) {
    final filterState = ref.watch(calendarFilterProvider);
    final visibleEvents =
        widget.events.where(filterState.isEventVisible).toList();

    final eventsByDay = <DateTime, List<EventSummary>>{};
    for (final e in visibleEvents) {
      eventsByDay.putIfAbsent(_normalise(e.parsedDate), () => []).add(e);
    }

    final filtered = _filterByDayOrMonth(visibleEvents);
    final unfilteredForCurrentRange =
        _filterByDayOrMonth(widget.events);

    final focusedDay = widget.focusedDay;
    final selectedDay = widget.selectedDay;
    final currentEvent = widget.currentEvent;

    final eventsKey = ValueKey(
        '${focusedDay.year}-${focusedDay.month}-${selectedDay?.day ?? ''}-${filterState.activeCount}');
    final slideDir = _slideDirection;

    return SliverList(
      delegate: SliverChildListDelegate([
        if (currentEvent != null)
          LiveNowCard(
            event: currentEvent,
            onTap: () => _navigateToEvent(context, currentEvent),
          ),
        _CalendarSection(
          focusedDay: focusedDay,
          selectedDay: selectedDay,
          eventsByDay: eventsByDay,
          onDaySelected: widget.onDaySelected,
          onPageChanged: widget.onPageChanged,
        ),
        const SizedBox(height: 8),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          transitionBuilder: (child, animation) {
            final offsetTween = Tween<Offset>(
              begin: Offset(0.15 * slideDir, 0),
              end: Offset.zero,
            );
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: offsetTween.animate(
                  CurvedAnimation(parent: animation, curve: Curves.easeOut),
                ),
                child: child,
              ),
            );
          },
          child: filtered.isEmpty
              ? _EmptyState(
                  key: eventsKey,
                  selectedDay: selectedDay,
                  focusedDay: focusedDay,
                  filterIsActive: filterState.isActive,
                  filterIsHidingEverything: filterState.isActive &&
                      unfilteredForCurrentRange.isNotEmpty,
                  onClearFilters: () =>
                      ref.read(calendarFilterProvider.notifier).clear(),
                )
              : _EventsList(
                  key: eventsKey,
                  events: filtered,
                  focusedDay: focusedDay,
                ),
        ),
        // Extra bottom padding so the floating filter button doesn't cover
        // the last event card.
        const SizedBox(height: 80),
      ]),
    );
  }

  void _navigateToEvent(BuildContext context, EventSummary event) {
    if (event.isRehearsal) {
      if (event.id != null) {
        context.push('/rehearsals/${event.id}');
      } else {
        context.push('/rehearsals/by-key/${event.key}');
      }
    } else {
      context.push('/events/${event.key}');
    }
  }
}

class _CalendarSection extends StatelessWidget {
  const _CalendarSection({
    required this.focusedDay,
    required this.selectedDay,
    required this.eventsByDay,
    required this.onDaySelected,
    this.onPageChanged,
  });

  final DateTime focusedDay;
  final DateTime? selectedDay;
  final Map<DateTime, List<EventSummary>> eventsByDay;
  final void Function(DateTime selected, DateTime focused) onDaySelected;
  final void Function(DateTime focusedDay)? onPageChanged;

  DateTime _normalise(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  @override
  Widget build(BuildContext context) {
    final brightness = MediaQuery.platformBrightnessOf(context);
    return Theme(
      data: ThemeData(brightness: brightness),
      child: Material(
        color: CupertinoColors.systemBackground.resolveFrom(context),
        child: TableCalendar<EventSummary>(
          firstDay: DateTime.now().subtract(const Duration(days: 365)),
          lastDay: DateTime.now().add(const Duration(days: 365)),
          focusedDay: focusedDay,
          selectedDayPredicate: (day) => isSameDay(selectedDay, day),
          eventLoader: (day) => eventsByDay[_normalise(day)] ?? const [],
          onDaySelected: onDaySelected,
          onPageChanged: onPageChanged,
          calendarFormat: CalendarFormat.month,
          rowHeight: 56,
          availableCalendarFormats: const {CalendarFormat.month: 'Month'},
          headerStyle: const HeaderStyle(
              formatButtonVisible: false, titleCentered: true),
          calendarStyle: const CalendarStyle(
            selectedDecoration: BoxDecoration(
                color: CupertinoColors.systemBlue, shape: BoxShape.circle),
            todayDecoration: BoxDecoration(
                color: CupertinoColors.systemBlue, shape: BoxShape.circle),
            todayTextStyle: TextStyle(color: CupertinoColors.white),
          ),
          calendarBuilders: CalendarBuilders<EventSummary>(
            markerBuilder: (context, day, dayEvents) {
              if (dayEvents.isEmpty) return null;
              return Padding(
                padding: const EdgeInsets.only(top: 28),
                child: CalendarDayMarkers(events: dayEvents),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _EventsList extends StatelessWidget {
  const _EventsList({super.key, required this.events, required this.focusedDay});

  final List<EventSummary> events;
  final DateTime focusedDay;

  String get _monthLabel {
    final now = DateTime.now();
    if (focusedDay.year == now.year && focusedDay.month == now.month) {
      return 'Upcoming Events';
    }
    return 'Events in ${DateFormat('MMMM yyyy').format(focusedDay)}';
  }

  void _navigateToEvent(BuildContext context, EventSummary event) {
    if (event.isRehearsal) {
      if (event.id != null) {
        context.push('/rehearsals/${event.id}');
      } else {
        context.push('/rehearsals/by-key/${event.key}');
      }
    } else {
      context.push('/events/${event.key}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            _monthLabel,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
        ),
        ...events.map(
          (event) => EventCard(
            event: event,
            onTap: () => _navigateToEvent(context, event),
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    super.key,
    required this.selectedDay,
    required this.focusedDay,
    required this.filterIsActive,
    required this.filterIsHidingEverything,
    required this.onClearFilters,
  });

  final DateTime? selectedDay;
  final DateTime focusedDay;
  final bool filterIsActive;
  final bool filterIsHidingEverything;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    if (filterIsActive && filterIsHidingEverything) {
      return Padding(
        padding:
            const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
        child: Column(
          children: [
            const EmptyStateView(
              icon: CupertinoIcons.line_horizontal_3_decrease,
              title: 'No events match your filters',
              subtitle: '',
            ),
            const SizedBox(height: 12),
            CupertinoButton.filled(
              onPressed: onClearFilters,
              child: const Text('Clear filters'),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      child: EmptyStateView(
        icon: CupertinoIcons.calendar,
        title: 'No events',
        subtitle: selectedDay != null
            ? 'Nothing on ${DateFormat('MMMM d').format(selectedDay)}.'
            : 'Nothing scheduled for ${DateFormat('MMMM').format(focusedDay)}.',
      ),
    );
  }
}
```

- [ ] **Step 4: Run the integration test to verify it passes**

Run: `flutter test test/widgets/dashboard_calendar_filter_integration_test.dart`
Expected: All tests PASS.

- [ ] **Step 5: Run the full test suite**

Run: `flutter test`
Expected: All tests PASS (no regressions in `dashboard_provider_test`, `event_card_test`, etc.).

- [ ] **Step 6: Run the analyzer**

Run: `flutter analyze`
Expected: No new warnings or errors.

- [ ] **Step 7: Manual smoke test on the running app**

Run: `flutter run -d chrome --dart-define=BASE_URL=http://localhost:8715`
Verify:
- The calendar shows band-avatar markers (logo or initial fallback) instead of generic blue dots.
- A floating filter button appears bottom-right.
- Tapping it opens the sheet; toggling a band hides its events from the calendar and the events list.
- The badge appears with the active count when a filter is on.
- Tapping "Clear All" in the sheet (or "Clear filters" in the empty state) restores the full calendar.
- Restarting the app restores the unfiltered calendar (no persistence).

- [ ] **Step 8: Commit**

```bash
git add lib/features/dashboard/screens/dashboard_screen.dart test/widgets/dashboard_calendar_filter_integration_test.dart
git commit -m "feat(dashboard): wire band-aware markers and floating filter into calendar"
```

---

## Self-review

**Spec coverage:**

- ✅ Marker rendering (avatar + ring, 1/2/+N) → Task 5.
- ✅ Ring color + status mapping → Task 5 (`_ringSpec`), backed by Task 1 (helper).
- ✅ Booking status normalization → Task 1.
- ✅ Accessibility semantics → Task 5 (`_semanticsLabel`) and Task 6 (button), Task 7 (band chips).
- ✅ Floating filter button + badge → Task 6.
- ✅ Filter sheet (drag handle, header, bands row, event-type switches, live update, haptics) → Task 7.
- ✅ "Clear All" inside the sheet → Task 7.
- ✅ Filter-aware empty state with inline "Clear filters" → Task 8.
- ✅ Provider (`hiddenBandIds`, `hiddenEventTypes`, `clear`, `toggle*`) → Task 4.
- ✅ Wiring into `_DashboardContent` (`visibleEvents`, `_eventsByDay`) → Task 8.
- ✅ `_getEventsForDay` returns real events instead of sentinel → Task 8 (`eventLoader: (day) => eventsByDay[...]`).
- ✅ Marker order: time ascending, nulls last → Task 5 (`CalendarDayMarkers` sort).
- ✅ Row-height bump (52→56) → Task 8 (`rowHeight: 56`).
- ✅ Shared `BandAvatar` with cached image → Tasks 2 + 3.
- ✅ Reset on app restart (no persistence) → Task 4 (plain `Notifier`).

**Type consistency:** `CalendarFilterState` field names (`hiddenBandIds`, `hiddenEventTypes`) used consistently across Tasks 4, 6, 7, 8. `BandAvatar.forBand` / `BandAvatar.forUser` used consistently in Tasks 2, 3, 5, 7. `bookingConfirmationFromStatus` used in Task 5's `_ringSpec` and `_semanticsLabel` exactly as defined in Task 1. `CalendarDayMarkers({required events, avatarSize})` and `CalendarEventMarker({required event, size})` signatures match between Task 5 (definition) and Task 8 (use, via `markerBuilder`).

**Placeholder scan:** No "TBD" / "TODO" / "appropriate" / "similar to" — every step has full code or an explicit command + expected outcome.

**Out of scope confirmed:** persistence, tap-to-filter from a marker, new event-type categories, backend changes — none introduced.

---

Plan complete and saved to `docs/superpowers/plans/2026-05-02-dashboard-calendar-markers.md`. Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — Execute tasks in this session with checkpoints for review.

Which approach?
