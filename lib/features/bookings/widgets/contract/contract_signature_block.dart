import 'package:clock/clock.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';

import '../../data/models/booking_contact.dart';

class ContractSignatureBlock extends StatelessWidget {
  const ContractSignatureBlock({
    super.key,
    required this.firstContact,
    this.buyerNameOverride,
  });

  final BookingContact? firstContact;
  final String? buyerNameOverride;

  @override
  Widget build(BuildContext context) {
    // With no override the buyer is the first signer (first contact by default).
    final signerName = firstContact?.name ?? 'Buyer';
    final hasOverride =
        buyerNameOverride != null && buyerNameOverride!.trim().isNotEmpty;
    final buyerName = hasOverride ? buyerNameOverride! : signerName;
    final today = DateFormat('M/d/yyyy').format(clock.now());

    final bold = CupertinoTheme.of(context).textTheme.textStyle.copyWith(
          fontWeight: FontWeight.w700,
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Buyer', style: bold),
          const SizedBox(height: 4),
          const Text('I Agree to the terms and conditions of this contract'),
          const SizedBox(height: 8),
          Text.rich(TextSpan(children: [
            TextSpan(
              text: buyerName,
              style: bold.copyWith(decoration: TextDecoration.underline),
            ),
            const TextSpan(text: ' - '),
            TextSpan(text: today, style: bold),
          ])),
          if (hasOverride) ...[
            const SizedBox(height: 4),
            Text('Each signer signs on behalf of $buyerName'),
          ],
          const SizedBox(height: 16),
          const Text('Signature: ___________________________'),
          const SizedBox(height: 8),
          Text(
            'Signers are chosen when you send the contract.',
            style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                  fontSize: 11,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                ),
          ),
        ],
      ),
    );
  }
}
