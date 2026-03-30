import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timelines_plus/timelines_plus.dart';
import '../../../shared/utils/time_format.dart';
import '../../../shared/widgets/status_chip.dart';
import '../data/models/event_detail.dart';
import '../data/events_repository.dart';
import '../providers/events_provider.dart';

// ── Mutable edit-time models ──────────────────────────────────────────────────

class _TimelineEntry {
  _TimelineEntry({required this.title, this.time});
  String title;
  String? time; // "HH:mm"
}

class _WeddingDance {
  _WeddingDance({required this.title, this.data});
  String title; // e.g. "first_dance"
  String? data; // song name / description
}

// ── Screen ────────────────────────────────────────────────────────────────────

class EventEditScreen extends ConsumerStatefulWidget {
  const EventEditScreen({super.key, required this.event});
  final EventDetail event;

  @override
  ConsumerState<EventEditScreen> createState() => _EventEditScreenState();
}

class _EventEditScreenState extends ConsumerState<EventEditScreen> {
  late final TextEditingController _title;
  late final TextEditingController _venueName;
  late final TextEditingController _venueAddress;
  late final TextEditingController _notes;
  late final TextEditingController _attire;

  late DateTime _date;
  String? _time; // "HH:mm" or null

  late bool? _isPublic;
  late bool? _outside;
  late bool? _backlineProvided;
  late bool? _productionNeeded;

  // Timeline
  late List<_TimelineEntry> _timeline;

  // Wedding dances (null means this event has no wedding block)
  bool? _weddingOnsite;
  List<_WeddingDance>? _weddingDances;

  // Attachments (managed immediately via separate API calls)
  late List<EventAttachment> _attachments;
  bool _uploading = false;

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.event;
    _title = TextEditingController(text: e.title);
    _venueName = TextEditingController(text: e.venueName ?? '');
    _venueAddress = TextEditingController(text: e.venueAddress ?? '');
    _notes = TextEditingController(text: _stripHtml(e.notes ?? ''));
    _attire = TextEditingController(text: e.attire ?? '');
    _date = e.parsedDate;
    _time = e.time;
    _isPublic = e.isPublic;
    _outside = e.outside;
    _backlineProvided = e.backlineProvided;
    _productionNeeded = e.productionNeeded;

    _timeline = e.timeline
        .map((t) => _TimelineEntry(
              title: t.title,
              time: t.time != null ? _normaliseDateTime(t.time!) : null,
            ))
        .toList();

    if (e.wedding != null) {
      _weddingOnsite = e.wedding!.onsite;
      _weddingDances = e.wedding!.dances
          .map((d) => _WeddingDance(title: d.title, data: d.data))
          .toList();
    }

    _attachments = List.of(e.attachments);
  }

  @override
  void dispose() {
    _title.dispose();
    _venueName.dispose();
    _venueAddress.dispose();
    _notes.dispose();
    _attire.dispose();
    super.dispose();
  }

  String _stripHtml(String html) => html
      .replaceAll(RegExp(r'<br\s*/?>'), '\n')
      .replaceAll(RegExp(r'<p[^>]*>'), '')
      .replaceAll('</p>', '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .trim();

  /// Extracts "HH:mm" from "HH:mm", "HH:mm:ss", or a full ISO datetime string.
  /// Normalises any datetime string to "YYYY-MM-DD HH:mm", preserving the full
  /// date so that entries after midnight sort and display correctly.
  String _normaliseDateTime(String raw) {
    final dt = DateTime.tryParse(raw);
    if (dt != null) {
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
          '${dt.day.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return raw;
  }

  // ── Save ────────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    final payload = <String, dynamic>{
      'title': _title.text.trim(),
      'date': '${_date.year.toString().padLeft(4, '0')}-'
          '${_date.month.toString().padLeft(2, '0')}-'
          '${_date.day.toString().padLeft(2, '0')}',
      'venue_name': _venueName.text.trim(),
      'venue_address': _venueAddress.text.trim(),
      'notes': _notes.text.trim(),
      'attire': _attire.text.trim(),
    };

    if (_time != null) payload['time'] = _time;
    if (_isPublic != null) payload['is_public'] = _isPublic;
    if (_outside != null) payload['outside'] = _outside;
    if (_backlineProvided != null) payload['backline_provided'] = _backlineProvided;
    if (_productionNeeded != null) payload['production_needed'] = _productionNeeded;

    // Timeline
    payload['timeline'] = _timeline
        .map((e) => {'title': e.title, 'time': e.time})
        .toList();

    // Wedding
    if (_weddingDances != null) {
      payload['wedding'] = {
        'onsite': _weddingOnsite,
        'dances': _weddingDances!
            .map((d) => {'title': d.title, 'data': d.data})
            .toList(),
      };
    }

    try {
      final repo = ref.read(eventsRepositoryProvider);
      await repo.updateEvent(widget.event.key, payload);
      ref.invalidate(eventDetailProvider(widget.event.key));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _saving = false;
      });
    }
  }

  // ── Date / time pickers ─────────────────────────────────────────────────────

  Future<void> _pickDate() async {
    DateTime picked = _date;
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => Container(
        height: 280,
        color: CupertinoColors.systemBackground.resolveFrom(context),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                CupertinoButton(
                  child: const Text('Cancel'),
                  onPressed: () => Navigator.pop(context),
                ),
                CupertinoButton(
                  child: const Text('Done'),
                  onPressed: () {
                    setState(() => _date = picked);
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
            Expanded(
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.date,
                initialDateTime: _date,
                onDateTimeChanged: (dt) => picked = dt,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickTime() async {
    DateTime initial;
    if (_time != null) {
      try {
        final parts = _time!.split(':');
        initial = DateTime(2000, 1, 1, int.parse(parts[0]), int.parse(parts[1]));
      } catch (_) {
        initial = DateTime(2000, 1, 1, 19, 0);
      }
    } else {
      initial = DateTime(2000, 1, 1, 19, 0);
    }

    DateTime picked = initial;
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => Container(
        height: 280,
        color: CupertinoColors.systemBackground.resolveFrom(context),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                CupertinoButton(
                  child: const Text('Clear'),
                  onPressed: () {
                    setState(() => _time = null);
                    Navigator.pop(context);
                  },
                ),
                CupertinoButton(
                  child: const Text('Done'),
                  onPressed: () {
                    setState(() => _time =
                        '${picked.hour.toString().padLeft(2, '0')}:'
                        '${picked.minute.toString().padLeft(2, '0')}');
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
            Expanded(
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.time,
                initialDateTime: initial,
                use24hFormat: true,
                onDateTimeChanged: (dt) => picked = dt,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Timeline helpers ────────────────────────────────────────────────────────

  Future<void> _addTimelineEntry() async {
    final titleCtrl = TextEditingController();
    // Default to event date at 19:00; user can scroll to any date/time including next day.
    DateTime picked = DateTime(_date.year, _date.month, _date.day, 19, 0);
    String? entryTime; // "YYYY-MM-DD HH:mm" or null

    await showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => CupertinoAlertDialog(
          title: const Text('Add Timeline Entry'),
          content: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(
              children: [
                CupertinoTextField(
                  controller: titleCtrl,
                  placeholder: 'Label (e.g. Doors Open)',
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () async {
                    await showCupertinoModalPopup<void>(
                      context: ctx,
                      builder: (_) => Container(
                        height: 320,
                        color: CupertinoColors.systemBackground.resolveFrom(ctx),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                CupertinoButton(
                                  child: const Text('Clear'),
                                  onPressed: () {
                                    setDlgState(() => entryTime = null);
                                    Navigator.pop(ctx);
                                  },
                                ),
                                CupertinoButton(
                                  child: const Text('Done'),
                                  onPressed: () {
                                    setDlgState(() => entryTime = _normaliseDateTime(picked.toIso8601String()));
                                    Navigator.pop(ctx);
                                  },
                                ),
                              ],
                            ),
                            Expanded(
                              child: CupertinoDatePicker(
                                mode: CupertinoDatePickerMode.dateAndTime,
                                initialDateTime: entryTime != null
                                    ? (DateTime.tryParse(entryTime!) ?? picked)
                                    : picked,
                                use24hFormat: true,
                                onDateTimeChanged: (dt) => picked = dt,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: CupertinoColors.separator.resolveFrom(ctx),
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        const Icon(CupertinoIcons.calendar, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          entryTime != null
                              ? _formatEntryLabel(entryTime!)
                              : 'Set date & time (optional)',
                          style: TextStyle(
                            fontSize: 14,
                            color: entryTime != null
                                ? CupertinoColors.label.resolveFrom(ctx)
                                : CupertinoColors.placeholderText.resolveFrom(ctx),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () {
                final label = titleCtrl.text.trim();
                if (label.isEmpty) return;
                setState(() {
                  _timeline.add(_TimelineEntry(title: label, time: entryTime));
                  _timeline.sort((a, b) {
                    if (a.time == null && b.time == null) return 0;
                    if (a.time == null) return 1;
                    if (b.time == null) return -1;
                    final aDt = DateTime.tryParse(a.time!);
                    final bDt = DateTime.tryParse(b.time!);
                    if (aDt == null || bDt == null) return a.time!.compareTo(b.time!);
                    return aDt.compareTo(bDt);
                  });
                });
                Navigator.pop(ctx);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    titleCtrl.dispose();
  }

  /// Human-readable label for a "YYYY-MM-DD HH:mm" entry time shown in the dialog.
  String _formatEntryLabel(String time) {
    final dt = DateTime.tryParse(time);
    if (dt == null) return time;
    final sameDay = dt.year == _date.year && dt.month == _date.month && dt.day == _date.day;
    final timeStr = toAmPm(time);
    return sameDay ? timeStr : '$timeStr (+1 day)';
  }

  void _removeTimelineEntry(int index) {
    setState(() => _timeline.removeAt(index));
  }

  // ── Wedding dance helpers ───────────────────────────────────────────────────

  static const _danceTypes = [
    ('first_dance', 'First Dance'),
    ('parent_dance', 'Parent Dance'),
    ('father_daughter', 'Father / Daughter'),
    ('mother_son', 'Mother / Son'),
    ('bridal_party', 'Bridal Party'),
    ('bouquet_toss', 'Bouquet Toss'),
    ('custom', 'Other'),
  ];

  Future<void> _addWeddingDance() async {
    String selectedType = _danceTypes.first.$1;
    final songCtrl = TextEditingController();
    final customCtrl = TextEditingController();

    await showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => CupertinoAlertDialog(
          title: const Text('Add Dance'),
          content: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Type picker
                SizedBox(
                  height: 120,
                  child: CupertinoPicker(
                    itemExtent: 32,
                    scrollController: FixedExtentScrollController(
                      initialItem: _danceTypes.indexWhere((t) => t.$1 == selectedType),
                    ),
                    onSelectedItemChanged: (i) =>
                        setDlgState(() => selectedType = _danceTypes[i].$1),
                    children: _danceTypes
                        .map((t) => Center(
                              child: Text(t.$2, style: const TextStyle(fontSize: 14)),
                            ))
                        .toList(),
                  ),
                ),
                const SizedBox(height: 8),
                if (selectedType == 'custom')
                  CupertinoTextField(
                    controller: customCtrl,
                    placeholder: 'Dance type',
                    textCapitalization: TextCapitalization.words,
                  ),
                const SizedBox(height: 8),
                CupertinoTextField(
                  controller: songCtrl,
                  placeholder: 'Song / details (optional)',
                  textCapitalization: TextCapitalization.sentences,
                ),
              ],
            ),
          ),
          actions: [
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () {
                final type = selectedType == 'custom'
                    ? customCtrl.text.trim().toLowerCase().replaceAll(' ', '_')
                    : selectedType;
                if (type.isEmpty) return;
                setState(() {
                  _weddingDances!.add(_WeddingDance(
                    title: type,
                    data: songCtrl.text.trim().isEmpty ? null : songCtrl.text.trim(),
                  ));
                });
                Navigator.pop(ctx);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    songCtrl.dispose();
    customCtrl.dispose();
  }

  void _removeWeddingDance(int index) {
    setState(() => _weddingDances!.removeAt(index));
  }

  // ── Attachment helpers ──────────────────────────────────────────────────────

  Future<void> _pickAndUploadAttachment() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: false);
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null) return;

    setState(() => _uploading = true);
    try {
      final repo = ref.read(eventsRepositoryProvider);
      final attachment = await repo.uploadAttachment(widget.event.key, File(path));
      setState(() => _attachments.add(attachment));
    } catch (e) {
      if (mounted) {
        showCupertinoDialog<void>(
          context: context,
          builder: (_) => CupertinoAlertDialog(
            title: const Text('Upload Failed'),
            content: Text(e.toString()),
            actions: [
              CupertinoDialogAction(
                isDefaultAction: true,
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _deleteAttachment(EventAttachment attachment) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Delete Attachment'),
        content: Text('Remove "${attachment.filename}"?'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final repo = ref.read(eventsRepositoryProvider);
      await repo.deleteAttachment(widget.event.key, attachment.id);
      setState(() => _attachments.removeWhere((a) => a.id == attachment.id));
    } catch (e) {
      if (mounted) {
        showCupertinoDialog<void>(
          context: context,
          builder: (_) => CupertinoAlertDialog(
            title: const Text('Delete Failed'),
            content: Text(e.toString()),
            actions: [
              CupertinoDialogAction(
                isDefaultAction: true,
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  String _formatDanceTitle(String raw) =>
      raw.replaceAll('_', ' ').split(' ').map((w) {
        if (w.isEmpty) return w;
        return w[0].toUpperCase() + w.substring(1);
      }).join(' ');

  IconData _attachmentIcon(String mimeType) {
    if (mimeType.startsWith('image/')) return CupertinoIcons.photo;
    if (mimeType == 'application/pdf') return CupertinoIcons.doc_text;
    if (mimeType.startsWith('audio/')) return CupertinoIcons.music_note;
    if (mimeType.startsWith('video/')) return CupertinoIcons.film;
    return CupertinoIcons.doc;
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Edit Event'),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _saving ? null : _save,
          child: _saving
              ? const CupertinoActivityIndicator()
              : const Text('Save', style: TextStyle(fontWeight: FontWeight.w600)),
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        children: [
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: CupertinoColors.systemRed
                    .resolveFrom(context)
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _error!,
                style: TextStyle(
                  color: CupertinoColors.systemRed.resolveFrom(context),
                  fontSize: 14,
                ),
              ),
            ),
          ],

          // ── Basic info ──────────────────────────────────────────────────────
          _SectionHeader(title: 'Event'),
          _FormCard(children: [
            _LabeledField(
              label: 'Title',
              child: CupertinoTextField.borderless(
                controller: _title,
                placeholder: 'Event title',
                textCapitalization: TextCapitalization.words,
              ),
            ),
            _Divider(),
            _LabeledRow(
              label: 'Date',
              onTap: _pickDate,
              value: _formatDate(_date),
            ),
            _Divider(),
            _LabeledRow(
              label: 'Time',
              onTap: _pickTime,
              value: _time ?? 'Not set',
              muted: _time == null,
            ),
          ]),

          const SizedBox(height: 20),

          // ── Venue ───────────────────────────────────────────────────────────
          _SectionHeader(title: 'Venue'),
          _FormCard(children: [
            _LabeledField(
              label: 'Name',
              child: CupertinoTextField.borderless(
                controller: _venueName,
                placeholder: 'Venue name',
                textCapitalization: TextCapitalization.words,
              ),
            ),
            _Divider(),
            _LabeledField(
              label: 'Address',
              child: CupertinoTextField.borderless(
                controller: _venueAddress,
                placeholder: 'Address',
              ),
            ),
          ]),

          const SizedBox(height: 20),

          // ── Notes & Attire ──────────────────────────────────────────────────
          _SectionHeader(title: 'Details'),
          _FormCard(children: [
            _LabeledField(
              label: 'Notes',
              child: CupertinoTextField.borderless(
                controller: _notes,
                placeholder: 'Notes',
                maxLines: 4,
                minLines: 1,
              ),
            ),
            _Divider(),
            _LabeledField(
              label: 'Attire',
              child: CupertinoTextField.borderless(
                controller: _attire,
                placeholder: 'Dress code',
                textCapitalization: TextCapitalization.sentences,
              ),
            ),
          ]),

          // ── Flags ───────────────────────────────────────────────────────────
          if (_isPublic != null ||
              _outside != null ||
              _backlineProvided != null ||
              _productionNeeded != null) ...[
            const SizedBox(height: 20),
            _SectionHeader(title: 'Options'),
            _FormCard(children: [
              if (_isPublic != null) ...[
                _ToggleRow(
                  label: 'Public',
                  value: _isPublic!,
                  onChanged: (v) => setState(() => _isPublic = v),
                ),
              ],
              if (_isPublic != null && _outside != null) _Divider(),
              if (_outside != null) ...[
                _ToggleRow(
                  label: 'Outdoor',
                  value: _outside!,
                  onChanged: (v) => setState(() => _outside = v),
                ),
              ],
              if (_outside != null && _backlineProvided != null) _Divider(),
              if (_backlineProvided != null) ...[
                _ToggleRow(
                  label: 'Backline Provided',
                  value: _backlineProvided!,
                  onChanged: (v) => setState(() => _backlineProvided = v),
                ),
              ],
              if (_backlineProvided != null && _productionNeeded != null) _Divider(),
              if (_productionNeeded != null) ...[
                _ToggleRow(
                  label: 'Production Needed',
                  value: _productionNeeded!,
                  onChanged: (v) => setState(() => _productionNeeded = v),
                ),
              ],
            ]),
          ],

          const SizedBox(height: 20),

          // ── Timeline ────────────────────────────────────────────────────────
          _SectionHeader(title: 'Timeline'),
          _FormCard(children: [
            if (_timeline.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Text(
                  'No timeline entries',
                  style: TextStyle(
                    fontSize: 14,
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(left: 16, top: 8, bottom: 4),
                child: FixedTimeline.tileBuilder(
                  theme: TimelineThemeData(
                    nodePosition: 0,
                    color: CupertinoColors.activeBlue.resolveFrom(context),
                    indicatorTheme: const IndicatorThemeData(size: 10, position: 0.5),
                    connectorTheme: ConnectorThemeData(
                      thickness: 1.5,
                      color: CupertinoColors.separator.resolveFrom(context),
                    ),
                  ),
                  builder: TimelineTileBuilder.connected(
                    itemCount: _timeline.length,
                    contentsBuilder: (context, i) => Padding(
                      padding: const EdgeInsets.only(left: 12, bottom: 16),
                      child: Row(
                        children: [
                          Text(
                            toAmPm(_timeline[i].time, fallback: '—'),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Menlo',
                              color: CupertinoColors.secondaryLabel.resolveFrom(context),
                            ),
                          ),
                          if (isNextDay(_timeline[i].time, _date)) ...[
                            const SizedBox(width: 4),
                            const NextDayBadge(),
                          ],
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _timeline[i].title,
                              style: const TextStyle(fontSize: 15),
                            ),
                          ),
                          CupertinoButton(
                            padding: EdgeInsets.zero,
                            minSize: 28,
                            onPressed: () => _removeTimelineEntry(i),
                            child: Icon(
                              CupertinoIcons.minus_circle,
                              size: 20,
                              color: CupertinoColors.systemRed.resolveFrom(context),
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                      ),
                    ),
                    indicatorBuilder: (context, i) => DotIndicator(
                      color: CupertinoColors.activeBlue.resolveFrom(context),
                      size: 10,
                    ),
                    connectorBuilder: (context, i, type) => SolidLineConnector(
                      color: CupertinoColors.separator.resolveFrom(context),
                      thickness: 1.5,
                    ),
                  ),
                ),
              ),
            if (_timeline.isNotEmpty) _Divider(),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              onPressed: _addTimelineEntry,
              child: Row(
                children: [
                  Icon(
                    CupertinoIcons.plus_circle,
                    size: 18,
                    color: CupertinoColors.activeBlue.resolveFrom(context),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Add Entry',
                    style: TextStyle(
                      fontSize: 15,
                      color: CupertinoColors.activeBlue.resolveFrom(context),
                    ),
                  ),
                ],
              ),
            ),
          ]),

          // ── Wedding Dances ──────────────────────────────────────────────────
          if (_weddingDances != null) ...[
            const SizedBox(height: 20),
            _SectionHeader(title: 'Wedding Dances'),
            _FormCard(children: [
              if (_weddingOnsite != null) ...[
                _ToggleRow(
                  label: 'Ceremony On-site',
                  value: _weddingOnsite!,
                  onChanged: (v) => setState(() => _weddingOnsite = v),
                ),
                _Divider(),
              ],
              if (_weddingDances!.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Text(
                    'No special dances',
                    style: TextStyle(
                      fontSize: 14,
                      color: CupertinoColors.secondaryLabel.resolveFrom(context),
                    ),
                  ),
                ),
              for (int i = 0; i < _weddingDances!.length; i++) ...[
                if (i > 0 || _weddingOnsite != null) _Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _formatDanceTitle(_weddingDances![i].title),
                              style: TextStyle(
                                fontSize: 13,
                                color: CupertinoColors.secondaryLabel.resolveFrom(context),
                              ),
                            ),
                            if (_weddingDances![i].data?.isNotEmpty == true)
                              Text(
                                _weddingDances![i].data!,
                                style: const TextStyle(fontSize: 15),
                              )
                            else
                              Text(
                                'TBD',
                                style: TextStyle(
                                  fontSize: 15,
                                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                                ),
                              ),
                          ],
                        ),
                      ),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        minSize: 28,
                        onPressed: () => _removeWeddingDance(i),
                        child: Icon(
                          CupertinoIcons.minus_circle,
                          size: 20,
                          color: CupertinoColors.systemRed.resolveFrom(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (_weddingDances!.isNotEmpty) _Divider(),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                onPressed: _addWeddingDance,
                child: Row(
                  children: [
                    Icon(
                      CupertinoIcons.plus_circle,
                      size: 18,
                      color: CupertinoColors.activeBlue.resolveFrom(context),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Add Dance',
                      style: TextStyle(
                        fontSize: 15,
                        color: CupertinoColors.activeBlue.resolveFrom(context),
                      ),
                    ),
                  ],
                ),
              ),
            ]),
          ],

          const SizedBox(height: 20),

          // ── Attachments ─────────────────────────────────────────────────────
          _SectionHeader(title: 'Attachments'),
          _FormCard(children: [
            if (_attachments.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Text(
                  'No attachments',
                  style: TextStyle(
                    fontSize: 14,
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
                ),
              ),
            for (int i = 0; i < _attachments.length; i++) ...[
              if (i > 0) _Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Icon(
                      _attachmentIcon(_attachments[i].mimeType),
                      size: 20,
                      color: CupertinoColors.secondaryLabel.resolveFrom(context),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _attachments[i].filename,
                            style: const TextStyle(fontSize: 15),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            _attachments[i].formattedSize,
                            style: TextStyle(
                              fontSize: 12,
                              color: CupertinoColors.secondaryLabel.resolveFrom(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      minSize: 28,
                      onPressed: () => _deleteAttachment(_attachments[i]),
                      child: Icon(
                        CupertinoIcons.minus_circle,
                        size: 20,
                        color: CupertinoColors.systemRed.resolveFrom(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_attachments.isNotEmpty) _Divider(),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              onPressed: _uploading ? null : _pickAndUploadAttachment,
              child: Row(
                children: [
                  if (_uploading)
                    const CupertinoActivityIndicator()
                  else
                    Icon(
                      CupertinoIcons.paperclip,
                      size: 18,
                      color: CupertinoColors.activeBlue.resolveFrom(context),
                    ),
                  const SizedBox(width: 8),
                  Text(
                    _uploading ? 'Uploading…' : 'Add Attachment',
                    style: TextStyle(
                      fontSize: 15,
                      color: _uploading
                          ? CupertinoColors.secondaryLabel.resolveFrom(context)
                          : CupertinoColors.activeBlue.resolveFrom(context),
                    ),
                  ),
                ],
              ),
            ),
          ]),

          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

// ── Layout helpers ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 6),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: CupertinoColors.secondaryLabel.resolveFrom(context),
        ),
      ),
    );
  }
}

class _FormCard extends StatelessWidget {
  const _FormCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _Divider extends StatelessWidget {
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
  const _LabeledField({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(fontSize: 15),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _LabeledRow extends StatelessWidget {
  const _LabeledRow({
    required this.label,
    required this.onTap,
    required this.value,
    this.muted = false,
  });
  final String label;
  final VoidCallback onTap;
  final String value;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 90,
              child: Text(label, style: const TextStyle(fontSize: 15)),
            ),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 15,
                  color: muted
                      ? CupertinoColors.secondaryLabel.resolveFrom(context)
                      : CupertinoColors.label.resolveFrom(context),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              CupertinoIcons.chevron_right,
              size: 14,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 15))),
          CupertinoSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
