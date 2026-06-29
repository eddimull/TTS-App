import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show ReorderableListView, Material, MaterialType;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/providers/selected_band_provider.dart';
import '../data/models/event_setlist.dart';
import '../providers/setlist_editor_provider.dart';
import '../widgets/generate_sheet.dart';
import '../widgets/refine_sheet.dart';
import '../widgets/setlist_row.dart';
import '../widgets/song_picker_sheet.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';

class SetlistEditorScreen extends ConsumerStatefulWidget {
  const SetlistEditorScreen({super.key, required this.eventKey});

  final String eventKey;

  @override
  ConsumerState<SetlistEditorScreen> createState() =>
      _SetlistEditorScreenState();
}

class _SetlistEditorScreenState extends ConsumerState<SetlistEditorScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(setlistEditorProvider(widget.eventKey).notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(setlistEditorProvider(widget.eventKey));
    final notifier =
        ref.read(setlistEditorProvider(widget.eventKey).notifier);

    // ── Loading state ─────────────────────────────────────────────────────────
    if (state.isLoading) {
      return const CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(middle: Text('Setlist')),
        child: Center(child: CupertinoActivityIndicator()),
      );
    }

    // ── Hard-error state (no setlist loaded yet) ──────────────────────────────
    if (state.error != null && state.setlist == null) {
      return CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(middle: Text('Setlist')),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  CupertinoIcons.exclamationmark_circle,
                  size: 48,
                  color: CupertinoColors.systemRed,
                ),
                const SizedBox(height: 12),
                Text(state.error!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                CupertinoButton.filled(
                  onPressed: notifier.load,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // ── Loaded state ──────────────────────────────────────────────────────────
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Setlist'),
        trailing: state.canWrite
            ? CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: state.isDirty && !state.isSaving
                    ? () => notifier.save()
                    : null,
                child: state.isSaving
                    ? const CupertinoActivityIndicator(radius: 10)
                    : Text(
                        'Save',
                        style: TextStyle(
                          color: state.isDirty
                              ? CupertinoColors.activeBlue
                                  .resolveFrom(context)
                              : CupertinoColors.systemGrey
                                  .resolveFrom(context),
                        ),
                      ),
              )
            : null,
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Error banner for save/generate failures on an already-loaded
            // setlist. Distinct from the full-screen error (setlist == null).
            if (state.error != null) _ErrorBanner(message: state.error!),
            _StatusBar(
              eventKey: widget.eventKey,
              state: state,
            ),
            Expanded(child: _Body(
              eventKey: widget.eventKey,
              state: state,
              notifier: notifier,
            )),
            if (state.canWrite)
              _BottomToolbar(
                eventKey: widget.eventKey,
                state: state,
                notifier: notifier,
              ),
          ],
        ),
      ),
    );
  }
}

// ── Error banner ───────────────────────────────────────────────────────────────

/// Shown inside the loaded scaffold when [state.error] is non-null after a
/// failed save or generate call. Distinct from the full-screen error view
/// which is shown when no setlist has been loaded at all.
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: CupertinoColors.systemRed
          .resolveFrom(context)
          .withValues(alpha: 0.12),
      child: Text(
        message,
        style: TextStyle(
          fontSize: 13,
          color: CupertinoColors.systemRed.resolveFrom(context),
        ),
      ),
    );
  }
}

// ── Status bar ─────────────────────────────────────────────────────────────────

class _StatusBar extends ConsumerWidget {
  const _StatusBar({required this.eventKey, required this.state});

  final String eventKey;
  final SetlistEditorState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setlist = state.setlist;
    if (setlist == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: CupertinoColors.systemGrey6.resolveFrom(context),
        border: Border(
          bottom: BorderSide(
            color: CupertinoColors.separator.resolveFrom(context),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          // Status badge — Draft (grey) or Ready (green).
          // Resolved so they adapt correctly in dark mode.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: (setlist.isReady
                      ? CupertinoColors.systemGreen
                      : CupertinoColors.systemGrey)
                  .resolveFrom(context),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              setlist.isReady ? 'Ready' : 'Draft',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: CupertinoColors.white,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${setlist.songCount} songs',
            style: TextStyle(
              fontSize: 13,
              color: context.secondaryText,
            ),
          ),
          const Spacer(),
          if (state.canWrite && !setlist.isReady)
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero, // Flutter 3.41: use minimumSize, not minSize
              onPressed: setlist.songs.isEmpty
                  ? null
                  : () => ref
                      .read(setlistEditorProvider(eventKey).notifier)
                      .markReady(),
              child: const Text('Mark Ready', style: TextStyle(fontSize: 13)),
            ),
        ],
      ),
    );
  }
}

// ── Body ───────────────────────────────────────────────────────────────────────

class _Body extends StatelessWidget {
  const _Body({
    required this.eventKey,
    required this.state,
    required this.notifier,
  });

  final String eventKey;
  final SetlistEditorState state;
  final SetlistEditorNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final setlist = state.setlist;
    if (setlist == null || setlist.songs.isEmpty) {
      return _EmptyState(canWrite: state.canWrite);
    }

    // Precompute song numbers in a single O(n) pass so itemBuilder doesn't
    // redo this work on every frame for each item (was O(n²)).
    final songNumbers = <int>[];
    var counter = 0;
    for (final e in setlist.songs) {
      songNumbers.add(e.isBreak ? 0 : ++counter);
    }

    // ReorderableListView is Material-only; wrap with transparent Material
    // so no ink splashes bleed onto the Cupertino background.
    return Material(
      type: MaterialType.transparency,
      child: ReorderableListView.builder(
        // Disable the default trailing drag handle — it collides with the
        // edit/remove action buttons. Instead, the rows' leading number column
        // is wrapped in a ReorderableDragStartListener (see SetlistSongRow and
        // SetlistBreakRow's dragIndex parameter) when canWrite is true.
        buildDefaultDragHandles: false,
        itemCount: setlist.songs.length,
        onReorder: notifier.reorder,
        itemBuilder: (_, i) {
          final entry = setlist.songs[i];

          if (entry.isBreak) {
            return SetlistBreakRow(
              key: ValueKey('break-$i'),
              canWrite: state.canWrite,
              onRemove: () => notifier.removeAt(i),
              dragIndex: i,
            );
          }

          return SetlistSongRow(
            // Stable key: prefer persisted entry id; fall back to title+index
            // for locally-added songs not yet saved.
            key: ValueKey('song-${entry.id ?? entry.displayTitle}-$i'),
            entry: entry,
            songNumber: songNumbers[i],
            canWrite: state.canWrite,
            onEdit: () => _editEntry(context, i, entry, notifier),
            onRemove: () => notifier.removeAt(i),
            dragIndex: i,
          );
        },
      ),
    );
  }

  Future<void> _editEntry(
    BuildContext context,
    int index,
    SetlistEntry entry,
    SetlistEditorNotifier notifier,
  ) async {
    final notesController = TextEditingController(text: entry.notes ?? '');
    await showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Edit Notes'),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: CupertinoTextField(
            controller: notesController,
            placeholder: 'Slot notes…',
            maxLines: 3,
          ),
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(ctx),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            child: const Text('Save'),
            onPressed: () {
              notifier.updateEntry(
                index,
                entry.copyWith(notes: notesController.text.trim()),
              );
              Navigator.pop(ctx);
            },
          ),
        ],
      ),
    );
    notesController.dispose();
  }
}

// ── Empty state ────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.canWrite});

  final bool canWrite;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.music_note_list,
              size: 56,
              color: context.secondaryText,
            ),
            const SizedBox(height: 12),
            const Text(
              'No setlist yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              canWrite
                  ? 'Add songs manually or generate one with AI.'
                  : 'A setlist hasn\'t been created yet.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: context.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Bottom toolbar ─────────────────────────────────────────────────────────────

class _BottomToolbar extends ConsumerWidget {
  const _BottomToolbar({
    required this.eventKey,
    required this.state,
    required this.notifier,
  });

  final String eventKey;
  final SetlistEditorState state;
  final SetlistEditorNotifier notifier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // selectedBandProvider is AsyncNotifier<int?> — .value is the int directly,
    // NOT an object with an .id field. Gate Generate when null.
    final bandId = ref.watch(selectedBandProvider).value;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground.resolveFrom(context),
        border: Border(
          top: BorderSide(
            color: CupertinoColors.separator.resolveFrom(context),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          // ── Song ─────────────────────────────────────────────────────────
          Expanded(
            child: Semantics(
              label: 'Add song',
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(vertical: 8),
                onPressed: () async {
                  final result = await showSongPickerSheet(
                    context,
                    songs: state.bandSongs,
                  );
                  if (result == null) return;
                  if (result.isLibrary) {
                    notifier.addSong(result.song!, notes: result.notes);
                  } else {
                    // isCustom path
                    notifier.addCustomSong(
                      title: result.customTitle!,
                      artist: result.customArtist,
                      notes: result.notes,
                    );
                  }
                },
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(CupertinoIcons.add_circled, size: 22),
                    SizedBox(height: 2),
                    Text('Song', style: TextStyle(fontSize: 11)),
                  ],
                ),
              ),
            ),
          ),

          // ── Break ─────────────────────────────────────────────────────────
          Expanded(
            child: Semantics(
              label: 'Add set break',
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(vertical: 8),
                onPressed: notifier.addBreak,
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(CupertinoIcons.pause_circle, size: 22),
                    SizedBox(height: 2),
                    Text('Break', style: TextStyle(fontSize: 11)),
                  ],
                ),
              ),
            ),
          ),

          // ── Generate ──────────────────────────────────────────────────────
          Expanded(
            child: Semantics(
              label: state.isGenerating ? 'Generating setlist' : 'Generate setlist with AI',
              // Hint surfaces when the button is disabled due to no band.
              hint: bandId == null ? 'Select a band first' : null,
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(vertical: 8),
                // Disabled when no band is selected or generation is in flight.
                onPressed: bandId == null || state.isGenerating
                    ? null
                    : () async {
                        // TODO(setlist): subscribe to SetlistGenerationProgress on
                        // App.Models.User.{id} for live step display — Pusher wiring
                        // deferred; isGenerating spinner covers progress for now.
                        final req = await showGenerateSheet(
                          context,
                          bandId: bandId,
                        );
                        if (req != null) {
                          await notifier.generate(context: req.context);
                        }
                      },
                child: state.isGenerating
                    ? const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CupertinoActivityIndicator(radius: 10),
                          SizedBox(height: 2),
                          Text('Generating…', style: TextStyle(fontSize: 11)),
                        ],
                      )
                    : const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(CupertinoIcons.sparkles, size: 22),
                          SizedBox(height: 2),
                          Text('Generate', style: TextStyle(fontSize: 11)),
                        ],
                      ),
              ),
            ),
          ),

          // ── Refine ────────────────────────────────────────────────────────
          Expanded(
            child: Semantics(
              label: 'Refine setlist with AI',
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(vertical: 8),
                // Disabled when there are no songs to refine.
                onPressed: (state.setlist?.songs.isEmpty ?? true)
                    ? null
                    : () => showRefineSheet(context, eventKey: eventKey),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(CupertinoIcons.text_bubble, size: 22),
                    SizedBox(height: 2),
                    Text('Refine', style: TextStyle(fontSize: 11)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
