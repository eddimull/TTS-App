import 'package:flutter/cupertino.dart';

import '../../data/models/booking_contact.dart';

class ContractSendSheetResult {
  const ContractSendSheetResult({required this.signerId, this.ccId});
  final int signerId;
  final int? ccId;
}

/// Bottom sheet that asks the user to pick the signer (and optionally a CC
/// contact) before sending the contract.
///
/// Returns null on cancel; a [ContractSendSheetResult] on confirm.
Future<ContractSendSheetResult?> showContractSendSheet(
  BuildContext context, {
  required List<BookingContact> contacts,
}) async {
  if (contacts.isEmpty) return null;

  var signerIndex = 0;
  var ccEnabled = false;
  var ccIndex = contacts.length > 1 ? 1 : 0;

  return showCupertinoModalPopup<ContractSendSheetResult>(
    context: context,
    builder: (sheetCtx) {
      return StatefulBuilder(
        builder: (ctx, setState) {
          return Container(
            color: CupertinoColors.systemBackground.resolveFrom(ctx),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        CupertinoButton(
                          onPressed: () => Navigator.pop(ctx, null),
                          child: const Text('Cancel'),
                        ),
                        const Text(
                          'Send Contract',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        CupertinoButton(
                          onPressed: () => Navigator.pop(
                            ctx,
                            ContractSendSheetResult(
                              signerId: contacts[signerIndex].id,
                              ccId: ccEnabled ? contacts[ccIndex].id : null,
                            ),
                          ),
                          child: const Text(
                            'Send',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    Text('Signer', style: CupertinoTheme.of(ctx).textTheme.textStyle),
                    SizedBox(
                      height: 120,
                      child: CupertinoPicker(
                        itemExtent: 36,
                        scrollController:
                            FixedExtentScrollController(initialItem: signerIndex),
                        onSelectedItemChanged: (i) =>
                            setState(() => signerIndex = i),
                        children: [
                          for (final c in contacts)
                            Center(child: Text(c.name)),
                        ],
                      ),
                    ),
                    if (contacts.length > 1) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text('CC another contact',
                              style: CupertinoTheme.of(ctx).textTheme.textStyle),
                          const Spacer(),
                          CupertinoSwitch(
                            value: ccEnabled,
                            onChanged: (v) => setState(() => ccEnabled = v),
                          ),
                        ],
                      ),
                      if (ccEnabled)
                        SizedBox(
                          height: 120,
                          child: CupertinoPicker(
                            itemExtent: 36,
                            scrollController: FixedExtentScrollController(
                                initialItem: ccIndex),
                            onSelectedItemChanged: (i) =>
                                setState(() => ccIndex = i),
                            children: [
                              for (final c in contacts)
                                Center(child: Text(c.name)),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}
