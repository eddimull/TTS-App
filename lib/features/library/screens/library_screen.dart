import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tts_bandmate/shared/widgets/empty_state_view.dart';
import 'package:tts_bandmate/shared/widgets/error_view.dart';

import '../../auth/data/models/band_summary.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../shared/providers/personal_band_provider.dart';
import '../../../shared/widgets/band_avatar.dart';
import '../data/models/chart.dart';
import '../providers/library_filter_provider.dart';
import '../providers/library_provider.dart';
import '../widgets/create_chart_sheet.dart';
import '../widgets/library_filter_button.dart';
import '../widgets/library_filter_sheet.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';

// ── Constants ─────────────────────────────────────────────────────────────────

const double _kRowHeight = 56.0;
const double _kSectionHeaderHeight = 20.0;
const double _kSearchBarHeight = 56.0;
const double _kIndexWidth = 16.0;
const double _kAvatarSize = 38.0;

const List<String> _kAlphabetLetters = [
  '#',
  'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
  'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
];

// ── Helpers ───────────────────────────────────────────────────────────────────

String _sectionKey(String title) {
  if (title.isEmpty) return '#';
  final first = title[0].toUpperCase();
  final code = first.codeUnitAt(0);
  if (code >= 65 && code <= 90) return first;
  return '#';
}

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

// ── Top-level screen ──────────────────────────────────────────────────────────

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();

  String _query = '';
  String? _overlayLetter;
  Timer? _overlayTimer;
  bool _addInProgress = false;

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _overlayTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() =>
      ref.read(libraryProvider.notifier).refresh();

  // ── Search ──────────────────────────────────────────────────────────────────

  void _onQueryChanged(String value) {
    setState(() => _query = value.trim());
  }

  // ── Delete ───────────────────────────────────────────────────────────────────

  Future<void> _confirmDeleteChart(BuildContext context, Chart chart) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Delete Chart'),
        content: Text(
            'Are you sure you want to delete "${chart.title}"? This cannot be undone.'),
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

    if (confirmed != true || !context.mounted) return;

    try {
      await ref
          .read(libraryProvider.notifier)
          .deleteChart(chart.bandId, chart.id);
    } catch (e) {
      if (context.mounted) {
        showCupertinoDialog<void>(
          context: context,
          builder: (ctx) => CupertinoAlertDialog(
            title: const Text('Delete Failed'),
            content: Text(e.toString()),
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

  // ── Alphabet scrubber ────────────────────────────────────────────────────────

  void _onIndexSelect(
    double dy,
    double indexHeight,
    Map<String, List<Chart>> groups,
  ) {
    final letterCount = _kAlphabetLetters.length;
    final fraction = (dy / indexHeight).clamp(0.0, 0.9999);
    final idx = (fraction * letterCount).floor();
    final tappedLetter = _kAlphabetLetters[idx.clamp(0, letterCount - 1)];

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
    _overlayTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _overlayLetter = null);
    });
  }

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

  // ── Filter sheet ────────────────────────────────────────────────────────────

  void _openFilterSheet() {
    final auth = ref.read(authProvider).value;
    final bands = (auth is AuthAuthenticated) ? auth.bands : <BandSummary>[];
    showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => LibraryFilterSheet(bands: bands),
    );
  }

  // ── Add flow ────────────────────────────────────────────────────────────────

  Future<void> _handleAddTapped() async {
    if (_addInProgress) return;
    setState(() => _addInProgress = true);
    try {
      final auth = ref.read(authProvider).value;
      if (auth is! AuthAuthenticated) return;

      final realBands = auth.bands.where((b) => !b.isPersonal).toList();
      final personal = auth.bands.firstWhere(
        (b) => b.isPersonal,
        orElse: () => const BandSummary(id: -1, name: '', isOwner: false),
      );

      // 0 real bands → ensure personal and push form.
      if (realBands.isEmpty) {
        try {
          final p = personal.id != -1
              ? personal
              : await ref.read(personalBandProvider.notifier).ensureExists();
          await _pushCreateAndMaybeOpenDetail(p);
        } catch (e) {
          if (mounted) {
            await showCupertinoDialog<void>(
              context: context,
              builder: (ctx) => CupertinoAlertDialog(
                title: const Text('Could not create chart'),
                content: const Text("Couldn't set up personal library."),
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
        return;
      }

      // 1 real band, no personal yet → skip the sheet.
      if (realBands.length == 1 && personal.id == -1) {
        await _pushCreateAndMaybeOpenDetail(realBands.single);
        return;
      }

      // Otherwise → show the picker.
      if (!mounted) return;
      await showCupertinoModalPopup<void>(
        context: context,
        builder: (sheetCtx) => CreateChartSheet(
          onBandSelected: (band) async {
            Navigator.of(sheetCtx).pop();
            await _pushCreateAndMaybeOpenDetail(band);
          },
        ),
      );
    } finally {
      if (mounted) setState(() => _addInProgress = false);
    }
  }

  Future<void> _pushCreateAndMaybeOpenDetail(BandSummary band) async {
    final result = await context.push<Chart>('/library/new', extra: band);
    if (!mounted || result == null) return;
    context.push('/library/${result.id}', extra: result.bandId);
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final libraryAsync = ref.watch(libraryProvider);
    final filter = ref.watch(libraryFilterProvider);
    final isSearching = _query.isNotEmpty;

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
                    child: libraryAsync.when(
                      loading: () =>
                          const Center(child: CupertinoActivityIndicator()),
                      error: (e, _) => CustomScrollView(
                        slivers: [
                          _buildNavBar(context),
                          SliverFillRemaining(
                            child: ErrorView(
                              message: ErrorView.friendlyMessage(e),
                              onRetry: _refresh,
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
                                      'Charts added to any of your bands will appear here.',
                                ),
                              ),
                            ],
                          );
                        }

                        // Apply band filter.
                        final visible = state.charts
                            .where((c) =>
                                c.band == null ||
                                !filter.hiddenBandIds.contains(c.band!.id))
                            .toList();

                        // All bands hidden → distinct empty state.
                        if (visible.isEmpty && filter.isActive) {
                          return Stack(
                            children: [
                              CustomScrollView(
                                slivers: [
                                  _buildNavBar(context),
                                  SliverFillRemaining(
                                    child: Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            CupertinoIcons.eye_slash,
                                            size: 48,
                                            color: context.secondaryText,
                                          ),
                                          const SizedBox(height: 12),
                                          const Text(
                                              'All bands hidden by filter'),
                                          const SizedBox(height: 12),
                                          CupertinoButton(
                                            onPressed: () => ref
                                                .read(libraryFilterProvider
                                                    .notifier)
                                                .clear(),
                                            child: const Text('Show all'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              _filterButtonOverlay(context),
                            ],
                          );
                        }

                        final groups = _buildGroups(visible);

                        if (isSearching) {
                          final q = _query.toLowerCase();
                          final filtered = visible
                              .where((c) =>
                                  c.title.toLowerCase().contains(q) ||
                                  c.composer.toLowerCase().contains(q))
                              .toList()
                            ..sort((a, b) => a.title
                                .toLowerCase()
                                .compareTo(b.title.toLowerCase()));

                          return Stack(children: [
                            CustomScrollView(
                              slivers: [
                                CupertinoSliverRefreshControl(onRefresh: _refresh),
                                _buildNavBar(context),
                                if (filtered.isEmpty)
                                  SliverFillRemaining(
                                    child: Center(
                                      child: Text('No matching charts',
                                          style: TextStyle(
                                              color: context.secondaryText)),
                                    ),
                                  )
                                else
                                  SliverList(
                                    delegate: SliverChildBuilderDelegate(
                                      (context, index) {
                                        final chart = filtered[index];
                                        return _ChartRow(
                                          chart: chart,
                                          showSeparator:
                                              index < filtered.length - 1,
                                          onTap: () => context.push(
                                              '/library/${chart.id}',
                                              extra: chart.bandId),
                                          onDelete: () =>
                                              _confirmDeleteChart(context, chart),
                                        );
                                      },
                                      childCount: filtered.length,
                                    ),
                                  ),
                                const SliverToBoxAdapter(
                                    child: SizedBox(height: 16)),
                              ],
                            ),
                            _filterButtonOverlay(context),
                          ]);
                        }

                        return Stack(
                          children: [
                            _GroupedScrollView(
                              groups: groups,
                              onRefresh: _refresh,
                              scrollController: _scrollController,
                              navBarBuilder: _buildNavBar,
                              onDeleteChart: (chart) =>
                                  _confirmDeleteChart(context, chart),
                            ),
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
                            _filterButtonOverlay(context),
                            if (_overlayLetter != null)
                              Center(
                                child: _LetterOverlay(letter: _overlayLetter!),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                  _BottomSearchBar(
                    controller: _searchController,
                    onChanged: _onQueryChanged,
                    onAdd: _addInProgress ? null : _handleAddTapped,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildNavBar(BuildContext context) {
    return const CupertinoSliverNavigationBar(
      largeTitle: Text('Library'),
    );
  }

  Widget _filterButtonOverlay(BuildContext context) => Positioned(
        top: MediaQuery.of(context).padding.top + 50,
        right: _kIndexWidth + 4,
        child: LibraryFilterButton(onPressed: _openFilterSheet),
      );
}

// ── Grouped scroll view ───────────────────────────────────────────────────────

class _GroupedScrollView extends StatelessWidget {
  const _GroupedScrollView({
    required this.groups,
    required this.onRefresh,
    required this.scrollController,
    required this.navBarBuilder,
    required this.onDeleteChart,
  });

  final Map<String, List<Chart>> groups;
  final Future<void> Function() onRefresh;
  final ScrollController scrollController;
  final Widget Function(BuildContext) navBarBuilder;
  final void Function(Chart) onDeleteChart;

  @override
  Widget build(BuildContext context) {
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
                showSeparator: !item.isLastInSection,
                onTap: () => context.push('/library/${chart.id}',
                    extra: chart.bandId),
                onDelete: () => onDeleteChart(chart),
              );
            },
            childCount: items.length,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 8)),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.letter});
  final String letter;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _kSectionHeaderHeight,
      child: Padding(
        padding: const EdgeInsets.only(left: 16),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            letter,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.secondaryText,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Chart row ─────────────────────────────────────────────────────────────────

class _ChartRow extends ConsumerWidget {
  const _ChartRow({
    required this.chart,
    required this.showSeparator,
    this.onTap,
    this.onDelete,
  });

  final Chart chart;
  final bool showSeparator;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider).value;
    final user = (auth is AuthAuthenticated) ? auth.user : null;
    final band = chart.band;
    final isPersonal = band?.isPersonal == true;

    Widget avatar;
    if (band == null) {
      // Defensive fallback if a chart somehow lacks band metadata.
      avatar = SizedBox(
        width: _kAvatarSize,
        height: _kAvatarSize,
        child: BandAvatar.forUser(
          imageUrl: user?.avatarUrl,
          name: user?.name ?? '?',
          size: _kAvatarSize,
        ),
      );
    } else if (isPersonal) {
      avatar = BandAvatar.forUser(
        imageUrl: user?.avatarUrl,
        name: user?.name ?? band.name,
        size: _kAvatarSize,
      );
    } else {
      // BandAvatar.forBand needs a BandSummary; build one from ChartBand.
      avatar = BandAvatar.forBand(
        band: BandSummary(
          id: band.id,
          name: band.name,
          isOwner: false,
          isPersonal: band.isPersonal,
          logoUrl: band.logoUrl,
        ),
        size: _kAvatarSize,
      );
    }

    return Semantics(
      button: true,
      label: '${chart.title}, by ${chart.composer}. Long press to delete.',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: onDelete,
        child: Container(
          height: _kRowHeight,
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
              const SizedBox(width: 16),
              avatar,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      chart.title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w400),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (chart.composer.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        chart.composer,
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
              Padding(
                padding: const EdgeInsets.only(right: 16),
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

// ── Alphabet scrubber ─────────────────────────────────────────────────────────

class _AlphabetIndex extends StatelessWidget {
  const _AlphabetIndex({required this.groups, required this.onSelect});

  final Map<String, List<Chart>> groups;
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
            label: 'Add chart',
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
