import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';
import 'package:tts_bandmate/shared/widgets/error_view.dart';

import '../../../shared/providers/selected_band_provider.dart';
import '../../personnel/data/models/roster.dart';
import '../data/models/song.dart';
import '../data/songs_repository.dart';
import '../providers/songs_provider.dart';

/// Full-screen modal form for creating ([existing] == null) or editing a
/// song, following the booking_form_screen.dart create/edit pattern.
/// Pops with the saved [Song] on success.
class SongFormScreen extends ConsumerStatefulWidget {
  const SongFormScreen({super.key, this.existing});

  final Song? existing;

  @override
  ConsumerState<SongFormScreen> createState() => _SongFormScreenState();
}

class _SongFormScreenState extends ConsumerState<SongFormScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _artistController;
  late final TextEditingController _keyController;
  late final TextEditingController _bpmController;
  late final TextEditingController _notesController;

  String _genre = '';
  int? _rating;
  int? _energy;
  bool _active = true;
  SongLeadSinger? _leadSinger;
  SongRef? _transitionSong;

  bool _isSaving = false;
  bool _isLookingUp = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _titleController = TextEditingController(text: existing?.title ?? '');
    _artistController = TextEditingController(text: existing?.artist ?? '');
    _keyController = TextEditingController(text: existing?.songKey ?? '');
    _bpmController = TextEditingController(
        text: (existing?.bpm ?? 0) > 0 ? existing!.bpm.toString() : '');
    _notesController = TextEditingController(text: existing?.notes ?? '');
    _genre = existing?.genre ?? '';
    _rating = existing?.rating;
    _energy = existing?.energy;
    _active = existing?.active ?? true;
    _leadSinger = existing?.leadSinger;
    _transitionSong = existing?.transitionSong;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    _keyController.dispose();
    _bpmController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  bool get _canSave => _titleController.text.trim().isNotEmpty && !_isSaving;

  Song _buildSong() {
    final bandId =
        widget.existing?.bandId ?? ref.read(selectedBandProvider).value ?? 0;
    return Song(
      id: widget.existing?.id ?? 0,
      bandId: bandId,
      title: _titleController.text.trim(),
      artist: _artistController.text.trim(),
      songKey: _keyController.text.trim(),
      genre: _genre,
      bpm: int.tryParse(_bpmController.text.trim()) ?? 0,
      notes: _notesController.text.trim(),
      rating: _rating,
      energy: _energy,
      active: _active,
      leadSinger: _leadSinger,
      transitionSong: _transitionSong,
      charts: widget.existing?.charts ?? const [],
    );
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      final draft = _buildSong();
      final saved = _isEdit
          ? await ref.read(songsProvider.notifier).updateSong(draft)
          : await ref.read(songsProvider.notifier).createSong(draft);
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _error = ErrorView.friendlyMessage(e);
      });
    }
  }

  Future<void> _lookupBpm() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Enter a title before looking up the BPM.');
      return;
    }
    setState(() {
      _isLookingUp = true;
      _error = null;
    });
    try {
      final result = await ref.read(songsRepositoryProvider).lookupBpm(
            title: title,
            artist: _artistController.text.trim(),
          );
      final bpm = (result['bpm'] as num?)?.toInt();
      final key = result['song_key'] as String?;
      if (!mounted) return;
      setState(() {
        if (bpm != null) _bpmController.text = bpm.toString();
        if (key != null &&
            key.isNotEmpty &&
            _keyController.text.trim().isEmpty) {
          _keyController.text = key;
        }
        if (bpm == null) _error = 'No BPM found for "$title".';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ErrorView.friendlyMessage(e));
    } finally {
      if (mounted) setState(() => _isLookingUp = false);
    }
  }

  // ── Pickers ─────────────────────────────────────────────────────────────────

  Future<void> _pickGenre() async {
    final genres = ref.read(songsProvider).value?.genres ?? const <String>[];
    final result = await _showListPicker<String>(
      context,
      title: 'Genre',
      options: genres,
      labelOf: (g) => g,
    );
    if (result != null) setState(() => _genre = result.value ?? '');
  }

  Future<void> _pickLeadSinger() async {
    final members = await ref.read(leadSingerOptionsProvider.future);
    if (!mounted) return;
    final result = await _showListPicker<RosterMember>(
      context,
      title: 'Lead Singer',
      options: members,
      labelOf: (m) => m.name,
    );
    if (result != null) {
      setState(() => _leadSinger = result.value == null
          ? null
          : SongLeadSinger(
              id: result.value!.id, displayName: result.value!.name));
    }
  }

  Future<void> _pickTransitionSong() async {
    final songs = (ref.read(songsProvider).value?.songs ?? const <Song>[])
        .where((s) => s.id != widget.existing?.id)
        .toList();
    final result = await _showListPicker<Song>(
      context,
      title: 'Transition Song',
      options: songs,
      labelOf: (s) =>
          s.artist.isNotEmpty ? '${s.title} — ${s.artist}' : s.title,
    );
    if (result != null) {
      setState(() => _transitionSong = result.value == null
          ? null
          : SongRef(
              id: result.value!.id,
              title: result.value!.title,
              artist: result.value!.artist,
            ));
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Watched (not just read on demand) so the band/songs data — needed for
    // the genre, lead singer and transition pickers, and for resolving the
    // band id on save — is already resolved by the time the user can
    // interact with the form instead of racing an in-flight async load.
    ref.watch(songsProvider);

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(_isEdit ? 'Edit Song' : 'New Song'),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        trailing: _isSaving
            ? const CupertinoActivityIndicator()
            : CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _canSave ? _save : null,
                child: Text(
                  'Save',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: _canSave
                        ? CupertinoColors.activeBlue.resolveFrom(context)
                        : CupertinoColors.tertiaryLabel.resolveFrom(context),
                  ),
                ),
              ),
      ),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth =
                constraints.maxWidth > 700 ? 700.0 : constraints.maxWidth;

            return Center(
              child: SizedBox(
                width: maxWidth,
                child: ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.only(top: 20, bottom: 40),
                  children: [
                    if (_error != null)
                      _ErrorBanner(
                        message: _error!,
                        onDismiss: () => setState(() => _error = null),
                      ),

                    // ── Identity ───────────────────────────────────────────
                    _FormSection(
                      children: [
                        _LabeledField(
                          label: 'Title',
                          child: CupertinoTextField(
                            controller: _titleController,
                            autofocus: !_isEdit,
                            placeholder: 'Required',
                            textInputAction: TextInputAction.next,
                            decoration: const BoxDecoration(),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        _FormDivider(),
                        _LabeledField(
                          label: 'Artist',
                          child: CupertinoTextField(
                            controller: _artistController,
                            placeholder: 'Optional',
                            textInputAction: TextInputAction.next,
                            decoration: const BoxDecoration(),
                          ),
                        ),
                      ],
                    ),

                    // ── Musical details ────────────────────────────────────
                    _FormSection(
                      children: [
                        _LabeledField(
                          label: 'Key',
                          child: CupertinoTextField(
                            controller: _keyController,
                            placeholder: 'e.g. E♭m',
                            textInputAction: TextInputAction.next,
                            decoration: const BoxDecoration(),
                          ),
                        ),
                        _FormDivider(),
                        _PickerRow(
                          label: 'Genre',
                          value: _genre.isEmpty ? null : _genre,
                          placeholder: 'None',
                          onTap: _pickGenre,
                        ),
                        _FormDivider(),
                        _LabeledField(
                          label: 'BPM',
                          child: Row(
                            children: [
                              Expanded(
                                child: CupertinoTextField(
                                  controller: _bpmController,
                                  placeholder: 'Optional',
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(3),
                                  ],
                                  decoration: const BoxDecoration(),
                                ),
                              ),
                              _isLookingUp
                                  ? const CupertinoActivityIndicator()
                                  : CupertinoButton(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8),
                                      minimumSize: Size.zero,
                                      onPressed: _lookupBpm,
                                      child: const Text(
                                        'Look up',
                                        style: TextStyle(fontSize: 15),
                                      ),
                                    ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    // ── People & flow ──────────────────────────────────────
                    _FormSection(
                      children: [
                        _PickerRow(
                          label: 'Lead singer',
                          value: _leadSinger?.displayName,
                          placeholder: 'None',
                          onTap: _pickLeadSinger,
                        ),
                        _FormDivider(),
                        _PickerRow(
                          label: 'Transition',
                          value: _transitionSong?.title,
                          placeholder: 'None',
                          onTap: _pickTransitionSong,
                        ),
                      ],
                    ),

                    // ── Rating / energy ────────────────────────────────────
                    _FormSection(
                      children: [
                        _StepperRow(
                          label: 'Rating',
                          value: _rating,
                          onChanged: (v) => setState(() => _rating = v),
                        ),
                        _FormDivider(),
                        _StepperRow(
                          label: 'Energy',
                          value: _energy,
                          onChanged: (v) => setState(() => _energy = v),
                        ),
                      ],
                    ),

                    // ── Notes ──────────────────────────────────────────────
                    _FormSection(
                      children: [
                        _LabeledField(
                          label: 'Notes',
                          alignLabelTop: true,
                          child: CupertinoTextField(
                            controller: _notesController,
                            placeholder: 'Optional',
                            maxLines: 3,
                            minLines: 3,
                            decoration: const BoxDecoration(),
                          ),
                        ),
                      ],
                    ),

                    // ── Active toggle ──────────────────────────────────────
                    _FormSection(
                      children: [
                        _SwitchRow(
                          label: 'Active',
                          subtitle:
                              'Inactive songs are hidden from search and the setlist picker',
                          value: _active,
                          onChanged: (v) => setState(() => _active = v),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ── List picker sheet ─────────────────────────────────────────────────────────

/// Wrapper distinguishing "picked None" ([value] == null) from a dismissed
/// sheet (the outer Future resolves to null).
class _PickerSelection<T> {
  const _PickerSelection(this.value);
  final T? value;
}

Future<_PickerSelection<T>?> _showListPicker<T>(
  BuildContext context, {
  required String title,
  required List<T> options,
  required String Function(T) labelOf,
}) {
  return showCupertinoModalPopup<_PickerSelection<T>>(
    context: context,
    builder: (sheetCtx) => Container(
      height: MediaQuery.of(sheetCtx).size.height * 0.6,
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground.resolveFrom(sheetCtx),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                title,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  _PickerOptionRow(
                    label: 'None',
                    onTap: () =>
                        Navigator.of(sheetCtx).pop(_PickerSelection<T>(null)),
                  ),
                  for (final option in options)
                    _PickerOptionRow(
                      label: labelOf(option),
                      onTap: () => Navigator.of(sheetCtx)
                          .pop(_PickerSelection<T>(option)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _PickerOptionRow extends StatelessWidget {
  const _PickerOptionRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: CupertinoColors.separator.resolveFrom(context),
              width: 0.5,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 15, color: context.primaryText),
        ),
      ),
    );
  }
}

// ── Form building blocks (create_chart_screen.dart conventions) ───────────────

class _FormSection extends StatelessWidget {
  const _FormSection({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: children),
    );
  }
}

class _FormDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 0.5,
      margin: const EdgeInsets.only(left: 16),
      color: CupertinoColors.separator.resolveFrom(context),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.child,
    this.alignLabelTop = false,
  });

  final String label;
  final Widget child;
  final bool alignLabelTop;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment:
            alignLabelTop ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 100,
            child: Padding(
              padding:
                  alignLabelTop ? const EdgeInsets.only(top: 4) : EdgeInsets.zero,
              child: Text(
                label,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// A tappable row for sheet-based pickers — label left, current value (or a
/// dimmed placeholder) and a chevron right.
class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.label,
    required this.value,
    required this.placeholder,
    required this.onTap,
  });

  final String label;
  final String? value;
  final String placeholder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label, ${value ?? placeholder}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 100,
                child: Text(
                  label,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w400),
                ),
              ),
              Expanded(
                child: Text(
                  value ?? placeholder,
                  style: TextStyle(
                    fontSize: 16,
                    color: value == null
                        ? context.secondaryText
                        : context.primaryText,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                CupertinoIcons.chevron_right,
                size: 14,
                color: context.tertiaryText,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A 1–10 stepper. Minus at 1 clears back to unset (null); plus from unset
/// starts at 1 and caps at 10.
class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
            ),
          ),
          Expanded(
            child: Text(
              value == null ? 'Not set' : '$value / 10',
              style: TextStyle(
                fontSize: 16,
                color:
                    value == null ? context.secondaryText : context.primaryText,
              ),
            ),
          ),
          Semantics(
            button: true,
            label: 'Decrease $label',
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: Size.zero,
              onPressed: value == null
                  ? null
                  : () => onChanged(value == 1 ? null : value! - 1),
              child: const Icon(CupertinoIcons.minus_circle, size: 24),
            ),
          ),
          Semantics(
            button: true,
            label: 'Increase $label',
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: Size.zero,
              onPressed: (value ?? 0) >= 10
                  ? null
                  : () => onChanged(value == null ? 1 : value! + 1),
              child: const Icon(CupertinoIcons.plus_circle, size: 24),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 16)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.secondaryText,
                    ),
                  ),
                ],
              ],
            ),
          ),
          CupertinoSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: CupertinoColors.systemRed.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: CupertinoColors.systemRed.resolveFrom(context),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.exclamationmark_circle,
            size: 16,
            color: CupertinoColors.systemRed.resolveFrom(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                color: CupertinoColors.systemRed.resolveFrom(context),
              ),
            ),
          ),
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            onPressed: onDismiss,
            child: Icon(
              CupertinoIcons.xmark,
              size: 14,
              color: CupertinoColors.systemRed.resolveFrom(context),
            ),
          ),
        ],
      ),
    );
  }
}
