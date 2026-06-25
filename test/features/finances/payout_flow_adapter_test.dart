// SPIKE — the correctness gate for the vyuh_node_flow payout-editor spike.
//
// Proves the LOGIC CONTRACT survives a round-trip TTS -> Vyuh -> TTS:
//   - every node's id / type / data is preserved exactly
//   - every edge's source / target (and meaningful sourceHandle) is preserved
// Layout (positions, ports, sizing) is regenerated and intentionally NOT asserted.
//
// Runs headless via `flutter test` against the pure JSON<->JSON adapter layer.

import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/finances/payout_editor/data/payout_flow_adapter.dart';
import 'package:tts_bandmate/features/finances/payout_editor/data/payout_flow_sample.dart';

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
  TestWidgetsFlutterBinding.ensureInitialized();

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

    test('port offsets follow vyuh convention (edge-relative x, absolute y)', () {
      // Per the library's own examples, offset.x is a tiny nudge past the node
      // edge (~-2 left / ~+2 right), NOT an absolute box coordinate, and
      // offset.y is an absolute pixel position within the node height. Getting
      // this wrong flings the port (and the node's interactive bounds) far off
      // the visible body, so node drag silently fails while the canvas still pans.
      const nodeHeight = 200.0;
      final vyuh = vyuhJsonFromTts(kSeedFlowWithConditional);
      final cond = (vyuh['nodes'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((n) => n['id'] == 'conditional-1');

      for (final p in (cond['ports'] as List).cast<Map<String, dynamic>>()) {
        final ox = (p['offset']['x'] as num).abs();
        final oy = p['offset']['y'] as num;
        expect(ox, lessThan(10),
            reason: 'port ${p['id']} offset.x must be a small edge nudge, got ${p['offset']['x']}');
        expect(oy, inInclusiveRange(0, nodeHeight),
            reason: 'port ${p['id']} offset.y must be within node height, got $oy');
      }

      // The two conditional outputs must be at distinct vertical positions.
      final outs = (cond['ports'] as List)
          .cast<Map<String, dynamic>>()
          .where((p) => p['type'] == 'output')
          .toList();
      expect(outs[0]['offset']['y'], isNot(outs[1]['offset']['y']));
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

  group('ttsFromControllerState merge (preserve web-only fields)', () {
    // An original flow carrying web-only presentation/runtime fields the web
    // editor depends on — these must survive a mobile save.
    final original = {
      'nodes': [
        {
          'id': 'income-1',
          'type': 'income',
          'data': {'amount': 1000, 'label': 'Income'},
          'position': {'x': 40.0, 'y': 200.0},
          'dimensions': {'width': 238, 'height': 183},
          'handleBounds': {'source': [], 'target': null},
          'computedPosition': {'x': 40.0, 'y': 200.0, 'z': 0},
          'selected': false,
        },
        {
          'id': 'payout-1',
          'type': 'payoutGroup',
          'data': {
            'label': 'Group A',
            'sourceType': 'allMembers',
            'allMembersConfig': {'includeOwners': true},
            'incomingAllocationType': 'remainder',
            'distributionMode': 'equal_split',
          },
          'position': {'x': 400.0, 'y': 200.0},
          'dimensions': {'width': 220, 'height': 400},
        },
      ],
      'edges': [
        {
          'source': 'income-1',
          'target': 'payout-1',
          // Web stores a handle even for single-output nodes — the merge must
          // still match this edge and preserve its rich fields.
          'sourceHandle': 'income-out',
          'targetHandle': 'payoutgroup-in',
          'sourceX': 285.0,
          'sourceY': 760.0,
          'sourceNode': {'id': 'income-1'},
          'animated': false,
        },
      ],
      'version': '1.0',
    };

    test('untouched nodes keep web-only fields; edited data is applied', () {
      // Build live state from the original, then simulate a config-form edit:
      // change the payout group's label.
      final nodes = nodesFromTts(original);
      final conns = connectionsFromTts(original);
      nodes.firstWhere((n) => n.id == 'payout-1').data['label'] = 'Renamed';

      final back = ttsFromControllerState(nodes, conns, original);
      final backNodes =
          (back['nodes'] as List).cast<Map<String, dynamic>>();

      final income = backNodes.firstWhere((n) => n['id'] == 'income-1');
      // Web-only fields preserved verbatim.
      expect(income['dimensions'], {'width': 238, 'height': 183});
      expect(income['handleBounds'], isNotNull);
      expect(income.containsKey('computedPosition'), isTrue);

      // The edit applied.
      final payout = backNodes.firstWhere((n) => n['id'] == 'payout-1');
      expect(payout['data']['label'], 'Renamed');
      // And ITS web-only field survived too.
      expect(payout['dimensions'], {'width': 220, 'height': 400});
    });

    test('edges preserve their web-only fields', () {
      final nodes = nodesFromTts(original);
      final conns = connectionsFromTts(original);

      final back = ttsFromControllerState(nodes, conns, original);
      final edge = (back['edges'] as List).cast<Map<String, dynamic>>().single;

      expect(edge['source'], 'income-1');
      expect(edge['target'], 'payout-1');
      // Rich web edge fields carried through.
      expect(edge['sourceX'], 285.0);
      expect(edge['sourceNode'], {'id': 'income-1'});
    });
  });
}
