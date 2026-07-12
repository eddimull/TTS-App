import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:tts_bandmate/core/theme/context_colors.dart';
import '../../../shared/widgets/error_view.dart';
import '../data/chat_repository.dart';
import '../data/models/chat_contact.dart';

/// Contacts you can DM (fetched fresh each open; small list).
final chatContactsProvider = FutureProvider.autoDispose<List<ChatContact>>(
  (ref) => ref.watch(chatRepositoryProvider).contacts(),
);

class NewMessageScreen extends ConsumerStatefulWidget {
  const NewMessageScreen({super.key});

  @override
  ConsumerState<NewMessageScreen> createState() => _NewMessageScreenState();
}

class _NewMessageScreenState extends ConsumerState<NewMessageScreen> {
  bool _opening = false;

  Future<void> _openDm(ChatContact contact) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final conversation =
          await ref.read(chatRepositoryProvider).openDm(contact.id);
      if (!mounted) return;
      context.pushReplacement(
        '/conversations/${conversation.id}',
        extra: {'title': conversation.title},
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _opening = false);
      showCupertinoDialog<void>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: const Text('Could not start conversation'),
          content: Text(ErrorView.friendlyMessage(e)),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final contactsAsync = ref.watch(chatContactsProvider);
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('New Message')),
      child: SafeArea(
        child: contactsAsync.when(
          loading: () => const Center(child: CupertinoActivityIndicator()),
          error: (e, _) => ErrorView(
            message: ErrorView.friendlyMessage(e),
            onRetry: () => ref.invalidate(chatContactsProvider),
          ),
          data: (contacts) => ListView.builder(
            itemCount: contacts.length,
            itemBuilder: (_, i) {
              final contact = contacts[i];
              return CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _opening ? null : () => _openDm(contact),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Icon(CupertinoIcons.person_crop_circle,
                          size: 30, color: context.secondaryText),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(contact.name,
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: context.primaryText)),
                            if (contact.context.isNotEmpty)
                              Text(
                                contact.isSub
                                    ? '${contact.context} · Sub'
                                    : contact.context,
                                style: TextStyle(
                                    fontSize: 13, color: context.secondaryText),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
