// SPIKE — the correctness gate for the vyuh_node_flow payout-editor spike.
//
// Proves the LOGIC CONTRACT survives a round-trip TTS -> Vyuh -> TTS:
//   - every node's id / type / data is preserved exactly
//   - every edge's source / target (and meaningful sourceHandle) is preserved
// Layout (positions, ports, sizing) is regenerated and intentionally NOT asserted.
//
// Runs headless via `flutter test` against the pure JSON<->JSON adapter layer.

import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/finances/_spike/payout_flow_adapter.dart';
import 'package:tts_bandmate/features/finances/_spike/spike_seed.dart';

/// Compares the logic contract of two TTS flows, ignoring node/edge ordering and
/// all layout fields. Returns null on match or a human-readable diff.
String? _logicDiff(Map<String, dynamic> a, Map<String, dynamic> b) {
  Map<String, Map<String, dynamic>> nodeLogic(Map<String, dynamic> f) => {
        for (final n in (f['nodes'] as List).cast<Map<String, dynamic>>())
          n['id'] as String: {'type': n['type'], 'data': n['data']},
      };
  Set<String> edgeLogic(Map<String, dynamic> f) => {
        for (final e in (f['edges'] as List).cast<Map<String, dynamic>>())
          '${e['source']}->${e['target']}@${e['sourceHandle'] ?? ''}',
      };

  final an = nodeLogic(a), bn = nodeLogic(b);
  if (an.keys.toSet().difference(bn.keys.toSet()).isNotEmpty ||
      bn.keys.toSet().difference(an.keys.toSet()).isNotEmpty) {
    return 'node id sets differ: ${an.keys} vs ${bn.keys}';
  }
  for (final id in an.keys) {
    if (an[id].toString() != bn[id].toString()) {
      return 'node "$id" logic differs:\n  a=${an[id]}\n  b=${bn[id]}';
    }
  }
  final ae = edgeLogic(a), be = edgeLogic(b);
  if (ae.difference(be).isNotEmpty || be.difference(ae).isNotEmpty) {
    return 'edge sets differ:\n  a=$ae\n  b=$be';
  }
  return null;
}

void main() {
  group('PayoutFlowAdapter round-trip (logic contract)', () {
    test('real backend fixture survives TTS -> Vyuh -> TTS', () {
      final vyuh = vyuhJsonFromTts(kFixtureFlow);
      final back = ttsFromVyuhJson(vyuh);

      expect(_logicDiff(kFixtureFlow, back), isNull,
          reason: 'logic contract changed across round-trip');
    });

    test('node data is passed through verbatim (nested config intact)', () {
      final vyuh = vyuhJsonFromTts(kFixtureFlow);
      final payoutA = (vyuh['nodes'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((n) => n['id'] == 'payout-1');

      // The deeply-nested payoutGroup config must be byte-identical.
      expect(payoutA['data'], kFixtureFlow['nodes'][1]['data']);
      expect(payoutA['data']['allMembersConfig']['includeOwners'], isTrue);
      expect(payoutA['data']['incomingAllocationValue'], 50);
    });

    test('conditional true/false branch handles round-trip', () {
      final vyuh = vyuhJsonFromTts(kSeedFlowWithConditional);

      // The conditional must expose exactly the two named output ports.
      final cond = (vyuh['nodes'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((n) => n['id'] == 'conditional-1');
      final outPorts = (cond['ports'] as List)
          .cast<Map<String, dynamic>>()
          .where((p) => p['type'] == 'output')
          .map((p) => p['id'])
          .toSet();
      expect(outPorts, {'true', 'false'});

      // And the branch edges must come back with their handles preserved.
      final back = ttsFromVyuhJson(vyuh);
      final edges = (back['edges'] as List).cast<Map<String, dynamic>>();
      final trueEdge = edges.firstWhere((e) => e['sourceHandle'] == 'true');
      final falseEdge = edges.firstWhere((e) => e['sourceHandle'] == 'false');
      expect(trueEdge['source'], 'conditional-1');
      expect(trueEdge['target'], 'payout-1');
      expect(falseEdge['target'], 'payout-2');
    });

    test('single-output edges omit a (meaningless) handle on the way back', () {
      final back = ttsFromVyuhJson(vyuhJsonFromTts(kFixtureFlow));
      for (final e in (back['edges'] as List).cast<Map<String, dynamic>>()) {
        // income has one output, so no handle should be emitted.
        expect(e.containsKey('sourceHandle'), isFalse);
      }
    });

    test('rejects a flow without exactly one income node', () {
      final bad = {
        'nodes': [
          {'id': 'p1', 'type': 'payoutGroup', 'data': {}},
        ],
        'edges': [],
      };
      expect(() => vyuhJsonFromTts(bad), throwsStateError);
    });
  });
}
