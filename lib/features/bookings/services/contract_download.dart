import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';

import '../data/bookings_repository.dart';

/// Download the booking's contract PDF and hand it to the OS PDF viewer.
///
/// Writes to the temporary directory because the file is a view-only
/// artifact, not something to persist in app documents. Errors surface
/// via Cupertino dialogs anchored to [context].
Future<void> downloadAndOpenContractPdf({
  required BuildContext context,
  required WidgetRef ref,
  required int bandId,
  required int bookingId,
}) async {
  try {
    final bytes = await ref
        .read(bookingsRepositoryProvider)
        .downloadContractPdf(bandId, bookingId);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/contract-$bookingId.pdf');
    await file.writeAsBytes(bytes);
    final result = await OpenFile.open(file.path, type: 'application/pdf');
    if (result.type != ResultType.done && context.mounted) {
      await showCupertinoDialog<void>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: const Text('Could not open PDF'),
          content: Text(result.message),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  } catch (e) {
    if (!context.mounted) return;
    await showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Download failed'),
        content: Text(e.toString()),
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
