import 'package:flutter/cupertino.dart';

const paymentTypes = [
  ('cash', 'Cash'),
  ('check', 'Check'),
  ('credit_card', 'Credit Card'),
  ('venmo', 'Venmo'),
  ('zelle', 'Zelle'),
  ('wire', 'Wire Transfer'),
  ('invoice', 'Invoice'),
  ('portal', 'Client Portal'),
  ('other', 'Other'),
];

/// A `CupertinoPicker`-based widget for selecting a payment type.
/// Shows the human-readable label and calls [onChanged] with the raw value.
class PaymentTypePicker extends StatelessWidget {
  const PaymentTypePicker({
    super.key,
    required this.selectedValue,
    required this.onChanged,
  });

  final String selectedValue;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final initialIndex =
        paymentTypes.indexWhere((t) => t.$1 == selectedValue);
    final safeIndex = initialIndex < 0 ? 0 : initialIndex;

    return CupertinoPicker(
      scrollController: FixedExtentScrollController(initialItem: safeIndex),
      itemExtent: 40,
      onSelectedItemChanged: (i) => onChanged(paymentTypes[i].$1),
      children: paymentTypes
          .map((t) => Center(
                child: Text(t.$2, style: const TextStyle(fontSize: 16)),
              ))
          .toList(),
    );
  }
}
