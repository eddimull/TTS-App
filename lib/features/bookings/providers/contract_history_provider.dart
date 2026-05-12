import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/bookings_repository.dart';
import '../data/models/contract_history_entry.dart';

final contractHistoryProvider = FutureProvider.autoDispose
    .family<List<ContractHistoryEntry>, String>((ref, envelopeId) {
  return ref
      .read(bookingsRepositoryProvider)
      .fetchContractHistory(envelopeId);
});
