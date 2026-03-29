import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show DraggableScrollableSheet, Material, Theme, ThemeData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/band_song.dart';
import '../data/models/live_session.dart';
import '../data/models/queue_entry.dart';
import '../providers/live_session_provider.dart';

class LiveSessionScreen extends ConsumerStatefulWidget {
  const LiveSessionScreen({super.key, required this.eventKey});

  final String eventKey;

  @override
  ConsumerState<LiveSessionScreen> createState() => _LiveSessionScreenState();
}

class _LiveSessionScreenState extends ConsumerState<LiveSessionScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(liveSessionProvider(widget.eventKey).notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(liveSessionProvider(widget.eventKey));

    if (state.isLoading) {
      return const CupertinoPageScaffold(
        child: Center(child: CupertinoActivityIndicator()),
      );
    }

    if (state.error != null && state.session == null) {
      return CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(
            middle: Text('Live Setlist')),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(CupertinoIcons.exclamationmark_circle,
                  size: 48, color: CupertinoColors.systemRed),
              const SizedBox(height: 16),
              Text(state.error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              CupertinoButton.filled(
                onPressed: () => ref
                    .read(liveSessionProvider(widget.eventKey).notifier)
                    .load(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (state.session == null || state.session!.isCompleted) {
      return _NoSessionView(eventKey: widget.eventKey, canWrite: state.canWrite);
    }

    return _ActiveSessionView(eventKey: widget.eventKey);
  }
}

class _NoSessionView extends ConsumerWidget {
  const _NoSessionView({required this.eventKey, required this.canWrite});

  final String eventKey;
  final bool canWrite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CupertinoPageScaffold(
      navigationBar:
          const CupertinoNavigationBar(middle: Text('Live Setlist')),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                CupertinoIcons.music_note_list,
                size: 64,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
              const SizedBox(height: 16),
              const Text(
                'No active session',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                canWrite
                    ? 'Start a session to go live.'
                    : 'Waiting for the captain to start the session.',
                style: TextStyle(
                    fontSize: 15,
                    color: CupertinoColors.secondaryLabel.resolveFrom(context)),
                textAlign: TextAlign.center,
              ),
              if (canWrite) ...[
                const SizedBox(height: 24),
                CupertinoButton.filled(
                  onPressed: () => ref
                      .read(liveSessionProvider(eventKey).notifier)
                      .startSession(),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(CupertinoIcons.play_arrow_solid, size: 18),
                      SizedBox(width: 8),
                      Text('Start Session'),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveSessionView extends ConsumerWidget {
  const _ActiveSessionView({required this.eventKey});

  final String eventKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(liveSessionProvider(eventKey));
    final session = state.session!;
    final notifier = ref.read(liveSessionProvider(eventKey).notifier);

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Live Setlist'),
        trailing: state.isCaptain && session.isActive
            ? CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () =>
                    _showCaptainMenu(context, state, notifier),
                child: const Icon(CupertinoIcons.ellipsis),
              )
            : null,
      ),
      child: Column(
        children: [
          if (session.isOnBreak)
            _BreakBanner(
              eventKey: eventKey,
              songs: state.songs,
              isCaptain: state.isCaptain,
            ),
          _NowPlayingCard(
            session: session,
            isCaptain: state.isCaptain,
            notifier: notifier,
          ),
          Expanded(
            child: _QueueList(
              session: session,
              isCaptain: state.isCaptain,
              notifier: notifier,
            ),
          ),
          if (state.isCaptain && session.isActive)
            Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: CupertinoButton(
                  onPressed: () =>
                      _showSongPicker(context, state.songs, notifier),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(CupertinoIcons.add, size: 18),
                      SizedBox(width: 6),
                      Text('Add Song'),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showCaptainMenu(
    BuildContext context,
    LiveSessionState state,
    LiveSessionNotifier notifier,
  ) {
    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(context);
              await notifier.startBreak();
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.hourglass, size: 18),
                SizedBox(width: 8),
                Text('Start Break'),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () async {
              Navigator.pop(context);
              _confirmEndSession(context, notifier);
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.stop_circle, size: 18),
                SizedBox(width: 8),
                Text('End Session'),
              ],
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  Future<void> _confirmEndSession(
    BuildContext context,
    LiveSessionNotifier notifier,
  ) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('End Session?'),
        content: const Text(
            'This will end the live setlist session for everyone.'),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context, false),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('End Session'),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (confirmed == true) await notifier.endSession();
  }

  Future<void> _showSongPicker(
    BuildContext context,
    List<BandSong> songs,
    LiveSessionNotifier notifier,
  ) async {
    final selected = await showCupertinoModalPopup<BandSong>(
      context: context,
      builder: (ctx) => Theme(
        data: ThemeData(brightness: MediaQuery.platformBrightnessOf(ctx)),
        child: Material(
          child: DraggableScrollableSheet(
            initialChildSize: 0.7,
            minChildSize: 0.4,
            maxChildSize: 0.95,
            expand: false,
            builder: (_, controller) => _SongPickerSheet(
              songs: songs,
              scrollController: controller,
            ),
          ),
        ),
      ),
    );

    if (selected != null) {
      await notifier.addOffSetlist(selected.id);
    }
  }
}

class _BreakBanner extends ConsumerWidget {
  const _BreakBanner({
    required this.eventKey,
    required this.songs,
    required this.isCaptain,
  });

  final String eventKey;
  final List<BandSong> songs;
  final bool isCaptain;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: double.infinity,
      color: CupertinoColors.systemOrange.resolveFrom(context).withValues(alpha: 0.15),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(CupertinoIcons.hourglass,
              color: CupertinoColors.systemOrange.resolveFrom(context)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'On Break',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: CupertinoColors.systemOrange.resolveFrom(context),
              ),
            ),
          ),
          if (isCaptain)
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => _resumeBreak(context, ref),
              child: const Text('Resume'),
            ),
        ],
      ),
    );
  }

  Future<void> _resumeBreak(BuildContext context, WidgetRef ref) async {
    final selected = await showCupertinoModalPopup<BandSong>(
      context: context,
      builder: (ctx) => Theme(
        data: ThemeData(brightness: MediaQuery.platformBrightnessOf(ctx)),
        child: Material(
          child: DraggableScrollableSheet(
            initialChildSize: 0.7,
            minChildSize: 0.4,
            maxChildSize: 0.95,
            expand: false,
            builder: (_, controller) => _SongPickerSheet(
              songs: songs,
              scrollController: controller,
              title: 'First song back from break',
            ),
          ),
        ),
      ),
    );

    if (selected != null) {
      await ref
          .read(liveSessionProvider(eventKey).notifier)
          .resumeFromBreak(selected.id);
    }
  }
}

class _NowPlayingCard extends StatelessWidget {
  const _NowPlayingCard({
    required this.session,
    required this.isCaptain,
    required this.notifier,
  });

  final LiveSession session;
  final bool isCaptain;
  final LiveSessionNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final current = session.currentSong;
    final next = session.nextSong;

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(CupertinoIcons.music_note,
                  color: CupertinoColors.systemBlue.resolveFrom(context), size: 18),
              const SizedBox(width: 6),
              Text(
                'NOW PLAYING',
                style: TextStyle(
                  color: CupertinoColors.systemBlue.resolveFrom(context),
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (current != null) ...[
            Text(
              current.title ?? 'Unknown',
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold),
            ),
            if (current.artist != null)
              Text(
                current.artist!,
                style: TextStyle(
                    fontSize: 15,
                    color: CupertinoColors.secondaryLabel.resolveFrom(context)),
              ),
            if (current.leadSinger != null || current.songKey != null) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                children: [
                  if (current.leadSinger != null)
                    _Chip(
                        label: current.leadSinger!,
                        icon: CupertinoIcons.mic),
                  if (current.songKey != null)
                    _Chip(label: 'Key: ${current.songKey!}'),
                  if (current.bpm != null)
                    _Chip(label: '${current.bpm!.toInt()} BPM'),
                ],
              ),
            ],
          ] else
            Text(
              session.isOnBreak ? 'On Break' : 'Queue empty',
              style: TextStyle(
                  fontSize: 17,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context)),
            ),

          if (isCaptain && current != null && session.isActive) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                _ReactionButton(
                  icon: CupertinoIcons.hand_thumbsup,
                  color: CupertinoColors.systemGreen.resolveFrom(context),
                  onPressed: () => notifier.react(current.id, 'positive'),
                ),
                const SizedBox(width: 8),
                _ReactionButton(
                  icon: CupertinoIcons.hand_thumbsdown,
                  color: CupertinoColors.systemRed.resolveFrom(context),
                  onPressed: () => notifier.react(current.id, 'negative'),
                ),
                const Spacer(),
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  onPressed: notifier.skip,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(CupertinoIcons.forward_end, size: 16),
                      SizedBox(width: 4),
                      Text('Skip'),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                CupertinoButton.filled(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  onPressed: notifier.next,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(CupertinoIcons.checkmark, size: 16),
                      SizedBox(width: 4),
                      Text('Next'),
                    ],
                  ),
                ),
              ],
            ),
          ],

          if (next != null) ...[
            Container(
                height: 0.5,
                color: CupertinoColors.separator.resolveFrom(context),
                margin: const EdgeInsets.symmetric(vertical: 10)),
            Row(
              children: [
                Icon(CupertinoIcons.list_bullet_below_rectangle,
                    size: 16, color: CupertinoColors.secondaryLabel.resolveFrom(context)),
                const SizedBox(width: 6),
                Text(
                  'UP NEXT',
                  style: TextStyle(
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                    letterSpacing: 1.1,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    next.title ?? 'Unknown',
                    style: const TextStyle(fontSize: 15),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _QueueList extends StatelessWidget {
  const _QueueList({
    required this.session,
    required this.isCaptain,
    required this.notifier,
  });

  final LiveSession session;
  final bool isCaptain;
  final LiveSessionNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final pending = session.queue
        .where(
            (e) => e.isPending && e.position > session.currentPosition)
        .toList()
      ..sort((a, b) => a.position.compareTo(b.position));

    final played = session.queue.where((e) => e.isPlayed).toList()
      ..sort((a, b) => b.position.compareTo(a.position));

    if (pending.isEmpty && played.isEmpty) {
      return const Center(child: Text('Queue is empty.'));
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      children: [
        if (pending.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'UPCOMING',
              style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 1.2,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context)),
            ),
          ),
          ...pending.map(
              (e) => _QueueTile(entry: e, isCaptain: isCaptain)),
        ],
        if (played.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'PLAYED',
              style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 1.2,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context)),
            ),
          ),
          ...played
              .map((e) => _QueueTile(entry: e, isCaptain: false)),
        ],
      ],
    );
  }
}

class _QueueTile extends StatelessWidget {
  const _QueueTile({
    required this.entry,
    required this.isCaptain,
  });

  final QueueEntry entry;
  final bool isCaptain;

  @override
  Widget build(BuildContext context) {
    final isPlayed = entry.isPlayed;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isPlayed
                  ? CupertinoColors.tertiarySystemBackground.resolveFrom(context)
                  : CupertinoColors.systemBlue.resolveFrom(context).withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: isPlayed
                  ? Icon(CupertinoIcons.checkmark,
                      size: 14,
                      color: CupertinoColors.secondaryLabel.resolveFrom(context))
                  : Text(
                      '${entry.position}',
                      style: TextStyle(
                        color: CupertinoColors.systemBlue.resolveFrom(context),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.isBreak ? '— Break —' : (entry.title ?? 'Unknown'),
                  style: TextStyle(
                    fontSize: 15,
                    color: isPlayed
                        ? CupertinoColors.secondaryLabel.resolveFrom(context)
                        : CupertinoColors.label.resolveFrom(context),
                    decoration: isPlayed ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (entry.artist != null && !isPlayed)
                  Text(
                    entry.artist!,
                    style: TextStyle(
                        fontSize: 13,
                        color: CupertinoColors.secondaryLabel.resolveFrom(context)),
                  ),
              ],
            ),
          ),
          if (entry.crowdReaction != null)
            Icon(
              entry.crowdReaction == 'positive'
                  ? CupertinoIcons.hand_thumbsup_fill
                  : entry.crowdReaction == 'negative'
                      ? CupertinoIcons.hand_thumbsdown_fill
                      : CupertinoIcons.minus_circle,
              size: 16,
              color: entry.crowdReaction == 'positive'
                  ? CupertinoColors.systemGreen.resolveFrom(context)
                  : entry.crowdReaction == 'negative'
                      ? CupertinoColors.systemRed.resolveFrom(context)
                      : CupertinoColors.systemGrey.resolveFrom(context),
            ),
        ],
      ),
    );
  }
}

class _SongPickerSheet extends StatefulWidget {
  const _SongPickerSheet({
    required this.songs,
    required this.scrollController,
    this.title = 'Add Song',
  });

  final List<BandSong> songs;
  final ScrollController scrollController;
  final String title;

  @override
  State<_SongPickerSheet> createState() => _SongPickerSheetState();
}

class _SongPickerSheetState extends State<_SongPickerSheet> {
  String _query = '';
  final _queryController = TextEditingController();

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _query.isEmpty
        ? widget.songs
        : widget.songs.where((s) {
            final q = _query.toLowerCase();
            return (s.title.toLowerCase().contains(q)) ||
                (s.artist?.toLowerCase().contains(q) ?? false);
          }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(widget.title,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w600)),
              ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => Navigator.pop(context),
                child: const Icon(CupertinoIcons.xmark),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: CupertinoSearchTextField(
            controller: _queryController,
            placeholder: 'Search songs…',
            autofocus: true,
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: widget.scrollController,
            itemCount: filtered.length,
            itemBuilder: (_, i) {
              final song = filtered[i];
              return GestureDetector(
                onTap: () => Navigator.pop(context, song),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(song.title,
                                style: const TextStyle(fontSize: 15)),
                            if (song.artist != null)
                              Text(song.artist!,
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: CupertinoColors.secondaryLabel.resolveFrom(context))),
                          ],
                        ),
                      ),
                      if (song.songKey != null)
                        _Chip(label: song.songKey!),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: CupertinoColors.secondaryLabel.resolveFrom(context)),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
                fontSize: 12, color: CupertinoColors.secondaryLabel.resolveFrom(context)),
          ),
        ],
      ),
    );
  }
}

class _ReactionButton extends StatelessWidget {
  const _ReactionButton({
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.4)),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }
}
