import 'package:flutter/cupertino.dart';
import '../data/models/event_setlist.dart';

// ── Public result type ────────────────────────────────────────────────────────

/// Sealed-style result returned by [showSongPickerSheet].
///
/// Exactly one of [song] (library pick) or [customTitle] (custom entry) will
/// be non-null — inspect [isLibrary] to distinguish the two cases.
class SongPickerResult {
  /// A song chosen from the band's library.
  const SongPickerResult.library(BandSongSummary this.song)
      : customTitle = null,
        customArtist = null;

  /// A custom song entered manually (not in the band's library).
  const SongPickerResult.custom({
    required String this.customTitle,
    this.customArtist,
  }) : song = null;

  final BandSongSummary? song;

  /// Non-null when [isCustom] — the user-typed title.
  final String? customTitle;

  /// Optional artist field for custom entries; always null for library picks.
  final String? customArtist;

  bool get isLibrary => song != null;
  bool get isCustom => customTitle != null;
}

// ── Public entry point ────────────────────────────────────────────────────────

/// Shows a modal bottom sheet that lets the user search the band's [songs] and
/// pick one, or switch to "Custom" mode to enter a title + optional artist.
///
/// Returns a [SongPickerResult] when the user makes a selection, or `null` if
/// the sheet is dismissed without a selection.
///
/// Typical usage from an editor screen:
/// ```dart
/// final result = await showSongPickerSheet(context, songs: state.songs);
/// if (result != null) {
///   notifier.addSong(result);
/// }
/// ```
Future<SongPickerResult?> showSongPickerSheet(
  BuildContext context, {
  required List<BandSongSummary> songs,
}) {
  return showCupertinoModalPopup<SongPickerResult>(
    context: context,
    builder: (_) => _SongPickerSheet(songs: songs),
  );
}

// ── Private sheet implementation ──────────────────────────────────────────────

class _SongPickerSheet extends StatefulWidget {
  const _SongPickerSheet({required this.songs});

  final List<BandSongSummary> songs;

  @override
  State<_SongPickerSheet> createState() => _SongPickerSheetState();
}

class _SongPickerSheetState extends State<_SongPickerSheet> {
  String _query = '';
  bool _customMode = false;

  final _customTitleController = TextEditingController();
  final _customArtistController = TextEditingController();

  // Tracks whether the "Add" button should be enabled.  Rebuilt on every
  // keystroke via [_onCustomTitleChanged].
  bool _customTitleFilled = false;

  @override
  void dispose() {
    _customTitleController.dispose();
    _customArtistController.dispose();
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

  void _pickLibrarySong(BandSongSummary song) {
    Navigator.of(context).pop(SongPickerResult.library(song));
  }

  void _submitCustom() {
    final title = _customTitleController.text.trim();
    if (title.isEmpty) return;
    final artist = _customArtistController.text.trim();
    Navigator.of(context).pop(
      SongPickerResult.custom(
        customTitle: title,
        customArtist: artist.isEmpty ? null : artist,
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
              titleFilled: _customTitleFilled,
              onTitleChanged: _onCustomTitleChanged,
              onSubmit: _customTitleFilled ? _submitCustom : null,
            ) : _LibraryList(
              songs: _filtered,
              query: _query,
              onQueryChanged: (v) => setState(() => _query = v),
              onPick: _pickLibrarySong,
            ),
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
              customMode ? 'Add Custom Song' : 'Pick a Song',
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
    required this.onQueryChanged,
    required this.onPick,
  });

  final List<BandSongSummary> songs;
  final String query;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<BandSongSummary> onPick;

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
                  itemBuilder: (context, i) =>
                      _SongTile(song: songs[i], onTap: () => onPick(songs[i])),
                ),
        ),
      ],
    );
  }
}

/// Single tappable row for a library song.
class _SongTile extends StatelessWidget {
  const _SongTile({required this.song, required this.onTap});

  final BandSongSummary song;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${song.title}${song.artist != null ? ", by ${song.artist}" : ""}',
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      style: TextStyle(
                        fontSize: 15,
                        // label resolves correctly in light/dark mode.
                        color: CupertinoColors.label.resolveFrom(context),
                      ),
                    ),
                    if ((song.artist ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          song.artist!,
                          style: TextStyle(
                            fontSize: 13,
                            color: CupertinoColors.secondaryLabel
                                .resolveFrom(context),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Song key shown on the trailing edge as a compact hint.
              if (song.songKey != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    song.songKey!,
                    style: TextStyle(
                      fontSize: 13,
                      color:
                          CupertinoColors.secondaryLabel.resolveFrom(context),
                    ),
                  ),
                ),
            ],
          ),
        ),
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
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
          ),
        ),
      ),
    );
  }
}

/// Form for entering a custom song title and optional artist.
class _CustomForm extends StatelessWidget {
  const _CustomForm({
    required this.titleController,
    required this.artistController,
    required this.titleFilled,
    required this.onTitleChanged,
    required this.onSubmit,
  });

  final TextEditingController titleController;
  final TextEditingController artistController;
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
