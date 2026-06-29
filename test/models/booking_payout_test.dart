import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_payout.dart';

Map<String, dynamic> _flat() => {
      'payout': {'id': 9, 'base_amount': '1000.00', 'adjusted_amount': '750.00', 'payout_config_id': 42},
      'config': {'id': 42, 'name': 'Standard Split', 'is_active': true},
      'result': {
        'total_amount': 750.0,
        'band_cut': 150.0,
        'distributable_amount': 600.0,
        'member_payouts': [
          {'name': 'Alice', 'role': 'Vocalist', 'amount': 300.0, 'user_id': 1, 'events_attended': 3, 'total_events': 3},
          {'name': 'Bob', 'role': 'Guitar', 'amount': 200.0, 'user_id': 2, 'events_attended': 2, 'total_events': 3},
        ],
        'payment_group_payouts': [],
      },
      'adjustments': [
        {'id': 7, 'amount': '-250.00', 'description': 'Gas', 'notes': 'Reimbursed'},
      ],
      'events': [
        {'id': 100, 'label': 'Fri Apr 12 · Gala', 'value': '333.00', 'members': [
          {'id': 555, 'user_id': 1, 'name': 'Alice', 'attendance_status': 'attended'},
        ]},
      ],
      'available_configs': [
        {'id': 42, 'name': 'Standard Split', 'is_active': true},
        {'id': 43, 'name': 'Even', 'is_active': false},
      ],
    };

void main() {
  group('BookingPayout.fromJson', () {
    test('parses flat member payouts, adjustments, events', () {
      final p = BookingPayout.fromJson(_flat());
      expect(p.adjustedTotal, 750.0);
      expect(p.config?.name, 'Standard Split');
      expect(p.members.length, 2);
      expect(p.members.first.attendanceLabel, '3/3');
      expect(p.members.first.displayAmount, r'$300.00');
      expect(p.groups, isEmpty);
      expect(p.adjustments.single.displayAmount, r'-$250.00');
      expect(p.events.single.members.single.attendanceStatus, 'attended');
      expect(p.availableConfigs.length, 2);
    });

    test('parses grouped payment_group_payouts', () {
      final json = _flat();
      (json['result'] as Map)['payment_group_payouts'] = [
        {'group_name': 'Players', 'total': 600.0, 'payouts': [
          {'user_name': 'Alice', 'role': 'Vocalist', 'amount': 300.0, 'user_id': 1},
        ]},
      ];
      final p = BookingPayout.fromJson(json);
      expect(p.groups.single.groupName, 'Players');
      expect(p.groups.single.members.single.name, 'Alice');
      expect(p.groups.single.displayTotal, r'$600.00');
    });

    test('handles null result (no active config)', () {
      final json = _flat();
      json['result'] = null;
      json['config'] = null;
      final p = BookingPayout.fromJson(json);
      expect(p.members, isEmpty);
      expect(p.bandCut, 0);
      expect(p.config, isNull);
    });
  });

  group('BookingPayout adjustmentDelta / displayAdjustmentDelta', () {
    test('negative delta: base 1000, adjusted 750 → delta -250 → "-\$250.00"', () {
      final p = BookingPayout.fromJson(_flat());
      expect(p.basePrice, 1000.0);
      expect(p.adjustedTotal, 750.0);
      expect(p.adjustmentDelta, -250.0);
      expect(p.displayAdjustmentDelta, r'-$250.00');
    });

    test('positive delta: adjusted > base → prefix "+"', () {
      final json = _flat();
      // Override adjusted_amount to be higher than base to simulate a positive adjustment.
      (json['payout'] as Map)['adjusted_amount'] = '1200.00';
      final p = BookingPayout.fromJson(json);
      expect(p.adjustmentDelta, 200.0);
      expect(p.displayAdjustmentDelta, r'+$200.00');
    });

    test('zero delta: no adjustments applied → no sign prefix', () {
      final json = _flat();
      (json['payout'] as Map)['adjusted_amount'] = '1000.00';
      final p = BookingPayout.fromJson(json);
      expect(p.adjustmentDelta, 0.0);
      // No sign prefix on zero.
      expect(p.displayAdjustmentDelta, r'$0.00');
    });
  });
}
