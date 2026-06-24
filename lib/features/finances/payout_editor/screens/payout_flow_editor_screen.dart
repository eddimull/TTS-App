// Payout flow editor screen. Loads a band's payout config, renders its
// flow_diagram on the vyuh_node_flow canvas, and (for owners) saves edits back
// via the mobile API. Non-owners get a navigable read-only view.
//
// Interactions (owner/edit mode):
//   • LONG-PRESS a node, then drag to move it
//   • DOUBLE-TAP a node to configure it
//   • TAP a connection line to delete it; DRAG from a port to create one
//
// Gesture note: vyuh_node_flow 0.27.3 has a known mobile bug where a single
// finger on a node is claimed by the canvas InteractiveViewer for panning
// instead of dragging the node (upstream issue #24 / PR #31). Rather than fight
// the gesture arena, this screen adds a LONG-PRESS-TO-MOVE overlay: a normal
// one-finger drag pans the canvas (the library's default); a long-press grabs
// the node under your finger and repositions it via controller.moveNode().
// Configure opens on DOUBLE-tap because the editor fires single-tap on
// pointer-down, which would pre-empt the long-press.

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tts_bandmate/shared/widgets/error_view.dart';
import 'package:vyuh_node_flow/connections.dart';
import 'package:vyuh_node_flow/controller.dart';
import 'package:vyuh_node_flow/editor.dart';
import 'package:vyuh_node_flow/nodes.dart';
import 'package:vyuh_node_flow/themes.dart';

import '../config/node_config_form.dart';
import '../data/payout_flow_adapter.dart';
import '../data/payout_flow_repository.dart';
import '../providers/payout_flow_provider.dart';

/// Loads a band's payout config and hosts the flow editor. Editing/saving is
/// gated to band owners (the backend PATCH is owner-only); others get a
/// read-only view.
class PayoutFlowEditorScreen extends ConsumerWidget {
  const PayoutFlowEditorScreen({
    super.key,
    required this.bandId,
    required this.configId,
  });

  final int bandId;
  final int configId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configAsync = ref.watch(
      payoutConfigProvider(PayoutConfigRef(bandId: bandId, configId: configId)),
    );
    final isOwner = ref.watch(isSelectedBandOwnerProvider);

    return configAsync.when(
      loading: () => const CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(middle: Text('Payout Flow')),
        child: Center(child: CupertinoActivityIndicator()),
      ),
      error: (e, _) => CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(middle: Text('Payout Flow')),
        child: ErrorView(
          message: ErrorView.friendlyMessage(e),
          onRetry: () => ref.invalidate(payoutConfigProvider(
              PayoutConfigRef(bandId: bandId, configId: configId))),
        ),
      ),
      data: (config) => _EditorBody(
        bandId: bandId,
        config: config,
        readOnly: !isOwner,
      ),
    );
  }
}

class _EditorBody extends ConsumerStatefulWidget {
  const _EditorBody({
    required this.bandId,
    required this.config,
    required this.readOnly,
  });

  final int bandId;
  final PayoutConfigDetail config;
  final bool readOnly;

  @override
  ConsumerState<_EditorBody> createState() => _EditorBodyState();
}

class _EditorBodyState extends ConsumerState<_EditorBody> {
  late final NodeFlowController<Map<String, dynamic>, dynamic> _controller;
  bool _saving = false;

  /// Id of the node currently grabbed via long-press, or null.
  String? _grabbedNodeId;

  /// Cumulative long-press offset at the previous move update, for computing
  /// the per-frame screen delta (LongPressMoveUpdateDetails gives cumulative
  /// offsetFromOrigin, not an incremental delta).
  Offset _lastLongPressOffset = Offset.zero;

  @override
  void initState() {
    super.initState();
    final flow = widget.config.flowDiagram;
    _controller = NodeFlowController<Map<String, dynamic>, dynamic>(
      nodes: nodesFromTts(flow),
      connections: connectionsFromTts(flow),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final flow = ttsFromControllerState(
      _controller.nodes.values,
      _controller.connections,
    );
    try {
      await ref.read(payoutFlowRepositoryProvider).updateFlow(
            widget.bandId,
            widget.config.id,
            flow,
          );
      // Refresh the configs list so any name/active changes surface.
      ref.invalidate(payoutConfigsProvider(widget.bandId));
      if (mounted) {
        await _alert('Saved', 'Payout flow saved.');
      }
    } catch (e) {
      if (mounted) {
        await _alert('Save failed', ErrorView.friendlyMessage(e));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _alert(String title, String message) {
    return showCupertinoDialog<void>(
      context: context,
      builder: (dlg) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(dlg),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ── Configure node (double tap) ──────────────────────────────────────────

  /// Pushes the full-fidelity NodeConfigForm (keepable widget) for this node.
  void _openConfigSheet(Node<Map<String, dynamic>> node) {
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => NodeConfigForm(
          nodeType: node.type,
          data: node.data,
          onChanged: () => _repaintNode(node),
          onDelete: () => _confirmDeleteNode(node),
        ),
      ),
    );
  }

  /// node.data is a plain (non-observable) map, so the editor's Observer won't
  /// repaint on its own after an edit. Toggle `selected` — which _buildNode
  /// reads — to force the node widget to rebuild and pick up the new values.
  void _repaintNode(Node<Map<String, dynamic>> node) {
    node.isSelected = !node.selected.value;
    node.isSelected = false;
    if (mounted) setState(() {});
  }

  // ── Delete (tap edge to delete; delete node from config sheet) ────────────

  void _confirmDeleteConnection(Connection<dynamic> connection) {
    showCupertinoDialog<void>(
      context: context,
      builder: (dlg) => CupertinoAlertDialog(
        title: const Text('Delete connection?'),
        content: Text(
          '${connection.sourceNodeId} → ${connection.targetNodeId}',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(dlg),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () {
              // removeConnection throws if already gone — guard against it.
              if (_controller.connections.any((c) => c.id == connection.id)) {
                _controller.removeConnection(connection.id);
              }
              Navigator.pop(dlg);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteNode(Node<Map<String, dynamic>> node) {
    showCupertinoDialog<void>(
      context: context,
      builder: (dlg) => CupertinoAlertDialog(
        title: const Text('Delete node?'),
        content: Text('${node.data['label'] ?? node.type} and its connections'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(dlg),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () {
              if (_controller.nodes.containsKey(node.id)) {
                _controller.removeNode(node.id);
              }
              Navigator.pop(dlg);
            },
            child: const Text('Delete'),
          ),
        ],
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
    final readOnly = widget.readOnly;
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(widget.config.name),
        trailing: readOnly
            ? const Text('View only',
                style: TextStyle(fontSize: 14, color: CupertinoColors.systemGrey))
            : CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const CupertinoActivityIndicator()
                    : const Text('Save'),
              ),
      ),
      child: SafeArea(
        child: Stack(
          children: [
            NodeFlowEditor<Map<String, dynamic>, dynamic>(
              controller: _controller,
              theme: NodeFlowTheme.light,
              // Owners can edit; everyone else gets a navigable read-only view.
              behavior:
                  readOnly ? NodeFlowBehavior.inspect : NodeFlowBehavior.design,
              nodeBuilder: _buildNode,
              events: readOnly
                  ? null
                  : NodeFlowEvents<Map<String, dynamic>, dynamic>(
                      // DOUBLE-tap (not single) opens configure. The editor fires
                      // NodeEvents.onTap from Listener.onPointerDown (instant, on
                      // the first touch), so single-tap-to-configure would
                      // pre-empt our long-press-to-move. onDoubleTap fires from a
                      // real DoubleTapGestureRecognizer that won't trip on a long
                      // hold, so the two gestures coexist cleanly: double-tap =
                      // configure, long-press = move.
                      node: NodeEvents<Map<String, dynamic>>(
                        onDoubleTap: _openConfigSheet,
                      ),
                      // Single tap on a connection → confirm + delete.
                      connection:
                          ConnectionEvents<Map<String, dynamic>, dynamic>(
                        onTap: _confirmDeleteConnection,
                      ),
                    ),
            ),
            // Transparent overlay that ONLY claims the long-press gesture (used
            // for node moves). Disabled in read-only mode.
            //
            // RawGestureDetector (not GestureDetector) so we can shorten the
            // hold duration to ~200ms — snappy enough to feel synced with the
            // lift animation, with enough margin that quick taps/pans don't
            // accidentally grab a node.
            if (!readOnly)
              Positioned.fill(
                child: RawGestureDetector(
                  behavior: HitTestBehavior.translucent,
                  gestures: {
                    LongPressGestureRecognizer:
                        GestureRecognizerFactoryWithHandlers<
                            LongPressGestureRecognizer>(
                      () => LongPressGestureRecognizer(
                        duration: const Duration(milliseconds: 200),
                      ),
                      (r) => r
                        ..onLongPressStart = _onLongPressStart
                        ..onLongPressMoveUpdate = _onLongPressMove
                        ..onLongPressEnd = _onLongPressEnd,
                    ),
                  },
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
        return _FlowNode(
          title: 'Income',
          color: const Color(0xFF2E7D32),
          subtitle: '\$${node.data['amount']}',
          grabbed: grabbed,
        );
      case 'conditional':
        return _FlowNode(
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
        return _FlowNode(
          title: node.data['label']?.toString() ?? 'Payout',
          color: const Color(0xFF1565C0),
          subtitle: '$pct% · $mode',
          grabbed: grabbed,
        );
      default:
        return _FlowNode(
          title: node.type,
          color: CupertinoColors.systemGrey,
          grabbed: grabbed,
        );
    }
  }
}

class _FlowNode extends StatelessWidget {
  const _FlowNode({
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
