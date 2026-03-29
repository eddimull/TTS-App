import 'package:flutter/material.dart';
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
    // Load after first frame so the provider is ready.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(liveSessionProvider(widget.eventKey).notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(liveSessionProvider(widget.eventKey));

    if (state.isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (state.error != null && state.session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Live Setlist')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(state.error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () =>
                    ref.read(liveSessionProvider(widget.eventKey).notifier).load(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    // No active session — show start button for users who can write.
    if (state.session == null || state.session!.isCompleted) {
      return _NoSessionView(eventKey: widget.eventKey, canWrite: state.canWrite);
    }

    return _ActiveSessionView(eventKey: widget.eventKey);
  }
}

// ── No session ─────────────────────────────────────────────────────────────────

class _NoSessionView extends ConsumerWidget {
  const _NoSessionView({required this.eventKey, required this.canWrite});

  final String eventKey;
  final bool canWrite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Live Setlist')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.music_off_outlined,
                size: 64,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                'No active session',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                canWrite
                    ? 'Start a session to go live.'
                    : 'Waiting for the captain to start the session.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              if (canWrite) ...[
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () =>
                      ref.read(liveSessionProvider(eventKey).notifier).startSession(),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start Session'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(200, 48),
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

// ── Active session ─────────────────────────────────────────────────────────────

class _ActiveSessionView extends ConsumerWidget {
  const _ActiveSessionView({required this.eventKey});

  final String eventKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(liveSessionProvider(eventKey));
    final session = state.session!;
    final notifier = ref.read(liveSessionProvider(eventKey).notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Setlist'),
        actions: [
          if (state.isCaptain && session.isActive)
            PopupMenuButton<_CaptainMenu>(
              onSelected: (action) => _handleCaptainMenu(context, action, state, notifier),
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: _CaptainMenu.startBreak,
                  child: ListTile(
                    leading: Icon(Icons.free_breakfast_outlined),
                    title: Text('Start Break'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: _CaptainMenu.endSession,
                  child: ListTile(
                    leading: Icon(Icons.stop_circle_outlined, color: Colors.red),
                    title: Text('End Session', style: TextStyle(color: Colors.red)),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          // Status banner.
          if (session.isOnBreak)
            _BreakBanner(
              eventKey: eventKey,
              songs: state.songs,
              isCaptain: state.isCaptain,
            ),
          // Current + next song.
          _NowPlayingCard(
            session: session,
            isCaptain: state.isCaptain,
            notifier: notifier,
          ),
          // Queue list.
          Expanded(
            child: _QueueList(
              session: session,
              isCaptain: state.isCaptain,
              notifier: notifier,
            ),
          ),
          // Add off-setlist button for captains.
          if (state.isCaptain && session.isActive)
            Padding(
              padding: const EdgeInsets.all(12),
              child: OutlinedButton.icon(
                onPressed: () => _showSongPicker(context, state.songs, notifier),
                icon: const Icon(Icons.add),
                label: const Text('Add Song'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _handleCaptainMenu(
    BuildContext context,
    _CaptainMenu action,
    LiveSessionState _,
    LiveSessionNotifier notifier,
  ) async {
    switch (action) {
      case _CaptainMenu.startBreak:
        await notifier.startBreak();
      case _CaptainMenu.endSession:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('End Session?'),
            content: const Text('This will end the live setlist session for everyone.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('End Session'),
              ),
            ],
          ),
        );
        if (confirmed == true) await notifier.endSession();
    }
  }

  Future<void> _showSongPicker(
    BuildContext context,
    List<BandSong> songs,
    LiveSessionNotifier notifier,
  ) async {
    final selected = await showModalBottomSheet<BandSong>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, controller) => _SongPickerSheet(
          songs: songs,
          scrollController: controller,
        ),
      ),
    );

    if (selected != null) {
      await notifier.addOffSetlist(selected.id);
    }
  }
}

enum _CaptainMenu { startBreak, endSession }

// ── Break banner ───────────────────────────────────────────────────────────────

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
      color: Colors.amber.shade100,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.free_breakfast_outlined, color: Colors.amber),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'On Break',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.amber,
              ),
            ),
          ),
          if (isCaptain)
            TextButton(
              onPressed: () => _resumeBreak(context, ref),
              child: const Text('Resume'),
            ),
        ],
      ),
    );
  }

  Future<void> _resumeBreak(BuildContext context, WidgetRef ref) async {
    final selected = await showModalBottomSheet<BandSong>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
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
    );

    if (selected != null) {
      await ref.read(liveSessionProvider(eventKey).notifier).resumeFromBreak(selected.id);
    }
  }
}

// ── Now playing card ───────────────────────────────────────────────────────────

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
    final theme = Theme.of(context);
    final current = session.currentSong;
    final next = session.nextSong;

    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Now playing.
            Row(
              children: [
                Icon(Icons.music_note, color: theme.colorScheme.primary, size: 18),
                const SizedBox(width: 6),
                Text(
                  'NOW PLAYING',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (current != null) ...[
              Text(
                current.title ?? 'Unknown',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (current.artist != null)
                Text(
                  current.artist!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              if (current.leadSinger != null || current.songKey != null) ...[
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: [
                    if (current.leadSinger != null)
                      _Chip(label: current.leadSinger!, icon: Icons.mic_outlined),
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
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),

            // Captain controls.
            if (isCaptain && current != null && session.isActive) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  // Reaction buttons.
                  _ReactionButton(
                    icon: Icons.thumb_up_outlined,
                    color: Colors.green,
                    onPressed: () => notifier.react(current.id, 'positive'),
                  ),
                  const SizedBox(width: 8),
                  _ReactionButton(
                    icon: Icons.thumb_down_outlined,
                    color: Colors.red,
                    onPressed: () => notifier.react(current.id, 'negative'),
                  ),
                  const Spacer(),
                  // Skip.
                  OutlinedButton.icon(
                    onPressed: notifier.skip,
                    icon: const Icon(Icons.skip_next, size: 18),
                    label: const Text('Skip'),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Next.
                  FilledButton.icon(
                    onPressed: notifier.next,
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Next'),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ],

            // Up next.
            if (next != null) ...[
              const Divider(height: 20),
              Row(
                children: [
                  Icon(Icons.queue_music, size: 16, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    'UP NEXT',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      next.title ?? 'Unknown',
                      style: theme.textTheme.bodyMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Queue list ─────────────────────────────────────────────────────────────────

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
        .where((e) => e.isPending && e.position > session.currentPosition)
        .toList()
      ..sort((a, b) => a.position.compareTo(b.position));

    final played = session.queue
        .where((e) => e.isPlayed)
        .toList()
      ..sort((a, b) => b.position.compareTo(a.position));

    if (pending.isEmpty && played.isEmpty) {
      return const Center(
        child: Text('Queue is empty.'),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      children: [
        if (pending.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'UPCOMING (${pending.length})',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.2,
                  ),
            ),
          ),
          ...pending.map((e) => _QueueTile(entry: e, isCaptain: isCaptain, notifier: notifier)),
        ],
        if (played.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'PLAYED',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.2,
                  ),
            ),
          ),
          ...played.map((e) => _QueueTile(entry: e, isCaptain: false, notifier: notifier)),
        ],
      ],
    );
  }
}

class _QueueTile extends StatelessWidget {
  const _QueueTile({
    required this.entry,
    required this.isCaptain,
    required this.notifier,
  });

  final QueueEntry entry;
  final bool isCaptain;
  final LiveSessionNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPlayed = entry.isPlayed;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: isPlayed
            ? theme.colorScheme.surfaceContainerHighest
            : theme.colorScheme.primaryContainer,
        child: isPlayed
            ? Icon(Icons.check, size: 16, color: theme.colorScheme.onSurfaceVariant)
            : Text(
                '${entry.position}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
      title: Text(
        entry.isBreak ? '— Break —' : (entry.title ?? 'Unknown'),
        style: theme.textTheme.bodyMedium?.copyWith(
          color: isPlayed ? theme.colorScheme.onSurfaceVariant : null,
          decoration: isPlayed ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: entry.artist != null && !isPlayed
          ? Text(
              entry.artist!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : null,
      trailing: entry.crowdReaction != null
          ? Icon(
              entry.crowdReaction == 'positive'
                  ? Icons.thumb_up
                  : entry.crowdReaction == 'negative'
                      ? Icons.thumb_down
                      : Icons.remove,
              size: 16,
              color: entry.crowdReaction == 'positive'
                  ? Colors.green
                  : entry.crowdReaction == 'negative'
                      ? Colors.red
                      : Colors.grey,
            )
          : null,
    );
  }
}

// ── Song picker sheet ──────────────────────────────────────────────────────────

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(widget.title, style: theme.textTheme.titleMedium),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: TextField(
            autofocus: true,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search songs…',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: widget.scrollController,
            itemCount: filtered.length,
            itemBuilder: (_, i) {
              final song = filtered[i];
              return ListTile(
                title: Text(song.title),
                subtitle: song.artist != null ? Text(song.artist!) : null,
                trailing: song.songKey != null
                    ? _Chip(label: song.songKey!)
                    : null,
                onTap: () => Navigator.pop(context, song),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Small widgets ──────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  const _Chip({required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
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
    return IconButton.outlined(
      onPressed: onPressed,
      icon: Icon(icon, color: color, size: 20),
      style: IconButton.styleFrom(
        side: BorderSide(color: color.withValues(alpha: 0.4)),
      ),
    );
  }
}
