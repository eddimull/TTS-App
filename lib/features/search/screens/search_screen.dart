import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/widgets/nav_row.dart';
import '../../../shared/widgets/status_chip.dart';
import '../data/models/search_models.dart';
import '../providers/search_provider.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchProvider);
    final isSearching = searchState.query.length >= 2;

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Music & Search'),
      ),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Cap width on wide screens (desktop/tablet) for readability.
            final maxWidth =
                constraints.maxWidth > 700 ? 700.0 : constraints.maxWidth;
            return Center(
              child: SizedBox(
                width: maxWidth,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: CupertinoSearchTextField(
                        controller: _controller,
                        placeholder: 'Search songs, charts, bookings...',
                        onChanged: (value) =>
                            ref.read(searchProvider.notifier).search(value),
                        onSuffixTap: () {
                          _controller.clear();
                          ref.read(searchProvider.notifier).search('');
                        },
                      ),
                    ),
                    Expanded(
                      child: isSearching
                          ? _SearchBody(state: searchState)
                          : const _BrowseBody(),
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

// ── Idle state (no active query) ─────────────────────────────────────────────

class _BrowseBody extends StatelessWidget {
  const _BrowseBody();

  @override
  Widget build(BuildContext context) {
    return const _CenteredHint(
      icon: CupertinoIcons.search,
      message: 'Search songs, charts, bookings, and contacts',
    );
  }
}

// ── Search results body ────────────────────────────────────────────────────────

class _SearchBody extends StatelessWidget {
  const _SearchBody({required this.state});

  final SearchState state;

  @override
  Widget build(BuildContext context) {
    if (state.isLoading) {
      return const Center(child: CupertinoActivityIndicator());
    }

    if (state.error != null) {
      return const _CenteredHint(
        icon: CupertinoIcons.exclamationmark_circle,
        message: 'Something went wrong. Please try again.',
        isError: true,
      );
    }

    if (state.results == null || state.results!.isEmpty) {
      return _CenteredHint(
        icon: CupertinoIcons.search,
        message: 'No results for "${state.query}"',
      );
    }

    return _ResultsList(results: state.results!);
  }
}

// ── Results list ──────────────────────────────────────────────────────────────

class _ResultsList extends StatelessWidget {
  const _ResultsList({required this.results});

  final SearchResults results;

  @override
  Widget build(BuildContext context) {
    // Build a flat list of tagged items so we can use ListView.builder
    // efficiently without nested columns.
    final items = <_ListItem>[];

    if (results.songs.isNotEmpty) {
      items.add(const _SectionHeader('Songs'));
      for (final s in results.songs) {
        items.add(_SongItem(s));
      }
    }

    if (results.charts.isNotEmpty) {
      items.add(const _SectionHeader('Charts'));
      for (final ch in results.charts) {
        items.add(_ChartItem(ch));
      }
    }

    if (results.bookings.isNotEmpty) {
      items.add(const _SectionHeader('Bookings'));
      for (final b in results.bookings) {
        items.add(_BookingItem(b));
      }
    }

    if (results.contacts.isNotEmpty) {
      items.add(const _SectionHeader('Contacts'));
      for (final c in results.contacts) {
        items.add(_ContactItem(c));
      }
    }

    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return switch (item) {
          _SectionHeader(:final label) => _SectionHeaderTile(label: label),
          _SongItem(:final song) => _SongRow(song: song),
          _ChartItem(:final chart) => _ChartRow(chart: chart),
          _BookingItem(:final booking) => _BookingRow(booking: booking),
          _ContactItem(:final contact) => _ContactRow(contact: contact),
        };
      },
    );
  }
}

// ── List item discriminated union ─────────────────────────────────────────────

sealed class _ListItem {
  const _ListItem();
}

final class _SectionHeader extends _ListItem {
  const _SectionHeader(this.label);
  final String label;
}

final class _SongItem extends _ListItem {
  const _SongItem(this.song);
  final SongResult song;
}

final class _ChartItem extends _ListItem {
  const _ChartItem(this.chart);
  final ChartResult chart;
}

final class _BookingItem extends _ListItem {
  const _BookingItem(this.booking);
  final BookingResult booking;
}

final class _ContactItem extends _ListItem {
  const _ContactItem(this.contact);
  final ContactResult contact;
}

// ── Section header tile — iOS grouped style ───────────────────────────────────

class _SectionHeaderTile extends StatelessWidget {
  const _SectionHeaderTile({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: CupertinoColors.secondaryLabel.resolveFrom(context),
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ── Song row ──────────────────────────────────────────────────────────────────

class _SongRow extends StatelessWidget {
  const _SongRow({required this.song});

  final SongResult song;

  @override
  Widget build(BuildContext context) {
    final subParts = [
      if (song.artist.isNotEmpty) song.artist,
      if (song.songKey.isNotEmpty) song.songKey,
      if (song.bpm > 0) '${song.bpm} BPM',
    ];
    final subLabel = subParts.isEmpty ? null : subParts.join(' · ');

    return NavRow(
      title: song.title,
      subtitle: subLabel,
      showChevron: false,
      leading: NavRowIcon(
        icon: CupertinoIcons.music_note,
        color: CupertinoColors.systemPurple.resolveFrom(context),
      ),
    );
  }
}

// ── Chart row ─────────────────────────────────────────────────────────────────

class _ChartRow extends StatelessWidget {
  const _ChartRow({required this.chart});

  final ChartResult chart;

  @override
  Widget build(BuildContext context) {
    return NavRow(
      title: chart.title,
      subtitle: chart.composer.isNotEmpty ? chart.composer : null,
      semanticLabel: '${chart.title}, by ${chart.composer}',
      leading: NavRowIcon(
        icon: CupertinoIcons.doc_text,
        color: CupertinoColors.systemTeal.resolveFrom(context),
      ),
      onTap: () => context.push('/library/${chart.id}', extra: chart.bandId),
    );
  }
}

// ── Booking row ───────────────────────────────────────────────────────────────

class _BookingRow extends ConsumerWidget {
  const _BookingRow({required this.booking});

  final BookingResult booking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accentColor = _accentColor(context, booking.status);

    return Semantics(
      button: true,
      label: '${booking.name}, ${booking.venueName}, ${booking.status}',
      child: GestureDetector(
        onTap: () => context.push('/bookings/${booking.bandId}/${booking.id}'),
        behavior: HitTestBehavior.opaque,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color:
                CupertinoColors.tertiarySystemBackground.resolveFrom(context),
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Coloured status accent stripe — matches bookings_screen.dart pattern.
                Container(width: 3, color: accentColor),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                booking.name,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (booking.status.isNotEmpty)
                              StatusChip(status: booking.status),
                          ],
                        ),
                        const SizedBox(height: 4),
                        if (booking.venueName.isNotEmpty)
                          Row(
                            children: [
                              Icon(
                                CupertinoIcons.location,
                                size: 11,
                                color: CupertinoColors.tertiaryLabel
                                    .resolveFrom(context),
                              ),
                              const SizedBox(width: 3),
                              Expanded(
                                child: Text(
                                  booking.venueName,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: CupertinoColors.secondaryLabel
                                        .resolveFrom(context),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        if (booking.date.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            booking.date,
                            style: TextStyle(
                              fontSize: 13,
                              color: CupertinoColors.secondaryLabel
                                  .resolveFrom(context),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Icon(
                    CupertinoIcons.chevron_right,
                    size: 14,
                    color:
                        CupertinoColors.tertiaryLabel.resolveFrom(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _accentColor(BuildContext context, String status) =>
      switch (status.toLowerCase()) {
        'confirmed' => CupertinoColors.systemGreen.resolveFrom(context),
        'pending' => CupertinoColors.systemOrange.resolveFrom(context),
        'draft' => CupertinoColors.systemBlue.resolveFrom(context),
        'cancelled' || 'canceled' =>
          CupertinoColors.systemRed.resolveFrom(context),
        _ => CupertinoColors.systemFill.resolveFrom(context),
      };
}

// ── Contact row ───────────────────────────────────────────────────────────────

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.contact});

  final ContactResult contact;

  @override
  Widget build(BuildContext context) {
    // Sub-label: prefer email, fall back to phone.
    final subLabel = contact.email.isNotEmpty
        ? contact.email
        : contact.phone.isNotEmpty
            ? contact.phone
            : null;

    final initial =
        contact.name.isNotEmpty ? contact.name[0].toUpperCase() : '?';
    final accentColor = CupertinoColors.systemBlue.resolveFrom(context);

    return NavRow(
      title: contact.name,
      subtitle: subLabel,
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: accentColor.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(
          initial,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: accentColor,
          ),
        ),
      ),
      onTap: () => _showComingSoon(context),
    );
  }

  void _showComingSoon(BuildContext context) {
    showCupertinoDialog<void>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Coming Soon'),
        content: const Text('Contact detail coming soon.'),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _CenteredHint extends StatelessWidget {
  const _CenteredHint({
    required this.icon,
    required this.message,
    this.isError = false,
  });

  final IconData icon;
  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError
        ? CupertinoColors.systemRed.resolveFrom(context)
        : CupertinoColors.tertiaryLabel.resolveFrom(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: color),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
