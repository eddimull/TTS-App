# Testing Guide — TTS Bandmate

How to run, organize, and write tests for this app. The repo already has a
substantial suite (model, provider, widget, flow, and screenshot tests) — keep
new tests consistent with what's here.

## Running tests

```bash
flutter pub get                          # install deps first
flutter test                             # run the whole suite
flutter test test/widgets/login_screen_test.dart   # run one file
flutter test test/models/                # run a directory
flutter test --name "logs in"            # run tests matching a name
flutter test --coverage                  # write coverage/lcov.info
flutter analyze                          # lints / static analysis
```

If you touch anything code-generated (`*.g.dart` / `*.freezed.dart`, Riverpod
generator, json_serializable), regenerate before running tests:

```bash
dart run build_runner build --delete-conflicting-outputs
```

Run both of these clean before pushing:

```bash
flutter analyze && flutter test
```

## Layout — tests mirror `lib/`

| Kind | Lives in | Examples |
| --- | --- | --- |
| Model `fromJson` | `test/models/` | `booking_summary_test.dart`, `event_detail_test.dart` |
| Providers (Riverpod) | `test/providers/`, `test/features/<x>/providers/` | `events_provider_test.dart`, `library_provider_test.dart` |
| Repositories | `test/features/<x>/` | `bookings_repository_user_bookings_test.dart` |
| Widgets / screens | `test/widgets/`, `test/features/<x>/{widgets,screens}/` | `event_card_test.dart`, `library_screen_test.dart` |
| End-to-end flows | `test/` (top level) | `login_flow_widget_test.dart`, `onboarding_flows_widget_test.dart` |
| Shared setup | `test/helpers/` | `test_harness.dart` |
| Screenshots | `test/screenshots/` | generated `*.png` |

Rules:
- File names **must** end in `_test.dart` or `flutter test` skips them.
- Put a test next to the mirror of the file it covers.
- Reach for `test/helpers/test_harness.dart` before hand-rolling container/widget
  setup — see `test/helpers/test_harness_smoke_test.dart` for usage. Extend the
  harness rather than copy-pasting boilerplate across files.

## Provider tests (Riverpod v2)

State is `AsyncNotifier` / `AsyncNotifierProvider`. Drive it through a
`ProviderContainer` and override dependencies (repositories, `SecureStorage`)
with fakes instead of hitting the network.

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(
      overrides: [
        // repositoryProvider.overrideWithValue(FakeRepository()),
        // secureStorageProvider.overrideWithValue(FakeSecureStorage()),
      ],
    );
    addTearDown(container.dispose); // always tear down
  });

  test('emits data on success', () async {
    final value = await container.read(someNotifierProvider.future);
    expect(value, isNotEmpty);
  });

  test('reflects an error state', () async {
    // arrange the fake to throw, then:
    expect(container.read(someNotifierProvider), isA<AsyncError>());
  });
}
```

Guidelines:
- Prefer hand-written fakes (e.g. `FakeSecureStorage`) for storage/repos.
- `addTearDown(container.dispose)` in every `setUp` so providers don't leak.
- Test the three `AsyncValue` shapes that matter for the feature: loading, data,
  error.

## Model tests

Models use hand-written `fromJson` factories with null-coalescing defaults
(`?? ''`, `?? 0`). Cover:
- a full/typical payload,
- missing/null fields (verify the defaults kick in, no throw),
- type edge cases (numbers as strings, empty lists).

```dart
test('falls back to defaults when fields are missing', () {
  final model = BookingSummary.fromJson({});
  expect(model.name, '');
});
```

## Widget tests (Cupertino)

The app is Cupertino-based, so wrap the widget in a Cupertino ancestor and a
`ProviderScope` with overrides.

```dart
await tester.pumpWidget(
  ProviderScope(
    overrides: [/* fakes */],
    child: const CupertinoApp(home: LoginScreen()),
  ),
);
await tester.enterText(find.byType(CupertinoTextField).first, 'a@b.com');
await tester.tap(find.text('Log In'));
await tester.pumpAndSettle();
expect(find.text('Invalid credentials'), findsNothing);
```

Use `pumpAndSettle()` after async/animated interactions; use `find.byType`,
`find.text`, or a `Key` to locate widgets. Follow the existing
`test/widgets/*_test.dart` files for the established patterns.

## Flow tests

`login_flow_widget_test.dart` and `onboarding_flows_widget_test.dart` exercise
multi-screen journeys (login → band selection → dashboard). When adding a new
end-to-end journey, put it at the top level of `test/` and lean on the harness
for app bootstrapping and provider overrides.

## Screenshots

Tests under `test/screenshots/` produce `*.png` artifacts (e.g.
`01_login_empty.png`, `03_after_signin.png`). If you change a captured screen,
re-run the relevant screenshot test and review the regenerated image before
committing it.

## Checklist for a new feature

1. Model `fromJson` test (happy path + missing fields).
2. Repository test with a fake HTTP/Dio layer.
3. Provider test covering loading / data / error.
4. Widget test for the screen's key interactions.
5. `flutter analyze && flutter test` both clean.
