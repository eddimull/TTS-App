import 'package:clock/clock.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';
import '../../../shared/providers/selected_band_provider.dart';
import '../../bookings/data/models/event_type.dart';
import '../../bookings/providers/bookings_provider.dart';
import '../data/models/price_estimate.dart';
import '../providers/pricing_provider.dart';
import '../widgets/estimate_result_card.dart';

/// Standalone price estimator (owners only; the backend enforces this too).
class PriceEstimatorScreen extends ConsumerStatefulWidget {
  const PriceEstimatorScreen({super.key});

  @override
  ConsumerState<PriceEstimatorScreen> createState() =>
      _PriceEstimatorScreenState();
}

class _PriceEstimatorScreenState extends ConsumerState<PriceEstimatorScreen> {
  int? _eventTypeId;
  DateTime? _date;
  DateTime? _start;
  DateTime? _end;
  final _venue = TextEditingController();
  final Set<String> _addOns = {};
  String? _validation;

  @override
  void dispose() {
    _venue.dispose();
    super.dispose();
  }

  static String _fmtTime(DateTime t) => DateFormat('HH:mm').format(t);

  Future<void> _pickEventType(List<EventType> types) async {
    if (types.isEmpty) return;
    int temp = types.indexWhere((t) => t.id == _eventTypeId);
    if (temp < 0) temp = 0;
    await _showSheet(
      CupertinoPicker(
        scrollController: FixedExtentScrollController(initialItem: temp),
        itemExtent: 40,
        onSelectedItemChanged: (i) => temp = i,
        children: types.map((t) => Center(child: Text(t.name))).toList(),
      ),
    );
    setState(() => _eventTypeId = types[temp].id);
  }

  Future<void> _pickDate() async {
    DateTime temp = _date ?? clock.now();
    await _showSheet(
      CupertinoDatePicker(
        mode: CupertinoDatePickerMode.date,
        initialDateTime: temp,
        minimumYear: clock.now().year - 1,
        maximumYear: clock.now().year + 5,
        onDateTimeChanged: (d) => temp = d,
      ),
    );
    setState(() => _date = temp);
  }

  Future<void> _pickTime({required bool start}) async {
    final init = (start ? _start : _end) ??
        (start ? DateTime(2000, 1, 1, 19) : DateTime(2000, 1, 1, 23));
    DateTime temp = init;
    await _showSheet(
      CupertinoDatePicker(
        mode: CupertinoDatePickerMode.time,
        initialDateTime: temp,
        minuteInterval: 5,
        onDateTimeChanged: (d) => temp = d,
      ),
    );
    setState(() => start ? _start = temp : _end = temp);
  }

  Future<void> _showSheet(Widget picker) {
    return showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => Container(
        height: 300,
        color: CupertinoColors.systemBackground.resolveFrom(ctx),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: CupertinoButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Done'),
                ),
              ),
              Expanded(child: picker),
            ],
          ),
        ),
      ),
    );
  }

  void _estimate(int bandId) {
    if (_eventTypeId == null || _date == null) {
      setState(() => _validation = 'Choose an event type and a date first.');
      return;
    }
    setState(() => _validation = null);
    ref.read(priceEstimateProvider.notifier).run(
          bandId,
          PriceEstimateRequest(
            eventTypeId: _eventTypeId!,
            date: DateFormat('yyyy-MM-dd').format(_date!),
            startTime: _start == null ? null : _fmtTime(_start!),
            endTime: _end == null ? null : _fmtTime(_end!),
            venueAddress: _venue.text,
            addOns: _addOns.toList(),
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    const navBar = CupertinoNavigationBar(middle: Text('Price Estimator'));
    final bandId = ref.watch(selectedBandProvider).value;
    if (bandId == null) {
      return const CupertinoPageScaffold(
        navigationBar: navBar,
        child: Center(child: CupertinoActivityIndicator()),
      );
    }

    final types = ref.watch(eventTypesProvider).value ?? const <EventType>[];
    final settings = ref.watch(pricingSettingsProvider(bandId)).value;
    final addOns = settings?.settings.addOns ?? const [];
    final result = ref.watch(priceEstimateProvider);
    final typeName = types.where((t) => t.id == _eventTypeId).firstOrNull?.name;

    return CupertinoPageScaffold(
      navigationBar: navBar,
      child: SafeArea(
        child: ListView(
          children: [
            CupertinoFormSection.insetGrouped(
              header: const Text('EVENT'),
              children: [
                _PickRow(
                  label: 'Event type',
                  value: typeName,
                  onTap: () => _pickEventType(types),
                ),
                _PickRow(
                  label: 'Date',
                  value:
                      _date == null ? null : DateFormat.yMMMEd().format(_date!),
                  onTap: _pickDate,
                ),
                _PickRow(
                  label: 'Start time',
                  value:
                      (_start == null ? null : DateFormat.jm().format(_start!)),
                  onTap: () => _pickTime(start: true),
                ),
                _PickRow(
                  label: 'End time',
                  value: (_end == null ? null : DateFormat.jm().format(_end!)),
                  onTap: () => _pickTime(start: false),
                ),
                CupertinoTextFormFieldRow(
                  controller: _venue,
                  prefix: const Text('Venue address'),
                  textAlign: TextAlign.end,
                  placeholder: 'For travel fees (optional)',
                  textInputAction: TextInputAction.done,
                ),
              ],
            ),
            if (addOns.isNotEmpty)
              CupertinoFormSection.insetGrouped(
                header: const Text('ADD-ONS'),
                children: [
                  for (final a in addOns)
                    CupertinoFormRow(
                      prefix: Text('${a.label} (+${formatMoney(a.amount)})'),
                      child: CupertinoSwitch(
                        value: _addOns.contains(a.key),
                        onChanged: (v) => setState(() =>
                            v ? _addOns.add(a.key) : _addOns.remove(a.key)),
                      ),
                    ),
                ],
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: CupertinoButton.filled(
                onPressed: result.isLoading ? null : () => _estimate(bandId),
                child: result.isLoading
                    ? const CupertinoActivityIndicator()
                    : const Text('Estimate'),
              ),
            ),
            if (_validation != null)
              _Message(text: _validation!, isError: true),
            if (result.hasError && !result.isLoading)
              _Message(
                  text: pricingErrorMessage(
                    result.error!,
                    fallback: 'Could not get an estimate. Please try again.',
                  ),
                  isError: true),
            if (result.value != null && !result.isLoading)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: EstimateResultCard(estimate: result.value!),
              ),
          ],
        ),
      ),
    );
  }
}

class _PickRow extends StatelessWidget {
  const _PickRow(
      {required this.label, required this.value, required this.onTap});
  final String label;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoFormRow(
      prefix: Text(label),
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        onPressed: onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Flexible(
              child: Text(
                value ?? 'Select',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: value == null
                      ? context.placeholderText
                      : context.secondaryText,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(CupertinoIcons.chevron_right,
                size: 14, color: context.tertiaryText),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, required this.isError});
  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: isError
                ? CupertinoColors.systemRed.resolveFrom(context)
                : context.secondaryText,
          ),
        ),
      );
}
