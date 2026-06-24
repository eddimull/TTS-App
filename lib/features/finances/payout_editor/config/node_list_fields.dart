// Inline add/remove-row editors for the nested-list fields in a payout node's
// `data`: tier tables, per-member allocations, role slots, and specific members.
// Each edits a List<Map> in place and calls onChanged so the host can persist +
// repaint. Member/role pickers reuse the band's existing members/roles data.

import 'package:flutter/cupertino.dart';
import 'package:tts_bandmate/features/band_settings/data/models/band_member.dart';
import 'package:tts_bandmate/features/personnel/data/models/band_role.dart';

/// Shared scaffolding for a labelled list of rows with an Add button.
class _ListSection extends StatelessWidget {
  const _ListSection({
    required this.title,
    required this.rows,
    required this.onAdd,
    this.addLabel = 'Add',
  });

  final String title;
  final List<Widget> rows;
  final VoidCallback onAdd;
  final String addLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 6),
          child: Text(title.toUpperCase(),
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: CupertinoColors.systemGrey)),
        ),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text('None yet',
                style: TextStyle(
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    color: CupertinoColors.systemGrey)),
          ),
        ...rows,
        Align(
          alignment: Alignment.centerLeft,
          child: CupertinoButton(
            padding: const EdgeInsets.symmetric(vertical: 6),
            onPressed: onAdd,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(CupertinoIcons.add_circled, size: 18),
              const SizedBox(width: 4),
              Text(addLabel),
            ]),
          ),
        ),
      ],
    );
  }
}

class _DeleteButton extends StatelessWidget {
  const _DeleteButton(this.onPressed);
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size(32, 32),
        onPressed: onPressed,
        child: const Icon(CupertinoIcons.minus_circle_fill,
            size: 20, color: CupertinoColors.destructiveRed),
      );
}

List<Map<String, dynamic>> _asRows(dynamic raw) =>
    (raw as List?)?.cast<Map<String, dynamic>>() ?? <Map<String, dynamic>>[];

// ── Tier table: [{min, max, type: percentage|fixed, value}] ──────────────────

class TierConfigField extends StatefulWidget {
  const TierConfigField({super.key, required this.data, required this.onChanged});
  final Map<String, dynamic> data;
  final VoidCallback onChanged;
  @override
  State<TierConfigField> createState() => _TierConfigFieldState();
}

class _TierConfigFieldState extends State<TierConfigField> {
  List<Map<String, dynamic>> get _rows => _asRows(widget.data['tierConfig']);

  void _commit(List<Map<String, dynamic>> rows) {
    setState(() => widget.data['tierConfig'] = rows);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return _ListSection(
      title: 'Tiers',
      addLabel: 'Add tier',
      onAdd: () => _commit([
        ...rows,
        {'min': 0, 'max': 0, 'type': 'percentage', 'value': 0},
      ]),
      rows: [
        for (var i = 0; i < rows.length; i++)
          Padding(
            key: ValueKey('tier-$i'),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Expanded(
                  child: _MiniNumber(
                      hint: 'Min',
                      value: rows[i]['min'],
                      onChanged: (v) {
                        rows[i]['min'] = v;
                        _commit(rows);
                      })),
              const SizedBox(width: 6),
              Expanded(
                  child: _MiniNumber(
                      hint: 'Max',
                      value: rows[i]['max'],
                      onChanged: (v) {
                        rows[i]['max'] = v;
                        _commit(rows);
                      })),
              const SizedBox(width: 6),
              _MiniEnum(
                value: '${rows[i]['type'] ?? 'percentage'}',
                options: const ['percentage', 'fixed'],
                onChanged: (v) {
                  rows[i]['type'] = v;
                  _commit(rows);
                },
              ),
              const SizedBox(width: 6),
              Expanded(
                  child: _MiniNumber(
                      hint: 'Value',
                      value: rows[i]['value'],
                      onChanged: (v) {
                        rows[i]['value'] = v;
                        _commit(rows);
                      })),
              _DeleteButton(() => _commit([...rows]..removeAt(i))),
            ]),
          ),
      ],
    );
  }
}

// ── Member allocations: [{identifier, type: percentage|fixed, value}] ────────

class MemberAllocationsField extends StatefulWidget {
  const MemberAllocationsField(
      {super.key, required this.data, required this.onChanged, required this.members});
  final Map<String, dynamic> data;
  final VoidCallback onChanged;
  final List<BandMember> members;
  @override
  State<MemberAllocationsField> createState() => _MemberAllocationsFieldState();
}

class _MemberAllocationsFieldState extends State<MemberAllocationsField> {
  List<Map<String, dynamic>> get _rows => _asRows(widget.data['memberAllocations']);

  void _commit(List<Map<String, dynamic>> rows) {
    setState(() => widget.data['memberAllocations'] = rows);
    widget.onChanged();
  }

  String _nameFor(String identifier) {
    final id = int.tryParse(identifier.replaceFirst('user_', ''));
    final m = widget.members.where((m) => m.id == id);
    return m.isEmpty ? identifier : m.first.name;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return _ListSection(
      title: 'Per-member allocations',
      addLabel: 'Add member',
      onAdd: () => _pickMember((member) => _commit([
            ...rows,
            {'identifier': 'user_${member.id}', 'type': 'percentage', 'value': 0},
          ])),
      rows: [
        for (var i = 0; i < rows.length; i++)
          Padding(
            key: ValueKey('alloc-$i'),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Expanded(
                  flex: 3,
                  child: Text(_nameFor('${rows[i]['identifier']}'),
                      style: const TextStyle(fontSize: 14),
                      overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 6),
              _MiniEnum(
                value: '${rows[i]['type'] ?? 'percentage'}',
                options: const ['percentage', 'fixed'],
                onChanged: (v) {
                  rows[i]['type'] = v;
                  _commit(rows);
                },
              ),
              const SizedBox(width: 6),
              Expanded(
                  flex: 2,
                  child: _MiniNumber(
                      hint: 'Value',
                      value: rows[i]['value'],
                      onChanged: (v) {
                        rows[i]['value'] = v;
                        _commit(rows);
                      })),
              _DeleteButton(() => _commit([...rows]..removeAt(i))),
            ]),
          ),
      ],
    );
  }

  void _pickMember(ValueChanged<BandMember> onPick) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetCtx) => CupertinoActionSheet(
        title: const Text('Add member'),
        actions: [
          for (final m in widget.members)
            CupertinoActionSheetAction(
              onPressed: () {
                onPick(m);
                Navigator.pop(sheetCtx);
              },
              child: Text(m.name),
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

// ── Role slots: [{role, required: bool, fallbackToRoster: bool}] ─────────────

class RoleSlotsField extends StatefulWidget {
  const RoleSlotsField(
      {super.key, required this.data, required this.onChanged, required this.roles});
  final Map<String, dynamic> data;
  final VoidCallback onChanged;
  final List<BandRole> roles;
  @override
  State<RoleSlotsField> createState() => _RoleSlotsFieldState();
}

class _RoleSlotsFieldState extends State<RoleSlotsField> {
  List<Map<String, dynamic>> get _rows => _asRows(widget.data['roleSlots']);

  void _commit(List<Map<String, dynamic>> rows) {
    setState(() => widget.data['roleSlots'] = rows);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return _ListSection(
      title: 'Role slots',
      addLabel: 'Add role',
      onAdd: () => _pickRole((role) => _commit([
            ...rows,
            {'role': role.name, 'required': true, 'fallbackToRoster': true},
          ])),
      rows: [
        for (var i = 0; i < rows.length; i++)
          Padding(
            key: ValueKey('role-$i'),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Expanded(
                  child: Text('${rows[i]['role']}',
                      style: const TextStyle(fontSize: 14),
                      overflow: TextOverflow.ellipsis)),
              const Text('Req', style: TextStyle(fontSize: 12, color: CupertinoColors.systemGrey)),
              CupertinoSwitch(
                value: rows[i]['required'] != false,
                onChanged: (v) {
                  rows[i]['required'] = v;
                  _commit(rows);
                },
              ),
              _DeleteButton(() => _commit([...rows]..removeAt(i))),
            ]),
          ),
      ],
    );
  }

  void _pickRole(ValueChanged<BandRole> onPick) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetCtx) => CupertinoActionSheet(
        title: const Text('Add role'),
        actions: [
          for (final r in widget.roles)
            CupertinoActionSheetAction(
              onPressed: () {
                onPick(r);
                Navigator.pop(sheetCtx);
              },
              child: Text(r.name),
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

// ── Roster role filter: rosterConfig.filterByRoleId = [roleId, ...] ──────────
// Multi-select of band roles; empty = all roles (no filter).

class RosterRoleFilterField extends StatefulWidget {
  const RosterRoleFilterField(
      {super.key, required this.data, required this.onChanged, required this.roles});
  final Map<String, dynamic> data;
  final VoidCallback onChanged;
  final List<BandRole> roles;
  @override
  State<RosterRoleFilterField> createState() => _RosterRoleFilterFieldState();
}

class _RosterRoleFilterFieldState extends State<RosterRoleFilterField> {
  Map<String, dynamic> get _roster =>
      Map<String, dynamic>.from(widget.data['rosterConfig'] as Map? ?? {});

  Set<int> get _selected {
    final raw = (_roster['filterByRoleId'] as List?) ?? const [];
    return raw.map((e) => e as int).toSet();
  }

  void _toggle(int roleId) {
    final sel = _selected;
    sel.contains(roleId) ? sel.remove(roleId) : sel.add(roleId);
    final roster = _roster..['filterByRoleId'] = sel.toList();
    setState(() => widget.data['rosterConfig'] = roster);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final sel = _selected;
    final accent = CupertinoColors.activeBlue.resolveFrom(context);
    final chipBg = CupertinoDynamicColor.resolve(
        CupertinoColors.tertiarySystemFill, context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 18, bottom: 2),
          child: Text('ROLES (PAY ONLY THESE)',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: CupertinoColors.systemGrey)),
        ),
        const Padding(
          padding: EdgeInsets.only(bottom: 6),
          child: Text('None selected = all roles',
              style: TextStyle(fontSize: 12, color: CupertinoColors.systemGrey)),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final role in widget.roles)
              GestureDetector(
                onTap: () => _toggle(role.id),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: sel.contains(role.id)
                        ? accent.withValues(alpha: 0.18)
                        : chipBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: sel.contains(role.id)
                          ? accent
                          : CupertinoColors.separator.resolveFrom(context),
                    ),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (sel.contains(role.id)) ...[
                      Icon(CupertinoIcons.check_mark, size: 14, color: accent),
                      const SizedBox(width: 4),
                    ],
                    Text(role.name,
                        style: TextStyle(
                            fontSize: 14,
                            color: sel.contains(role.id)
                                ? accent
                                : CupertinoDynamicColor.resolve(
                                    CupertinoColors.label, context))),
                  ]),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// ── Specific members: [{user_id, roster_member_id, name}] ────────────────────

class SpecificMembersField extends StatefulWidget {
  const SpecificMembersField(
      {super.key, required this.data, required this.onChanged, required this.members});
  final Map<String, dynamic> data;
  final VoidCallback onChanged;
  final List<BandMember> members;
  @override
  State<SpecificMembersField> createState() => _SpecificMembersFieldState();
}

class _SpecificMembersFieldState extends State<SpecificMembersField> {
  List<Map<String, dynamic>> get _rows => _asRows(widget.data['specificMembers']);

  void _commit(List<Map<String, dynamic>> rows) {
    setState(() => widget.data['specificMembers'] = rows);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final chosen = rows.map((r) => r['user_id']).toSet();
    return _ListSection(
      title: 'Specific members',
      addLabel: 'Add member',
      onAdd: () => _pickMember(
        chosen,
        (m) => _commit([
          ...rows,
          {'user_id': m.id, 'roster_member_id': null, 'name': m.name},
        ]),
      ),
      rows: [
        for (var i = 0; i < rows.length; i++)
          Padding(
            key: ValueKey('specific-$i'),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Expanded(
                  child: Text('${rows[i]['name']}',
                      style: const TextStyle(fontSize: 14),
                      overflow: TextOverflow.ellipsis)),
              _DeleteButton(() => _commit([...rows]..removeAt(i))),
            ]),
          ),
      ],
    );
  }

  void _pickMember(Set<dynamic> exclude, ValueChanged<BandMember> onPick) {
    final available = widget.members.where((m) => !exclude.contains(m.id)).toList();
    showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetCtx) => CupertinoActionSheet(
        title: const Text('Add member'),
        actions: [
          for (final m in available)
            CupertinoActionSheetAction(
              onPressed: () {
                onPick(m);
                Navigator.pop(sheetCtx);
              },
              child: Text(m.name),
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

// ── Small inline inputs ──────────────────────────────────────────────────────

class _MiniNumber extends StatefulWidget {
  const _MiniNumber({required this.hint, required this.value, required this.onChanged});
  final String hint;
  final dynamic value;
  final ValueChanged<num> onChanged;
  @override
  State<_MiniNumber> createState() => _MiniNumberState();
}

class _MiniNumberState extends State<_MiniNumber> {
  late final TextEditingController _c =
      TextEditingController(text: '${widget.value ?? ''}');
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CupertinoTextField(
        controller: _c,
        placeholder: widget.hint,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: const TextStyle(fontSize: 13),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        onChanged: (raw) {
          final n = num.tryParse(raw.trim());
          if (n != null) widget.onChanged(n);
        },
      );
}

class _MiniEnum extends StatelessWidget {
  const _MiniEnum({required this.value, required this.options, required this.onChanged});
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) {
    final fill = CupertinoDynamicColor.resolve(
        CupertinoColors.tertiarySystemFill, context);
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      color: fill,
      minimumSize: const Size(0, 0),
      onPressed: () => showCupertinoModalPopup<void>(
        context: context,
        builder: (sheetCtx) => CupertinoActionSheet(
          actions: [
            for (final o in options)
              CupertinoActionSheetAction(
                onPressed: () {
                  onChanged(o);
                  Navigator.pop(sheetCtx);
                },
                child: Text(o),
              ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(sheetCtx),
            child: const Text('Cancel'),
          ),
        ),
      ),
      child: Text(value == 'percentage' ? '%' : (value == 'fixed' ? '\$' : value),
          style: TextStyle(
              fontSize: 13,
              color: CupertinoDynamicColor.resolve(CupertinoColors.label, context))),
    );
  }
}
