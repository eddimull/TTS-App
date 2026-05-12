import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';

import '../../data/models/booking_contact.dart';

class ContractSignatureBlock extends StatelessWidget {
  const ContractSignatureBlock({super.key, required this.firstContact});

  final BookingContact? firstContact;

  @override
  Widget build(BuildContext context) {
    final name = firstContact?.name ?? 'Buyer';
    final today = DateFormat('M/d/yyyy').format(DateTime.now());

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
              text: name,
              style: bold.copyWith(decoration: TextDecoration.underline),
            ),
            const TextSpan(text: ' - '),
            TextSpan(text: today, style: bold),
          ])),
          const SizedBox(height: 16),
          const Text('Signature: ___________________________'),
        ],
      ),
    );
  }
}
