import 'package:flutter/cupertino.dart';

/// Banner shown above the contract preview/history when the booking is no
/// longer editable. Copy/color mirrors the web's three-way conditional in
/// Contract.vue.
class ContractLockBanner extends StatelessWidget {
  const ContractLockBanner({
    super.key,
    required this.status,
    required this.contractOption,
  });

  final String status;
  final String contractOption;

  String get _message {
    if (status == 'pending') {
      return 'This contract is pending. The contract is no longer editable.';
    }
    if (status == 'confirmed' && contractOption == 'external') {
      return 'This contract is confirmed and was created externally. '
          'The contract is no longer editable.';
    }
    return 'This contract is confirmed. The contract is no longer editable.';
  }

  Color _backgroundColor(BuildContext context) {
    final base = status == 'pending'
        ? CupertinoColors.systemBlue
        : CupertinoColors.systemYellow;
    return base.resolveFrom(context).withValues(alpha: 0.15);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _backgroundColor(context),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        _message,
        textAlign: TextAlign.center,
        style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
      ),
    );
  }
}
