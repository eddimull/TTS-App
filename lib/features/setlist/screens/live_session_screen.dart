import 'package:collection/collection.dart' show MapEquality;
import 'package:flutter/cupertino.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter/material.dart'
    show DraggableScrollableSheet, Material, Theme, ThemeData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../data/models/band_song.dart';
import '../data/models/client_notes.dart';
import '../../setlist_editor/data/models/event_setlist.dart'
    show ClientSongStatus;
import '../../setlist_editor/widgets/client_request_marker.dart';
import '../data/models/live_session.dart';
import '../data/models/queue_entry.dart';
import '../providers/live_session_provider.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';
import 'package:tts_bandmate/shared/providers/connectivity_provider.dart';

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

    // Reconnect revalidation: after the offline cached fallback (error
    // cleared, controls disabled — see LiveSessionNotifier.load's catch
    // branch), nothing re-fetches on its own when connectivity returns. Mirror
    // the offline→online edge detection in AppScaffold's connectivityProvider
    // listener so the captain regains write access without leaving the screen.
    ref.listen(connectivityProvider, (previous, next) {
      final wasOffline = previous?.value == false;
      final isOnline = next.value == true;
      if (wasOffline && isOnline) {
        ref.read(liveSessionProvider(widget.eventKey).notifier).load();
      }
    });

    if (state.isLoading) {
      return CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          leading: _LiveBackButton(eventKey: widget.eventKey),
          middle: const Text('Live Setlist'),
        ),
        child: const Center(child: CupertinoActivityIndicator()),
      );
    }

    if (state.error != null && state.session == null) {
      return CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          leading: _LiveBackButton(eventKey: widget.eventKey),
          middle: const Text('Live Setlist'),
        ),
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
      return _NoSessionView(
          eventKey: widget.eventKey, canWrite: state.canWrite);
    }

    return _ActiveSessionView(eventKey: widget.eventKey);
  }
}

/// Leaves the live screen without ending the session. Explicit rather than
/// the nav bar's implied back button, which is missing when this screen was
/// opened directly (push notification, deep link) — and iOS has no system
/// back gesture to fall back on. With nothing to pop, goes to the event.
class _LiveBackButton extends StatelessWidget {
  const _LiveBackButton({required this.eventKey});

  final String eventKey;

  @override
  Widget build(BuildContext context) {
    return CupertinoNavigationBarBackButton(
      previousPageTitle: 'Event',
      onPressed: () {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/events/$eventKey');
        }
      },
    );
  }
}

class _NoSessionView extends ConsumerWidget {
  const _NoSessionView({required this.eventKey, required this.canWrite});

  final String eventKey;
  final bool canWrite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        leading: _LiveBackButton(eventKey: eventKey),
        middle: const Text('Live Setlist'),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                CupertinoIcons.music_note_list,
                size: 64,
                color: context.secondaryText,
              ),
              const SizedBox(height: 16),
              const Text(
                'No active session',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                canWrite
                    ? 'Plays through the event\'s setlist if it has one — or pick '
                        'songs as you go. You\'ll be the captain and the band '
                        'follows along.'
                    : 'Waiting for the captain to start the session.',
                style: TextStyle(fontSize: 15, color: context.secondaryText),
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

/// Gives each singer a fixed color so the captain can scan lists by color
/// instead of reading names. Assigned in alphabetical singer order, so a
/// singer keeps their color across the picker, queue and Now Playing.
class _SingerColors extends InheritedWidget {
  _SingerColors({required Iterable<BandSong> songs, required super.child})
      : _index = {
          for (final (i, name) in ({
            for (final s in songs)
              if ((s.leadSinger?.trim() ?? '').isNotEmpty) s.leadSinger!.trim(),
          }.toList()
                ..sort())
              .indexed)
            name: i,
        };

  final Map<String, int> _index;

  // Distinct hues; blue is left out (it means "selected"/action in this app)
  // and red goes last (it also means remove / thumbs-down).
  static const _palette = [
    CupertinoColors.systemPink,
    CupertinoColors.systemOrange,
    CupertinoColors.systemGreen,
    CupertinoColors.systemPurple,
    CupertinoColors.systemTeal,
    CupertinoColors.systemYellow,
    CupertinoColors.systemIndigo,
    CupertinoColors.systemBrown,
    CupertinoColors.systemRed,
  ];

  /// The singer's color, or null for no singer / outside a live screen.
  static Color? of(BuildContext context, String? singer) {
    final name = singer?.trim() ?? '';
    if (name.isEmpty) return null;
    final i = context
        .dependOnInheritedWidgetOfExactType<_SingerColors>()
        ?._index[name];
    if (i == null) return null;
    return _palette[i % _palette.length].resolveFrom(context);
  }

  @override
  bool updateShouldNotify(_SingerColors old) =>
      !const MapEquality<String, int>().equals(old._index, _index);
}

/// Readable text color on a solid [background].
Color _onColor(Color background) => background.computeLuminance() > 0.5
    ? CupertinoColors.black
    : CupertinoColors.white;

class _ActiveSessionView extends ConsumerWidget {
  const _ActiveSessionView({required this.eventKey});

  final String eventKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(liveSessionProvider(eventKey));
    final session = state.session!;
    final notifier = ref.read(liveSessionProvider(eventKey).notifier);

    return _SingerColors(
      songs: state.songs,
      child: CupertinoPageScaffold(
      // The keyboard only ever belongs to the song picker sheet on top; don't
      // squeeze this screen under it (overflowed in landscape).
      resizeToAvoidBottomInset: false,
      navigationBar: CupertinoNavigationBar(
        leading: _LiveBackButton(eventKey: eventKey),
        middle: const Text('Live Setlist'),
        trailing: state.isCaptain && session.isActive
            ? CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => _showCaptainMenu(context, state, notifier),
                child: const Icon(CupertinoIcons.ellipsis),
              )
            : null,
      ),
      child: OrientationBuilder(
        builder: (context, orientation) {
          final canPick = state.isCaptain && session.isActive;
          if (!canPick) return _buildMain(context, state, notifier, docked: false);

          // The captain's song list stays docked on screen — beside the
          // queue in landscape, below it in portrait — so a single tap
          // queues a song, no popup.
          final landscape = orientation == Orientation.landscape;
          final picker = _SongPickerSheet(
            songs: state.songs,
            title: session.isDynamic ? 'Tap to queue' : 'Tap to play next',
            playedIds: _songIds(session, (e) => e.isPlayed),
            queuedIds: _songIds(session, (e) => e.isPending),
            mustPlayIds: state.mustPlayIds,
            ifTimeIds: state.ifTimeIds,
            doNotPlayIds: state.doNotPlayIds,
            requests: state.clientNotes?.pickable.toList() ?? const [],
            takenTitles: {
              for (final e in session.queue)
                if (e.songId == null && (e.isPending || e.isPlayed))
                  (e.title ?? '').trim().toLowerCase(),
            },
            onPickCustom: (r) =>
                notifier.addCustomSong(r.title, artist: r.artist),
            top: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if ((state.clientNotes?.rules.isNotEmpty ?? false) ||
                    state.clientNotes?.crowd != null)
                  _ClientRulesBanner(state.clientNotes!),
                _SuggestionCard(state: state, notifier: notifier),
              ],
            ),
            onPick: (song) => notifier.addSongs([song.id]),
          );
          final divider = Container(
            width: landscape ? 0.5 : null,
            height: landscape ? null : 0.5,
            color: CupertinoColors.separator.resolveFrom(context),
          );
          final main = _buildMain(context, state, notifier, docked: true);
          return SafeArea(
            top: false,
            child: landscape
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 11, child: main),
                      divider,
                      Expanded(flex: 9, child: picker),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // The keyboard (only ever the picker's search) would
                      // cover the list at the bottom — give it the screen.
                      if (MediaQuery.viewInsetsOf(context).bottom == 0) ...[
                        main,
                        divider,
                      ],
                      Expanded(child: picker),
                    ],
                  ),
          );
        },
      ),
    ),
    );
  }

  /// Now Playing + queue. Docked (captain): the picker marks played songs,
  /// so only Upcoming is listed; in portrait it's capped so the picker below
  /// keeps most of the screen.
  Widget _buildMain(
    BuildContext context,
    LiveSessionState state,
    LiveSessionNotifier notifier, {
    required bool docked,
  }) {
    final session = state.session!;
    final portraitDocked = docked &&
        MediaQuery.of(context).orientation == Orientation.portrait;
    final queue = _QueueList(
      session: session,
      isCaptain: state.isCaptain,
      notifier: notifier,
      showPlayed: !docked,
      compact: portraitDocked,
    );
    return Column(
      mainAxisSize: portraitDocked ? MainAxisSize.min : MainAxisSize.max,
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
          // Landscape is short — squeeze the card so Upcoming gets room.
          compact: docked && !portraitDocked,
          songNote: state.clientNotes?.noteFor(
            songId: session.currentSong?.songId,
            title: session.currentSong?.title,
          ),
        ),
        if (portraitDocked)
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.2,
            ),
            child: queue,
          )
        else
          Expanded(child: queue),
      ],
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
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('End Session?'),
        content:
            const Text('This will end the live setlist session for everyone.'),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(dialogContext, false),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('End Session'),
            onPressed: () => Navigator.pop(dialogContext, true),
          ),
        ],
      ),
    );
    if (confirmed == true) await notifier.endSession();
  }
}

Set<int> _songIds(LiveSession session, bool Function(QueueEntry) test) => {
      for (final e in session.queue)
        if (e.songId != null && test(e)) e.songId!,
    };

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
      color: CupertinoColors.systemOrange
          .resolveFrom(context)
          .withValues(alpha: 0.15),
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
            builder: (_, controller) => _SingerColors(
              songs: songs,
              child: _SongPickerSheet(
                songs: songs,
                scrollController: controller,
                title: 'First song back from break',
              ),
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
    this.compact = false,
    this.songNote,
  });

  final LiveSession session;
  final bool isCaptain;
  final LiveSessionNotifier notifier;

  /// Single-row layout for landscape: song info beside the controls, no
  /// "Up next" line (the Upcoming list sits right below).
  final bool compact;

  /// The client's instruction for the song now playing (lyric change…).
  final String? songNote;

  Widget _note(BuildContext context) {
    final orange = clientMustPlayColor(context);
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: orange.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(CupertinoIcons.exclamationmark_bubble_fill,
              size: 14, color: orange),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              songNote!,
              maxLines: compact ? 1 : 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (compact) return _buildCompact(context);
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
                  color: CupertinoColors.systemBlue.resolveFrom(context),
                  size: 18),
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
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            if (current.artist != null)
              Text(
                current.artist!,
                style: TextStyle(fontSize: 15, color: context.secondaryText),
              ),
            if (current.leadSinger != null || current.songKey != null) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                children: [
                  if (current.leadSinger != null)
                    _Chip(
                      label: current.leadSinger!,
                      icon: CupertinoIcons.mic,
                      color: _SingerColors.of(context, current.leadSinger),
                    ),
                  if (current.songKey != null)
                    _Chip(label: 'Key: ${current.songKey!}'),
                  if (current.bpm != null)
                    _Chip(label: '${current.bpm!.toInt()} BPM'),
                ],
              ),
            ],
            if (songNote != null) _note(context),
          ] else ...[
            Text(
              session.isOnBreak
                  ? 'On Break'
                  : isCaptain
                      ? 'Nothing playing — tap a song to start'
                      : 'Waiting for the captain to pick a song',
              style: TextStyle(fontSize: 17, color: context.secondaryText),
            ),
          ],
          if (isCaptain && current != null && session.isActive) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                _ReactionButton(
                  selected: current.crowdReaction == 'positive',
                  icon: CupertinoIcons.hand_thumbsup,
                  color: CupertinoColors.systemGreen.resolveFrom(context),
                  onPressed: () => notifier.react(current.id, 'positive'),
                ),
                const SizedBox(width: 8),
                _ReactionButton(
                  selected: current.crowdReaction == 'negative',
                  icon: CupertinoIcons.hand_thumbsdown,
                  color: CupertinoColors.systemRed.resolveFrom(context),
                  onPressed: () => notifier.react(current.id, 'negative'),
                ),
                const Spacer(),
                CupertinoButton(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                    size: 16, color: context.secondaryText),
                const SizedBox(width: 6),
                Text(
                  'UP NEXT',
                  style: TextStyle(
                    color: context.secondaryText,
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

  Widget _buildCompact(BuildContext context) {
    final current = session.currentSong;
    final blue = CupertinoColors.systemBlue.resolveFrom(context);
    final singer = current?.leadSinger?.trim() ?? '';
    final singerColor = _SingerColors.of(context, singer);
    final details = current == null
        ? const <InlineSpan>[]
        : <InlineSpan>[
            for (final (i, part) in [
              if ((current.artist ?? '').isNotEmpty)
                TextSpan(text: current.artist!),
              if (singer.isNotEmpty)
                TextSpan(
                  text: '● $singer',
                  style: TextStyle(
                    color: singerColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              if ((current.songKey ?? '').isNotEmpty)
                TextSpan(text: 'Key ${current.songKey}'),
            ].indexed) ...[
              if (i > 0) const TextSpan(text: '  ·  '),
              part,
            ],
          ];

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'NOW PLAYING',
                  style: TextStyle(
                    color: blue,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  current?.title ??
                      (session.isOnBreak
                          ? 'On Break'
                          : isCaptain
                              ? 'Nothing playing — tap a song'
                              : 'Waiting for the captain'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: current != null ? 19 : 15,
                    fontWeight:
                        current != null ? FontWeight.bold : FontWeight.normal,
                    color: current != null ? null : context.secondaryText,
                  ),
                ),
                if (details.isNotEmpty)
                  Text.rich(
                    TextSpan(children: details),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: 13, color: context.secondaryText),
                  ),
                if (current != null && songNote != null) _note(context),
              ],
            ),
          ),
          if (isCaptain && current != null && session.isActive) ...[
            _ReactionButton(
              selected: current.crowdReaction == 'positive',
              icon: CupertinoIcons.hand_thumbsup,
              color: CupertinoColors.systemGreen.resolveFrom(context),
              onPressed: () => notifier.react(current.id, 'positive'),
            ),
            const SizedBox(width: 6),
            _ReactionButton(
              selected: current.crowdReaction == 'negative',
              icon: CupertinoIcons.hand_thumbsdown,
              color: CupertinoColors.systemRed.resolveFrom(context),
              onPressed: () => notifier.react(current.id, 'negative'),
            ),
            Semantics(
              label: 'Skip',
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(40, 40),
                onPressed: notifier.skip,
                child: const Icon(CupertinoIcons.forward_end, size: 20),
              ),
            ),
            CupertinoButton.filled(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: const Size(40, 40),
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
    this.showPlayed = true,
    this.compact = false,
  });

  final LiveSession session;
  final bool isCaptain;
  final LiveSessionNotifier notifier;

  /// The captain's docked picker already marks played songs, so the captain
  /// view drops this section; band members still see it.
  final bool showPlayed;

  /// Sized to its content (portrait, above the docked picker) rather than
  /// filling the space; renders nothing when there's nothing upcoming.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final pending = session.queue
        .where((e) => e.isPending && e.position > session.currentPosition)
        .toList()
      ..sort((a, b) => a.position.compareTo(b.position));

    final played = showPlayed
        ? (session.queue.where((e) => e.isPlayed).toList()
          ..sort((a, b) => b.position.compareTo(a.position)))
        : const <QueueEntry>[];

    if (pending.isEmpty && played.isEmpty) {
      if (compact) return const SizedBox.shrink();
      return const Center(child: Text('Queue is empty.'));
    }

    if (isCaptain && session.isActive && !showPlayed) {
      return _EditableUpcoming(
        upcoming: pending,
        notifier: notifier,
        compact: compact,
      );
    }

    return ListView(
      shrinkWrap: compact,
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
                  color: context.secondaryText),
            ),
          ),
          for (final e in pending) _QueueTile(entry: e, isCaptain: isCaptain),
        ],
        if (played.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'PLAYED',
              style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 1.2,
                  color: context.secondaryText),
            ),
          ),
          ...played.map((e) => _QueueTile(entry: e, isCaptain: false)),
        ],
      ],
    );
  }
}

/// The captain's Upcoming list: drag the ≡ handle (or long-press a row) to
/// reorder, swipe a row left to remove it.
class _EditableUpcoming extends StatelessWidget {
  const _EditableUpcoming({
    required this.upcoming,
    required this.notifier,
    required this.compact,
  });

  final List<QueueEntry> upcoming;
  final LiveSessionNotifier notifier;

  /// Sized to content (portrait, above the docked picker).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final list = ReorderableList(
      shrinkWrap: compact,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: upcoming.length,
      onReorder: notifier.reorderUpcoming,
      proxyDecorator: (child, _, animation) => AnimatedBuilder(
        animation: animation,
        builder: (context, child) => Container(
          decoration: BoxDecoration(
            color: CupertinoColors.secondarySystemBackground
                .resolveFrom(context),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: CupertinoColors.black
                    .withValues(alpha: 0.3 * animation.value),
                blurRadius: 12,
              ),
            ],
          ),
          child: child,
        ),
        child: child,
      ),
      itemBuilder: (context, i) {
        final e = upcoming[i];
        return _SwipeToRemove(
          key: ValueKey(e.id),
          onRemove: () => notifier.removeUpcoming(e.id),
          child: ReorderableDelayedDragStartListener(
            index: i,
            child: Row(
              children: [
                Expanded(child: _QueueTile(entry: e, isCaptain: true)),
                ReorderableDragStartListener(
                  index: i,
                  child: Semantics(
                    label: 'Drag to reorder',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 10),
                      child: Icon(
                        CupertinoIcons.line_horizontal_3,
                        size: 20,
                        color: context.secondaryText,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    return Column(
      mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Text(
            'UPCOMING',
            style: TextStyle(
              fontSize: 12,
              letterSpacing: 1.2,
              color: context.secondaryText,
            ),
          ),
        ),
        if (compact) Flexible(child: list) else Expanded(child: list),
      ],
    );
  }
}

/// Swipe an upcoming row right-to-left to drop it from the queue.
class _SwipeToRemove extends StatelessWidget {
  const _SwipeToRemove({
    required super.key,
    required this.onRemove,
    required this.child,
  });

  final VoidCallback onRemove;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final red = CupertinoColors.systemRed.resolveFrom(context);
    return Dismissible(
      key: key!,
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onRemove(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: red,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.trash, size: 18, color: CupertinoColors.white),
            SizedBox(width: 6),
            Text(
              'Remove',
              style: TextStyle(
                color: CupertinoColors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      child: Semantics(
        // Swipes aren't discoverable to screen readers; expose an action.
        customSemanticsActions: {
          const CustomSemanticsAction(label: 'Remove from queue'): onRemove,
        },
        child: child,
      ),
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
    // Singer color when known, so Upcoming scans like the picker.
    final singerColor = _SingerColors.of(context, entry.leadSinger);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isPlayed
                  ? CupertinoColors.tertiarySystemBackground
                      .resolveFrom(context)
                  : singerColor ??
                      CupertinoColors.systemBlue
                          .resolveFrom(context)
                          .withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: isPlayed
                  ? Icon(CupertinoIcons.checkmark,
                      size: 14, color: context.secondaryText)
                  : Text(
                      '${entry.position}',
                      style: TextStyle(
                        color: singerColor != null
                            ? _onColor(singerColor)
                            : CupertinoColors.systemBlue.resolveFrom(context),
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
                    style:
                        TextStyle(fontSize: 13, color: context.secondaryText),
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
    this.scrollController,
    this.onPick,
    this.title = 'Add Song',
    this.playedIds = const {},
    this.queuedIds = const {},
    this.mustPlayIds = const {},
    this.ifTimeIds = const {},
    this.doNotPlayIds = const {},
    this.requests = const [],
    this.takenTitles = const {},
    this.onPickCustom,
    this.top,
  });

  final List<BandSong> songs;
  final ScrollController? scrollController;
  final String title;

  /// Docked mode (landscape panel): each tap calls this immediately instead
  /// of popping the sheet. The row shows a spinner until it completes.
  final Future<void> Function(BandSong song)? onPick;

  /// Songs already played this session / still waiting in the queue, so the
  /// captain doesn't repeat one by accident.
  final Set<int> playedIds;
  final Set<int> queuedIds;

  /// Client questionnaire picks: must-play songs get a ★; do-not-play songs
  /// are struck through and can't be picked.
  final Set<int> mustPlayIds;
  final Set<int> doNotPlayIds;

  /// Client "if time permits" songs: a hollow ☆.
  final Set<int> ifTimeIds;

  /// Pickable free-text requests, listed on top under "Client requests".
  final List<ClientRequest> requests;

  /// Lower-cased titles of non-catalog entries already in the session.
  final Set<String> takenTitles;

  /// Queues a request that isn't in the catalog.
  final Future<void> Function(ClientRequest request)? onPickCustom;

  /// Shown at the top of the list (rules banner + AI suggestion card in
  /// docked mode); scrolls away with the songs.
  final Widget? top;

  @override
  State<_SongPickerSheet> createState() => _SongPickerSheetState();
}

class _SongPickerSheetState extends State<_SongPickerSheet> {
  String _query = '';
  final _queryController = TextEditingController();

  /// Singers whose songs to show; empty = everyone.
  final Set<String> _singers = {};

  /// Show only the client's must-play songs.
  bool _requestsOnly = false;

  /// Text search is tucked away behind a button — the singer chips are the
  /// primary filter on stage.
  bool _searchOpen = false;

  void _toggleSearch() => setState(() {
        _searchOpen = !_searchOpen;
        if (!_searchOpen) {
          _queryController.clear();
          _query = '';
        }
      });

  void _toggleSinger(String singer) => setState(() {
        if (!_singers.remove(singer)) _singers.add(singer);
      });

  /// Docked-mode songs whose add request is still in flight — guards against
  /// a double tap queuing the same song twice.
  final Set<int> _adding = {};
  final Set<String> _addingTitles = {};

  Future<void> _onPickCustom(ClientRequest r) async {
    final onPick = widget.onPickCustom;
    if (onPick == null || !_addingTitles.add(r.title)) return;
    setState(() {});
    try {
      await onPick(r);
    } finally {
      if (mounted) setState(() => _addingTitles.remove(r.title));
    }
  }

  bool get _docked => widget.onPick != null;

  Future<void> _onTap(BandSong song) async {
    if (_docked) {
      if (!_adding.add(song.id)) return;
      setState(() {});
      try {
        await widget.onPick!(song);
      } finally {
        if (mounted) setState(() => _adding.remove(song.id));
      }
      return;
    }
    Navigator.pop(context, song);
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();
    final filtered = widget.songs.where((s) {
      if (_requestsOnly &&
          !widget.mustPlayIds.contains(s.id) &&
          !widget.ifTimeIds.contains(s.id)) {
        return false;
      }
      if (_singers.isNotEmpty && !_singers.contains(s.leadSinger?.trim())) {
        return false;
      }
      if (q.isEmpty) return true;
      return s.title.toLowerCase().contains(q) ||
          (s.artist?.toLowerCase().contains(q) ?? false);
    }).toList();
    final singers = {
      for (final s in widget.songs)
        if ((s.leadSinger?.trim() ?? '').isNotEmpty) s.leadSinger!.trim(),
    }.toList()
      ..sort();

    return Column(
      children: [
        Padding(
          padding: _docked
              ? const EdgeInsets.fromLTRB(16, 10, 16, 4)
              : const EdgeInsets.fromLTRB(16, 16, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(widget.title,
                    style: TextStyle(
                      fontSize: _docked ? 13 : 17,
                      fontWeight: FontWeight.w600,
                      color: _docked ? context.secondaryText : null,
                    )),
              ),
              Semantics(
                label: _searchOpen ? 'Close search' : 'Search songs',
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(36, 36),
                  onPressed: _toggleSearch,
                  child: Icon(
                    _searchOpen
                        ? CupertinoIcons.search_circle_fill
                        : CupertinoIcons.search,
                    size: 22,
                  ),
                ),
              ),
              if (!_docked)
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(36, 36),
                  onPressed: () => Navigator.pop(context),
                  child: const Icon(CupertinoIcons.xmark),
                ),
            ],
          ),
        ),
        if (_searchOpen)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: CupertinoSearchTextField(
              controller: _queryController,
              placeholder: 'Search songs…',
              // Opened on purpose, so go straight to typing.
              autofocus: true,
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
        if (singers.isNotEmpty ||
            widget.mustPlayIds.isNotEmpty ||
            widget.requests.isNotEmpty)
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              children: [
                _SingerChip(
                  label: 'All',
                  selected: _singers.isEmpty && !_requestsOnly,
                  onTap: () => setState(() {
                    _singers.clear();
                    _requestsOnly = false;
                  }),
                ),
                if (widget.mustPlayIds.isNotEmpty || widget.requests.isNotEmpty)
                  _SingerChip(
                    label: 'Requests',
                    icon: CupertinoIcons.star_fill,
                    color: clientMustPlayColor(context),
                    selected: _requestsOnly,
                    onTap: () =>
                        setState(() => _requestsOnly = !_requestsOnly),
                  ),
                for (final singer in singers)
                  _SingerChip(
                    label: singer,
                    icon: CupertinoIcons.mic,
                    color: _SingerColors.of(context, singer),
                    selected: _singers.contains(singer),
                    onTap: () => _toggleSinger(singer),
                  ),
              ],
            ),
          ),
        Expanded(
          child: ListView(
            controller: widget.scrollController,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.only(
              bottom: _docked ? MediaQuery.of(context).viewInsets.bottom : 0,
            ),
            children: _listItems(context, filtered),
          ),
        ),
      ],
    );
  }

  /// The client's pickable free-text requests on top (unless a singer filter
  /// or search narrows the list), then the catalog.
  List<Widget> _listItems(BuildContext context, List<BandSong> filtered) {
    // The banner / suggestion card scroll with the list: pinned, they don't
    // fit above it in portrait.
    // Hidden while searching so results get the room above the keyboard.
    final top = _query.isEmpty ? widget.top : null;
    final requests = widget.requests;
    final showRequests = requests.isNotEmpty &&
        _singers.isEmpty &&
        _query.isEmpty;
    if (!showRequests) {
      return [
        if (top != null) top,
        for (final song in filtered) _libraryRow(context, song),
      ];
    }
    final byId = {for (final s in widget.songs) s.id: s};
    return [
      if (top != null) top,
      const _SectionLabel('Client requests'),
      for (final r in requests)
        if (r.songId != null && byId.containsKey(r.songId))
          _libraryRow(context, byId[r.songId]!, request: r)
        else
          _CustomRequestRow(
            request: r,
            taken: widget.takenTitles.contains(r.title.trim().toLowerCase()),
            adding: _addingTitles.contains(r.title),
            onTap: () => _onPickCustom(r),
          ),
      if (!_requestsOnly) ...[
        const _SectionLabel('All songs'),
        for (final song in filtered) _libraryRow(context, song),
      ],
    ];
  }

  Widget _libraryRow(BuildContext context, BandSong song,
      {ClientRequest? request}) {
    // Already queued or played this session — can't be picked again.
    final taken = widget.queuedIds.contains(song.id) ||
        widget.playedIds.contains(song.id);
    final doNotPlay = widget.doNotPlayIds.contains(song.id);
    final mustPlay = widget.mustPlayIds.contains(song.id);
    final ifTime = !mustPlay && widget.ifTimeIds.contains(song.id);
    final clientStatus = doNotPlay
        ? ClientSongStatus.doNotPlay
        : mustPlay
            ? ClientSongStatus.mustPlay
            : ClientSongStatus.none;
    final blocked = taken || doNotPlay;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: blocked ? null : () => _onTap(song),
      child: Opacity(
        opacity: blocked ? 0.45 : 1,
        child: Container(
          // Singer color stripe for scanning by color.
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: _SingerColors.of(context, song.leadSinger) ??
                    const Color(0x00000000),
                width: 5,
              ),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(11, 10, 16, 10),
          child: Row(
            children: [
              if (blocked && _docked)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Icon(
                    doNotPlay && !taken
                        ? CupertinoIcons.nosign
                        : CupertinoIcons.checkmark_circle,
                    size: 24,
                    color: context.secondaryText,
                  ),
                )
              else if (_docked)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: _adding.contains(song.id)
                        ? const CupertinoActivityIndicator(radius: 9)
                        : Icon(
                            CupertinoIcons.add_circled,
                            size: 24,
                            color: CupertinoColors.activeBlue
                                .resolveFrom(context),
                          ),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (mustPlay)
                          const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: ClientRequestStar(size: 14),
                          )
                        else if (ifTime)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(
                              CupertinoIcons.star,
                              size: 14,
                              color: clientMustPlayColor(context),
                              semanticLabel: 'If time permits',
                            ),
                          ),
                        Flexible(
                          child: Text(
                            song.title,
                            style: clientRequestTextStyle(
                              context,
                              clientStatus,
                              const TextStyle(fontSize: 15),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (song.artist != null)
                      Text(song.artist!,
                          style: TextStyle(
                              fontSize: 13,
                              color: context.secondaryText)),
                    if (request?.note != null) _RequestNote(request!.note!),
                    if (doNotPlay)
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: ClientRequestCaption(
                            ClientSongStatus.doNotPlay),
                      )
                    else if (widget.queuedIds.contains(song.id))
                      _PickerStatus(
                        label: 'In queue',
                        color: CupertinoColors.systemBlue
                            .resolveFrom(context),
                      )
                    else if (widget.playedIds.contains(song.id))
                      _PickerStatus(
                        label: 'Played',
                        color: CupertinoColors.systemGreen
                            .resolveFrom(context),
                      ),
                  ],
                ),
              ),
              if ((song.leadSinger ?? '').isNotEmpty) ...[
                const SizedBox(width: 8),
                ConstrainedBox(
                  // Keep long names from squeezing the title.
                  constraints: const BoxConstraints(maxWidth: 120),
                  child: _Chip(
                    label: song.leadSinger!,
                    icon: CupertinoIcons.mic,
                    color:
                        _SingerColors.of(context, song.leadSinger),
                  ),
                ),
              ],
              if (song.songKey != null) ...[
                const SizedBox(width: 6),
                _Chip(label: song.songKey!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Small all-caps divider label inside the picker list.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w600,
            color: context.secondaryText,
          ),
        ),
      );
}

/// One-line context under a requested song ("Bride's favorite").
class _RequestNote extends StatelessWidget {
  const _RequestNote(this.note);

  final String note;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          note,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            fontStyle: FontStyle.italic,
            color: clientMustPlayColor(context),
          ),
        ),
      );
}

/// A client request that isn't in the band's catalog — queued by title.
class _CustomRequestRow extends StatelessWidget {
  const _CustomRequestRow({
    required this.request,
    required this.taken,
    required this.adding,
    required this.onTap,
  });

  final ClientRequest request;
  final bool taken;
  final bool adding;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final orange = clientMustPlayColor(context);
    final (badge, icon) = switch (request.kind) {
      ClientRequestKind.mustPlay => ('Must play', CupertinoIcons.star_fill),
      ClientRequestKind.ifTime => ('If time', CupertinoIcons.star),
      _ => ('Moment', CupertinoIcons.heart_fill),
    };
    return Semantics(
      button: true,
      label: '${request.title}, $badge, not in library',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: taken ? null : onTap,
        child: Opacity(
          opacity: taken ? 0.45 : 1,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: taken
                        ? Icon(CupertinoIcons.checkmark_circle,
                            size: 24, color: context.secondaryText)
                        : adding
                            ? const CupertinoActivityIndicator(radius: 9)
                            : Icon(CupertinoIcons.add_circled,
                                size: 24,
                                color: CupertinoColors.activeBlue
                                    .resolveFrom(context)),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(icon, size: 14, color: orange),
                          ),
                          Flexible(
                            child: Text(request.title,
                                style: const TextStyle(fontSize: 15)),
                          ),
                        ],
                      ),
                      if (request.artist != null)
                        Text(request.artist!,
                            style: TextStyle(
                                fontSize: 13, color: context.secondaryText)),
                      if (request.note != null) _RequestNote(request.note!),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _Chip(label: badge, color: orange),
                    const SizedBox(height: 4),
                    Text('Not in library',
                        style: TextStyle(
                            fontSize: 11, color: context.tertiaryText)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The client's blanket rules and crowd, one line until tapped.
class _ClientRulesBanner extends StatefulWidget {
  const _ClientRulesBanner(this.notes);

  final ClientNotes notes;

  @override
  State<_ClientRulesBanner> createState() => _ClientRulesBannerState();
}

class _ClientRulesBannerState extends State<_ClientRulesBanner> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final lines = [
      ...widget.notes.rules,
      if (widget.notes.crowd != null) 'Crowd: ${widget.notes.crowd}',
    ];
    final orange = clientMustPlayColor(context);
    return Semantics(
      button: true,
      label: _open ? 'Collapse client notes' : 'Expand client notes',
      child: GestureDetector(
        onTap: () => setState(() => _open = !_open),
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          decoration: BoxDecoration(
            color: orange.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1, right: 6),
                child: Icon(CupertinoIcons.doc_text, size: 14, color: orange),
              ),
              Expanded(
                child: _open
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final l in lines)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Text('• $l',
                                  style: const TextStyle(fontSize: 13)),
                            ),
                        ],
                      )
                    : Text(
                        lines.join('  ·  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
              ),
              Icon(
                _open
                    ? CupertinoIcons.chevron_up
                    : CupertinoIcons.chevron_down,
                size: 14,
                color: context.secondaryText,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// AI "what's next" at the top of the docked picker: ask, then queue the
/// pick or ask for another.
class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({required this.state, required this.notifier});

  final LiveSessionState state;
  final LiveSessionNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final purple = CupertinoColors.systemPurple.resolveFrom(context);
    final suggestion = state.suggestion;

    Widget body;
    if (state.isSuggesting) {
      body = Row(
        children: [
          const CupertinoActivityIndicator(radius: 9),
          const SizedBox(width: 10),
          Text('Picking a song…',
              style: TextStyle(fontSize: 14, color: context.secondaryText)),
        ],
      );
    } else if (suggestion != null) {
      final singerColor = _SingerColors.of(context, suggestion.leadSinger);
      final details = [
        if ((suggestion.artist ?? '').isNotEmpty) suggestion.artist!,
        if ((suggestion.songKey ?? '').isNotEmpty) 'Key ${suggestion.songKey}',
        if (suggestion.isCustom) 'not in library',
      ].join('  ·  ');
      body = Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(CupertinoIcons.sparkles, size: 12, color: purple),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        suggestion.forcedTransition
                            ? 'TRANSITION'
                            : suggestion.mustPlay || suggestion.isCustom
                                ? 'SUGGESTED · CLIENT REQUEST'
                                : 'SUGGESTED',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 1.1,
                          fontWeight: FontWeight.w700,
                          color: purple,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (suggestion.mustPlay)
                      const Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: ClientRequestStar(size: 14),
                      ),
                    Flexible(
                      child: Text(
                        suggestion.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                if (details.isNotEmpty ||
                    (suggestion.leadSinger ?? '').isNotEmpty)
                  Text.rich(
                    TextSpan(children: [
                      if ((suggestion.leadSinger ?? '').isNotEmpty)
                        TextSpan(
                          text: '● ${suggestion.leadSinger}'
                              '${details.isNotEmpty ? '  ·  ' : ''}',
                          style: TextStyle(
                            color: singerColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      TextSpan(text: details),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: 13, color: context.secondaryText),
                  ),
                if (suggestion.note != null) _RequestNote(suggestion.note!),
              ],
            ),
          ),
          Semantics(
            label: 'Suggest another song',
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(40, 40),
              onPressed: () => notifier.suggestNext(another: true),
              child: const Icon(CupertinoIcons.arrow_2_circlepath, size: 20),
            ),
          ),
          CupertinoButton.filled(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            minimumSize: const Size(40, 36),
            onPressed: notifier.acceptSuggestion,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(CupertinoIcons.add, size: 16),
                SizedBox(width: 2),
                Text('Queue'),
              ],
            ),
          ),
        ],
      );
    } else {
      body = Row(
        children: [
          Expanded(
            child: state.suggestionError != null
                ? Text(state.suggestionError!,
                    style:
                        TextStyle(fontSize: 13, color: context.secondaryText))
                : Text('Not sure what\'s next?',
                    style:
                        TextStyle(fontSize: 14, color: context.secondaryText)),
          ),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            minimumSize: const Size(40, 36),
            onPressed: notifier.suggestNext,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(CupertinoIcons.sparkles, size: 16, color: purple),
                const SizedBox(width: 4),
                Text('Suggest',
                    style: TextStyle(
                        color: purple, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      );
    }

    final card = Container(
      margin: const EdgeInsets.fromLTRB(12, 2, 12, 4),
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: purple.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: body,
    );
    // A suggestion (or the "couldn't suggest" note) swipes away either way.
    if (suggestion == null && state.suggestionError == null) return card;
    return Dismissible(
      key: ValueKey('suggestion-${suggestion?.songId}-${state.suggestionError}'),
      onDismissed: (_) => notifier.dismissSuggestion(),
      child: Semantics(
        customSemanticsActions: {
          const CustomSemanticsAction(label: 'Dismiss suggestion'):
              notifier.dismissSuggestion,
        },
        child: card,
      ),
    );
  }
}

/// Pill toggle in the picker's singer filter row.
class _SingerChip extends StatelessWidget {
  const _SingerChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.color,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  /// Singer color: fills the chip when selected, tints it otherwise.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? CupertinoColors.activeBlue.resolveFrom(context);
    final fg = selected ? _onColor(accent) : context.primaryText;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Semantics(
        button: true,
        selected: selected,
        label: icon != null ? 'Singer $label' : label,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? accent
                  : color?.withValues(alpha: 0.22) ??
                      CupertinoColors.tertiarySystemFill.resolveFrom(context),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 13, color: selected ? fg : accent),
                  const SizedBox(width: 4),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PickerStatus extends StatelessWidget {
  const _PickerStatus({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(CupertinoIcons.checkmark_circle_fill, size: 12, color: color),
          const SizedBox(width: 3),
          Text(
            label,
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

class _Chip extends StatelessWidget {
  const _Chip({required this.label, this.icon, this.color});

  final String label;
  final IconData? icon;

  /// Singer color: tints the chip so it reads at a glance.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: c?.withValues(alpha: 0.22) ??
            CupertinoColors.tertiarySystemBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: c ?? context.secondaryText),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: c != null ? context.primaryText : context.secondaryText,
                fontWeight: c != null ? FontWeight.w500 : null,
              ),
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
    this.selected = false,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  /// This reaction is the one recorded for the song — shown filled.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: icon == CupertinoIcons.hand_thumbsup
          ? 'Crowd liked it'
          : 'Crowd did not like it',
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onPressed();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: selected ? color : null,
            border: Border.all(
                color: selected ? color : color.withValues(alpha: 0.4)),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Icon(
              selected ? _filled(icon) : icon,
              color: selected ? _onColor(color) : color,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }

  static IconData _filled(IconData icon) => switch (icon) {
        CupertinoIcons.hand_thumbsup => CupertinoIcons.hand_thumbsup_fill,
        CupertinoIcons.hand_thumbsdown => CupertinoIcons.hand_thumbsdown_fill,
        _ => icon,
      };
}
