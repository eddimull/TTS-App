import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/storage/secure_storage.dart';

class SelectedBandNotifier extends AsyncNotifier<int?> {
  @override
  Future<int?> build() async {
    final storage = ref.watch(secureStorageProvider);
    final raw = await storage.readBandId();
    if (raw == null) return null;
    return int.tryParse(raw);
  }

  /// Persist a new band selection and update state.
  Future<void> selectBand(int id) async {
    final storage = ref.read(secureStorageProvider);
    await storage.writeBandId(id.toString());
    state = AsyncValue.data(id);
  }

  /// Clear the selected band (e.g. on logout or band switch).
  Future<void> clear() async {
    final storage = ref.read(secureStorageProvider);
    await storage.deleteBandId();
    state = const AsyncValue.data(null);
  }
}

final selectedBandProvider =
    AsyncNotifierProvider<SelectedBandNotifier, int?>(
  () => SelectedBandNotifier(),
);
