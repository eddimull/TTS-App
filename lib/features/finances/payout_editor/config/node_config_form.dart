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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tts_bandmate/features/personnel/providers/roles_provider.dart';

import '../providers/payout_flow_provider.dart';
import 'guided_config_scaffold.dart';
import 'node_list_fields.dart';

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

  /// Human-readable labels for raw enum values (mirrors the web schema's
  /// `label:` fields). Falls back to the raw value when unmapped.
  static const Map<String, String> labels = {
    // condition types
    'bookingPrice': 'Booking Price',
    'eventCount': 'Event Count',
    'eventType': 'Event Type',
    'dayOfWeek': 'Day of Week',
    'memberCount': 'Member Count',
    'eventMultiplier': 'Event Value Multiplier',
    // operators
    '>': 'Greater than (>)',
    '<': 'Less than (<)',
    '>=': 'At least (≥)',
    '<=': 'At most (≤)',
    '==': 'Equals (=)',
    '!=': 'Not equal (≠)',
    // cut / distribution / allocation
    'percentage': 'Percentage',
    'fixed': 'Fixed amount',
    'tiered': 'Tiered',
    'equal_split': 'Equal split',
    'weighted': 'Weighted',
    'remainder': 'Remainder',
    // source types
    'roster': 'Roster',
    'paymentGroup': 'Payment group',
    'specific': 'Specific members',
    'roles': 'Role slots',
    'allMembers': 'All members',
    // member type filter
    'all': 'All',
    'members_only': 'Members only',
    'substitutes_only': 'Substitutes only',
    // event types
    'performance': 'Performance',
    'rehearsal': 'Rehearsal',
    'recording': 'Recording',
    'other': 'Other',
  };

  /// Display label for a raw value (days of week and unmapped values pass through).
  static String labelFor(String value) => labels[value] ?? value;
}

/// A modal config form for a single node. Edits [data] in place; calls
/// [onChanged] after each edit so the host can repaint the node and persist.
class NodeConfigForm extends ConsumerStatefulWidget {
  const NodeConfigForm({
    super.key,
    required this.bandId,
    required this.nodeType,
    required this.data,
    required this.onChanged,
    this.onDelete,
    this.previewValues,
  });

  final int bandId;
  final String nodeType;
  final Map<String, dynamic> data;
  final VoidCallback onChanged;
  final VoidCallback? onDelete;

  /// This node's computed values from the preview API (input/output/allocated/
  /// perMember/memberCount/bandCut), or null when not yet available.
  final Map<String, dynamic>? previewValues;

  @override
  ConsumerState<NodeConfigForm> createState() => _NodeConfigFormState();
}

class _NodeConfigFormState extends ConsumerState<NodeConfigForm> {
  Map<String, dynamic> get _d => widget.data;

  String _friendlyType(String type) => const {
        'income': 'Income',
        'bandCut': 'Band Cut',
        'conditional': 'Condition',
        'payoutGroup': 'Payout Group',
      }[type] ?? type;

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
    // Prefer the node's own label; fall back to a friendly type name.
    final title = (widget.data['label'] as String?)?.trim().isNotEmpty == true
        ? widget.data['label'] as String
        : _friendlyType(widget.nodeType);
    return GuidedConfigScaffold(
      title: title,
      trailing: widget.onDelete == null
          ? null
          : CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () {
                Navigator.pop(context);
                widget.onDelete!();
              },
              child: const Icon(CupertinoIcons.delete,
                  color: CupertinoColors.destructiveRed),
            ),
      preview: _previewBar(),
      steps: _stepsForType(),
    );
  }

  PreviewBar _previewBar() {
    final v = widget.previewValues;
    String money(dynamic n) {
      final d = (n as num?)?.toDouble() ?? 0;
      return '\$${d.toStringAsFixed(d.truncateToDouble() == d ? 0 : 2)}';
    }

    switch (widget.nodeType) {
      case 'payoutGroup':
        final mc = v?['memberCount'];
        return PreviewBar(
          label: 'Each member gets',
          value: v == null
              ? null
              : '${money(v['perMember'])}${mc != null ? ' · $mc people' : ''}',
        );
      case 'bandCut':
        return PreviewBar(label: 'To members', value: v == null ? null : money(v['output']));
      case 'income':
        return PreviewBar(label: 'Output', value: v == null ? null : money(v['output']));
      default:
        return PreviewBar(label: 'Input', value: v == null ? null : money(v['input']));
    }
  }

  List<ConfigStep> _stepsForType() {
    switch (widget.nodeType) {
      case 'payoutGroup':
        return _payoutGroupSteps();
      case 'income':
        return [
          ConfigStep(
            tab: 'Income',
            question: 'How much income?',
            subtitle: 'The money entering this flow.',
            builder: (_) => Column(children: [
              _activeToggle(),
              _TextField(label: 'Label', value: '${_d['label'] ?? ''}', onChanged: (v) => _set('label', v)),
              _NumberField(label: 'Amount (\$)', value: _d['amount'], onChanged: (v) => _set('amount', v)),
            ]),
          ),
        ];
      case 'bandCut':
        return [
          ConfigStep(
            tab: 'The cut',
            question: "What's the band's cut?",
            subtitle: 'Taken before members are paid.',
            builder: (_) => Column(children: [
              _activeToggle(),
              _TextField(label: 'Label', value: '${_d['customLabel'] ?? ''}', onChanged: (v) => _set('customLabel', v)),
              OptionCardGroup(
                selected: '${_d['cutType'] ?? 'percentage'}',
                options: kCutSpecs,
                onSelect: (v) => _set('cutType', v),
              ),
              if (_d['cutType'] != 'tiered')
                _NumberField(label: 'Value', value: _d['value'], onChanged: (v) => _set('value', v)),
              if (_d['cutType'] == 'tiered')
                TierConfigField(data: _d, onChanged: widget.onChanged),
            ]),
          ),
        ];
      case 'conditional':
        final condType = '${_d['conditionType'] ?? 'bookingPrice'}';
        return [
          ConfigStep(
            tab: 'Condition',
            question: 'When does this apply?',
            subtitle: 'Routes to TRUE or FALSE based on the booking.',
            builder: (_) => Column(children: [
              _activeToggle(),
              _TextField(label: 'Label', value: '${_d['label'] ?? ''}', onChanged: (v) => _set('label', v)),
              _EnumRow(label: 'If', value: condType, options: PayoutNodeOptions.conditionTypes, onChanged: (v) {
                // Reset operator if the new type doesn't allow the current one.
                final ops = PayoutNodeOptions.operatorsFor(v);
                if (!ops.contains(_d['operator'])) _d['operator'] = ops.first;
                _set('conditionType', v);
              }),
              _EnumRow(
                label: 'Is',
                value: '${_d['operator'] ?? PayoutNodeOptions.operatorsFor(condType).first}',
                options: PayoutNodeOptions.operatorsFor(condType),
                onChanged: (v) => _set('operator', v),
              ),
              _valueFieldForCondition(condType),
            ]),
          ),
        ];
      default:
        return [
          ConfigStep(
            tab: 'Config',
            question: 'Settings',
            subtitle: '',
            builder: (_) => _TextField(label: 'Label', value: '${_d['label'] ?? ''}', onChanged: (v) => _set('label', v)),
          ),
        ];
    }
  }

  Widget _activeToggle() => _ToggleField(
        label: 'Node active',
        value: _d['deactivated'] != true,
        onChanged: (v) => _set('deactivated', !v),
      );

  Widget _valueFieldForCondition(String condType) {
    switch (condType) {
      case 'eventType':
        return _EnumRow(label: 'Value', value: '${_d['value'] ?? PayoutNodeOptions.eventTypes.first}', options: PayoutNodeOptions.eventTypes, onChanged: (v) => _set('value', v));
      case 'dayOfWeek':
        return _EnumRow(label: 'Value', value: '${_d['value'] ?? PayoutNodeOptions.daysOfWeek.first}', options: PayoutNodeOptions.daysOfWeek, onChanged: (v) => _set('value', v));
      default:
        return _NumberField(label: 'Value', value: _d['value'], onChanged: (v) => _set('value', v));
    }
  }

  List<ConfigStep> _payoutGroupSteps() {
    final sourceType = '${_d['sourceType'] ?? 'roster'}';
    final distMode = '${_d['distributionMode'] ?? 'equal_split'}';
    final incomingType = '${_d['incomingAllocationType'] ?? 'remainder'}';
    final allMembers = Map<String, dynamic>.from(_d['allMembersConfig'] as Map? ?? {});
    final roster = Map<String, dynamic>.from(_d['rosterConfig'] as Map? ?? {});

    return [
      ConfigStep(
        tab: 'Recipients',
        question: 'Who gets paid?',
        subtitle: "Choose where this group's people come from.",
        builder: (_) => Column(children: [
          _activeToggle(),
          _TextField(label: 'Label', value: '${_d['label'] ?? ''}', onChanged: (v) => _set('label', v)),
          OptionCardGroup(selected: sourceType, options: kSourceSpecs, onSelect: (v) => _set('sourceType', v)),
          if (sourceType == 'allMembers') ...[
            _ToggleField(label: 'Include owners', value: allMembers['includeOwners'] == true, onChanged: (v) => _setNested('allMembersConfig', 'includeOwners', v)),
            _ToggleField(label: 'Include members', value: allMembers['includeMembers'] == true, onChanged: (v) => _setNested('allMembersConfig', 'includeMembers', v)),
            _ToggleField(label: 'Include production', value: allMembers['includeProduction'] == true, onChanged: (v) => _setNested('allMembersConfig', 'includeProduction', v)),
            if (allMembers['includeProduction'] == true)
              _NumberField(label: 'Production count', value: allMembers['productionCount'], onChanged: (v) => _setNested('allMembersConfig', 'productionCount', v)),
          ],
          if (sourceType == 'roster') ...[
            _ToggleField(label: 'Weight by attendance', value: roster['useAttendanceWeighting'] != false, onChanged: (v) => _setNested('rosterConfig', 'useAttendanceWeighting', v)),
            _EnumRow(label: 'Member type', value: '${roster['memberTypeFilter'] ?? 'all'}', options: PayoutNodeOptions.memberTypeFilters, onChanged: (v) => _setNested('rosterConfig', 'memberTypeFilter', v)),
            _NumberField(label: 'Min events to qualify', value: roster['minEventsToQualify'], onChanged: (v) => _setNested('rosterConfig', 'minEventsToQualify', v)),
            _rosterRoleFilterField(),
          ],
          if (sourceType == 'paymentGroup')
            _NumberField(label: 'Payment group ID', value: _d['paymentGroupId'], onChanged: (v) => _set('paymentGroupId', v)),
          if (sourceType == 'specific') _specificMembersField(),
          if (sourceType == 'roles') _roleSlotsField(),
        ]),
      ),
      ConfigStep(
        tab: 'Take',
        question: 'How much does this group take?',
        subtitle: 'Out of the money flowing into this group.',
        builder: (_) => Column(children: [
          OptionCardGroup(selected: incomingType, options: kIncomingSpecs, onSelect: (v) => _set('incomingAllocationType', v)),
          if (incomingType != 'remainder')
            _NumberField(
              label: incomingType == 'percentage' ? 'Percent (%)' : 'Amount (\$)',
              value: _d['incomingAllocationValue'],
              onChanged: (v) => _set('incomingAllocationValue', v),
            ),
        ]),
      ),
      ConfigStep(
        tab: 'Split',
        question: 'How is it split?',
        subtitle: 'Among the people in this group.',
        builder: (_) => Column(children: [
          OptionCardGroup(selected: distMode, options: kDistributionSpecs, onSelect: (v) => _set('distributionMode', v)),
          // Fixed mode pays each member a flat amount (fixedAmountPerMember), so
          // it gets a single amount field — NOT the per-member allocation list
          // (which is for percentage/weighted splits).
          if (distMode == 'fixed')
            _NumberField(label: 'Fixed amount per member (\$)', value: _d['fixedAmountPerMember'], onChanged: (v) => _set('fixedAmountPerMember', v)),
          if (distMode == 'percentage' || distMode == 'weighted')
            _memberAllocationsField(),
          if (distMode == 'tiered')
            TierConfigField(data: _d, onChanged: widget.onChanged),
          _ToggleField(label: 'Respect custom payouts', value: _d['respectCustomPayouts'] != false, onChanged: (v) => _set('respectCustomPayouts', v)),
          _NumberField(label: 'Minimum payout (\$)', value: _d['minimumPayout'], onChanged: (v) => _set('minimumPayout', v)),
        ]),
      ),
    ];
  }

  // ── Async-backed list fields (members / roles loaded from the band) ────────

  /// Small loading/error stand-in while the band's members/roles load.
  Widget _loadingNote(String what) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          const CupertinoActivityIndicator(radius: 8),
          const SizedBox(width: 8),
          Text('Loading $what…',
              style: const TextStyle(fontSize: 13, color: CupertinoColors.systemGrey)),
        ]),
      );

  Widget _specificMembersField() {
    final async = ref.watch(payoutBandMembersProvider(widget.bandId));
    return async.when(
      loading: () => _loadingNote('members'),
      error: (_, __) => const Text('Could not load members',
          style: TextStyle(fontSize: 13, color: CupertinoColors.systemRed)),
      data: (members) => SpecificMembersField(
          data: _d, onChanged: widget.onChanged, members: members),
    );
  }

  Widget _memberAllocationsField() {
    final async = ref.watch(payoutBandMembersProvider(widget.bandId));
    return async.when(
      loading: () => _loadingNote('members'),
      error: (_, __) => const Text('Could not load members',
          style: TextStyle(fontSize: 13, color: CupertinoColors.systemRed)),
      data: (members) => MemberAllocationsField(
          data: _d, onChanged: widget.onChanged, members: members),
    );
  }

  Widget _roleSlotsField() {
    final async = ref.watch(rolesProvider(widget.bandId));
    return async.when(
      loading: () => _loadingNote('roles'),
      error: (_, __) => const Text('Could not load roles',
          style: TextStyle(fontSize: 13, color: CupertinoColors.systemRed)),
      data: (roles) =>
          RoleSlotsField(data: _d, onChanged: widget.onChanged, roles: roles),
    );
  }

  /// Role multi-select for the Roster source — pick which roles the payout
  /// goes to. Empty = all roles. Writes rosterConfig.filterByRoleId (the
  /// backend's preferred id-based filter).
  Widget _rosterRoleFilterField() {
    final async = ref.watch(rolesProvider(widget.bandId));
    return async.when(
      loading: () => _loadingNote('roles'),
      error: (_, __) => const Text('Could not load roles',
          style: TextStyle(fontSize: 13, color: CupertinoColors.systemRed)),
      data: (roles) => RosterRoleFilterField(
        data: _d,
        onChanged: widget.onChanged,
        roles: roles,
      ),
    );
  }
}

// ── Reusable Cupertino field building blocks ─────────────────────────────────

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

class _TextField extends StatefulWidget {
  const _TextField({required this.label, required this.value, required this.onChanged});
  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  @override
  State<_TextField> createState() => _TextFieldState();
}

class _TextFieldState extends State<_TextField> {
  // Persistent controller: created once so typing doesn't recreate it on every
  // parent rebuild (which would reset the caret to offset 0 — the cursor-jump
  // bug). The controller is the source of truth while editing.
  late final TextEditingController _c =
      TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(covariant _TextField old) {
    super.didUpdateWidget(old);
    // Only adopt an externally-changed value (not our own edits), and never
    // clobber the caret mid-type.
    if (widget.value != _c.text) _c.text = widget.value;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _FieldRow(
        label: widget.label,
        child: CupertinoTextField(
          controller: _c,
          onSubmitted: widget.onChanged,
          onChanged: widget.onChanged,
        ),
      );
}

class _NumberField extends StatefulWidget {
  const _NumberField({required this.label, required this.value, required this.onChanged});
  final String label;
  final dynamic value;
  final ValueChanged<num> onChanged;
  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _c =
      TextEditingController(text: '${widget.value ?? ''}');

  @override
  void didUpdateWidget(covariant _NumberField old) {
    super.didUpdateWidget(old);
    final incoming = '${widget.value ?? ''}';
    // Adopt external changes, but ignore reformatting of the same number the
    // user is currently typing (e.g. "5" vs 5) to avoid caret jumps.
    if (num.tryParse(_c.text.trim()) != widget.value && incoming != _c.text) {
      _c.text = incoming;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _FieldRow(
        label: widget.label,
        child: CupertinoTextField(
          controller: _c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (raw) {
            final n = num.tryParse(raw.trim());
            if (n != null) widget.onChanged(n);
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

class _EnumRow extends StatelessWidget {
  const _EnumRow({required this.label, required this.value, required this.options, required this.onChanged});
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    // Resolve dynamic colors against the current brightness — passing them
    // unresolved (as static constants) falls back to light-mode values, which
    // renders dark text on the dark fill in dark mode.
    final fill = CupertinoDynamicColor.resolve(
        CupertinoColors.tertiarySystemFill, context);
    final textColor =
        CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    return _FieldRow(
      label: label,
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        color: fill,
        onPressed: () => _pick(context),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
                child: Text(PayoutNodeOptions.labelFor(value),
                    style: TextStyle(fontSize: 14, color: textColor),
                    overflow: TextOverflow.ellipsis)),
            const Icon(CupertinoIcons.chevron_up_chevron_down,
                size: 16, color: CupertinoColors.systemGrey),
          ],
        ),
      ),
    );
  }

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
              child: Text(PayoutNodeOptions.labelFor(o), style: TextStyle(fontWeight: o == value ? FontWeight.bold : FontWeight.normal)),
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
