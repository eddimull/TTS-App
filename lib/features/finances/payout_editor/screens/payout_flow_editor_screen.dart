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
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tts_bandmate/shared/widgets/error_view.dart';
import 'package:vyuh_node_flow/connections.dart';
import 'package:vyuh_node_flow/controller.dart';
import 'package:vyuh_node_flow/editor.dart';
import 'package:vyuh_node_flow/nodes.dart';
import 'package:vyuh_node_flow/ports.dart';
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

  /// Per-node computed values (input/output/bandCut/allocated/...) from the
  /// preview calc, keyed by node id. Drives each node card's amounts footer.
  Map<String, dynamic> _nodeValues = const {};

  @override
  void initState() {
    super.initState();
    final flow = widget.config.flowDiagram;
    _controller = NodeFlowController<Map<String, dynamic>, dynamic>(
      nodes: nodesFromTts(flow),
      connections: connectionsFromTts(flow),
    );
    _refreshComputedValues();
  }

  /// Run the preview calc and stash per-node values for the cards. Uses the
  /// income node's amount as the test amount (what the flow actually starts
  /// with). Best-effort: failures just leave the amount footer hidden.
  Future<void> _refreshComputedValues() async {
    final flow = ttsFromControllerState(
      _controller.nodes.values,
      _controller.connections,
      widget.config.flowDiagram,
    );
    final income = (flow['nodes'] as List).cast<Map<String, dynamic>>().firstWhere(
          (n) => n['type'] == 'income',
          orElse: () => const {},
        );
    final amount = (income['data']?['amount'] as num?) ?? 0;
    if (amount <= 0) {
      // No valid amount to compute — drop any stale footers.
      if (mounted && _nodeValues.isNotEmpty) {
        setState(() => _nodeValues = const {});
      }
      return;
    }
    try {
      final result = await ref
          .read(payoutFlowRepositoryProvider)
          .preview(widget.bandId, flow, amount);
      if (!mounted) return;
      setState(() {
        _nodeValues =
            (result['node_values'] as Map?)?.cast<String, dynamic>() ?? const {};
      });
    } catch (_) {
      // Preview failed — hide the footer rather than show stale numbers.
      if (mounted) setState(() => _nodeValues = const {});
    }
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
      widget.config.flowDiagram, // merge onto the original to preserve web fields
    );
    try {
      await ref.read(payoutFlowRepositoryProvider).updateFlow(
            widget.bandId,
            widget.config.id,
            flow,
          );
      // Invalidate BOTH the list and THIS config's detail provider — otherwise
      // reopening the editor re-seeds from the cached pre-save flow and the
      // edits appear to revert.
      ref.invalidate(payoutConfigsProvider(widget.bandId));
      ref.invalidate(payoutConfigProvider(
          PayoutConfigRef(bandId: widget.bandId, configId: widget.config.id)));
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

  // ── Add node ───────────────────────────────────────────────────────────────

  static const _addLabels = {
    'income': 'Income',
    'bandCut': 'Band Cut',
    'conditional': 'Condition',
    'payoutGroup': 'Payout Group',
  };

  void _showAddNodeSheet() {
    final hasIncome = _controller.nodes.values.any((n) => n.type == 'income');
    showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetCtx) => CupertinoActionSheet(
        title: const Text('Add node'),
        actions: [
          for (final type in kAddableNodeTypes)
            CupertinoActionSheetAction(
              // Only one income node is allowed (backend rule).
              onPressed: (type == 'income' && hasIncome)
                  ? () {}
                  : () {
                      Navigator.pop(sheetCtx);
                      _addNode(type);
                    },
              child: Text(
                type == 'income' && hasIncome
                    ? 'Income (already added)'
                    : _addLabels[type] ?? type,
                style: TextStyle(
                  color: (type == 'income' && hasIncome)
                      ? CupertinoColors.inactiveGray
                      : null,
                ),
              ),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetCtx),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  void _addNode(String type) {
    // Place the new node near the centre of the current viewport (graph coords).
    final v = _controller.viewport;
    final size = context.size ?? const Size(360, 600);
    final center = Offset(
      (size.width / 2 - v.x) / v.zoom,
      (size.height / 2 - v.y) / v.zoom,
    );
    final id = 'node-${DateTime.now().microsecondsSinceEpoch}';
    _controller.addNode(newNodeForType(type, id, center));
    HapticFeedback.selectionClick();
    setState(() {});
    _refreshComputedValues();
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
          bandId: widget.bandId,
          nodeType: node.type,
          data: node.data,
          previewValues: (_nodeValues[node.id] as Map?)?.cast<String, dynamic>(),
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
    _refreshComputedValues(); // config edits can change the amounts
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
                _refreshComputedValues();
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
                _refreshComputedValues();
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

  /// Graph-space radius (in logical px) around a port within which a press
  /// counts as "on the port" — generous so a thumb reliably hits it.
  static const double _portHitRadius = 34.0;

  /// Default port widget size (theme default is 12x12).
  static const Size _portSize = Size(12, 12);

  /// The port's true visual center in graph coordinates. Uses the library's
  /// own geometry (visualPosition + visual port origin), NOT position+offset —
  /// `port.offset` is a small edge nudge, so naive math puts right-side output
  /// ports a full node-width away and they never hit-test.
  Offset _portCenter(Node<Map<String, dynamic>> node, Port port) {
    return node.getPortCenter(port.id, portSize: port.size ?? _portSize);
  }

  /// A port hit result: enough to start a connection drag.
  ({String nodeId, String portId, bool isOutput, Offset center, Rect bounds})?
      _portAtGraph(Offset graphPoint) {
    ({String nodeId, String portId, bool isOutput, Offset center, Rect bounds})?
        best;
    double bestDist = _portHitRadius;
    for (final node in _controller.nodes.values) {
      for (final port in node.ports) {
        final center = _portCenter(node, port);
        final dist = (graphPoint - center).distance;
        if (dist <= bestDist) {
          bestDist = dist;
          best = (
            nodeId: node.id,
            portId: port.id,
            isOutput: port.type == PortType.output,
            center: center,
            bounds: node.getBounds(),
          );
        }
      }
    }
    return best;
  }

  /// While dragging a connection: the source port's id + direction, so we can
  /// find a valid (opposite-direction) target. Null when not connecting.
  ({String nodeId, String portId, bool isOutput})? _connectSource;
  bool get _connecting => _connectSource != null;

  /// Whether a valid target was under the finger at the last move (for the
  /// hover haptic — fire once on entering a valid target, not every frame).
  bool _hadValidTarget = false;

  /// Find a port that is a VALID connection target for the current source:
  /// opposite direction, different node. Forgiving radius so near-misses count.
  ({String nodeId, String portId, Offset center, Rect bounds})?
      _targetPortFor(Offset graphPoint) {
    final src = _connectSource;
    if (src == null) return null;
    ({String nodeId, String portId, Offset center, Rect bounds})? best;
    double bestDist = _portHitRadius;
    for (final node in _controller.nodes.values) {
      if (node.id == src.nodeId) continue; // no same-node
      for (final port in node.ports) {
        // Output source → input target, and vice versa.
        final isOutput = port.type == PortType.output;
        if (isOutput == src.isOutput) continue;
        final center = _portCenter(node, port);
        final dist = (graphPoint - center).distance;
        if (dist <= bestDist) {
          bestDist = dist;
          best = (nodeId: node.id, portId: port.id, center: center, bounds: node.getBounds());
        }
      }
    }
    return best;
  }

  void _onLongPressStart(LongPressStartDetails d) {
    final graph = _toGraph(d.localPosition);

    // Port under the finger → start a connection drag from it.
    final port = _portAtGraph(graph);
    if (port != null) {
      final result = _controller.startConnectionDrag(
        nodeId: port.nodeId,
        portId: port.portId,
        isOutput: port.isOutput,
        startPoint: port.center,
        nodeBounds: port.bounds,
      );
      if (result.allowed) {
        _connectSource =
            (nodeId: port.nodeId, portId: port.portId, isOutput: port.isOutput);
        _hadValidTarget = false;
        // mediumImpact (not selectionClick) so the start is clearly felt — a
        // selectionClick is too faint to distinguish on many devices.
        HapticFeedback.mediumImpact(); // started a connection
        return;
      }
    }

    // Otherwise a node-body press → move that node.
    final node = _nodeAtGraph(graph);
    if (node != null) {
      _lastLongPressOffset = Offset.zero;
      // Drive the on-node cue via `selected` — an observable the editor's own
      // Observer watches, so the node repaints with the lift styling. (A plain
      // setState here would repaint the overlay pill but not the cached node
      // widget.)
      node.isSelected = true;
      HapticFeedback.selectionClick(); // grabbed a node to move
      setState(() => _grabbedNodeId = node.id);
    }
  }

  void _onLongPressMove(LongPressMoveUpdateDetails d) {
    final graph = _toGraph(d.localPosition);

    if (_connecting) {
      // Highlight the valid target port (if any) under the finger.
      final target = _targetPortFor(graph);
      _controller.updateConnectionDrag(
        graphPosition: graph,
        targetNodeId: target?.nodeId,
        targetPortId: target?.portId,
        targetNodeBounds: target?.bounds,
      );
      // Fire the same strong haptic as a completed connect the moment the
      // finger enters a valid target (still down) — so the "this will connect"
      // moment feels identical whether you hold or release.
      final valid = target != null;
      if (valid && !_hadValidTarget) HapticFeedback.mediumImpact();
      _hadValidTarget = valid;
      return;
    }

    final id = _grabbedNodeId;
    if (id == null) return;
    // offsetFromOrigin is cumulative; take the per-frame screen delta and
    // convert to a graph delta by dividing by zoom.
    final screenDelta = d.offsetFromOrigin - _lastLongPressOffset;
    _lastLongPressOffset = d.offsetFromOrigin;
    _controller.moveNode(id, screenDelta / _controller.viewport.zoom);
  }

  /// True if an edge with this exact source/sourcePort/target already exists.
  /// Mirrors the web rule: duplicate connections (same source+target+handle)
  /// are rejected; fan-out to DIFFERENT targets is fine.
  bool _connectionExists(String sourceNodeId, String sourcePortId, String targetNodeId) {
    return _controller.connections.any((c) =>
        c.sourceNodeId == sourceNodeId &&
        c.sourcePortId == sourcePortId &&
        c.targetNodeId == targetNodeId);
  }

  void _onLongPressEnd(LongPressEndDetails d) {
    if (_connecting) {
      // Complete the connection if released over a VALID target port (correct
      // direction, different node) that isn't already connected; otherwise cancel.
      final target = _targetPortFor(_toGraph(d.localPosition));
      final src = _connectSource;
      final isDuplicate = target != null &&
          src != null &&
          _connectionExists(src.nodeId, src.portId, target.nodeId);
      Connection<dynamic>? created;
      if (target != null && !isDuplicate) {
        created = _controller.completeConnectionDrag(
          targetNodeId: target.nodeId,
          targetPortId: target.portId,
        );
      } else {
        _controller.cancelConnectionDrag();
      }
      if (created != null) {
        HapticFeedback.mediumImpact(); // connected!
        _refreshComputedValues(); // new edge changes the amounts
      }
      _connectSource = null;
      _hadValidTarget = false;
      return;
    }

    final id = _grabbedNodeId;
    if (id != null) {
      _controller.nodes[id]?.isSelected = false;
      setState(() => _grabbedNodeId = null);
    }
  }

  /// A real tap-up that didn't move. If it landed on a connection, prompt to
  /// delete it. Taps on nodes/ports/empty canvas are ignored here (nodes use
  /// double-tap; ports use long-press) so this never interferes.
  void _onTapUp(TapUpDetails d) {
    final connId = _controller.hitTestConnections(_toGraph(d.localPosition));
    if (connId == null) return;
    final conn = _controller.connections.where((c) => c.id == connId);
    if (conn.isNotEmpty) _confirmDeleteConnection(conn.first);
  }

  @override
  Widget build(BuildContext context) {
    final readOnly = widget.readOnly;
    // Match the canvas + grid to the system brightness so the editor isn't a
    // hard-white sheet in dark mode. Node cards adapt too (see _FlowNode).
    final isDark =
        CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final editorTheme = isDark ? NodeFlowTheme.dark : NodeFlowTheme.light;
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
              theme: editorTheme,
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
                      // NOTE: connection delete is NOT wired via the library's
                      // ConnectionEvents.onTap — that fires from a raw
                      // pointer-down (no movement check), so a stray brush while
                      // panning instantly prompts delete. Instead our overlay's
                      // TapGestureRecognizer (below) handles it: it only fires on
                      // a real tap-up that didn't move, so panning never triggers
                      // a delete.
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
                    // A real tap (down + up WITHOUT moving) on a connection
                    // prompts delete. Because a pan moves the finger, the tap
                    // recognizer loses the arena during a pan — so brushing a
                    // connection while panning never triggers a delete.
                    TapGestureRecognizer:
                        GestureRecognizerFactoryWithHandlers<
                            TapGestureRecognizer>(
                      () => TapGestureRecognizer(),
                      (r) => r..onTapUp = _onTapUp,
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
            // Floating add-node button (owners only). Last in the stack so it
            // sits above the long-press overlay and stays tappable.
            if (!readOnly)
              Positioned(
                right: 20,
                bottom: 24,
                child: _FloatingAddButton(
                  onPressed: _saving ? null : _showAddNodeSheet,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNode(BuildContext context, Node<Map<String, dynamic>> node) {
    final deactivated = node.data['deactivated'] == true;
    final inner = _buildNodeInner(node);
    // Visual-only state: deactivated nodes render dimmed with a grey power
    // badge; active nodes show a green one. The badge is NON-interactive
    // (IgnorePointer) and stays INSIDE the node bounds so it neither shifts the
    // node's content nor competes with the long-press move overlay. The actual
    // toggle lives in the config sheet ("Node active").
    return Stack(
      children: [
        Opacity(opacity: deactivated ? 0.45 : 1.0, child: inner),
        Positioned(
          top: 4,
          right: 4,
          child: IgnorePointer(
            child: Icon(
              CupertinoIcons.power,
              size: 14,
              color: deactivated
                  ? CupertinoColors.systemGrey
                  : CupertinoColors.activeGreen,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNodeInner(Node<Map<String, dynamic>> node) {
    // Read the observable so the editor's Observer repaints this node when it's
    // grabbed (selection is our grab indicator — see _onLongPressStart).
    final grabbed = node.selected.value;
    final d = node.data;
    final values = (_nodeValues[node.id] as Map?)?.cast<String, dynamic>();

    switch (node.type) {
      case 'income':
        return _FlowNode(
          icon: CupertinoIcons.money_dollar,
          title: (d['label'] as String?)?.trim().isNotEmpty == true
              ? d['label'] as String
              : 'Income',
          color: const Color(0xFF2E7D32),
          grabbed: grabbed,
          body: [_kv('Amount', _money(d['amount']))],
          calc: [
            if (values != null) _calc('Output', values['output'], _kGreen, bold: true),
          ],
        );
      case 'conditional':
        final cond = '${_condLabel(d['conditionType'])} '
            '${d['operator']} ${_condValue(d)}';
        return _FlowNode(
          icon: CupertinoIcons.question_circle,
          title: (d['label'] as String?)?.trim().isNotEmpty == true
              ? d['label'] as String
              : 'Condition',
          color: const Color(0xFFB26A00),
          grabbed: grabbed,
          body: [_summaryBox(cond, const Color(0xFFB26A00))],
          chips: const [
            (_kGreen, 'TRUE'),
            (_kRed, 'FALSE'),
          ],
          calc: [
            if (values != null) _calc('Input', values['input'], _kLabel),
          ],
        );
      case 'bandCut':
        final label = (d['customLabel'] as String?)?.trim();
        final cutType = '${d['cutType'] ?? 'percentage'}';
        return _FlowNode(
          icon: CupertinoIcons.percent,
          title: (label != null && label.isNotEmpty) ? label : 'Band Cut',
          color: _kPurple,
          grabbed: grabbed,
          body: [
            _kv('Cut type', _capitalize(cutType)),
            if (cutType != 'tiered' && cutType != 'none')
              _kv(cutType == 'percentage' ? 'Percentage' : 'Amount',
                  cutType == 'percentage' ? '${d['value']}%' : _money(d['value'])),
            if (cutType == 'tiered')
              _kv('Tiers', '${(d['tierConfig'] as List?)?.length ?? 0}'),
          ],
          calc: [
            if (values != null) ...[
              _calc('Input', values['input'], _kLabel),
              _calc('Band cut', values['bandCut'], _kPurple, bold: true),
              _calc('To members', values['output'], _kGreen, bold: true),
            ],
          ],
        );
      case 'payoutGroup':
        final src = '${d['sourceType'] ?? 'roster'}';
        final mode = '${d['distributionMode'] ?? 'equal_split'}';
        final allocType = '${d['incomingAllocationType'] ?? 'remainder'}';
        return _FlowNode(
          icon: CupertinoIcons.group,
          title: (d['label'] as String?)?.trim().isNotEmpty == true
              ? d['label'] as String
              : 'Payout Group',
          color: const Color(0xFF1565C0),
          grabbed: grabbed,
          body: [
            _kv('Source', _sourceLabel(src)),
            _modeBox(_modeLabel(mode), const Color(0xFF1565C0)),
            _kv(
              'Allocation',
              allocType == 'remainder'
                  ? 'Remainder'
                  : allocType == 'percentage'
                      ? 'Takes ${d['incomingAllocationValue']}%'
                      : 'Takes ${_money(d['incomingAllocationValue'])}',
            ),
            if (values != null && (values['memberCount'] ?? 0) > 0)
              _kv('Members', '${values['memberCount']}'),
          ],
          calc: [
            if (values != null) ...[
              _calc('Input', values['input'], _kLabel),
              _calc('Allocated', values['allocated'], const Color(0xFF1565C0), bold: true),
              if ((values['memberCount'] ?? 0) > 0)
                _calc('Per member', values['perMember'], _kGreen, bold: true),
              _calc('Remaining', values['output'], CupertinoColors.systemGrey),
            ],
          ],
        );
      default:
        return _FlowNode(
          icon: CupertinoIcons.square,
          title: node.type,
          color: CupertinoColors.systemGrey,
          grabbed: grabbed,
        );
    }
  }

  // ── Node-card content helpers ────────────────────────────────────────────

  static String _money(dynamic v) {
    final n = (v as num?)?.toDouble() ?? 0;
    return '\$${n.toStringAsFixed(n.truncateToDouble() == n ? 0 : 2)}';
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  static String _condLabel(dynamic t) => const {
        'bookingPrice': 'Booking Price',
        'eventCount': 'Event Count',
        'eventType': 'Event Type',
        'dayOfWeek': 'Day of Week',
        'memberCount': 'Member Count',
        'eventMultiplier': 'Event Multiplier',
      }['$t'] ?? '$t';

  static String _condValue(Map<String, dynamic> d) {
    final t = '${d['conditionType']}';
    if (t == 'bookingPrice') return _money(d['value']);
    return '${d['value']}';
  }

  static String _sourceLabel(String s) => const {
        'roster': 'Roster',
        'paymentGroup': 'Payment group',
        'specific': 'Specific members',
        'roles': 'Role slots',
        'allMembers': 'All members',
      }[s] ?? s;

  static String _modeLabel(String m) => const {
        'equal_split': 'Equal split',
        'percentage': 'Percentage',
        'fixed': 'Fixed amount',
        'tiered': 'Tiered',
        'weighted': 'Weighted',
      }[m] ?? m;

  static _BodyRow _kv(String label, String value) => _BodyRow.kv(label, value);
  static _BodyRow _summaryBox(String text, Color color) =>
      _BodyRow.box(text, color, mono: true);
  static _BodyRow _modeBox(String text, Color color) =>
      _BodyRow.box(text, color);
  static _CalcRow _calc(String label, dynamic value, Color color,
          {bool bold = false}) =>
      _CalcRow(label, _money(value), color, bold: bold);
}

const _kGreen = Color(0xFF16A34A);
const _kRed = Color(0xFFDC2626);
const _kPurple = Color(0xFF7E22CE);
const _kLabel = CupertinoColors.label;

/// A labelled body row: either a "label: value" line, or a coloured box
/// (condition summary / distribution-mode pill).
class _BodyRow {
  _BodyRow.kv(this.label, this.value)
      : isBox = false,
        boxColor = null,
        mono = false;
  _BodyRow.box(this.value, this.boxColor, {this.mono = false})
      : label = null,
        isBox = true;

  final String? label;
  final String value;
  final bool isBox;
  final Color? boxColor;
  final bool mono;

  Widget build(BuildContext context) {
    if (isBox) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: boxColor!.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: boxColor!.withValues(alpha: 0.4)),
        ),
        child: Text(value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: boxColor,
              fontFamily: mono ? 'Menlo' : null,
            )),
      );
    }
    // Resolve `label` against context so the value is dark text on a light card
    // and light text on a dark card.
    final valueColor =
        CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('$label',
              style: const TextStyle(
                  fontSize: 11, color: CupertinoColors.systemGrey)),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: valueColor)),
          ),
        ],
      ),
    );
  }
}

/// A computed-values footer row (label → coloured amount).
class _CalcRow {
  const _CalcRow(this.label, this.value, this.color, {this.bold = false});
  final String label;
  final String value;
  final Color color;
  final bool bold;
}

class _FlowNode extends StatelessWidget {
  const _FlowNode({
    required this.icon,
    required this.title,
    required this.color,
    this.body = const [],
    this.chips = const [],
    this.calc = const [],
    this.grabbed = false,
  });

  final IconData icon;
  final String title;
  final Color color;
  final List<_BodyRow> body;

  /// Coloured label chips (e.g. conditional TRUE/FALSE).
  final List<(Color, String)> chips;
  final List<_CalcRow> calc;

  /// True while this node is grabbed via long-press — show a "lifted" cue.
  final bool grabbed;

  @override
  Widget build(BuildContext context) {
    final calcRows = calc;
    // Adaptive card fill: white in light mode, a raised dark grey in dark mode
    // (distinct from the near-black canvas). Borders/icons/text accents stay.
    final cardFill = CupertinoDynamicColor.resolve(
        CupertinoColors.secondarySystemBackground, context);
    return AnimatedScale(
      scale: grabbed ? 1.06 : 1.0,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        // Fill the node's box (vyuh sizes it to node.size).
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: cardFill,
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
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header: icon + title
            Row(children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(title,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: color, fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ]),
            // Body fields
            ...body.map((b) => b.build(context)),
            // Branch chips (conditional)
            if (chips.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  for (final (c, label) in chips)
                    Expanded(
                      child: Container(
                        margin: EdgeInsets.only(right: label == chips.last.$2 ? 0 : 4),
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        decoration: BoxDecoration(
                          color: c.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: c.withValues(alpha: 0.4)),
                        ),
                        child: Text(label,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 10, fontWeight: FontWeight.bold, color: c)),
                      ),
                    ),
                ],
              ),
            ],
            // Computed-values footer
            if (calcRows.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(height: 0.5, color: CupertinoColors.separator),
              const SizedBox(height: 4),
              for (final r in calcRows)
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${r.label}:',
                          style: const TextStyle(
                              fontSize: 11, color: CupertinoColors.systemGrey)),
                      Text(r.value,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: r.bold ? FontWeight.bold : FontWeight.normal,
                              // Resolve so _kLabel (CupertinoColors.label) flips
                              // dark↔light with the card; fixed accents pass through.
                              color: CupertinoDynamicColor.resolve(r.color, context))),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Transient cue shown while a node is grabbed via long-press.
/// Floating circular "+" button to add a node.
class _FloatingAddButton extends StatelessWidget {
  const _FloatingAddButton({required this.onPressed});
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: CupertinoColors.activeBlue,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: CupertinoColors.black.withValues(alpha: 0.25),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: const Icon(CupertinoIcons.add, size: 30, color: CupertinoColors.white),
      ),
    );
  }
}

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
