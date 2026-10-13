import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/pricing/data/models/price_estimate.dart';
import 'package:tts_bandmate/features/pricing/data/models/pricing_settings.dart';
import 'package:tts_bandmate/features/pricing/utils/percent.dart';

void main() {
  group('PriceEstimate.fromJson', () {
    test('parses the full contract payload', () {
      final e = PriceEstimate.fromJson({
        'estimate': 11250.0,
        'low': 9800,
        'high': '12600.00',
        'confidence': 'high',
        'baseline_source': 'history',
        'sample_size': 42,
        'baseline': 9400.0,
        'duration_hours': 4.0,
        'distance_miles': 12.3,
        'breakdown': [
          {'key': 'baseline', 'label': 'Wedding baseline', 'type': 'base', 'factor': null, 'amount': 9400.0},
          {'key': 'season', 'label': 'May', 'type': 'multiplier', 'factor': 1.1, 'amount': 940.0},
          {'key': 'addon:production', 'label': 'Production', 'type': 'fee', 'factor': null, 'amount': 1500},
        ],
        'warnings': [
          {'code': 'date_conflict', 'message': 'You already have a booking.'}
        ],
        'comparables': [
          {'booking_id': 12, 'name': 'Smith Wedding', 'date': '2026-05-09', 'price': 9800.0, 'venue_name': 'Hall'}
        ],
      });
      expect(e.hasEstimate, isTrue);
      expect(e.estimate, 11250.0);
      expect(e.low, 9800.0);
      expect(e.high, 12600.0);
      expect(e.confidence, 'high');
      expect(e.sampleSize, 42);
      expect(e.breakdown, hasLength(3));
      expect(e.breakdown[0].factor, isNull);
      expect(e.breakdown[1].factor, 1.1);
      expect(e.breakdown[2].amount, 1500.0);
      expect(e.warnings.single.code, 'date_conflict');
      expect(e.comparables.single.bookingId, 12);
      expect(e.comparables.single.venueName, 'Hall');
    });

    test('null estimate (no_baseline) and missing lists are safe', () {
      final e = PriceEstimate.fromJson({
        'estimate': null,
        'warnings': [
          {'code': 'no_baseline', 'message': 'No history.'}
        ],
      });
      expect(e.hasEstimate, isFalse);
      expect(e.breakdown, isEmpty);
      expect(e.comparables, isEmpty);
      expect(e.confidence, 'low');
      expect(e.warnings.single.code, 'no_baseline');
    });
  });

  test('PriceEstimateRequest.toJson matches contract keys', () {
    const r = PriceEstimateRequest(
      eventTypeId: 1,
      date: '2027-05-15',
      startTime: '19:00',
      endTime: '23:00',
      venueAddress: '  ',
      addOns: ['production'],
    );
    final j = r.toJson();
    expect(j['event_type_id'], 1);
    expect(j['date'], '2027-05-15');
    expect(j['start_time'], '19:00');
    expect(j['venue_address'], isNull);
    expect(j['add_ons'], ['production']);
  });

  group('PricingSettingsBundle.fromJson', () {
    final json = {
      'settings': {
        'season_multipliers': {'1': 1.0, '5': '1.1', '12': 1},
        'day_of_week_multipliers': {'0': 0.9, '6': 1.0},
        'special_dates': [
          {'date': '12-31', 'label': "New Year's Eve", 'multiplier': 1.5}
        ],
        'standard_hours': 4,
        'standard_hours_by_type': [], // PHP empty array
        'overtime_pct_per_hour': 15,
        'min_duration_factor': 0.75,
        'short_notice_days': '30',
        'short_notice_multiplier': 1.0,
        'annual_increase_pct': 3,
        'free_radius_miles': 50,
        'per_mile_rate': 2.0,
        'lodging_threshold_miles': 150,
        'lodging_fee': 0,
        'add_ons': [
          {'key': 'production', 'label': 'Production', 'amount': 1500}
        ],
        'base_rates': {'1': 9000},
        'round_to': 50,
      },
      'event_types': [
        {'id': 1, 'name': 'Wedding'}
      ],
      'history': [
        {'event_type_id': 1, 'sample_size': 42, 'baseline': 9400.0}
      ],
    };

    test('parses settings, event types and history', () {
      final b = PricingSettingsBundle.fromJson(json);
      expect(b.settings.seasonMultipliers[5], 1.1);
      expect(b.settings.seasonMultipliers[12], 1.0);
      expect(b.settings.dayOfWeekMultipliers[0], 0.9);
      expect(b.settings.specialDates.single.multiplier, 1.5);
      expect(b.settings.standardHoursByType, isEmpty);
      expect(b.settings.shortNoticeDays, 30);
      expect(b.settings.addOns.single.amount, 1500.0);
      expect(b.settings.baseRates[1], 9000.0);
      expect(b.eventTypes.single.name, 'Wedding');
      expect(b.historyFor(1)!.sampleSize, 42);
      expect(b.historyFor(2), isNull);
    });

    test('toJson round-trips with string keys', () {
      final s = PricingSettingsBundle.fromJson(json).settings;
      final out = s.toJson();
      expect((out['season_multipliers'] as Map)['5'], 1.1);
      expect((out['base_rates'] as Map)['1'], 9000.0);
      final again = PricingSettings.fromJson(out);
      expect(again.toJson(), out);
    });

    test('empty payload yields defaults without throwing', () {
      final b = PricingSettingsBundle.fromJson({});
      expect(b.settings.standardHours, 4);
      expect(b.eventTypes, isEmpty);
    });
  });

  group('percent helpers', () {
    test('multiplier <-> percent', () {
      expect(multiplierToPercent(1.1), 10);
      expect(percentToMultiplier(-20), 0.8);
      expect(percentToMultiplier(multiplierToPercent(1.05)), 1.05);
    });
    test('formatMultiplier', () {
      expect(formatMultiplier(1.1), '+10%');
      expect(formatMultiplier(0.8), '-20%');
      expect(formatMultiplier(1.0), '0%');
      expect(formatMultiplier(1.5), '+50%');
    });
  });
}
