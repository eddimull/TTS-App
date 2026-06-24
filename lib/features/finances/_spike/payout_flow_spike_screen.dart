// SPIKE — throwaway. A bare NodeFlowEditor wired to the seed via the adapter,
// for assessing touch feel on a physical device. Not routed into app nav.
//
// On-device checklist this screen supports:
//   1. drag each node by thumb
//   2. wire ports — especially the conditional's `true` / `false` outputs
//   3. tap "Dump TTS JSON" to confirm the reverse adapter produces backend-valid
//      flow JSON from whatever you've drawn (printed to the console + a sheet).

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
        child: NodeFlowEditor<Map<String, dynamic>, dynamic>(
          controller: _controller,
          theme: NodeFlowTheme.light,
          behavior: NodeFlowBehavior.design,
          nodeBuilder: _buildNode,
        ),
      ),
    );
  }

  Widget _buildNode(BuildContext context, Node<Map<String, dynamic>> node) {
    switch (node.type) {
      case 'income':
        return _SpikeNode(
          title: 'Income',
          color: const Color(0xFF2E7D32),
          subtitle: '\$${node.data['amount']}',
        );
      case 'conditional':
        return _SpikeNode(
          title: 'Condition',
          color: const Color(0xFFB26A00),
          subtitle:
              '${node.data['conditionType']} ${node.data['operator']} ${node.data['value']}',
          footer: 'true / false',
        );
      case 'payoutGroup':
        final mode = node.data['distributionMode'];
        final pct = node.data['incomingAllocationValue'];
        return _SpikeNode(
          title: node.data['label']?.toString() ?? 'Payout',
          color: const Color(0xFF1565C0),
          subtitle: '$pct% · $mode',
        );
      default:
        return _SpikeNode(title: node.type, color: CupertinoColors.systemGrey);
    }
  }
}

class _SpikeNode extends StatelessWidget {
  const _SpikeNode({
    required this.title,
    required this.color,
    this.subtitle,
    this.footer,
  });

  final String title;
  final Color color;
  final String? subtitle;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: CupertinoColors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color, width: 2),
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
    );
  }
}
