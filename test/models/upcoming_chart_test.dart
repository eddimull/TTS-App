import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/dashboard/data/models/upcoming_chart.dart';

void main() {
  group('UpcomingChart.fromJson', () {
    test('test_parses_chart_item', () {
      final chart = UpcomingChart.fromJson({
        'type': 'chart',
        'chart_id': 5,
        'title': 'My Way',
        'composer': 'Paul Anka',
        'url': null,
        'event_title': 'Corporate Gig',
        'event_date': '2026-04-15',
        'venue_name': 'The Grand Hotel',
      });

      expect(chart.type, 'chart');
      expect(chart.chartId, 5);
      expect(chart.title, 'My Way');
      expect(chart.composer, 'Paul Anka');
      expect(chart.url, isNull);
      expect(chart.eventTitle, 'Corporate Gig');
      expect(chart.eventDate, '2026-04-15');
      expect(chart.venueName, 'The Grand Hotel');
    });

    test('test_parses_song_item_with_url', () {
      final song = UpcomingChart.fromJson({
        'type': 'song',
        'chart_id': null,
        'title': 'Fly Me to the Moon',
        'composer': null,
        'url': 'https://youtube.com/watch?v=abc',
        'event_title': 'Jazz Night',
        'event_date': '2026-05-01',
        'venue_name': null,
      });

      expect(song.type, 'song');
      expect(song.chartId, isNull);
      expect(song.url, 'https://youtube.com/watch?v=abc');
      expect(song.composer, isNull);
      expect(song.venueName, isNull);
    });

    test('test_type_defaults_to_chart_when_missing', () {
      final item = UpcomingChart.fromJson({
        'title': 'Unknown',
        'event_title': 'Some Gig',
        'event_date': '2026-01-01',
      });
      expect(item.type, 'chart');
    });

    test('test_equality_based_on_chart_id_title_and_date', () {
      final a = UpcomingChart.fromJson({
        'type': 'chart', 'chart_id': 3, 'title': 'Song A',
        'event_title': 'Gig 1', 'event_date': '2026-04-15',
      });
      final b = UpcomingChart.fromJson({
        'type': 'chart', 'chart_id': 3, 'title': 'Song A',
        'event_title': 'Gig 2', 'event_date': '2026-04-15',
      });
      expect(a, equals(b));
    });
  });
}
