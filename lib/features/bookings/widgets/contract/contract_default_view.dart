import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/booking_detail.dart';
import 'contract_editor.dart';
import 'contract_history_list.dart';
import 'contract_lock_banner.dart';
import 'contract_preview_webview.dart';

class ContractDefaultView extends ConsumerStatefulWidget {
  const ContractDefaultView({super.key, required this.booking});

  final BookingDetail booking;

  @override
  ConsumerState<ContractDefaultView> createState() =>
      _ContractDefaultViewState();
}

enum _LockedTab { preview, history }

class _ContractDefaultViewState extends ConsumerState<ContractDefaultView> {
  _LockedTab _tab = _LockedTab.preview;

  bool get _isLocked {
    final s = widget.booking.status;
    return s == 'pending' || s == 'confirmed';
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLocked) {
      return ContractEditor(booking: widget.booking);
    }

    final envelopeId = widget.booking.contract?.envelopeId;

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('Contract')),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: ContractLockBanner(
                status: widget.booking.status ?? 'confirmed',
                contractOption: widget.booking.contractOption ?? 'default',
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: CupertinoSlidingSegmentedControl<_LockedTab>(
                groupValue: _tab,
                onValueChanged: (v) {
                  if (v != null) setState(() => _tab = v);
                },
                children: const {
                  _LockedTab.preview: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Text('Preview'),
                  ),
                  _LockedTab.history: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Text('History'),
                  ),
                },
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: switch (_tab) {
                _LockedTab.preview => ContractPreviewWebView(
                    bandId: widget.booking.band!.id,
                    bookingId: widget.booking.id,
                  ),
                _LockedTab.history => envelopeId == null
                    ? const Center(child: Text('No PandaDoc envelope yet.'))
                    : ContractHistoryList(envelopeId: envelopeId),
              },
            ),
          ],
        ),
      ),
    );
  }
}
