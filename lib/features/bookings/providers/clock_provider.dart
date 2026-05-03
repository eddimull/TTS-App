import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Returns the current `DateTime` when called. Override in tests to pin
/// "now" for deterministic date-range math.
///
/// ```dart
/// // In a test:
/// container = ProviderContainer(overrides: [
///   clockProvider.overrideWithValue(() => DateTime(2026, 5, 3, 12, 0)),
/// ]);
/// ```
final clockProvider = Provider<DateTime Function()>((_) => DateTime.now);
