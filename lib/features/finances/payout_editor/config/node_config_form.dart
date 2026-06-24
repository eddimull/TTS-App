// Per-node-type configuration forms for the payout flow editor.
//
// Keepable (not throwaway): these forms are the real config UI for the native
// payout editor. They edit a node's `data` map in place. Covers all
// scalar/enum/toggle fields per node type; nested list fields
// (memberAllocations, roleSlots, tierConfig, specificMembers) are surfaced as
// deferred placeholders — their dedicated row editors are a follow-up.
//
// Field set and enums mirror the web editor's schema
// (resources/js/composables/useFlowNodeSchemas.js in the TTS repo).

import 'package:flutter/cupertino.dart';

/// Enum option sets, mirrored from the web schema.
class PayoutNodeOptions {
  static const cutTypes = ['percentage', 'fixed', 'tiered'];

  static const conditionTypes = [
    'bookingPrice',
    'eventCount',
    'eventType',
    'dayOfWeek',
    'memberCount',
    'eventMultiplier',
  ];

  /// Operators valid per condition type (eventType/dayOfWeek are equality-only).
  static List<String> operatorsFor(String conditionType) {
    switch (conditionType) {
      case 'eventType':
      case 'dayOfWeek':
        return const ['==', '!='];
      default:
        return const ['>', '<', '>=', '<=', '==', '!='];
    }
  }

  static const eventTypes = ['performance', 'rehearsal', 'recording', 'other'];
  static const daysOfWeek = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];

  static const sourceTypes = [
    'roster', 'paymentGroup', 'specific', 'roles', 'allMembers',
  ];
  static const distributionModes = [
    'equal_split', 'percentage', 'fixed', 'tiered', 'weighted',
  ];
  static const incomingAllocationTypes = ['remainder', 'percentage', 'fixed'];
  static const memberTypeFilters = ['all', 'members_only', 'substitutes_only'];
}

/// A modal config form for a single node. Edits [data] in place; calls
/// [onChanged] after each edit so the host can repaint the node and persist.
class NodeConfigForm extends StatefulWidget {
  const NodeConfigForm({
    super.key,
    required this.nodeType,
    required this.data,
    required this.onChanged,
    this.onDelete,
  });

  final String nodeType;
  final Map<String, dynamic> data;
  final VoidCallback onChanged;
  final VoidCallback? onDelete;

  @override
  State<NodeConfigForm> createState() => _NodeConfigFormState();
}

class _NodeConfigFormState extends State<NodeConfigForm> {
  Map<String, dynamic> get _d => widget.data;

  void _set(String key, dynamic value) {
    setState(() => _d[key] = value);
    widget.onChanged();
  }

  void _setNested(String parent, String key, dynamic value) {
    final map = Map<String, dynamic>.from(_d[parent] as Map? ?? {});
    map[key] = value;
    setState(() => _d[parent] = map);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text('Configure ${widget.nodeType}'),
        trailing: widget.onDelete == null
            ? null
            : CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () {
                  Navigator.pop(context);
                  widget.onDelete!();
                },
                child: const Icon(
                  CupertinoIcons.delete,
                  color: CupertinoColors.destructiveRed,
                ),
              ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: _fieldsForType(),
        ),
      ),
    );
  }

  List<Widget> _fieldsForType() {
    switch (widget.nodeType) {
      case 'income':
        return [
          _TextField(label: 'Label', value: '${_d['label'] ?? ''}', onChanged: (v) => _set('label', v)),
          _NumberField(label: 'Amount (\$)', value: _d['amount'], onChanged: (v) => _set('amount', v)),
        ];
      case 'bandCut':
        return [
          _TextField(label: 'Label', value: '${_d['customLabel'] ?? ''}', onChanged: (v) => _set('customLabel', v)),
          _EnumField(label: 'Cut type', value: '${_d['cutType'] ?? 'percentage'}', options: PayoutNodeOptions.cutTypes, onChanged: (v) => _set('cutType', v)),
          if (_d['cutType'] != 'tiered')
            _NumberField(label: 'Value', value: _d['value'], onChanged: (v) => _set('value', v)),
          if (_d['cutType'] == 'tiered')
            const _DeferredField(label: 'Tier table', hint: 'tierConfig — list editor coming'),
        ];
      case 'conditional':
        final condType = '${_d['conditionType'] ?? 'bookingPrice'}';
        return [
          _TextField(label: 'Label', value: '${_d['label'] ?? ''}', onChanged: (v) => _set('label', v)),
          _EnumField(
            label: 'Condition type',
            value: condType,
            options: PayoutNodeOptions.conditionTypes,
            onChanged: (v) {
              // Reset operator if the new type doesn't allow the current one.
              final ops = PayoutNodeOptions.operatorsFor(v);
              if (!ops.contains(_d['operator'])) _d['operator'] = ops.first;
              _set('conditionType', v);
            },
          ),
          _EnumField(
            label: 'Operator',
            value: '${_d['operator'] ?? PayoutNodeOptions.operatorsFor(condType).first}',
            options: PayoutNodeOptions.operatorsFor(condType),
            onChanged: (v) => _set('operator', v),
          ),
          _valueFieldForCondition(condType),
        ];
      case 'payoutGroup':
        return _payoutGroupFields();
      default:
        return [_TextField(label: 'Label', value: '${_d['label'] ?? ''}', onChanged: (v) => _set('label', v))];
    }
  }

  Widget _valueFieldForCondition(String condType) {
    switch (condType) {
      case 'eventType':
        return _EnumField(label: 'Value', value: '${_d['value'] ?? PayoutNodeOptions.eventTypes.first}', options: PayoutNodeOptions.eventTypes, onChanged: (v) => _set('value', v));
      case 'dayOfWeek':
        return _EnumField(label: 'Value', value: '${_d['value'] ?? PayoutNodeOptions.daysOfWeek.first}', options: PayoutNodeOptions.daysOfWeek, onChanged: (v) => _set('value', v));
      default:
        return _NumberField(label: 'Value', value: _d['value'], onChanged: (v) => _set('value', v));
    }
  }

  List<Widget> _payoutGroupFields() {
    final sourceType = '${_d['sourceType'] ?? 'roster'}';
    final distMode = '${_d['distributionMode'] ?? 'equal_split'}';
    final incomingType = '${_d['incomingAllocationType'] ?? 'remainder'}';
    final allMembers = Map<String, dynamic>.from(_d['allMembersConfig'] as Map? ?? {});
    final roster = Map<String, dynamic>.from(_d['rosterConfig'] as Map? ?? {});

    return [
      _TextField(label: 'Label', value: '${_d['label'] ?? ''}', onChanged: (v) => _set('label', v)),
      const _SectionHeader('Source'),
      _EnumField(label: 'Source type', value: sourceType, options: PayoutNodeOptions.sourceTypes, onChanged: (v) => _set('sourceType', v)),

      if (sourceType == 'allMembers') ...[
        _ToggleField(label: 'Include owners', value: allMembers['includeOwners'] == true, onChanged: (v) => _setNested('allMembersConfig', 'includeOwners', v)),
        _ToggleField(label: 'Include members', value: allMembers['includeMembers'] == true, onChanged: (v) => _setNested('allMembersConfig', 'includeMembers', v)),
        _ToggleField(label: 'Include production', value: allMembers['includeProduction'] == true, onChanged: (v) => _setNested('allMembersConfig', 'includeProduction', v)),
        if (allMembers['includeProduction'] == true)
          _NumberField(label: 'Production count', value: allMembers['productionCount'], onChanged: (v) => _setNested('allMembersConfig', 'productionCount', v)),
      ],
      if (sourceType == 'roster') ...[
        _ToggleField(label: 'Weight by attendance', value: roster['useAttendanceWeighting'] != false, onChanged: (v) => _setNested('rosterConfig', 'useAttendanceWeighting', v)),
        _EnumField(label: 'Member type', value: '${roster['memberTypeFilter'] ?? 'all'}', options: PayoutNodeOptions.memberTypeFilters, onChanged: (v) => _setNested('rosterConfig', 'memberTypeFilter', v)),
        _NumberField(label: 'Min events to qualify', value: roster['minEventsToQualify'], onChanged: (v) => _setNested('rosterConfig', 'minEventsToQualify', v)),
      ],
      if (sourceType == 'paymentGroup')
        _NumberField(label: 'Payment group ID', value: _d['paymentGroupId'], onChanged: (v) => _set('paymentGroupId', v)),
      if (sourceType == 'specific')
        const _DeferredField(label: 'Specific members', hint: 'specificMembers — list editor coming'),
      if (sourceType == 'roles')
        const _DeferredField(label: 'Role slots', hint: 'roleSlots — list editor coming'),

      const _SectionHeader('Incoming allocation'),
      _EnumField(label: 'Type', value: incomingType, options: PayoutNodeOptions.incomingAllocationTypes, onChanged: (v) => _set('incomingAllocationType', v)),
      if (incomingType != 'remainder')
        _NumberField(label: incomingType == 'percentage' ? 'Percent (%)' : 'Amount (\$)', value: _d['incomingAllocationValue'], onChanged: (v) => _set('incomingAllocationValue', v)),

      const _SectionHeader('Distribution'),
      _EnumField(label: 'Mode', value: distMode, options: PayoutNodeOptions.distributionModes, onChanged: (v) => _set('distributionMode', v)),
      if (distMode == 'percentage' || distMode == 'fixed' || distMode == 'weighted')
        const _DeferredField(label: 'Per-member allocations', hint: 'memberAllocations — list editor coming'),
      if (distMode == 'tiered')
        const _DeferredField(label: 'Tier table', hint: 'tierConfig — list editor coming'),

      const _SectionHeader('Overrides'),
      _ToggleField(label: 'Respect custom payouts', value: _d['respectCustomPayouts'] != false, onChanged: (v) => _set('respectCustomPayouts', v)),
      _NumberField(label: 'Minimum payout (\$)', value: _d['minimumPayout'], onChanged: (v) => _set('minimumPayout', v)),
    ];
  }
}

// ── Reusable Cupertino field building blocks ─────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 6),
        child: Text(title.toUpperCase(),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: CupertinoColors.systemGrey)),
      );
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.label, required this.child});
  final String label;
  final Widget child;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(flex: 4, child: Text(label, style: const TextStyle(fontSize: 15))),
            Expanded(flex: 5, child: child),
          ],
        ),
      );
}

class _TextField extends StatelessWidget {
  const _TextField({required this.label, required this.value, required this.onChanged});
  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => _FieldRow(
        label: label,
        child: CupertinoTextField(
          controller: TextEditingController(text: value),
          onSubmitted: onChanged,
          onChanged: onChanged,
        ),
      );
}

class _NumberField extends StatelessWidget {
  const _NumberField({required this.label, required this.value, required this.onChanged});
  final String label;
  final dynamic value;
  final ValueChanged<num> onChanged;
  @override
  Widget build(BuildContext context) => _FieldRow(
        label: label,
        child: CupertinoTextField(
          controller: TextEditingController(text: '${value ?? ''}'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (raw) {
            final n = num.tryParse(raw.trim());
            if (n != null) onChanged(n);
          },
        ),
      );
}

class _ToggleField extends StatelessWidget {
  const _ToggleField({required this.label, required this.value, required this.onChanged});
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => _FieldRow(
        label: label,
        child: Align(
          alignment: Alignment.centerRight,
          child: CupertinoSwitch(value: value, onChanged: onChanged),
        ),
      );
}

class _EnumField extends StatelessWidget {
  const _EnumField({required this.label, required this.value, required this.options, required this.onChanged});
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => _FieldRow(
        label: label,
        child: CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          color: CupertinoColors.tertiarySystemFill,
          onPressed: () => _pick(context),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(child: Text(value, style: const TextStyle(fontSize: 14, color: CupertinoColors.label), overflow: TextOverflow.ellipsis)),
              const Icon(CupertinoIcons.chevron_up_chevron_down, size: 16, color: CupertinoColors.systemGrey),
            ],
          ),
        ),
      );

  void _pick(BuildContext context) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetCtx) => CupertinoActionSheet(
        title: Text(label),
        actions: [
          for (final o in options)
            CupertinoActionSheetAction(
              onPressed: () {
                onChanged(o);
                Navigator.pop(sheetCtx);
              },
              child: Text(o, style: TextStyle(fontWeight: o == value ? FontWeight.bold : FontWeight.normal)),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetCtx),
          child: const Text('Cancel'),
        ),
      ),
    );
  }
}

/// Placeholder for nested-list fields whose dedicated row editor is a follow-up.
class _DeferredField extends StatelessWidget {
  const _DeferredField({required this.label, required this.hint});
  final String label;
  final String hint;
  @override
  Widget build(BuildContext context) => _FieldRow(
        label: label,
        child: Text(hint,
            style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: CupertinoColors.systemGrey)),
      );
}
