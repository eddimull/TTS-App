import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tts_bandmate/shared/widgets/error_view.dart';
import '../data/models/chart.dart';
import '../providers/library_provider.dart';

class ChartDetailScreen extends ConsumerWidget {
  const ChartDetailScreen({
    super.key,
    required this.bandId,
    required this.chartId,
  });

  final int bandId;
  final int chartId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chartAsync =
        ref.watch(chartDetailProvider((bandId: bandId, chartId: chartId)));

    return chartAsync.when(
      loading: () => const CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(middle: Text('Chart')),
        child: Center(child: CupertinoActivityIndicator()),
      ),
      error: (e, _) => CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(middle: Text('Chart')),
        child: ErrorView(
          message: 'Could not load chart.\n$e',
          onRetry: () =>
              ref.invalidate(chartDetailProvider((bandId: bandId, chartId: chartId))),
        ),
      ),
      data: (chart) => _ChartDetailBody(chart: chart),
    );
  }
}

// ── Body ──────────────────────────────────────────────────────────────────────

class _ChartDetailBody extends StatelessWidget {
  const _ChartDetailBody({required this.chart});

  final Chart chart;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(chart.title),
      ),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth =
                constraints.maxWidth > 700 ? 700.0 : constraints.maxWidth;
            return Center(
              child: SizedBox(
                width: maxWidth,
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  children: [
                    // Metadata section
                    const _SectionHeader(label: 'Details'),
                    _MetadataCard(chart: chart),
                    // Uploads section
                    if (chart.uploads.isNotEmpty) ...[
                      const _SectionHeader(label: 'Uploads'),
                      ...chart.uploads.map((u) => _UploadRow(upload: u)),
                    ],
                    if (chart.uploads.isEmpty) ...[
                      const _SectionHeader(label: 'Uploads'),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Text(
                          'No uploads for this chart.',
                          style: TextStyle(
                            fontSize: 14,
                            color:
                                CupertinoColors.secondaryLabel.resolveFrom(context),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
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

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

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
          letterSpacing: 0.5,
          color: CupertinoColors.secondaryLabel.resolveFrom(context),
        ),
      ),
    );
  }
}

// ── Metadata card ─────────────────────────────────────────────────────────────

class _MetadataCard extends StatelessWidget {
  const _MetadataCard({required this.chart});

  final Chart chart;

  @override
  Widget build(BuildContext context) {
    // Build only the rows that have meaningful data.
    final rows = <Widget>[];

    if (chart.composer.isNotEmpty) {
      rows.add(_MetaRow(label: 'Composer', value: chart.composer));
    }

    if (chart.description.isNotEmpty) {
      rows.add(_MetaRow(label: 'Description', value: chart.description));
    }

    if (chart.price > 0) {
      // Format as currency, e.g. "$12.00"
      final priceStr = '\$${chart.price.toStringAsFixed(2)}';
      rows.add(_MetaRow(label: 'Price', value: priceStr));
    }

    if (rows.isEmpty) {
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            'No additional details.',
            style: TextStyle(
              fontSize: 14,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            rows[i],
            if (i < rows.length - 1)
              Container(
                height: 0.5,
                margin: const EdgeInsets.only(left: 16),
                color: CupertinoColors.separator.resolveFrom(context),
              ),
          ],
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Upload row ────────────────────────────────────────────────────────────────

class _UploadRow extends StatelessWidget {
  const _UploadRow({required this.upload});

  final ChartUpload upload;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  upload.displayName.isNotEmpty
                      ? upload.displayName
                      : 'Untitled upload',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (upload.typeName.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemGrey5.resolveFrom(context),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    upload.typeName,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color:
                          CupertinoColors.secondaryLabel.resolveFrom(context),
                    ),
                  ),
                ),
            ],
          ),
          if (upload.notes.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              upload.notes,
              style: TextStyle(
                fontSize: 13,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
