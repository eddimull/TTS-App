import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';
import '../../../shared/providers/selected_band_provider.dart';
import '../data/models/pricing_settings.dart';
import '../providers/pricing_provider.dart';
import '../utils/percent.dart';
import '../widgets/estimate_result_card.dart' show formatMoney;

const _dowNames = [
  'Sunday',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday'
];

/// Edit the band's pricing rules (owners only; the backend enforces this too).
class PricingSettingsScreen extends ConsumerStatefulWidget {
  const PricingSettingsScreen({super.key});

  @override
  ConsumerState<PricingSettingsScreen> createState() =>
      _PricingSettingsScreenState();
}

class _PricingSettingsScreenState extends ConsumerState<PricingSettingsScreen> {
  PricingSettings? _draft;
  bool _saving = false;

  PricingSettings get _s => _draft!;

  void _update(PricingSettings s) => setState(() => _draft = s);

  Future<void> _save(int bandId) async {
    setState(() => _saving = true);
    try {
      await ref.read(pricingSettingsProvider(bandId).notifier).save(_s);
      if (mounted) Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      await showCupertinoDialog<void>(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('Could not save'),
          content: Text(pricingErrorMessage(
            e,
            fallback: 'Could not save your pricing rules. Please try again.',
          )),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bandId = ref.watch(selectedBandProvider).value;
    const title = Text('Pricing Rules');
    if (bandId == null) {
      return const CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(middle: title),
        child: Center(child: CupertinoActivityIndicator()),
      );
    }

    final async = ref.watch(pricingSettingsProvider(bandId));
    if (async.isLoading && !async.hasValue) {
      return const CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(middle: title),
        child: Center(child: CupertinoActivityIndicator()),
      );
    }
    if (async.hasError && !async.hasValue) {
      return CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(middle: title),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Failed to load pricing rules.',
                  style: TextStyle(color: context.secondaryText)),
              CupertinoButton(
                onPressed: () =>
                    ref.invalidate(pricingSettingsProvider(bandId)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final bundle = async.value!;
    _draft ??= bundle.settings;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: title,
        trailing: _saving
            ? const CupertinoActivityIndicator()
            : CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => _save(bandId),
                child: const Text('Save'),
              ),
      ),
      child: SafeArea(
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            _baseRates(bundle),
            _seasons(),
            _daysOfWeek(),
            _specialDates(),
            _duration(),
            _timing(),
            _travel(),
            _addOns(),
            _rounding(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ── Sections ──────────────────────────────────────────────────────────────

  Widget _baseRates(PricingSettingsBundle bundle) {
    if (bundle.eventTypes.isEmpty) return const SizedBox.shrink();
    return CupertinoFormSection.insetGrouped(
      header: const Text('BASE RATES'),
      footer: const Text(
          'Leave blank to use the rate learned from your past bookings.'),
      children: [
        for (final t in bundle.eventTypes)
          _BaseRateRow(
            key: ValueKey('base-${t.id}'),
            name: t.name,
            history: bundle.historyFor(t.id),
            value: _s.baseRates[t.id],
            onChanged: (v) {
              final m = Map<int, double>.from(_s.baseRates);
              v == null ? m.remove(t.id) : m[t.id] = v;
              _update(_s.copyWith(baseRates: m));
            },
          ),
      ],
    );
  }

  Widget _seasons() => CupertinoFormSection.insetGrouped(
        header: const Text('SEASON ADJUSTMENT'),
        footer: const Text('Percent above (+) or below (−) your baseline.'),
        children: [
          for (var m = 1; m <= 12; m++)
            _NumRow(
              key: ValueKey('season-$m'),
              label: DateFormat.MMMM().format(DateTime(2000, m)),
              initial: trimNumber(
                  multiplierToPercent(_s.seasonMultipliers[m] ?? 1.0)),
              suffix: '%',
              signed: true,
              onChanged: (v) {
                final map = Map<int, double>.from(_s.seasonMultipliers);
                map[m] = percentToMultiplier(v ?? 0);
                _update(_s.copyWith(seasonMultipliers: map));
              },
            ),
        ],
      );

  Widget _daysOfWeek() => CupertinoFormSection.insetGrouped(
        header: const Text('DAY OF WEEK ADJUSTMENT'),
        children: [
          for (var d = 0; d < 7; d++)
            _NumRow(
              key: ValueKey('dow-$d'),
              label: _dowNames[d],
              initial: trimNumber(
                  multiplierToPercent(_s.dayOfWeekMultipliers[d] ?? 1.0)),
              suffix: '%',
              signed: true,
              onChanged: (v) {
                final map = Map<int, double>.from(_s.dayOfWeekMultipliers);
                map[d] = percentToMultiplier(v ?? 0);
                _update(_s.copyWith(dayOfWeekMultipliers: map));
              },
            ),
        ],
      );

  Widget _specialDates() => CupertinoFormSection.insetGrouped(
        header: const Text('SPECIAL DATES'),
        children: [
          for (var i = 0; i < _s.specialDates.length; i++)
            _ListTapRow(
              title: _s.specialDates[i].label.isEmpty
                  ? _s.specialDates[i].date
                  : _s.specialDates[i].label,
              subtitle: _s.specialDates[i].date,
              trailing: formatMultiplier(_s.specialDates[i].multiplier),
              onTap: () => _editSpecialDate(i),
              onDelete: () {
                final l = List<SpecialDate>.from(_s.specialDates)..removeAt(i);
                _update(_s.copyWith(specialDates: l));
              },
            ),
          _AddRow(
              label: 'Add special date', onTap: () => _editSpecialDate(null)),
        ],
      );

  Widget _duration() => CupertinoFormSection.insetGrouped(
        header: const Text('DURATION'),
        footer: const Text(
            'Gigs longer than the standard length add the overtime percent per extra hour.'),
        children: [
          _NumRow(
            key: const ValueKey('std-hours'),
            label: 'Standard hours',
            initial: trimNumber(_s.standardHours),
            suffix: 'h',
            onChanged: (v) => _update(_s.copyWith(standardHours: v ?? 4)),
          ),
          _NumRow(
            key: const ValueKey('overtime'),
            label: 'Overtime per hour',
            initial: trimNumber(_s.overtimePctPerHour),
            suffix: '%',
            onChanged: (v) => _update(_s.copyWith(overtimePctPerHour: v ?? 0)),
          ),
          _NumRow(
            key: const ValueKey('min-dur'),
            label: 'Shortest-gig floor',
            initial: trimNumber(_s.minDurationFactor * 100),
            suffix: '%',
            onChanged: (v) =>
                _update(_s.copyWith(minDurationFactor: (v ?? 100) / 100)),
          ),
        ],
      );

  Widget _timing() => CupertinoFormSection.insetGrouped(
        header: const Text('TIMING'),
        children: [
          _NumRow(
            key: const ValueKey('notice-days'),
            label: 'Short notice under',
            initial: _s.shortNoticeDays.toString(),
            suffix: 'days',
            onChanged: (v) =>
                _update(_s.copyWith(shortNoticeDays: (v ?? 0).round())),
          ),
          _NumRow(
            key: const ValueKey('notice-mult'),
            label: 'Short notice adjustment',
            initial: trimNumber(multiplierToPercent(_s.shortNoticeMultiplier)),
            suffix: '%',
            signed: true,
            onChanged: (v) => _update(_s.copyWith(
                shortNoticeMultiplier: percentToMultiplier(v ?? 0))),
          ),
          _NumRow(
            key: const ValueKey('annual'),
            label: 'Annual increase',
            initial: trimNumber(_s.annualIncreasePct),
            suffix: '%',
            onChanged: (v) => _update(_s.copyWith(annualIncreasePct: v ?? 0)),
          ),
        ],
      );

  Widget _travel() => CupertinoFormSection.insetGrouped(
        header: const Text('TRAVEL'),
        footer: const Text(
            'Travel fee = miles beyond the free radius × 2 (round trip) × per-mile rate.'),
        children: [
          _NumRow(
            key: const ValueKey('free-radius'),
            label: 'Free radius',
            initial: trimNumber(_s.freeRadiusMiles),
            suffix: 'mi',
            onChanged: (v) => _update(_s.copyWith(freeRadiusMiles: v ?? 0)),
          ),
          _NumRow(
            key: const ValueKey('per-mile'),
            label: 'Per-mile rate',
            initial: trimNumber(_s.perMileRate),
            prefix: r'$',
            onChanged: (v) => _update(_s.copyWith(perMileRate: v ?? 0)),
          ),
          _NumRow(
            key: const ValueKey('lodging-miles'),
            label: 'Lodging beyond',
            initial: trimNumber(_s.lodgingThresholdMiles),
            suffix: 'mi',
            onChanged: (v) =>
                _update(_s.copyWith(lodgingThresholdMiles: v ?? 0)),
          ),
          _NumRow(
            key: const ValueKey('lodging-fee'),
            label: 'Lodging fee',
            initial: trimNumber(_s.lodgingFee),
            prefix: r'$',
            onChanged: (v) => _update(_s.copyWith(lodgingFee: v ?? 0)),
          ),
        ],
      );

  Widget _addOns() => CupertinoFormSection.insetGrouped(
        header: const Text('ADD-ONS'),
        children: [
          for (var i = 0; i < _s.addOns.length; i++)
            _ListTapRow(
              title: _s.addOns[i].label,
              trailing: formatMoney(_s.addOns[i].amount),
              onTap: () => _editAddOn(i),
              onDelete: () {
                final l = List<AddOn>.from(_s.addOns)..removeAt(i);
                _update(_s.copyWith(addOns: l));
              },
            ),
          _AddRow(label: 'Add add-on', onTap: () => _editAddOn(null)),
        ],
      );

  Widget _rounding() => CupertinoFormSection.insetGrouped(
        header: const Text('ROUNDING'),
        children: [
          _NumRow(
            key: const ValueKey('round-to'),
            label: 'Round to nearest',
            initial: trimNumber(_s.roundTo),
            prefix: r'$',
            onChanged: (v) => _update(_s.copyWith(roundTo: v ?? 1)),
          ),
        ],
      );

  // ── Edit dialogs ──────────────────────────────────────────────────────────

  Future<void> _editAddOn(int? index) async {
    final existing = index == null ? null : _s.addOns[index];
    final label = TextEditingController(text: existing?.label ?? '');
    final amount = TextEditingController(
        text: existing == null ? '' : trimNumber(existing.amount));
    final ok = await _fieldsDialog(
      title: existing == null ? 'New add-on' : 'Edit add-on',
      fields: [
        _DialogField(label, 'Name (e.g. Production)', TextInputType.text),
        _DialogField(amount, r'Amount ($)',
            const TextInputType.numberWithOptions(decimal: true)),
      ],
    );
    final name = label.text.trim();
    final amt = double.tryParse(amount.text.trim());
    label.dispose();
    amount.dispose();
    if (ok != true || name.isEmpty || amt == null) return;
    final l = List<AddOn>.from(_s.addOns);
    if (existing == null) {
      l.add(AddOn(
          key: _uniqueKey(name, l.map((e) => e.key)),
          label: name,
          amount: amt));
    } else {
      l[index!] = existing.copyWith(label: name, amount: amt);
    }
    _update(_s.copyWith(addOns: l));
  }

  Future<void> _editSpecialDate(int? index) async {
    final existing = index == null ? null : _s.specialDates[index];
    final date = TextEditingController(text: existing?.date ?? '');
    final label = TextEditingController(text: existing?.label ?? '');
    final pct = TextEditingController(
        text: existing == null
            ? ''
            : trimNumber(multiplierToPercent(existing.multiplier)));
    final ok = await _fieldsDialog(
      title: existing == null ? 'New special date' : 'Edit special date',
      fields: [
        _DialogField(
            date, 'MM-DD (yearly) or YYYY-MM-DD', TextInputType.datetime),
        _DialogField(label, 'Label (e.g. New Year\'s Eve)', TextInputType.text),
        _DialogField(pct, 'Adjustment % (e.g. 50)',
            const TextInputType.numberWithOptions(decimal: true, signed: true)),
      ],
    );
    final d = date.text.trim();
    final lbl = label.text.trim();
    final p = double.tryParse(pct.text.trim());
    date.dispose();
    label.dispose();
    pct.dispose();
    final valid = RegExp(r'^(\d{4}-)?\d{2}-\d{2}$').hasMatch(d);
    if (ok != true || !valid || p == null) return;
    final item =
        SpecialDate(date: d, label: lbl, multiplier: percentToMultiplier(p));
    final l = List<SpecialDate>.from(_s.specialDates);
    index == null ? l.add(item) : l[index] = item;
    _update(_s.copyWith(specialDates: l));
  }

  Future<bool?> _fieldsDialog({
    required String title,
    required List<_DialogField> fields,
  }) {
    return showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title),
        content: Column(
          children: [
            const SizedBox(height: 8),
            for (final f in fields)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: CupertinoTextField(
                  controller: f.controller,
                  placeholder: f.placeholder,
                  keyboardType: f.keyboardType,
                ),
              ),
          ],
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  static String _uniqueKey(String name, Iterable<String> taken) {
    final base = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final root = base.isEmpty ? 'addon' : base;
    final used = taken.toSet();
    var key = root;
    var n = 2;
    while (used.contains(key)) {
      key = '${root}_$n';
      n++;
    }
    return key;
  }
}

class _DialogField {
  const _DialogField(this.controller, this.placeholder, this.keyboardType);
  final TextEditingController controller;
  final String placeholder;
  final TextInputType keyboardType;
}

// ── Row widgets ───────────────────────────────────────────────────────────────

/// Label + right-aligned numeric field. Owns its controller; [onChanged] gets
/// the parsed number (null when the field is empty/unparseable).
class _NumRow extends StatefulWidget {
  const _NumRow({
    super.key,
    required this.label,
    required this.initial,
    required this.onChanged,
    this.suffix,
    this.prefix,
    this.signed = false,
  });

  final String label;
  final String initial;
  final String? suffix;
  final String? prefix;
  final bool signed;
  final ValueChanged<double?> onChanged;

  @override
  State<_NumRow> createState() => _NumRowState();
}

class _NumRowState extends State<_NumRow> {
  late final TextEditingController _c =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoFormRow(
      prefix: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 150),
        child: Text(widget.label, maxLines: 2, overflow: TextOverflow.ellipsis),
      ),
      child: SizedBox(
        width: 96,
        child: CupertinoTextField(
          controller: _c,
          textAlign: TextAlign.end,
          decoration: null,
          prefix: widget.prefix == null
              ? null
              : Text(widget.prefix!,
                  style: TextStyle(color: context.secondaryText)),
          suffix: widget.suffix == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(widget.suffix!,
                      style: TextStyle(color: context.secondaryText)),
                ),
          keyboardType: TextInputType.numberWithOptions(
              decimal: true, signed: widget.signed),
          onChanged: (t) => widget.onChanged(double.tryParse(t.trim())),
        ),
      ),
    );
  }
}

class _BaseRateRow extends StatefulWidget {
  const _BaseRateRow({
    super.key,
    required this.name,
    required this.history,
    required this.value,
    required this.onChanged,
  });

  final String name;
  final PricingHistoryEntry? history;
  final double? value;
  final ValueChanged<double?> onChanged;

  @override
  State<_BaseRateRow> createState() => _BaseRateRowState();
}

class _BaseRateRowState extends State<_BaseRateRow> {
  late final TextEditingController _c = TextEditingController(
      text: widget.value == null ? '' : trimNumber(widget.value!));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.history;
    final learned = (h == null || h.baseline == null)
        ? 'No history yet'
        : 'Learned ${formatMoney(h.baseline!)} · ${h.sampleSize} '
            '${h.sampleSize == 1 ? 'booking' : 'bookings'}';
    return CupertinoFormRow(
      prefix: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 170),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(learned,
                style: TextStyle(fontSize: 12, color: context.secondaryText)),
          ],
        ),
      ),
      child: SizedBox(
        width: 90,
        child: CupertinoTextField(
          controller: _c,
          textAlign: TextAlign.end,
          decoration: null,
          placeholder: 'Auto',
          prefix: Text(r'$', style: TextStyle(color: context.secondaryText)),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (t) {
            final v = double.tryParse(t.trim());
            widget.onChanged(v != null && v > 0 ? v : null);
          },
        ),
      ),
    );
  }
}

class _ListTapRow extends StatelessWidget {
  const _ListTapRow({
    required this.title,
    this.subtitle,
    required this.trailing,
    required this.onTap,
    required this.onDelete,
  });

  final String title;
  final String? subtitle;
  final String trailing;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return CupertinoListTile(
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      additionalInfo: Text(trailing),
      trailing: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size(32, 32),
        onPressed: onDelete,
        child: Icon(CupertinoIcons.minus_circle_fill,
            size: 22, color: CupertinoColors.systemRed.resolveFrom(context)),
      ),
      onTap: onTap,
    );
  }
}

class _AddRow extends StatelessWidget {
  const _AddRow({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => CupertinoListTile(
        leading: Icon(CupertinoIcons.add_circled_solid,
            color: CupertinoColors.systemGreen.resolveFrom(context)),
        title: Text(label),
        onTap: onTap,
      );
}
