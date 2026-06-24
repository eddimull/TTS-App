// SPIKE — throwaway. A bare NodeFlowEditor wired to the seed via the adapter,
// for assessing touch feel on a physical device. Not routed into app nav.
//
// On-device checklist this screen supports:
//   1. LONG-PRESS a node, then drag to move it (see gesture note below)
//   2. wire ports — especially the conditional's `true` / `false` outputs
//   3. tap "Dump TTS JSON" to confirm the reverse adapter produces backend-valid
//      flow JSON from whatever you've drawn (printed to the console + a sheet).
//
// Gesture note: vyuh_node_flow 0.27.3 has a known mobile bug where a single
// finger on a node is claimed by the canvas InteractiveViewer for panning
// instead of dragging the node (upstream issue #24 / PR #31). Rather than fight
// the gesture arena, this screen adds a LONG-PRESS-TO-MOVE overlay: a normal
// one-finger drag pans the canvas (the library's default); a long-press grabs
// the node under your finger and subsequent movement repositions it via
// controller.moveNode(). Ports/taps still fall through to the editor.

import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:vyuh_node_flow/controller.dart';
import 'package:vyuh_node_flow/editor.dart';
import 'package:vyuh_node_flow/nodes.dart';
import 'package:vyuh_node_flow/themes.dart';

import 'payout_flow_adapter.dart';
import 'spike_seed.dart';

class PayoutFlowSpikeScreen extends StatefulWidget {
  const PayoutFlowSpikeScreen({super.key});

  @override
  State<PayoutFlowSpikeScreen> createState() => _PayoutFlowSpikeScreenState();
}

class _PayoutFlowSpikeScreenState extends State<PayoutFlowSpikeScreen> {
  late final NodeFlowController<Map<String, dynamic>, dynamic> _controller;

  /// Id of the node currently grabbed via long-press, or null.
  String? _grabbedNodeId;

  /// Cumulative long-press offset at the previous move update, for computing
  /// the per-frame screen delta (LongPressMoveUpdateDetails gives cumulative
  /// offsetFromOrigin, not an incremental delta).
  Offset _lastLongPressOffset = Offset.zero;

  @override
  void initState() {
    super.initState();
    _controller = NodeFlowController<Map<String, dynamic>, dynamic>(
      nodes: nodesFromTts(kSeedFlowWithConditional),
      connections: connectionsFromTts(kSeedFlowWithConditional),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _dumpJson() {
    final tts = ttsFromControllerState(
      _controller.nodes.values,
      _controller.connections,
    );
    final pretty = const JsonEncoder.withIndent('  ').convert(tts);
    debugPrint('=== TTS flow_diagram from live graph ===\n$pretty');
    showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: const Text('TTS flow_diagram (reverse adapter)'),
        message: SizedBox(
          height: 360,
          child: SingleChildScrollView(
            child: Text(
              pretty,
              style: const TextStyle(fontFamily: 'Menlo', fontSize: 11),
            ),
          ),
        ),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ),
    );
  }

  // ── Long-press-to-move gesture handling ──────────────────────────────────

  /// Converts a screen-local point to graph coordinates using the live
  /// viewport. Transform: graph = (screen - pan) / zoom.
  Offset _toGraph(Offset screenLocal) {
    final v = _controller.viewport;
    return Offset((screenLocal.dx - v.x) / v.zoom, (screenLocal.dy - v.y) / v.zoom);
  }

  /// Top-most node (highest zIndex) whose bounds contain the graph point.
  Node<Map<String, dynamic>>? _nodeAtGraph(Offset graphPoint) {
    Node<Map<String, dynamic>>? best;
    for (final node in _controller.nodes.values) {
      if (node.containsPoint(graphPoint)) {
        if (best == null || node.zIndex.value >= best.zIndex.value) {
          best = node;
        }
      }
    }
    return best;
  }

  void _onLongPressStart(LongPressStartDetails d) {
    final node = _nodeAtGraph(_toGraph(d.localPosition));
    if (node != null) {
      _lastLongPressOffset = Offset.zero;
      // Drive the on-node cue via `selected` — an observable the editor's own
      // Observer watches, so the node repaints with the lift styling. (A plain
      // setState here would repaint the overlay pill but not the cached node
      // widget.)
      node.isSelected = true;
      setState(() => _grabbedNodeId = node.id);
    }
  }

  void _onLongPressMove(LongPressMoveUpdateDetails d) {
    final id = _grabbedNodeId;
    if (id == null) return;
    // offsetFromOrigin is cumulative; take the per-frame screen delta and
    // convert to a graph delta by dividing by zoom.
    final screenDelta = d.offsetFromOrigin - _lastLongPressOffset;
    _lastLongPressOffset = d.offsetFromOrigin;
    _controller.moveNode(id, screenDelta / _controller.viewport.zoom);
  }

  void _onLongPressEnd(LongPressEndDetails d) {
    final id = _grabbedNodeId;
    if (id != null) {
      _controller.nodes[id]?.isSelected = false;
      setState(() => _grabbedNodeId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Payout Flow Spike'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _dumpJson,
          child: const Text('Dump JSON'),
        ),
      ),
      child: SafeArea(
        child: Stack(
          children: [
            NodeFlowEditor<Map<String, dynamic>, dynamic>(
              controller: _controller,
              theme: NodeFlowTheme.light,
              behavior: NodeFlowBehavior.design,
              nodeBuilder: _buildNode,
            ),
            // Transparent overlay that ONLY claims the long-press gesture.
            // Taps and one-finger drags fall through to the editor (canvas pan,
            // port wiring); a long-press grabs the node under the finger.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onLongPressStart: _onLongPressStart,
                onLongPressMoveUpdate: _onLongPressMove,
                onLongPressEnd: _onLongPressEnd,
              ),
            ),
            if (_grabbedNodeId != null)
              const Positioned(
                left: 0,
                right: 0,
                bottom: 12,
                child: IgnorePointer(
                  child: Center(
                    child: _GrabPill(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNode(BuildContext context, Node<Map<String, dynamic>> node) {
    // Read the observable so the editor's Observer repaints this node when it's
    // grabbed (selection is our grab indicator — see _onLongPressStart).
    final grabbed = node.selected.value;
    switch (node.type) {
      case 'income':
        return _SpikeNode(
          title: 'Income',
          color: const Color(0xFF2E7D32),
          subtitle: '\$${node.data['amount']}',
          grabbed: grabbed,
        );
      case 'conditional':
        return _SpikeNode(
          title: 'Condition',
          color: const Color(0xFFB26A00),
          subtitle:
              '${node.data['conditionType']} ${node.data['operator']} ${node.data['value']}',
          footer: 'true / false',
          grabbed: grabbed,
        );
      case 'payoutGroup':
        final mode = node.data['distributionMode'];
        final pct = node.data['incomingAllocationValue'];
        return _SpikeNode(
          title: node.data['label']?.toString() ?? 'Payout',
          color: const Color(0xFF1565C0),
          subtitle: '$pct% · $mode',
          grabbed: grabbed,
        );
      default:
        return _SpikeNode(
          title: node.type,
          color: CupertinoColors.systemGrey,
          grabbed: grabbed,
        );
    }
  }
}

class _SpikeNode extends StatelessWidget {
  const _SpikeNode({
    required this.title,
    required this.color,
    this.subtitle,
    this.footer,
    this.grabbed = false,
  });

  final String title;
  final Color color;
  final String? subtitle;
  final String? footer;

  /// True while this node is grabbed via long-press — show a "lifted" cue.
  final bool grabbed;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: grabbed ? 1.06 : 1.0,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: CupertinoColors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color, width: grabbed ? 3 : 2),
          boxShadow: grabbed
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.45),
                    blurRadius: 16,
                    spreadRadius: 1,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle!,
                  style: const TextStyle(
                      fontSize: 12, color: CupertinoColors.label)),
            ],
            if (footer != null) ...[
              const SizedBox(height: 4),
              Text(footer!,
                  style: const TextStyle(
                      fontSize: 10, color: CupertinoColors.systemGrey)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Transient cue shown while a node is grabbed via long-press.
class _GrabPill extends StatelessWidget {
  const _GrabPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: CupertinoColors.black.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Text(
        'Moving node — drag to reposition',
        style: TextStyle(color: CupertinoColors.white, fontSize: 13),
      ),
    );
  }
}
