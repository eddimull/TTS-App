import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/models/contract_history_entry.dart';
import 'package:tts_bandmate/features/bookings/providers/contract_history_provider.dart';
import 'package:tts_bandmate/features/bookings/widgets/contract/contract_history_list.dart';

void main() {
  testWidgets('renders empty state when no entries', (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        contractHistoryProvider('env-1')
            .overrideWith((ref) async => <ContractHistoryEntry>[]),
      ],
      child: const CupertinoApp(
        home: CupertinoPageScaffold(
          child: ContractHistoryList(envelopeId: 'env-1'),
        ),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.textContaining('No history'), findsOneWidget);
  });

  testWidgets('renders entries', (t) async {
    final entry = ContractHistoryEntry(
      id: '1',
      createdAt: DateTime(2026, 5, 11, 12, 0),
      action: 'Document Sent',
      actionCode: 6,
      userEmail: 'eddie@example.com',
      description: 'Sent to signer.',
      status: 'completed',
      ipAddress: '1.2.3.4',
    );
    await t.pumpWidget(ProviderScope(
      overrides: [
        contractHistoryProvider('env-1')
            .overrideWith((ref) async => [entry]),
      ],
      child: const CupertinoApp(
        home: CupertinoPageScaffold(
          child: ContractHistoryList(envelopeId: 'env-1'),
        ),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.text('Document Sent'), findsOneWidget);
    expect(find.text('eddie@example.com'), findsOneWidget);
    expect(find.text('Sent to signer.'), findsOneWidget);
    expect(find.textContaining('IP:'), findsOneWidget);
  });
}
