import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../data/setlist_editor_repository.dart';

final setlistEditorRepositoryProvider = Provider<SetlistEditorRepository>((ref) {
  return SetlistEditorRepository(ref.read(apiClientProvider).dio);
});
