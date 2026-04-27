import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show LinearProgressIndicator;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tts_bandmate/shared/widgets/error_view.dart';
import '../data/library_repository.dart';
import '../data/models/chart.dart';
import '../providers/library_provider.dart';

// ── Upload type constants ─────────────────────────────────────────────────────

const _kUploadTypes = <int, String>{
  3: 'Sheet Music',
  1: 'Audio',
  2: 'Video',
};

// ── Root screen — resolves async chart state ──────────────────────────────────

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

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) > 300 && context.canPop()) {
          context.pop();
        }
      },
      child: chartAsync.when(
        loading: () => const CupertinoPageScaffold(
          navigationBar: CupertinoNavigationBar(middle: Text('Chart')),
          child: Center(child: CupertinoActivityIndicator()),
        ),
        error: (e, _) => CupertinoPageScaffold(
          navigationBar: const CupertinoNavigationBar(middle: Text('Chart')),
          child: ErrorView(
            message: ErrorView.friendlyMessage(e),
            onRetry: () => ref.invalidate(
                chartDetailProvider((bandId: bandId, chartId: chartId))),
          ),
        ),
        data: (chart) => _ChartDetailBody(
          chart: chart,
          bandId: bandId,
          chartId: chartId,
        ),
      ),
    );
  }
}

// ── Body ──────────────────────────────────────────────────────────────────────

class _ChartDetailBody extends ConsumerWidget {
  const _ChartDetailBody({
    required this.chart,
    required this.bandId,
    required this.chartId,
  });

  final Chart chart;
  final int bandId;
  final int chartId;

  Future<void> _openUpload(
    BuildContext context,
    WidgetRef ref,
    ChartUpload upload,
  ) async {
    try {
      final result = await ref
          .read(libraryRepositoryProvider)
          .downloadChartUpload(bandId, chartId, upload.id);

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${result.filename}');
      await file.writeAsBytes(result.bytes);
      await OpenFile.open(file.path, type: result.mimeType);
    } catch (e) {
      if (context.mounted) {
        showCupertinoDialog<void>(
          context: context,
          builder: (ctx) => CupertinoAlertDialog(
            title: const Text('Could Not Open File'),
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

  void _showAddUploadSheet(BuildContext context, WidgetRef ref) {
    // showCupertinoModalPopup creates a new route and loses the ProviderScope
    // ancestor. Wrap in UncontrolledProviderScope to re-attach the existing
    // container so AutoDispose providers (chartUploadProvider) work correctly.
    final container = ProviderScope.containerOf(context);
    showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => UncontrolledProviderScope(
        container: container,
        child: _AddUploadSheet(
          bandId: bandId,
          chartId: chartId,
          onUploaded: () => ref.invalidate(
            chartDetailProvider((bandId: bandId, chartId: chartId)),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDeleteUpload(
    BuildContext context,
    WidgetRef ref,
    ChartUpload upload,
  ) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Delete Upload'),
        content: Text(
            'Are you sure you want to delete "${upload.displayName}"? This cannot be undone.'),
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
      await ref.read(chartUploadProvider.notifier).deleteChartUpload(
            bandId,
            chartId,
            upload.id,
          );
      if (context.mounted) {
        ref.invalidate(
            chartDetailProvider((bandId: bandId, chartId: chartId)));
      }
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(chart.title),
        trailing: Semantics(
          button: true,
          label: 'Add upload',
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => _showAddUploadSheet(context, ref),
            child: const Icon(CupertinoIcons.plus_circle),
          ),
        ),
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
                    const _SectionHeader(label: 'Uploads'),
                    if (chart.uploads.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Text(
                          'No uploads yet. Tap + to add one.',
                          style: TextStyle(
                            fontSize: 14,
                            color: CupertinoColors.secondaryLabel
                                .resolveFrom(context),
                          ),
                        ),
                      )
                    else
                      ...chart.uploads.map(
                        (u) => _UploadRow(
                          upload: u,
                          onOpen: () => _openUpload(context, ref, u),
                          onDelete: () =>
                              _confirmDeleteUpload(context, ref, u),
                        ),
                      ),
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
    final rows = <Widget>[];

    if (chart.composer.isNotEmpty) {
      rows.add(_MetaRow(label: 'Composer', value: chart.composer));
    }

    if (chart.description.isNotEmpty) {
      rows.add(_MetaRow(label: 'Description', value: chart.description));
    }

    if (chart.price > 0) {
      final priceStr = '\$${chart.price.toStringAsFixed(2)}';
      rows.add(_MetaRow(label: 'Price', value: priceStr));
    }

    rows.add(_MetaRow(
        label: 'Visibility', value: chart.isPublic ? 'Public' : 'Private'));

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
  const _UploadRow({
    required this.upload,
    required this.onOpen,
    required this.onDelete,
  });

  final ChartUpload upload;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          '${upload.displayName}, ${upload.typeName}. Tap to open. Long press to delete.',
      child: GestureDetector(
        onTap: onOpen,
        onLongPress: onDelete,
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color:
                CupertinoColors.tertiarySystemBackground.resolveFrom(context),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
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
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: CupertinoColors.systemGrey5
                                  .resolveFrom(context),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              upload.typeName,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: CupertinoColors.secondaryLabel
                                    .resolveFrom(context),
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
                          color: CupertinoColors.secondaryLabel
                              .resolveFrom(context),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              // Open-in icon — tapping anywhere on the row also triggers onOpen,
              // but this icon makes the affordance visible.
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                onPressed: onOpen,
                child: Icon(
                  CupertinoIcons.arrow_up_right_square,
                  size: 18,
                  color: CupertinoColors.activeBlue.resolveFrom(context),
                ),
              ),
              const SizedBox(width: 4),
              // Trash icon affords deletion without long-press discovery.
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                onPressed: onDelete,
                child: Icon(
                  CupertinoIcons.trash,
                  size: 18,
                  color: CupertinoColors.destructiveRed.resolveFrom(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Add upload sheet ──────────────────────────────────────────────────────────

/// Bottom-sheet modal for picking a file and uploading it to a chart.
///
/// Uses [chartUploadProvider] (AutoDispose) so upload state is scoped to this
/// sheet's lifetime. When the upload completes, [onUploaded] is called and the
/// sheet closes.
class _AddUploadSheet extends ConsumerStatefulWidget {
  const _AddUploadSheet({
    required this.bandId,
    required this.chartId,
    required this.onUploaded,
  });

  final int bandId;
  final int chartId;
  final VoidCallback onUploaded;

  @override
  ConsumerState<_AddUploadSheet> createState() => _AddUploadSheetState();
}

class _AddUploadSheetState extends ConsumerState<_AddUploadSheet> {
  PlatformFile? _pickedFile;
  final _displayNameController = TextEditingController();
  final _notesController = TextEditingController();

  // Default to Sheet Music (3).
  int _uploadTypeId = 3;

  @override
  void dispose() {
    _displayNameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      // PDF, audio, and video formats relevant to charts.
      allowedExtensions: ['pdf', 'mp3', 'wav', 'm4a', 'mp4', 'mov'],
      withData: true, // ensures PlatformFile.bytes is populated on all platforms
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    setState(() {
      _pickedFile = file;
      // Pre-fill display name from filename, stripping the extension.
      final name = file.name;
      final dotIndex = name.lastIndexOf('.');
      _displayNameController.text =
          dotIndex > 0 ? name.substring(0, dotIndex) : name;
    });
  }

  Future<void> _upload() async {
    final file = _pickedFile;
    if (file == null) return;

    final displayName = _displayNameController.text.trim().isEmpty
        ? file.name
        : _displayNameController.text.trim();

    await ref.read(chartUploadProvider.notifier).uploadChartFile(
          widget.bandId,
          widget.chartId,
          file: file,
          displayName: displayName,
          uploadTypeId: _uploadTypeId,
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
        );

    final uploadState = ref.read(chartUploadProvider);
    if (uploadState.error == null && mounted) {
      widget.onUploaded();
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final uploadState = ref.watch(chartUploadProvider);
    final isUploading = uploadState.isUploading;
    final canUpload = _pickedFile != null && !isUploading;

    return Container(
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground.resolveFrom(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      // Let the sheet grow with content but stop short of the full screen.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 6),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: CupertinoColors.systemGrey3.resolveFrom(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Title row with close button
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 8, 12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Add Upload',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed:
                        isUploading ? null : () => Navigator.of(context).pop(),
                    child: const Icon(CupertinoIcons.xmark_circle_fill),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Error banner
                    if (uploadState.error != null)
                      _UploadErrorBanner(message: uploadState.error!),

                    // File picker button
                    _FilePicker(
                      pickedFile: _pickedFile,
                      onTap: isUploading ? null : _pickFile,
                    ),

                    const SizedBox(height: 16),

                    // Type selector
                    _TypeSelector(
                      selectedId: _uploadTypeId,
                      onChanged: isUploading
                          ? null
                          : (id) => setState(() => _uploadTypeId = id),
                    ),

                    const SizedBox(height: 16),

                    // Display name
                    _SheetTextField(
                      controller: _displayNameController,
                      label: 'Display Name',
                      placeholder: 'e.g. Piano Lead Sheet',
                      enabled: !isUploading,
                    ),

                    const SizedBox(height: 12),

                    // Notes
                    _SheetTextField(
                      controller: _notesController,
                      label: 'Notes',
                      placeholder: 'Optional',
                      maxLines: 2,
                      enabled: !isUploading,
                    ),

                    const SizedBox(height: 20),

                    // Progress bar — only shown while uploading
                    if (isUploading)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _UploadProgressBar(
                            progress: uploadState.progress),
                      ),

                    // Upload button
                    SizedBox(
                      height: 50,
                      child: CupertinoButton.filled(
                        onPressed: canUpload ? _upload : null,
                        child: isUploading
                            ? const CupertinoActivityIndicator(
                                color: CupertinoColors.white)
                            : const Text('Upload'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sheet sub-widgets ─────────────────────────────────────────────────────────

class _FilePicker extends StatelessWidget {
  const _FilePicker({required this.pickedFile, required this.onTap});

  final PlatformFile? pickedFile;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final hasFile = pickedFile != null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasFile
                ? CupertinoColors.activeBlue.resolveFrom(context)
                : CupertinoColors.separator.resolveFrom(context),
            width: hasFile ? 1.5 : 0.5,
          ),
        ),
        child: Row(
          children: [
            Icon(
              hasFile
                  ? CupertinoIcons.doc_fill
                  : CupertinoIcons.folder_badge_plus,
              size: 22,
              color: hasFile
                  ? CupertinoColors.activeBlue.resolveFrom(context)
                  : CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                hasFile ? pickedFile!.name : 'Choose a file…',
                style: TextStyle(
                  fontSize: 15,
                  color: hasFile
                      ? CupertinoColors.label.resolveFrom(context)
                      : CupertinoColors.secondaryLabel.resolveFrom(context),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (hasFile)
              Icon(
                CupertinoIcons.checkmark_circle_fill,
                size: 18,
                color: CupertinoColors.activeGreen.resolveFrom(context),
              ),
          ],
        ),
      ),
    );
  }
}

/// Segmented control for selecting the upload type (Sheet Music / Audio / Video).
class _TypeSelector extends StatelessWidget {
  const _TypeSelector({required this.selectedId, required this.onChanged});

  final int selectedId;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Type',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: CupertinoSegmentedControl<int>(
            groupValue: selectedId,
            onValueChanged: onChanged ?? (_) {},
            children: {
              for (final e in _kUploadTypes.entries)
                e.key: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 6),
                  child: Text(
                    e.value,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
            },
          ),
        ),
      ],
    );
  }
}

class _SheetTextField extends StatelessWidget {
  const _SheetTextField({
    required this.controller,
    required this.label,
    required this.placeholder,
    this.maxLines = 1,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String label;
  final String placeholder;
  final int maxLines;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
          ),
        ),
        const SizedBox(height: 6),
        CupertinoTextField(
          controller: controller,
          placeholder: placeholder,
          maxLines: maxLines,
          minLines: maxLines,
          enabled: enabled,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: CupertinoColors.separator.resolveFrom(context),
              width: 0.5,
            ),
          ),
        ),
      ],
    );
  }
}

/// Linear progress bar shown during an active upload.
class _UploadProgressBar extends StatelessWidget {
  const _UploadProgressBar({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Uploading…',
              style: TextStyle(
                fontSize: 12,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
            Text(
              '${(progress * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                fontSize: 12,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: CupertinoColors.systemGrey5.resolveFrom(context),
            valueColor: AlwaysStoppedAnimation<Color>(
              CupertinoColors.activeBlue.resolveFrom(context),
            ),
          ),
        ),
      ],
    );
  }
}

/// Error banner displayed inside the upload sheet.
class _UploadErrorBanner extends StatelessWidget {
  const _UploadErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: CupertinoColors.systemRed.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: CupertinoColors.systemRed.resolveFrom(context),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.exclamationmark_circle,
            size: 16,
            color: CupertinoColors.systemRed.resolveFrom(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                color: CupertinoColors.systemRed.resolveFrom(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
