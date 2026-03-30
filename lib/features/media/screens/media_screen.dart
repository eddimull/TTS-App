import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Material, Theme, ThemeData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../../../shared/providers/selected_band_provider.dart';
import '../../../shared/widgets/auth_thumbnail.dart';
import '../data/models/media_file.dart';
import '../providers/media_provider.dart';

class MediaScreen extends ConsumerStatefulWidget {
  const MediaScreen({super.key});

  @override
  ConsumerState<MediaScreen> createState() => _MediaScreenState();
}

class _MediaScreenState extends ConsumerState<MediaScreen> {
  String? _folderPath;
  String? _mediaTypeFilter;
  final _searchController = TextEditingController();
  String _search = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  MediaListParams get _params {
    final bandId = ref.read(selectedBandProvider).valueOrNull ?? 0;
    return MediaListParams(
      bandId: bandId,
      folderPath: _folderPath,
      mediaType: _mediaTypeFilter,
      search: _search.isEmpty ? null : _search,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bandId = ref.watch(selectedBandProvider).valueOrNull ?? 0;
    final listState = ref.watch(mediaListProvider(_params));
    final uploadState = ref.watch(uploadProvider);

    return CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          middle: _folderPath != null
              ? Text(_folderPath!.split('/').last)
              : const Text('Media'),
          leading: _folderPath != null
              ? CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: () => setState(() => _folderPath = null),
                  child: const Icon(CupertinoIcons.back),
                )
              : null,
          trailing: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => _showFilterSheet(context),
            child: const Icon(CupertinoIcons.line_horizontal_3_decrease),
          ),
        ),
        child: Column(
          children: [
            // Search bar
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: CupertinoSearchTextField(
                controller: _searchController,
                placeholder: 'Search…',
                onChanged: (v) => setState(() => _search = v),
                onSuffixTap: () {
                  _searchController.clear();
                  setState(() => _search = '');
                },
              ),
            ),
            // Upload progress banner.
            if (uploadState.isUploading)
              _UploadProgressBanner(progress: uploadState.progress),
            if (uploadState.error != null)
              _ErrorBanner(
                message: uploadState.error!,
                onDismiss: () => ref.read(uploadProvider.notifier).reset(),
              ),
            // Upload button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: SizedBox(
                width: double.infinity,
                child: CupertinoButton.filled(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  onPressed: () => _showUploadSheet(context, bandId),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(CupertinoIcons.arrow_up_circle, size: 18),
                      SizedBox(width: 6),
                      Text('Upload'),
                    ],
                  ),
                ),
              ),
            ),
            // Content.
            Expanded(child: _buildBody(listState, bandId)),
          ],
        ),
    );
  }

  void _showFilterSheet(BuildContext context) {
    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: const Text('Filter by Type'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _mediaTypeFilter = null);
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_mediaTypeFilter == null)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Icon(CupertinoIcons.checkmark, size: 16),
                  ),
                const Text('All'),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _mediaTypeFilter = 'image');
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_mediaTypeFilter == 'image')
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Icon(CupertinoIcons.checkmark, size: 16),
                  ),
                const Text('Images'),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _mediaTypeFilter = 'video');
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_mediaTypeFilter == 'video')
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Icon(CupertinoIcons.checkmark, size: 16),
                  ),
                const Text('Videos'),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _mediaTypeFilter = 'audio');
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_mediaTypeFilter == 'audio')
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Icon(CupertinoIcons.checkmark, size: 16),
                  ),
                const Text('Audio'),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _mediaTypeFilter = 'document');
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_mediaTypeFilter == 'document')
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Icon(CupertinoIcons.checkmark, size: 16),
                  ),
                const Text('Documents'),
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

  Widget _buildBody(MediaListState state, int bandId) {
    if (state.isLoading) {
      return const Center(child: CupertinoActivityIndicator());
    }

    if (state.error != null && state.files.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(state.error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            CupertinoButton.filled(
              onPressed: () =>
                  ref.read(mediaListProvider(_params).notifier).load(),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (state.folders.isEmpty && state.files.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.photo_on_rectangle, size: 48,
                color: CupertinoColors.secondaryLabel.resolveFrom(context)),
            const SizedBox(height: 12),
            const Text('No media yet.'),
          ],
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n is ScrollEndNotification &&
            n.metrics.extentAfter < 200 &&
            state.hasMore &&
            !state.isLoadingMore) {
          ref.read(mediaListProvider(_params).notifier).loadMore();
        }
        return false;
      },
      child: CustomScrollView(
        slivers: [
          CupertinoSliverRefreshControl(
            onRefresh: () =>
                ref.read(mediaListProvider(_params).notifier).load(),
          ),
          if (state.folders.isNotEmpty)
            SliverToBoxAdapter(
              child: _FolderRow(
                folders: state.folders,
                onTap: (f) => setState(() => _folderPath = f),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.all(8),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  if (i < state.files.length) {
                    return _MediaTile(
                      file: state.files[i],
                      bandId: bandId,
                      onDeleted: () => ref
                          .read(mediaListProvider(_params).notifier)
                          .removeFile(state.files[i].id),
                    );
                  }
                  return null;
                },
                childCount: state.files.length,
              ),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
              ),
            ),
          ),
          if (state.isLoadingMore)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CupertinoActivityIndicator()),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showUploadSheet(BuildContext context, int bandId) async {
    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: const Text('Upload Media'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(context);
              await _pickAndUpload(context, bandId, ImageSource.gallery);
            },
            child: const Text('Photo / Video from Library'),
          ),
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(context);
              await _pickAndUpload(context, bandId, ImageSource.camera);
            },
            child: const Text('Take Photo'),
          ),
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(context);
              await _pickDocument(context, bandId);
            },
            child: const Text('Document / Audio file'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  Future<void> _pickAndUpload(
    BuildContext context,
    int bandId,
    ImageSource source,
  ) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 85);
    if (picked == null) return;

    await ref.read(uploadProvider.notifier).upload(
          bandId,
          File(picked.path),
          folderPath: _folderPath,
        );
  }

  Future<void> _pickDocument(BuildContext context, int bandId) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.any,
    );
    if (result == null || result.files.single.path == null) return;

    await ref.read(uploadProvider.notifier).upload(
          bandId,
          File(result.files.single.path!),
          folderPath: _folderPath,
        );
  }
}

class _FolderRow extends StatelessWidget {
  const _FolderRow({required this.folders, required this.onTap});

  final List<String> folders;
  final void Function(String) onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: folders.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final name = folders[i].split('/').last;
          return GestureDetector(
            onTap: () => onTap(folders[i]),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(CupertinoIcons.folder,
                      size: 16,
                      color: CupertinoColors.secondaryLabel.resolveFrom(context)),
                  const SizedBox(width: 4),
                  Text(name,
                      style: TextStyle(
                          fontSize: 14,
                          color: CupertinoColors.label.resolveFrom(context))),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MediaTile extends ConsumerWidget {
  const _MediaTile({
    required this.file,
    required this.bandId,
    required this.onDeleted,
  });

  final MediaFile file;
  final int bandId;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => _showDetail(context, ref),
      onLongPress: () => _showOptions(context, ref),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (file.isImage && file.thumbnailUrl != null)
              AuthThumbnail(url: file.thumbnailUrl!)
            else
              Container(
                color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
                child: Center(
                  child: Icon(
                    _iconForType(file.mediaType),
                    size: 32,
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
                ),
              ),
            if (!file.isImage)
              Positioned(
                bottom: 4,
                right: 4,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0x99000000),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    file.mediaType.toUpperCase(),
                    style: const TextStyle(
                      color: CupertinoColors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  IconData _iconForType(String type) => switch (type) {
        'video' => CupertinoIcons.videocam,
        'audio' => CupertinoIcons.music_note,
        'document' => CupertinoIcons.doc_text,
        _ => CupertinoIcons.doc,
      };

  void _showDetail(BuildContext context, WidgetRef ref) {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => Theme(
        data: ThemeData(brightness: MediaQuery.platformBrightnessOf(ctx)),
        child: Material(
          child: DraggableScrollableSheet(
            initialChildSize: 0.6,
            minChildSize: 0.4,
            maxChildSize: 0.95,
            expand: false,
            builder: (_, controller) => _MediaDetailSheet(
              file: file,
              bandId: bandId,
              onDeleted: onDeleted,
              scrollController: controller,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showOptions(BuildContext context, WidgetRef ref) async {
    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () async {
              Navigator.pop(context);
              _confirmDelete(context, ref);
            },
            child: const Text('Delete'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Delete file?'),
        content: Text('Delete "${file.title}"?'),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context, false),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('Delete'),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ref.read(mediaRepositoryProvider).deleteFile(bandId, file.id);
        onDeleted();
      } catch (e) {
        if (context.mounted) {
          showCupertinoDialog(
            context: context,
            builder: (_) => CupertinoAlertDialog(
              title: const Text('Error'),
              content: Text('Delete failed: $e'),
              actions: [
                CupertinoDialogAction(
                  child: const Text('OK'),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          );
        }
      }
    }
  }
}


class _MediaDetailSheet extends StatelessWidget {
  const _MediaDetailSheet({
    required this.file,
    required this.bandId,
    required this.onDeleted,
    required this.scrollController,
  });

  final MediaFile file;
  final int bandId;
  final VoidCallback onDeleted;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: CupertinoColors.secondaryLabel.resolveFrom(context).withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(file.title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        if (file.description != null && file.description!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(file.description!,
              style: TextStyle(
                  fontSize: 13, color: CupertinoColors.secondaryLabel.resolveFrom(context))),
        ],
        const SizedBox(height: 16),
        _DetailRow(label: 'Type', value: file.mediaType),
        _DetailRow(label: 'Size', value: file.formattedSize),
        if (file.folderPath != null)
          _DetailRow(label: 'Folder', value: file.folderPath!),
        if (file.uploaderName != null)
          _DetailRow(label: 'Uploaded by', value: file.uploaderName!),
        if (file.tags.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            children: file.tags
                .map((t) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(t.name,
                          style: const TextStyle(fontSize: 12)),
                    ))
                .toList(),
          ),
        ],
        const SizedBox(height: 24),
        CupertinoButton(
          onPressed: () => Navigator.pop(context),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(CupertinoIcons.xmark, size: 16),
              SizedBox(width: 6),
              Text('Close'),
            ],
          ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    color: CupertinoColors.secondaryLabel.resolveFrom(context))),
          ),
          Expanded(
              child: Text(value,
                  style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

class _UploadProgressBanner extends StatelessWidget {
  const _UploadProgressBanner({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: CupertinoColors.systemBlue.resolveFrom(context).withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Uploading…',
                    style: TextStyle(
                        fontSize: 12,
                        color: CupertinoColors.systemBlue.resolveFrom(context))),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: SizedBox(
                    height: 4,
                    child: Stack(
                      children: [
                        Container(color: CupertinoColors.systemBlue.resolveFrom(context).withValues(alpha: 0.2)),
                        FractionallySizedBox(
                          widthFactor: progress.clamp(0.0, 1.0),
                          child: Container(color: CupertinoColors.systemBlue.resolveFrom(context)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${(progress * 100).toInt()}%',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: CupertinoColors.systemRed.resolveFrom(context).withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(CupertinoIcons.exclamationmark_circle,
              color: CupertinoColors.systemRed.resolveFrom(context), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: TextStyle(
                    color: CupertinoColors.systemRed.resolveFrom(context), fontSize: 12)),
          ),
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: onDismiss,
            child: Icon(CupertinoIcons.xmark,
                size: 18, color: CupertinoColors.systemRed.resolveFrom(context)),
          ),
        ],
      ),
    );
  }
}
