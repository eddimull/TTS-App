import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/chat_repository.dart';
import '../data/models/chat_contact.dart';

/// Contacts you can DM (fetched fresh each open; small list).
final chatContactsProvider = FutureProvider.autoDispose<List<ChatContact>>(
  (ref) => ref.watch(chatRepositoryProvider).contacts(),
);
