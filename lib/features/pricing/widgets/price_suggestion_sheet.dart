import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/price_estimate.dart';
import '../providers/pricing_provider.dart';
import 'estimate_result_card.dart';

/// Opens the estimate for [request] in a bottom sheet. Resolves with the
/// suggested price when the user taps "Use this price", otherwise null.
Future<double?> showPriceSuggestionSheet(
  BuildContext context, {
  required int bandId,
  required PriceEstimateRequest request,
}) {
  return showCupertinoModalPopup<double>(
    context: context,
    builder: (_) => _PriceSuggestionSheet(bandId: bandId, request: request),
  );
}

class _PriceSuggestionSheet extends ConsumerStatefulWidget {
  const _PriceSuggestionSheet({required this.bandId, required this.request});
  final int bandId;
  final PriceEstimateRequest request;

  @override
  ConsumerState<_PriceSuggestionSheet> createState() =>
      _PriceSuggestionSheetState();
}

class _PriceSuggestionSheetState extends ConsumerState<_PriceSuggestionSheet> {
  @override
  void initState() {
    super.initState();
    Future.microtask(_run);
  }

  void _run() {
    if (!mounted) return;
    ref
        .read(priceEstimateProvider.notifier)
        .run(widget.bandId, widget.request);
  }

  @override
  Widget build(BuildContext context) {
    final result = ref.watch(priceEstimateProvider);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;

    Widget body;
    if (result.isLoading) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CupertinoActivityIndicator()),
      );
    } else if (result.hasError) {
      body = Column(
        children: [
          Text(pricingErrorMessage(result.error!),
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: CupertinoColors.systemRed.resolveFrom(context))),
          CupertinoButton(onPressed: _run, child: const Text('Try again')),
        ],
      );
    } else if (result.value != null) {
      final est = result.value!;
      body = EstimateResultCard(
        estimate: est,
        onUsePrice:
            est.hasEstimate ? () => Navigator.of(context).pop(est.estimate) : null,
      );
    } else {
      body = const SizedBox.shrink();
    }

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: CupertinoColors.systemGroupedBackground.resolveFrom(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Suggested price',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w600)),
                  ),
                  CupertinoButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: DefaultTextStyle.merge(
                  style: const TextStyle(decoration: TextDecoration.none),
                  child: body,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
