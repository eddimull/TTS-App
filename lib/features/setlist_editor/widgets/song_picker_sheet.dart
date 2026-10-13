import 'package:flutter/cupertino.dart';
import '../data/models/event_setlist.dart';
import 'client_request_marker.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';

// ── Public result type ────────────────────────────────────────────────────────

/// Sealed-style result returned by [showSongPickerSheet].
///
/// Either [songs] is non-empty (library picks) or [customTitle] is non-null
/// (custom entry) — inspect [isLibrary] to distinguish the two cases.
class SongPickerResult {
  /// One or more songs chosen from the band's library, in the order the user
  /// selected them.
  ///
  /// Library picks never carry notes — the editor screen exposes a per-row
  /// edit action for that.
  const SongPickerResult.library(this.songs)
      : customTitle = null,
        customArtist = null,
        notes = null;

  /// A custom song entered manually (not in the band's library).
  const SongPickerResult.custom({
    required String this.customTitle,
    this.customArtist,
    this.notes,
  }) : songs = const [];

  /// Library songs in selection order; empty for custom entries.
  final List<BandSongSummary> songs;

  /// Non-null when [isCustom] — the user-typed title.
  final String? customTitle;

  /// Optional artist field for custom entries; always null for library picks.
  final String? customArtist;

  /// Optional free-text notes passed through to the setlist entry.
  ///
  /// Populated from the Notes field in custom mode; null for library picks
  /// (the editor screen lets users set notes on a row after it is added).
  final String? notes;

  bool get isLibrary => songs.isNotEmpty;
  bool get isCustom => customTitle != null;
}

// ── Public entry point ────────────────────────────────────────────────────────

/// Shows a modal bottom sheet that lets the user search the band's [songs] and
/// tap to select several in a row, or switch to "Custom" mode to enter a
/// title + optional artist.
///
/// [onSetlistIds] marks library songs already on the setlist so the user can
/// avoid accidental duplicates (they remain selectable, e.g. for a reprise).
///
/// Returns a [SongPickerResult] when the user confirms, or `null` if the sheet
/// is dismissed without a selection.
///
/// Typical usage from an editor screen:
/// ```dart
/// final result = await showSongPickerSheet(context, songs: state.songs);
/// for (final song in result?.songs ?? const []) {
///   notifier.addSong(song);
/// }
/// ```
Future<SongPickerResult?> showSongPickerSheet(
  BuildContext context, {
  required List<BandSongSummary> songs,
  ClientSongRequests? clientRequests,
  Set<int> onSetlistIds = const {},
}) {
  return showCupertinoModalPopup<SongPickerResult>(
    context: context,
    builder: (_) => _SongPickerSheet(
      songs: songs,
      clientRequests: clientRequests,
      onSetlistIds: onSetlistIds,
    ),
  );
}

// ── Private sheet implementation ──────────────────────────────────────────────

class _SongPickerSheet extends StatefulWidget {
  const _SongPickerSheet({
    required this.songs,
    this.clientRequests,
    this.onSetlistIds = const {},
  });

  final List<BandSongSummary> songs;
  final ClientSongRequests? clientRequests;
  final Set<int> onSetlistIds;

  @override
  State<_SongPickerSheet> createState() => _SongPickerSheetState();
}

class _SongPickerSheetState extends State<_SongPickerSheet> {
  String _query = '';
  bool _customMode = false;

  /// Library songs the user has tapped, in tap order. Survives search changes
  /// so the user can search, pick, search again, pick again.
  final List<BandSongSummary> _selected = [];

  final _customTitleController = TextEditingController();
  final _customArtistController = TextEditingController();
  final _customNotesController = TextEditingController();

  // Tracks whether the "Add" button should be enabled.  Rebuilt on every
  // keystroke via [_onCustomTitleChanged].
  bool _customTitleFilled = false;

  @override
  void dispose() {
    _customTitleController.dispose();
    _customArtistController.dispose();
    _customNotesController.dispose();
    super.dispose();
  }

  List<BandSongSummary> get _filtered {
    if (_query.isEmpty) return widget.songs;
    final q = _query.toLowerCase();
    return widget.songs.where((s) {
      return s.title.toLowerCase().contains(q) ||
          (s.artist?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  void _onCustomTitleChanged(String value) {
    final filled = value.trim().isNotEmpty;
    if (filled != _customTitleFilled) {
      setState(() => _customTitleFilled = filled);
    }
  }

  void _toggleLibrarySong(BandSongSummary song) {
    setState(() {
      final i = _selected.indexWhere((s) => s.id == song.id);
      if (i >= 0) {
        _selected.removeAt(i);
      } else {
        _selected.add(song);
      }
    });
  }

  void _submitLibrary() {
    if (_selected.isEmpty) return;
    Navigator.of(context)
        .pop(SongPickerResult.library(List.unmodifiable(_selected)));
  }

  void _submitCustom() {
    final title = _customTitleController.text.trim();
    if (title.isEmpty) return;
    final artist = _customArtistController.text.trim();
    final notes = _customNotesController.text.trim();
    Navigator.of(context).pop(
      SongPickerResult.custom(
        customTitle: title,
        customArtist: artist.isEmpty ? null : artist,
        notes: notes.isEmpty ? null : notes,
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      // 75 % of screen height leaves enough room on all phones without cutting
      // off the keyboard on compact devices.
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground.resolveFrom(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Grabber(),
          _Header(
            customMode: _customMode,
            onToggle: () => setState(() {
              _customMode = !_customMode;
              // Clear query when switching modes so the list resets.
              _query = '';
            }),
          ),
          Expanded(
            child: _customMode ? _CustomForm(
              titleController: _customTitleController,
              artistController: _customArtistController,
              notesController: _customNotesController,
              titleFilled: _customTitleFilled,
              onTitleChanged: _onCustomTitleChanged,
              onSubmit: _customTitleFilled ? _submitCustom : null,
            ) : _LibraryList(
              songs: _filtered,
              query: _query,
              clientRequests: widget.clientRequests,
              onSetlistIds: widget.onSetlistIds,
              selected: _selected,
              onQueryChanged: (v) => setState(() => _query = v),
              onToggle: _toggleLibrarySong,
            ),
          ),
          if (!_customMode)
            _AddSelectedBar(
              count: _selected.length,
              onSubmit: _selected.isEmpty ? null : _submitLibrary,
            ),
        ],
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

/// The draggable handle pip shown at the top of the sheet.
class _Grabber extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        margin: const EdgeInsets.only(top: 8, bottom: 4),
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          // withValues(alpha:) is the Flutter 3.x idiom — withOpacity is
          // deprecated in 3.41.
          color: CupertinoColors.systemGrey3.resolveFrom(context),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// Title row with mode toggle button.
class _Header extends StatelessWidget {
  const _Header({required this.customMode, required this.onToggle});

  final bool customMode;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              customMode ? 'Add Custom Song' : 'Pick Songs',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // Semantics label spells out the full intent so screen-reader users
          // aren't confused by the terse toggle label.
          Semantics(
            label: customMode
                ? 'Switch to library search'
                : 'Enter a custom song not in the library',
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              minimumSize: Size.zero,
              onPressed: onToggle,
              child: Text(
                customMode ? 'From Library' : 'Custom',
                style: TextStyle(
                  fontSize: 15,
                  color: CupertinoColors.activeBlue.resolveFrom(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Search-filtered list of library songs.
class _LibraryList extends StatelessWidget {
  const _LibraryList({
    required this.songs,
    required this.query,
    required this.selected,
    required this.onQueryChanged,
    required this.onToggle,
    this.clientRequests,
    this.onSetlistIds = const {},
  });

  final List<BandSongSummary> songs;
  final String query;
  final ClientSongRequests? clientRequests;
  final Set<int> onSetlistIds;
  final List<BandSongSummary> selected;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<BandSongSummary> onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: CupertinoSearchTextField(
            placeholder: 'Search songs…',
            onChanged: onQueryChanged,
          ),
        ),
        Expanded(
          child: songs.isEmpty
              ? _EmptySearch(hasQuery: query.isNotEmpty)
              : ListView.builder(
                  itemCount: songs.length,
                  // keyboardDismissBehavior: drag hides the keyboard that the
                  // search field may have raised, improving the browse UX.
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  itemBuilder: (context, i) {
                    final song = songs[i];
                    final order =
                        selected.indexWhere((s) => s.id == song.id) + 1;
                    return _SongTile(
                      song: song,
                      clientStatus: clientRequests?.statusFor(song.id) ??
                          ClientSongStatus.none,
                      onSetlist: onSetlistIds.contains(song.id),
                      selectionOrder: order == 0 ? null : order,
                      onTap: () => onToggle(song),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Single tappable row for a library song. Tapping toggles selection.
class _SongTile extends StatelessWidget {
  const _SongTile({
    required this.song,
    required this.onTap,
    this.clientStatus = ClientSongStatus.none,
    this.onSetlist = false,
    this.selectionOrder,
  });

  final BandSongSummary song;
  final VoidCallback onTap;
  final ClientSongStatus clientStatus;

  /// True when this song is already an entry on the setlist being edited.
  final bool onSetlist;

  /// 1-based position in the pending selection, or null when not selected.
  final int? selectionOrder;

  @override
  Widget build(BuildContext context) {
    final singer = song.leadSinger?.trim() ?? '';
    return Semantics(
      button: true,
      selected: selectionOrder != null,
      label: [
        song.title,
        if (song.artist != null) 'by ${song.artist}',
        if (singer.isNotEmpty) 'sung by $singer',
        if (onSetlist) 'already on setlist',
      ].join(', '),
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        onPressed: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: CupertinoColors.separator.resolveFrom(context),
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _SelectionMark(order: selectionOrder),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (clientStatus == ClientSongStatus.mustPlay)
                          const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: ClientRequestStar(size: 14),
                          ),
                        Flexible(
                          child: Text(
                            song.title,
                            style: clientRequestTextStyle(
                              context,
                              clientStatus,
                              TextStyle(
                                fontSize: 15,
                                // label resolves correctly in light/dark mode.
                                color: context.primaryText,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if ((song.artist ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          song.artist!,
                          style: clientRequestTextStyle(
                            context,
                            clientStatus,
                            TextStyle(
                              fontSize: 13,
                              color: context.secondaryText,
                            ),
                          ),
                        ),
                      ),
                    if (clientStatus != ClientSongStatus.none)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: ClientRequestCaption(clientStatus),
                      ),
                    if (onSetlist) const _OnSetlistCaption(),
                  ],
                ),
              ),
              // Lead singer shown on the trailing edge as a compact hint.
              if (singer.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        CupertinoIcons.mic,
                        size: 13,
                        color: context.secondaryText,
                      ),
                      const SizedBox(width: 2),
                      ConstrainedBox(
                        // Keep long names from squeezing the title.
                        constraints: const BoxConstraints(maxWidth: 110),
                        child: Text(
                          singer,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: context.secondaryText,
                          ),
                        ),
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
}

/// Leading selection indicator: an empty ring, or a filled badge showing the
/// order the song will be appended in.
class _SelectionMark extends StatelessWidget {
  const _SelectionMark({this.order});

  final int? order;

  @override
  Widget build(BuildContext context) {
    final blue = CupertinoColors.activeBlue.resolveFrom(context);
    final selected = order != null;
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? blue : null,
        border: selected
            ? null
            : Border.all(
                color: CupertinoColors.systemGrey3.resolveFrom(context),
                width: 1.5,
              ),
      ),
      child: selected
          ? Text(
              '$order',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: CupertinoColors.white,
              ),
            )
          : null,
    );
  }
}

/// Caption marking a song that is already on the setlist.
class _OnSetlistCaption extends StatelessWidget {
  const _OnSetlistCaption();

  @override
  Widget build(BuildContext context) {
    final color = CupertinoColors.systemGreen.resolveFrom(context);
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(CupertinoIcons.checkmark_circle_fill, size: 12, color: color),
          const SizedBox(width: 3),
          Text(
            'On setlist',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom bar confirming the pending library selection.
class _AddSelectedBar extends StatelessWidget {
  const _AddSelectedBar({required this.count, required this.onSubmit});

  final int count;

  /// Null when nothing is selected — disables the button.
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final label = switch (count) {
      0 => 'Select Songs',
      1 => 'Add 1 Song',
      _ => 'Add $count Songs',
    };
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: CupertinoColors.separator.resolveFrom(context),
            width: 0.5,
          ),
        ),
      ),
      child: CupertinoButton.filled(
        onPressed: onSubmit,
        child: Text(label),
      ),
    );
  }
}

/// Placeholder shown when the search query returns no results.
class _EmptySearch extends StatelessWidget {
  const _EmptySearch({required this.hasQuery});

  final bool hasQuery;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          hasQuery
              ? 'No songs match your search.\nSwitch to Custom to add it manually.'
              : 'No songs in the library yet.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: context.secondaryText,
          ),
        ),
      ),
    );
  }
}

/// Form for entering a custom song title, optional artist, and optional notes.
class _CustomForm extends StatelessWidget {
  const _CustomForm({
    required this.titleController,
    required this.artistController,
    required this.notesController,
    required this.titleFilled,
    required this.onTitleChanged,
    required this.onSubmit,
  });

  final TextEditingController titleController;
  final TextEditingController artistController;

  /// Receives the free-text notes the user may type before submitting.
  final TextEditingController notesController;

  final bool titleFilled;
  final ValueChanged<String> onTitleChanged;

  /// Null when the title field is empty — disables the Add button.
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      // Ensure the Add button remains visible when the keyboard is open.
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CupertinoTextField(
            controller: titleController,
            placeholder: 'Song title',
            textCapitalization: TextCapitalization.words,
            padding: const EdgeInsets.all(12),
            onChanged: onTitleChanged,
            autofocus: true,
          ),
          const SizedBox(height: 12),
          CupertinoTextField(
            controller: artistController,
            placeholder: 'Artist (optional)',
            textCapitalization: TextCapitalization.words,
            padding: const EdgeInsets.all(12),
          ),
          const SizedBox(height: 12),
          // Two-line notes field: enough for a cue without dominating the form.
          CupertinoTextField(
            controller: notesController,
            placeholder: 'Notes (optional)',
            maxLines: 2,
            minLines: 1,
            textCapitalization: TextCapitalization.sentences,
            padding: const EdgeInsets.all(12),
          ),
          const SizedBox(height: 20),
          CupertinoButton.filled(
            // Disabled (null) until title has content.
            onPressed: onSubmit,
            child: const Text('Add Song'),
          ),
        ],
      ),
    );
  }
}
