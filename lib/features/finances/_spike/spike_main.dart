// SPIKE — throwaway entrypoint so the editor can be launched standalone on a
// device without wiring it into app nav/auth. Run with:
//
//   flutter run -t lib/features/finances/_spike/spike_main.dart -d <device>
//
// Delete the _spike/ folder to revert the whole experiment.

import 'package:flutter/cupertino.dart';

import 'payout_flow_spike_screen.dart';

void main() => runApp(const _SpikeApp());

class _SpikeApp extends StatelessWidget {
  const _SpikeApp();

  @override
  Widget build(BuildContext context) {
    return const CupertinoApp(
      title: 'Payout Flow Spike',
      home: PayoutFlowSpikeScreen(),
    );
  }
}
