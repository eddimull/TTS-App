import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/events/data/event_tabs.dart';
import 'package:tts_bandmate/features/events/data/models/event_detail.dart';
import 'package:tts_bandmate/features/events/widgets/event_sections/wedding_section.dart';

void main() {
  group('WeddingDetail.fromJson details', () {
    test('reads answers with the question as the title', () {
      final wedding = WeddingDetail.fromJson({
        'dances': [],
        'details': [
          {'title': "Groom's mother's name", 'data': 'Linda Smith'},
        ],
      });

      expect(wedding.details.single.title, "Groom's mother's name");
      expect(wedding.details.single.data, 'Linda Smith');
    });

    test('tolerates a backend that does not send details yet', () {
      expect(WeddingDetail.fromJson({'dances': []}).details, isEmpty);
    });
  });

  testWidgets('shows each answer beside its question', (tester) async {
    await tester.pumpWidget(const CupertinoApp(
      home: CupertinoPageScaffold(
        child: WeddingSection(
          wedding: WeddingDetail(
            onsite: true,
            dances: [],
            details: [
              WeddingQuestionDetail(
                title: 'How would you like to be introduced?',
                data: 'Mr. and Mrs. Smith',
              ),
            ],
          ),
        ),
      ),
    ));

    expect(find.text('How would you like to be introduced?'), findsOneWidget);
    expect(find.text('Mr. and Mrs. Smith'), findsOneWidget);
    expect(find.text('Special Dances'), findsNothing);
  });

  test('details alone do not add the Music tab', () {
    final event = EventDetail.fromJson({
      'id': 1,
      'key': 'evt-1',
      'title': 'Test',
      'date': '2026-04-15',
      'members': [],
      'timeline': [],
      'wedding': {
        'dances': [],
        'details': [
          {'title': 'Introduced as', 'data': 'The Smiths'},
        ],
      },
    });

    expect(visibleTabs(event), isNot(contains(EventTab.music)));
  });
}
