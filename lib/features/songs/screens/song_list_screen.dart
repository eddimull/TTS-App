import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';
import 'package:tts_bandmate/shared/widgets/empty_state_view.dart';
import 'package:tts_bandmate/shared/widgets/error_view.dart';

import '../../auth/providers/auth_provider.dart';
import '../../../shared/providers/selected_band_provider.dart';
import '../data/models/song.dart';
import '../providers/songs_provider.dart';

/// The band's song list (repertoire) — browse, search, add, edit, and
/// (owner-only) delete. Rendered inside the segmented Library tab and pushed
/// standalone from the Operations screen ('/songs').
class SongListScreen extends ConsumerStatefulWidget {
  /// Whether this screen is pushed as its own route with no tab bar below
  /// (e.g. `/songs`), so the bottom bar must absorb the home-indicator inset
  /// itself. When embedded in [LibraryTabScreen], the `CupertinoTabBar`
  /// already consumes that inset, so leave this false to avoid double
  /// padding.
  const SongListScreen({super.key, this.standalone = false});

  final bool standalone;

  @override
  ConsumerState<SongListScreen> createState() => _SongListScreenState();
}

class _SongListScreenState extends ConsumerState<SongListScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() => ref.read(songsProvider.notifier).refresh();

  /// Whether the current user owns the selected band. Computed from watched
  /// providers (not `ref.read`) so the row's delete affordance updates once
  /// auth/band resolve — those can still be loading on the frame the songs
  /// list first renders, since [songsProvider] resolves independently.
  bool _isOwner(WidgetRef ref) {
    final auth = ref.watch(authProvider).value;
    final bandId = ref.watch(selectedBandProvider).value;
    if (auth is! AuthAuthenticated || bandId == null) return false;
    return auth.bands.where((b) => b.id == bandId).firstOrNull?.isOwner ??
        false;
  }

  Future<void> _openCreateAndMaybeOpenDetail() async {
    final created = await context.push<Song>('/songs/new');
    if (!mounted || created == null) return;
    context.push('/songs/${created.id}');
  }

  Future<void> _confirmDeleteSong(Song song) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Delete Song'),
        content: Text(
            'Are you sure you want to delete "${song.title}"? Linked sheet music is kept. This cannot be undone.'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await ref.read(songsProvider.notifier).deleteSong(song.id);
    } catch (e) {
      if (mounted) {
        showCupertinoDialog<void>(
          context: context,
          builder: (ctx) => CupertinoAlertDialog(
            title: const Text('Delete Failed'),
            content: Text(ErrorView.friendlyMessage(e)),
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
  }

  List<Song> _visibleSongs(SongsState state, bool showInactive) {
    var songs = state.songs.where((s) => showInactive || s.active);
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      songs = songs.where((s) =>
          s.title.toLowerCase().contains(q) ||
          s.artist.toLowerCase().contains(q));
    }
    return songs.toList();
  }

  @override
  Widget build(BuildContext context) {
    final songsAsync = ref.watch(songsProvider);
    final showInactive = ref.watch(showInactiveSongsProvider);
    final isOwner = _isOwner(ref);

    return CupertinoPageScaffold(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth =
              constraints.maxWidth > 700 ? 700.0 : constraints.maxWidth;

          return Center(
            child: SizedBox(
              width: maxWidth,
              child: Column(
                children: [
                  Expanded(
                    child: songsAsync.when(
                      loading: () =>
                          const Center(child: CupertinoActivityIndicator()),
                      error: (e, _) => CustomScrollView(
                        slivers: [
                          _buildNavBar(context, showInactive),
                          SliverFillRemaining(
                            child: ErrorView(
                              message: ErrorView.friendlyMessage(e),
                              onRetry: _refresh,
                            ),
                          ),
                        ],
                      ),
                      data: (state) {
                        final visible = _visibleSongs(state, showInactive);

                        return CustomScrollView(
                          slivers: [
                            CupertinoSliverRefreshControl(onRefresh: _refresh),
                            _buildNavBar(context, showInactive),
                            if (state.songs.isEmpty)
                              const SliverFillRemaining(
                                child: EmptyStateView(
                                  icon: CupertinoIcons.music_mic,
                                  title: 'No songs yet',
                                  subtitle:
                                      'Add the songs your band plays to build setlists faster.',
                                ),
                              )
                            else if (visible.isEmpty)
                              SliverFillRemaining(
                                child: Center(
                                  child: Text(
                                    'No matching songs',
                                    style:
                                        TextStyle(color: context.secondaryText),
                                  ),
                                ),
                              )
                            else
                              SliverList(
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) {
                                    final song = visible[index];
                                    return _SongRow(
                                      song: song,
                                      showSeparator: index < visible.length - 1,
                                      onTap: () =>
                                          context.push('/songs/${song.id}'),
                                      onDelete: isOwner
                                          ? () => _confirmDeleteSong(song)
                                          : null,
                                    );
                                  },
                                  childCount: visible.length,
                                ),
                              ),
                            const SliverToBoxAdapter(
                                child: SizedBox(height: 16)),
                          ],
                        );
                      },
                    ),
                  ),
                  if (widget.standalone)
                    SafeArea(
                      top: false,
                      child: _BottomSearchBar(
                        controller: _searchController,
                        onChanged: (v) => setState(() => _query = v.trim()),
                        onAdd: _openCreateAndMaybeOpenDetail,
                      ),
                    )
                  else
                    _BottomSearchBar(
                      controller: _searchController,
                      onChanged: (v) => setState(() => _query = v.trim()),
                      onAdd: _openCreateAndMaybeOpenDetail,
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildNavBar(BuildContext context, bool showInactive) {
    return CupertinoSliverNavigationBar(
      largeTitle: const Text('Song list'),
      trailing: Semantics(
        button: true,
        toggled: showInactive,
        label: showInactive ? 'Hide inactive songs' : 'Show inactive songs',
        child: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () =>
              ref.read(showInactiveSongsProvider.notifier).toggle(),
          child: Icon(
            showInactive ? CupertinoIcons.eye_fill : CupertinoIcons.eye_slash,
          ),
        ),
      ),
    );
  }
}

// ── Song row ──────────────────────────────────────────────────────────────────

class _SongRow extends StatelessWidget {
  const _SongRow({
    required this.song,
    required this.showSeparator,
    this.onTap,
    this.onDelete,
  });

  final Song song;
  final bool showSeparator;
  final VoidCallback? onTap;

  /// Null when the current user is not an owner of the selected band —
  /// long-press deletion is an owner-only affordance (server enforces too).
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: song.artist.isNotEmpty
          ? '${song.title}, by ${song.artist}'
          : song.title,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: onDelete,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: showSeparator
              ? BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: CupertinoColors.separator.resolveFrom(context),
                      width: 0.5,
                    ),
                  ),
                )
              : null,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w400),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (song.artist.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        song.artist,
                        style: TextStyle(
                          fontSize: 13,
                          color: context.secondaryText,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (!song.active)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemGrey5.resolveFrom(context),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Inactive',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: context.secondaryText,
                    ),
                  ),
                ),
              if (song.songKey.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    song.songKey,
                    style: TextStyle(
                      fontSize: 13,
                      color: context.secondaryText,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(
                  CupertinoIcons.chevron_right,
                  size: 14,
                  color: context.tertiaryText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Bottom search bar (matches the library screen's) ─────────────────────────

class _BottomSearchBar extends StatelessWidget {
  const _BottomSearchBar({
    required this.controller,
    required this.onChanged,
    required this.onAdd,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground.resolveFrom(context),
        border: Border(
          top: BorderSide(
            color: CupertinoColors.separator.resolveFrom(context),
            width: 0.5,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: CupertinoSearchTextField(
              controller: controller,
              onChanged: onChanged,
              placeholder: 'Search',
            ),
          ),
          const SizedBox(width: 10),
          Semantics(
            button: true,
            enabled: onAdd != null,
            label: 'Add song',
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: onAdd,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: onAdd == null
                      ? CupertinoColors.systemGrey4.resolveFrom(context)
                      : CupertinoColors.activeBlue.resolveFrom(context),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(
                  CupertinoIcons.plus,
                  color: CupertinoColors.white,
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
