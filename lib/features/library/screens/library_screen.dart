import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';
import 'package:tts_bandmate/shared/widgets/empty_state_view.dart';
import 'package:tts_bandmate/shared/widgets/error_view.dart';
import '../data/models/chart.dart';
import '../providers/library_provider.dart';

// ── Constants ─────────────────────────────────────────────────────────────────

const double _kRowHeight = 56.0;
// Section header is just a tiny letter label — keep it compact.
const double _kSectionHeaderHeight = 20.0;
// Total height of the fixed bottom bar (search field + vertical padding).
const double _kSearchBarHeight = 56.0;
// Width of the alphabet scrubber strip flush against the right edge.
const double _kIndexWidth = 16.0;
// Diameter of the circular avatar.
const double _kAvatarSize = 38.0;

const List<String> _kAlphabetLetters = [
  '#',
  'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
  'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
];

// Fixed palette for avatar background colours.  Index is derived from
// title.hashCode so the same title always gets the same colour.
const List<Color> _kAvatarPalette = [
  Color(0xFF4A90D9), // blue
  Color(0xFF7B68EE), // medium slate blue
  Color(0xFF5BA85A), // green
  Color(0xFFE07B39), // orange
  Color(0xFFD95050), // red
  Color(0xFF50A8A8), // teal
  Color(0xFF9B59B6), // purple
  Color(0xFF2ECC71), // emerald
  Color(0xFFE67E22), // carrot
  Color(0xFF1ABC9C), // turquoise
  Color(0xFFE74C3C), // alizarin
  Color(0xFF3498DB), // peter river
];

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Returns the section key for a chart title.
/// Titles whose first character is not A-Z fall into the '#' bucket.
String _sectionKey(String title) {
  if (title.isEmpty) return '#';
  final first = title[0].toUpperCase();
  final code = first.codeUnitAt(0);
  if (code >= 65 && code <= 90) return first; // A-Z
  return '#';
}

/// Builds an ordered map of section-letter → sorted charts.
/// '#' is first, then A-Z; empty letters are omitted.
Map<String, List<Chart>> _buildGroups(List<Chart> charts) {
  final sorted = List<Chart>.from(charts)
    ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

  final map = <String, List<Chart>>{};
  for (final chart in sorted) {
    final key = _sectionKey(chart.title);
    (map[key] ??= []).add(chart);
  }

  final ordered = <String, List<Chart>>{};
  for (final letter in _kAlphabetLetters) {
    if (map.containsKey(letter)) ordered[letter] = map[letter]!;
  }
  return ordered;
}

/// Returns the avatar background colour for a given title.
Color _avatarColor(String title) {
  final index = title.hashCode.abs() % _kAvatarPalette.length;
  return _kAvatarPalette[index];
}

/// Returns the 1–2 char initials shown inside the avatar.
/// Uses the first letter; if the title has a second word, appends its first
/// letter to produce two-letter initials (e.g. "Fly Me To" → "FM").
String _avatarInitials(String title) {
  if (title.isEmpty) return '?';
  final words = title.trim().split(RegExp(r'\s+'));
  if (words.length == 1) return words[0][0].toUpperCase();
  return (words[0][0] + words[1][0]).toUpperCase();
}

// ── Top-level screen (band resolution shell) ──────────────────────────────────

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  int? _bandId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadIfReady());
  }

  void _loadIfReady() {
    ref.read(selectedBandProvider).whenData((bandId) {
      if (bandId != null) {
        _bandId = bandId;
        ref.read(libraryProvider.notifier).load(bandId);
      }
    });
  }

  Future<void> _refresh() async {
    final bandId = _bandId;
    if (bandId == null) return;
    await ref.read(libraryProvider.notifier).load(bandId);
  }

  @override
  Widget build(BuildContext context) {
    final bandAsync = ref.watch(selectedBandProvider);

    return bandAsync.when(
      loading: () => const CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(middle: Text('Library')),
        child: Center(child: CupertinoActivityIndicator()),
      ),
      error: (e, _) => CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(middle: Text('Library')),
        child: ErrorView(message: 'Could not determine band.\n$e'),
      ),
      data: (bandId) {
        if (bandId == null) {
          return const CupertinoPageScaffold(
            navigationBar: CupertinoNavigationBar(middle: Text('Library')),
            child: ErrorView(message: 'No band selected.'),
          );
        }
        if (_bandId != bandId) _bandId = bandId;
        return _LibraryBody(bandId: bandId, onRefresh: _refresh);
      },
    );
  }
}

// ── Body ──────────────────────────────────────────────────────────────────────

class _LibraryBody extends ConsumerStatefulWidget {
  const _LibraryBody({required this.bandId, required this.onRefresh});

  final int bandId;
  final Future<void> Function() onRefresh;

  @override
  ConsumerState<_LibraryBody> createState() => _LibraryBodyState();
}

class _LibraryBodyState extends ConsumerState<_LibraryBody> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();

  String _query = '';

  // The letter currently shown in the large centre overlay (null = hidden).
  String? _overlayLetter;
  Timer? _overlayTimer;

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _overlayTimer?.cancel();
    super.dispose();
  }

  // ── Search ──────────────────────────────────────────────────────────────────

  void _onQueryChanged(String value) {
    setState(() => _query = value.trim());
  }

  // ── Alphabet scrubber interaction ────────────────────────────────────────────

  /// [dy] is the local Y position within the scrubber strip widget.
  /// [indexHeight] is the total rendered height of that strip.
  void _onIndexSelect(
    double dy,
    double indexHeight,
    Map<String, List<Chart>> groups,
  ) {
    final letterCount = _kAlphabetLetters.length;
    final fraction = (dy / indexHeight).clamp(0.0, 0.9999);
    final idx = (fraction * letterCount).floor();
    final tappedLetter = _kAlphabetLetters[idx.clamp(0, letterCount - 1)];

    // Find the nearest section at or after the tapped letter that has data.
    final sectionKeys = groups.keys.toList();
    String? targetKey;
    for (final letter
        in _kAlphabetLetters.skip(_kAlphabetLetters.indexOf(tappedLetter))) {
      if (sectionKeys.contains(letter)) {
        targetKey = letter;
        break;
      }
    }
    targetKey ??= sectionKeys.isNotEmpty ? sectionKeys.last : null;

    if (targetKey != null) {
      _showOverlay(targetKey);
      _jumpToSection(targetKey, groups);
    }
  }

  void _showOverlay(String letter) {
    _overlayTimer?.cancel();
    setState(() => _overlayLetter = letter);
    // Hide the overlay 600 ms after the last interaction.
    _overlayTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _overlayLetter = null);
    });
  }

  /// Calculates the cumulative scroll offset for [targetKey] and jumps to it.
  ///
  /// The CustomScrollView contains:
  ///   1. CupertinoSliverRefreshControl  — 0-height when idle
  ///   2. CupertinoSliverNavigationBar   — large-title bar (~96px expanded)
  ///   3. SliverList                     — section headers + rows
  ///
  /// We approximate the nav-bar height as a constant because sliver geometry
  /// is not queryable without a full RenderSliver walk.
  void _jumpToSection(String targetKey, Map<String, List<Chart>> groups) {
    const navBarOffset = 96.0;

    double offset = navBarOffset;
    for (final key in groups.keys) {
      if (key == targetKey) break;
      offset += _kSectionHeaderHeight;
      offset += groups[key]!.length * _kRowHeight;
    }

    if (!_scrollController.hasClients) return;
    _scrollController.jumpTo(
      offset.clamp(0.0, _scrollController.position.maxScrollExtent),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final libraryAsync = ref.watch(libraryProvider);
    final isSearching = _query.isNotEmpty;

    return CupertinoPageScaffold(
      // No navigationBar on the scaffold — CupertinoSliverNavigationBar is
      // inside the CustomScrollView so the large title collapses on scroll.
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Cap at 700px on wide desktop/web layouts.
          final maxWidth =
              constraints.maxWidth > 700 ? 700.0 : constraints.maxWidth;

          return Center(
            child: SizedBox(
              width: maxWidth,
              child: Column(
                children: [
                  Expanded(
                    child: libraryAsync.when(
                      loading: () =>
                          const Center(child: CupertinoActivityIndicator()),
                      error: (e, _) => CustomScrollView(
                        slivers: [
                          _buildNavBar(context),
                          SliverFillRemaining(
                            child: ErrorView(
                              message: 'Could not load library.\n$e',
                              onRetry: widget.onRefresh,
                            ),
                          ),
                        ],
                      ),
                      data: (state) {
                        if (state.charts.isEmpty) {
                          return CustomScrollView(
                            slivers: [
                              _buildNavBar(context),
                              const SliverFillRemaining(
                                child: EmptyStateView(
                                  icon: CupertinoIcons.music_note_list,
                                  title: 'No charts in your library',
                                  subtitle:
                                      'Charts added to your band will appear here.',
                                ),
                              ),
                            ],
                          );
                        }

                        final groups = _buildGroups(state.charts);

                        // ── Search results: flat filtered list, no sections ──
                        if (isSearching) {
                          final q = _query.toLowerCase();
                          final filtered = state.charts
                              .where((c) =>
                                  c.title.toLowerCase().contains(q) ||
                                  c.composer.toLowerCase().contains(q))
                              .toList()
                            ..sort((a, b) => a.title
                                .toLowerCase()
                                .compareTo(b.title.toLowerCase()));

                          return CustomScrollView(
                            slivers: [
                              _buildNavBar(context),
                              CupertinoSliverRefreshControl(
                                  onRefresh: widget.onRefresh),
                              if (filtered.isEmpty)
                                const SliverFillRemaining(
                                  child: Center(
                                    child: Text(
                                      'No matching charts',
                                      style: TextStyle(
                                        color: CupertinoColors.secondaryLabel,
                                      ),
                                    ),
                                  ),
                                )
                              else
                                SliverList(
                                  delegate: SliverChildBuilderDelegate(
                                    (context, index) {
                                      final chart = filtered[index];
                                      return _ChartRow(
                                        chart: chart,
                                        // Show separator for all but the last row.
                                        showSeparator:
                                            index < filtered.length - 1,
                                        onTap: () => context.push(
                                          '/library/${chart.id}',
                                          extra: widget.bandId,
                                        ),
                                      );
                                    },
                                    childCount: filtered.length,
                                  ),
                                ),
                              const SliverToBoxAdapter(
                                  child: SizedBox(height: 16)),
                            ],
                          );
                        }

                        // ── Normal grouped view with alphabet scrubber ───────
                        return Stack(
                          children: [
                            _GroupedScrollView(
                              groups: groups,
                              bandId: widget.bandId,
                              onRefresh: widget.onRefresh,
                              scrollController: _scrollController,
                              navBarBuilder: _buildNavBar,
                            ),
                            // Alphabet scrubber flush to the right edge.
                            Positioned(
                              top: 0,
                              bottom: 0,
                              right: 0,
                              width: _kIndexWidth,
                              child: _AlphabetIndex(
                                groups: groups,
                                onSelect: (dy, height) =>
                                    _onIndexSelect(dy, height, groups),
                              ),
                            ),
                            // Large letter overlay, visible only during scrubbing.
                            if (_overlayLetter != null)
                              Center(
                                child: _LetterOverlay(letter: _overlayLetter!),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                  // Fixed bottom bar: search field + add button.
                  _BottomSearchBar(
                    controller: _searchController,
                    onChanged: _onQueryChanged,
                    onAdd: () =>
                        context.push('/library/new', extra: widget.bandId),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Builds the CupertinoSliverNavigationBar.
  /// The `+` action lives in the bottom bar, so there is no trailing button.
  Widget _buildNavBar(BuildContext context) {
    return const CupertinoSliverNavigationBar(
      largeTitle: Text('Library'),
    );
  }
}

// ── Grouped scroll view ───────────────────────────────────────────────────────

/// The main scrollable content: one section header row + chart rows per group.
/// Extracted so the Stack in the parent can overlay the alphabet scrubber
/// without wrapping the entire Sliver pipeline.
class _GroupedScrollView extends StatelessWidget {
  const _GroupedScrollView({
    required this.groups,
    required this.bandId,
    required this.onRefresh,
    required this.scrollController,
    required this.navBarBuilder,
  });

  final Map<String, List<Chart>> groups;
  final int bandId;
  final Future<void> Function() onRefresh;
  final ScrollController scrollController;
  final Widget Function(BuildContext) navBarBuilder;

  @override
  Widget build(BuildContext context) {
    // Flatten groups into a single list of tagged items for the sliver delegate.
    // Using a record type avoids a separate private class.
    final List<({String letter, Chart? chart, bool isLastInSection})> items =
        [];

    for (final entry in groups.entries) {
      items.add((letter: entry.key, chart: null, isLastInSection: false));
      for (var i = 0; i < entry.value.length; i++) {
        items.add((
          letter: entry.key,
          chart: entry.value[i],
          isLastInSection: i == entry.value.length - 1,
        ));
      }
    }

    return CustomScrollView(
      controller: scrollController,
      slivers: [
        CupertinoSliverRefreshControl(onRefresh: onRefresh),
        navBarBuilder(context),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final item = items[index];

              if (item.chart == null) {
                return _SectionHeader(letter: item.letter);
              }

              final chart = item.chart!;
              return _ChartRow(
                chart: chart,
                // Suppress the separator after the last row of each section;
                // the next section header provides enough visual separation.
                showSeparator: !item.isLastInSection,
                onTap: () => context.push(
                  '/library/${chart.id}',
                  extra: bandId,
                ),
              );
            },
            childCount: items.length,
          ),
        ),
        // Extra bottom padding so the last row is not obscured by the search bar.
        const SliverToBoxAdapter(child: SizedBox(height: 8)),
      ],
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────

/// A tiny grey letter in the left gutter — not a full-width coloured bar.
/// Matches the iOS Contacts app's section label style.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.letter});

  final String letter;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _kSectionHeaderHeight,
      child: Padding(
        // Left padding aligns the letter with the text in chart rows.
        padding: const EdgeInsets.only(left: 16),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            letter,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Chart row ─────────────────────────────────────────────────────────────────

/// Flat Contacts-style row: circular coloured avatar, title + composer, chevron.
/// [showSeparator] controls the hairline bottom divider.
class _ChartRow extends StatelessWidget {
  const _ChartRow({
    required this.chart,
    required this.showSeparator,
    this.onTap,
  });

  final Chart chart;
  final bool showSeparator;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final avatarColor = _avatarColor(chart.title);
    final initials = _avatarInitials(chart.title);

    return Semantics(
      button: true,
      label: '${chart.title}, by ${chart.composer}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: _kRowHeight,
          // The separator sits at the very bottom of the row, inset from the
          // left edge to align with the text column — matching iOS Contacts.
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
              // Left inset matching section header left padding.
              const SizedBox(width: 16),
              // Circular coloured avatar with initials.
              Container(
                width: _kAvatarSize,
                height: _kAvatarSize,
                decoration: BoxDecoration(
                  color: avatarColor,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  initials,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: CupertinoColors.white,
                    // Ensure the text never wraps inside the circle.
                    height: 1.0,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Title and composer, flex to available width.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      chart.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (chart.composer.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        chart.composer,
                        style: TextStyle(
                          fontSize: 13,
                          color:
                              CupertinoColors.secondaryLabel.resolveFrom(context),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              // Disclosure chevron, matching standard iOS list rows.
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Icon(
                  CupertinoIcons.chevron_right,
                  size: 14,
                  color: CupertinoColors.tertiaryLabel.resolveFrom(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Alphabet scrubber ─────────────────────────────────────────────────────────

/// A vertical column of tiny letters flush to the right edge.
/// Only letters that have data in [groups] are rendered in the active colour;
/// the rest are rendered dimmer so the scrubber still provides a consistent
/// touch target across the full alphabet.
class _AlphabetIndex extends StatelessWidget {
  const _AlphabetIndex({required this.groups, required this.onSelect});

  final Map<String, List<Chart>> groups;

  /// Called with the local Y offset within the strip and its total height.
  final void Function(double dy, double height) onSelect;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalHeight = constraints.maxHeight;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => onSelect(d.localPosition.dy, totalHeight),
          onVerticalDragUpdate: (d) => onSelect(d.localPosition.dy, totalHeight),
          child: SizedBox(
            width: _kIndexWidth,
            height: totalHeight,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: _kAlphabetLetters.map((letter) {
                final isActive = groups.containsKey(letter);
                return Flexible(
                  child: Center(
                    child: Text(
                      letter,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        // Active sections use system blue; inactive are dimmed.
                        color: isActive
                            ? CupertinoColors.activeBlue.resolveFrom(context)
                            : CupertinoColors.tertiaryLabel.resolveFrom(context),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }
}

// ── Large letter overlay ──────────────────────────────────────────────────────

/// A 72×72 semi-transparent dark rounded rectangle shown in the centre of the
/// screen during scrubber interaction.  Uses an explicit dark colour so the
/// white letter is legible in both light and dark mode.
class _LetterOverlay extends StatelessWidget {
  const _LetterOverlay({required this.letter});

  final String letter;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          // A dark semi-transparent fill that reads well in both modes.
          color: const Color(0xCC1C1C1E),
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: Text(
          letter,
          style: const TextStyle(
            fontSize: 40,
            fontWeight: FontWeight.w600,
            color: CupertinoColors.white,
          ),
        ),
      ),
    );
  }
}

// ── Bottom search bar ─────────────────────────────────────────────────────────

/// Fixed bar above the tab bar: a search field on the left and a filled
/// circular `+` button on the right, separated from the list by a hairline.
class _BottomSearchBar extends StatelessWidget {
  const _BottomSearchBar({
    required this.controller,
    required this.onChanged,
    required this.onAdd,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _kSearchBarHeight,
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
          // Search field takes all available width, leaving room for the button.
          Expanded(
            child: CupertinoSearchTextField(
              controller: controller,
              onChanged: onChanged,
              placeholder: 'Search',
            ),
          ),
          const SizedBox(width: 10),
          // Circular filled add button — 36×36 to stay within the bar height.
          Semantics(
            button: true,
            label: 'Add chart',
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: onAdd,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: CupertinoColors.activeBlue.resolveFrom(context),
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
