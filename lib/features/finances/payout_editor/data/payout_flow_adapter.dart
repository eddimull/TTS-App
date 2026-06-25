// SPIKE — but this adapter is the one piece worth keeping if the spike succeeds.
//
// Converts between the TTS `flow_diagram` JSON (consumed by
// BandPayoutConfig::calculatePayouts on the backend) and vyuh_node_flow's
// model.
//
// Two layers:
//   1. Pure JSON<->JSON (`vyuhJsonFromTts` / `ttsFromVyuhJson`) — no Flutter or
//      Vyuh imports, so it's unit-testable headlessly. This is the correctness
//      core and what the round-trip test exercises.
//   2. A thin object builder (`nodesFromTts` / `connectionsFromTts` /
//      `ttsFromControllerState`) that produces live Vyuh `Node`/`Connection`
//      objects for the editor and reads them back. Trivial wrappers over layer 1.
//
// Design rationale (see the spec): the TTS column has two contracts. The
// *logic* contract — node `id`/`type`/`data` and edge `source`/`target` — must
// survive a round-trip exactly. The *layout* contract — positions, port
// geometry, edge styling — is owned by the mobile editor and regenerated freely.

import 'dart:ui' show Offset, Size;

import 'package:vyuh_node_flow/nodes.dart';
import 'package:vyuh_node_flow/ports.dart';
import 'package:vyuh_node_flow/connections.dart';

/// Static description of a node type's ports. The TTS flow JSON does not carry
/// port geometry; we synthesize it here from the node `type`. Port ids match the
/// handle-id conventions the Vue editor uses, so edges that *do* carry handles
/// (e.g. a conditional's true/false branches) map straight through.
class _PortSpec {
  const _PortSpec(this.id, this.position, this.type, {this.fraction = 0.5});
  final String id;
  final PortPosition position;
  final PortType type;

  /// Vertical placement on the node edge, 0..1 (used for multi-output nodes).
  final double fraction;
}

/// Default node box size used when synthesizing layout for Vyuh.
const Size _kNodeSize = Size(180, 96);

/// Per-type port tables. Input ports on the left, outputs on the right.
/// `conditional` has two outputs named exactly 'true' / 'false' (the backend +
/// Vue handle convention), proving Vyuh's multi-named-port wiring on-device.
const Map<String, List<_PortSpec>> _kPortTable = {
  'income': [
    _PortSpec('income-out', PortPosition.right, PortType.output),
  ],
  'bandCut': [
    _PortSpec('bandcut-in', PortPosition.left, PortType.input),
    _PortSpec('bandcut-out', PortPosition.right, PortType.output),
  ],
  'conditional': [
    _PortSpec('conditional-in', PortPosition.left, PortType.input),
    _PortSpec('true', PortPosition.right, PortType.output, fraction: 0.33),
    _PortSpec('false', PortPosition.right, PortType.output, fraction: 0.66),
  ],
  'payoutGroup': [
    _PortSpec('payoutgroup-in', PortPosition.left, PortType.input),
    _PortSpec('payoutgroup-out', PortPosition.right, PortType.output),
  ],
};

/// The single output port id for a node type (used when a TTS edge omits its
/// `sourceHandle`, as the real fixture does). Throws for `conditional`, which is
/// ambiguous and must always carry an explicit handle.
String _defaultOutputPort(String type) {
  final outs = (_kPortTable[type] ?? const [])
      .where((p) => p.type == PortType.output)
      .toList();
  if (outs.length != 1) {
    throw StateError(
      "Node type '$type' has ${outs.length} output ports; "
      'edges from it must specify a sourceHandle.',
    );
  }
  return outs.first.id;
}

/// The single input port id for a node type (TTS edges rarely set targetHandle).
String _defaultInputPort(String type) {
  final ins = (_kPortTable[type] ?? const [])
      .where((p) => p.type == PortType.input)
      .toList();
  if (ins.length != 1) {
    throw StateError(
      "Node type '$type' has ${ins.length} input ports; "
      'edges into it must specify a targetHandle.',
    );
  }
  return ins.first.id;
}

// ─── Layer 1: pure JSON <-> JSON ────────────────────────────────────────────

/// TTS `flow_diagram` JSON -> Vyuh `NodeGraph` JSON.
///
/// - Node `data` is passed through verbatim (Vyuh treats it as opaque).
/// - `position.{x,y}` is flattened to top-level `x`/`y`; missing positions are
///   laid out left-to-right so the seed is at least usable.
/// - `ports` are synthesized from [_kPortTable].
Map<String, dynamic> vyuhJsonFromTts(Map<String, dynamic> tts) {
  _validateTtsLogic(tts);
  final ttsNodes = (tts['nodes'] as List).cast<Map<String, dynamic>>();
  final ttsEdges = (tts['edges'] as List? ?? const [])
      .cast<Map<String, dynamic>>();

  final nodes = <Map<String, dynamic>>[];
  for (var i = 0; i < ttsNodes.length; i++) {
    final n = ttsNodes[i];
    final type = n['type'] as String;
    final pos = n['position'] as Map<String, dynamic>?;
    final x = (pos?['x'] as num?)?.toDouble() ?? (40.0 + i * 240.0);
    final y = (pos?['y'] as num?)?.toDouble() ?? 200.0;

    nodes.add({
      'id': n['id'],
      'type': type,
      'x': x,
      'y': y,
      'width': _kNodeSize.width,
      'height': _kNodeSize.height,
      'data': n['data'], // verbatim passthrough
      'ports': _portsJsonFor(type),
    });
  }

  final connections = <Map<String, dynamic>>[];
  for (var i = 0; i < ttsEdges.length; i++) {
    final e = ttsEdges[i];
    final source = e['source'] as String;
    final target = e['target'] as String;
    connections.add({
      'id': e['id'] as String? ?? 'edge-$i-$source-$target',
      'sourceNodeId': source,
      'sourcePortId': e['sourceHandle'] as String? ??
          _defaultOutputPort(_typeOf(ttsNodes, source)),
      'targetNodeId': target,
      'targetPortId': e['targetHandle'] as String? ??
          _defaultInputPort(_typeOf(ttsNodes, target)),
    });
  }

  return {
    'nodes': nodes,
    'connections': connections,
    'viewport': {'x': 0.0, 'y': 0.0, 'zoom': 1.0},
    'metadata': {'ttsVersion': tts['version'] ?? '1.0'},
  };
}

/// Vyuh `NodeGraph` JSON -> TTS `flow_diagram` JSON.
///
/// Emits only the logic contract the backend consumes: nodes as
/// `{id, type, data}` and edges as `{source, target, sourceHandle?}`. Layout
/// (x/y/ports/width/height) is intentionally dropped — the backend ignores it.
/// `sourceHandle` is preserved only when it carries meaning (conditional
/// branches); default single-output handles are omitted to match the fixture.
Map<String, dynamic> ttsFromVyuhJson(Map<String, dynamic> vyuh) {
  final vNodes = (vyuh['nodes'] as List).cast<Map<String, dynamic>>();
  final vConns = (vyuh['connections'] as List? ?? const [])
      .cast<Map<String, dynamic>>();

  final nodes = vNodes
      .map((n) => {
            'id': n['id'],
            'type': n['type'],
            'data': n['data'],
          })
      .toList();

  final edges = vConns.map((c) {
    final sourceType = _typeOf(vNodes, c['sourceNodeId'] as String);
    final edge = <String, dynamic>{
      'source': c['sourceNodeId'],
      'target': c['targetNodeId'],
    };
    // Keep the handle only when the source has multiple outputs (it's
    // semantically required, e.g. conditional true/false).
    final outs = (_kPortTable[sourceType] ?? const [])
        .where((p) => p.type == PortType.output)
        .length;
    if (outs > 1) {
      edge['sourceHandle'] = c['sourcePortId'];
    }
    return edge;
  }).toList();

  return {'nodes': nodes, 'edges': edges, 'version': '1.0'};
}

List<Map<String, dynamic>> _portsJsonFor(String type) {
  final specs = _kPortTable[type] ?? const [];
  return specs
      .map((p) => {
            'id': p.id,
            'name': p.id,
            'type': p.type.name,
            'position': p.position.name,
            // vyuh convention (see the package's own examples): offset.x is a
            // tiny nudge just past the node edge (negative on the left, positive
            // on the right), and offset.y is an absolute pixel position within
            // the node height. Using absolute box coordinates here mis-sizes the
            // node's interactive bounds and silently breaks node dragging.
            'offset': {
              'x': p.position == PortPosition.left ? -2.0 : 2.0,
              'y': _kNodeSize.height * p.fraction,
            },
          })
      .toList();
}

String _typeOf(List<Map<String, dynamic>> nodes, String id) {
  for (final n in nodes) {
    if (n['id'] == id) return n['type'] as String;
  }
  throw StateError("Edge references unknown node id '$id'.");
}

/// Enforces the backend's structural rules so the spike fails loudly on bad
/// input rather than producing a silently-wrong graph.
void _validateTtsLogic(Map<String, dynamic> tts) {
  final nodes = (tts['nodes'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
  final incomeCount = nodes.where((n) => n['type'] == 'income').length;
  if (incomeCount != 1) {
    throw StateError('Flow must have exactly one income node, found $incomeCount.');
  }
}

// ─── Layer 2: live Vyuh objects (thin wrappers over layer 1) ─────────────────

/// Builds Vyuh [Node]s from TTS flow JSON for feeding a NodeFlowController.
List<Node<Map<String, dynamic>>> nodesFromTts(Map<String, dynamic> tts) {
  final graph = vyuhJsonFromTts(tts);
  return (graph['nodes'] as List).cast<Map<String, dynamic>>().map((n) {
    return Node<Map<String, dynamic>>(
      id: n['id'] as String,
      type: n['type'] as String,
      position: Offset(n['x'] as double, n['y'] as double),
      size: Size(n['width'] as double, n['height'] as double),
      data: Map<String, dynamic>.from(n['data'] as Map),
      ports: (n['ports'] as List).cast<Map<String, dynamic>>().map(_portFromJson).toList(),
    );
  }).toList();
}

/// Builds Vyuh [Connection]s from TTS flow JSON.
List<Connection<dynamic>> connectionsFromTts(Map<String, dynamic> tts) {
  final graph = vyuhJsonFromTts(tts);
  return (graph['connections'] as List).cast<Map<String, dynamic>>().map((c) {
    return Connection<dynamic>(
      id: c['id'] as String,
      sourceNodeId: c['sourceNodeId'] as String,
      sourcePortId: c['sourcePortId'] as String,
      targetNodeId: c['targetNodeId'] as String,
      targetPortId: c['targetPortId'] as String,
    );
  }).toList();
}

/// Reads live controller state (nodes + connections) back into TTS flow JSON,
/// MERGED onto [original] so web-only fields (positions, dimensions,
/// handleBounds, edge coordinates, embedded node snapshots, runtime data) are
/// preserved. The web editor depends on those; emitting a stripped flow breaks
/// the web canvas. Mobile only owns: node `data` edits, node positions, and the
/// set of nodes/edges (adds/removes).
Map<String, dynamic> ttsFromControllerState(
  Iterable<Node<Map<String, dynamic>>> nodes,
  Iterable<Connection<dynamic>> connections,
  Map<String, dynamic> original,
) {
  final origNodes = (original['nodes'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
  final origEdges = (original['edges'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
  final origNodeById = {for (final n in origNodes) n['id'] as String: n};

  // ── Nodes: preserve each original, overlay live data + position ──────────
  final outNodes = <Map<String, dynamic>>[];
  for (final n in nodes) {
    final orig = origNodeById[n.id];
    final pos = {'x': n.position.value.dx, 'y': n.position.value.dy};
    if (orig != null) {
      // Start from the full original; overlay only what mobile changed.
      final merged = Map<String, dynamic>.from(orig);
      merged['data'] = n.data; // mobile's config-form edits win
      merged['position'] = pos;
      if (merged.containsKey('computedPosition')) {
        merged['computedPosition'] = {...pos, 'z': 0};
      }
      outNodes.add(merged);
    } else {
      // Mobile-added node: minimal shape; the web editor backfills the rest.
      outNodes.add({'id': n.id, 'type': n.type, 'data': n.data, 'position': pos});
    }
  }

  // ── Edges: preserve originals that still exist; add minimal new ones ──────
  // Match by source+target+sourcePortId. Compare against the original's stored
  // sourceHandle directly (NOT our "omit single-output handle" logic — the web
  // stores a handle like "income-out" even for single-output nodes, so dropping
  // it here would miss the match and strip the rich edge).
  String edgeKey(String s, String t, String? h) => '$s|$t|${h ?? ''}';
  final origByExactKey = <String, Map<String, dynamic>>{};
  final origByPair = <String, Map<String, dynamic>>{};
  for (final e in origEdges) {
    final s = e['source'] as String, t = e['target'] as String;
    origByExactKey[edgeKey(s, t, e['sourceHandle'] as String?)] = e;
    origByPair['$s|$t'] = e; // fallback when handles differ in representation
  }

  final liveNodeType = {for (final n in nodes) n.id: n.type};
  final outEdges = <Map<String, dynamic>>[];
  for (final c in connections) {
    final type = liveNodeType[c.sourceNodeId];
    final outs = (_kPortTable[type] ?? const [])
        .where((p) => p.type == PortType.output)
        .length;
    // For multi-output sources (conditional true/false) the handle is needed to
    // disambiguate; otherwise source+target identifies the edge.
    final orig = origByExactKey[
            edgeKey(c.sourceNodeId, c.targetNodeId, c.sourcePortId)] ??
        (outs > 1 ? null : origByPair['${c.sourceNodeId}|${c.targetNodeId}']);
    if (orig != null) {
      outEdges.add(orig); // preserve the web's rich edge verbatim
    } else {
      final e = <String, dynamic>{'source': c.sourceNodeId, 'target': c.targetNodeId};
      if (outs > 1) e['sourceHandle'] = c.sourcePortId;
      outEdges.add(e);
    }
  }

  return {
    'nodes': outNodes,
    'edges': outEdges,
    'version': original['version'] ?? '1.0',
  };
}

Port _portFromJson(Map<String, dynamic> j) {
  return Port(
    id: j['id'] as String,
    name: j['name'] as String,
    type: PortType.values.byName(j['type'] as String),
    position: PortPosition.values.byName(j['position'] as String),
    offset: Offset(
      (j['offset']['x'] as num).toDouble(),
      (j['offset']['y'] as num).toDouble(),
    ),
  );
}
