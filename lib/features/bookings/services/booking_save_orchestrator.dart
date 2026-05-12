import '../data/models/event_draft.dart';

/// Sealed status of one sub-operation in a booking save.
sealed class OperationStatus {
  const OperationStatus();
}

class OperationPending extends OperationStatus {
  const OperationPending();
}

class OperationSuccess extends OperationStatus {
  const OperationSuccess();
}

class OperationFailure extends OperationStatus {
  const OperationFailure(this.message);
  final String message;
}

/// Snapshot of the booking form's intended save at the moment the user
/// hits Save. The orchestrator runs the diff against the server: booking
/// PATCH first, then each event sub-op sequentially.
///
/// Callers build this from form state vs the original loaded values.
class BookingFormSnapshot {
  const BookingFormSnapshot({
    this.bookingPatch,
    this.eventUpdates = const {},
    this.eventCreates = const {},
    this.eventDeletes = const {},
  });

  /// Booking-level fields the user changed. Null when no booking-level
  /// fields were dirty (orchestrator skips the PATCH entirely).
  final BookingFieldDiff? bookingPatch;

  /// Keyed by existing event `key` (UUID). Each value is the new state the
  /// user wants written. Events the user didn't touch are absent.
  final Map<String, EventDraft> eventUpdates;

  /// Keyed by a local row-key string (e.g. "new-1") so the UI can map
  /// per-op failures back to the corresponding form row.
  final Map<String, EventDraft> eventCreates;

  /// Set of existing event ids the user removed from the form.
  final Set<int> eventDeletes;

  bool get isEmpty =>
      bookingPatch == null &&
      eventUpdates.isEmpty &&
      eventCreates.isEmpty &&
      eventDeletes.isEmpty;
}

/// Booking-level fields. All null means no diff; the orchestrator treats
/// an all-null diff as "skip the PATCH."
class BookingFieldDiff {
  const BookingFieldDiff({
    this.name,
    this.eventTypeId,
    this.price,
    this.status,
    this.contractOption,
    this.notes,
  });

  final String? name;
  final int? eventTypeId;
  final String? price;
  final String? status;
  final String? contractOption;
  final String? notes;

  bool get isEmpty =>
      name == null &&
      eventTypeId == null &&
      price == null &&
      status == null &&
      contractOption == null &&
      notes == null;
}

/// Result of running a snapshot through the orchestrator. Each sub-op's
/// outcome is captured; the UI layer reads [failureKeys] to highlight
/// failed rows and reads [partiallySucceeded] / [allFailed] to choose
/// between the inline-error UX and the full-failure banner.
class BookingSaveResult {
  BookingSaveResult({
    required this.bookingPatch,
    required this.eventUpdates,
    required this.eventCreates,
    required this.eventDeletes,
  });

  final OperationStatus bookingPatch;
  final Map<String, OperationStatus> eventUpdates;
  final Map<String, OperationStatus> eventCreates;
  final Map<int, OperationStatus> eventDeletes;

  Iterable<OperationStatus> get _all sync* {
    yield bookingPatch;
    yield* eventUpdates.values;
    yield* eventCreates.values;
    yield* eventDeletes.values;
  }

  bool get allSucceeded =>
      _all.every((s) => s is OperationSuccess);

  bool get allFailed {
    final ran = _all.where((s) => s is! OperationPending).toList();
    if (ran.isEmpty) return false;
    return ran.every((s) => s is OperationFailure);
  }

  bool get partiallySucceeded {
    final hasSuccess = _all.any((s) => s is OperationSuccess);
    final hasFailure = _all.any((s) => s is OperationFailure);
    return hasSuccess && hasFailure;
  }

  int get failedCount => _all.whereType<OperationFailure>().length;

  /// Row keys that failed. "BOOKING" for the booking-level patch,
  /// "EVT-{key|id}" for an existing-event op (update by key or delete by id),
  /// or "NEW-{localKey}" for a create op.
  Iterable<MapEntry<String, OperationFailure>> get failureKeys sync* {
    if (bookingPatch is OperationFailure) {
      yield MapEntry('BOOKING', bookingPatch as OperationFailure);
    }
    for (final e in eventUpdates.entries) {
      if (e.value is OperationFailure) {
        yield MapEntry('EVT-${e.key}', e.value as OperationFailure);
      }
    }
    for (final e in eventCreates.entries) {
      if (e.value is OperationFailure) {
        yield MapEntry('NEW-${e.key}', e.value as OperationFailure);
      }
    }
    for (final e in eventDeletes.entries) {
      if (e.value is OperationFailure) {
        yield MapEntry('EVT-${e.key}', e.value as OperationFailure);
      }
    }
  }
}
