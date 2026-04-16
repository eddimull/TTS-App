import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../../../shared/providers/selected_band_provider.dart';
import '../../../shared/widgets/auth_thumbnail.dart';
import '../data/models/media_file.dart';
import '../providers/media_provider.dart';
import 'media_viewer.dart';

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
    final bandId = ref.read(selectedBandProvider).value ?? 0;
    return MediaListParams(
      bandId: bandId,
      folderPath: _folderPath,
      mediaType: _mediaTypeFilter,
      search: _search.isEmpty ? null : _search,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bandId = ref.watch(selectedBandProvider).value ?? 0;
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
          if (uploadState.isUploading)
            _UploadProgressBanner(progress: uploadState.progress),
          if (uploadState.error != null)
            _ErrorBanner(
              message: uploadState.error!,
              onDismiss: () => ref.read(uploadProvider.notifier).reset(),
            ),
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
          _filterAction(context, null, 'All'),
          _filterAction(context, 'image', 'Images'),
          _filterAction(context, 'video', 'Videos'),
          _filterAction(context, 'audio', 'Audio'),
          _filterAction(context, 'document', 'Documents'),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  CupertinoActionSheetAction _filterAction(
      BuildContext context, String? type, String label) {
    return CupertinoActionSheetAction(
      onPressed: () {
        Navigator.pop(context);
        setState(() => _mediaTypeFilter = type);
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_mediaTypeFilter == type)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Icon(CupertinoIcons.checkmark, size: 16),
            ),
          Text(label),
        ],
      ),
    );
  }

  Widget _buildBody(MediaListState state, int bandId) {
    if (state.isLoading) {
      return const Center(child: CupertinoActivityIndicator());
    }

    if (state.error != null && state.files.isEmpty && state.folders.isEmpty) {
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
          SliverPadding(
            padding: const EdgeInsets.all(8),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate(
                (context, i) => _buildGridItem(context, i, state, bandId),
                childCount: _gridItemCount(state),
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
          if (state.folders.isEmpty && state.files.isEmpty)
            SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(CupertinoIcons.photo_on_rectangle,
                          size: 48,
                          color: CupertinoColors.secondaryLabel.resolveFrom(context)),
                      const SizedBox(height: 12),
                      const Text('No media yet.'),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  int _gridItemCount(MediaListState state) =>
      1 + state.folders.length + state.files.length;

  Widget? _buildGridItem(
      BuildContext context, int i, MediaListState state, int bandId) {
    if (i == 0) {
      return _NewFolderTile(
        onTap: () => _showNewFolderDialog(context, bandId),
      );
    }
    final folderIndex = i - 1;
    if (folderIndex < state.folders.length) {
      return _FolderTile(
        name: state.folders[folderIndex].split('/').last,
        onTap: () => setState(() => _folderPath = state.folders[folderIndex]),
      );
    }
    final fileIndex = folderIndex - state.folders.length;
    if (fileIndex < state.files.length) {
      return _MediaTile(
        file: state.files[fileIndex],
        bandId: bandId,
        onDeleted: () => ref
            .read(mediaListProvider(_params).notifier)
            .removeFile(state.files[fileIndex].id),
      );
    }
    return null;
  }

  Future<void> _showNewFolderDialog(BuildContext context, int bandId) async {
    await showCupertinoDialog(
      context: context,
      builder: (_) => _NewFolderDialog(
        onConfirm: (name) async {
          final path = await ref
              .read(mediaListProvider(_params).notifier)
              .createFolder(bandId, name);
          if (path != null && mounted) {
            setState(() => _folderPath = path);
          }
          return path != null;
        },
      ),
    );
  }

  Future<void> _showUploadSheet(BuildContext context, int bandId) async {
    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: _folderPath != null
            ? Text('Uploading to 📁 ${_folderPath!.split('/').last}')
            : const Text('Upload Media'),
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
      BuildContext context, int bandId, ImageSource source) async {
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

// ── New Folder tile ────────────────────────────────────────────────────────────

class _NewFolderTile extends StatelessWidget {
  const _NewFolderTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          color: CupertinoColors.systemBlue.resolveFrom(context).withValues(alpha: 0.12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(CupertinoIcons.folder_badge_plus,
                  size: 28,
                  color: CupertinoColors.systemBlue.resolveFrom(context)),
              const SizedBox(height: 4),
              Text(
                'New Folder',
                style: TextStyle(
                  fontSize: 11,
                  color: CupertinoColors.systemBlue.resolveFrom(context),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Folder tile ────────────────────────────────────────────────────────────────

class _FolderTile extends StatelessWidget {
  const _FolderTile({required this.name, required this.onTap});
  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          color: const Color(0xFFFEF3C7),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(CupertinoIcons.folder_fill, size: 32, color: Color(0xFFF59E0B)),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  name,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF92400E),
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── New Folder dialog ──────────────────────────────────────────────────────────

class _NewFolderDialog extends StatefulWidget {
  const _NewFolderDialog({required this.onConfirm});
  final Future<bool> Function(String name) onConfirm;

  @override
  State<_NewFolderDialog> createState() => _NewFolderDialogState();
}

class _NewFolderDialogState extends State<_NewFolderDialog> {
  final _controller = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Folder name cannot be empty');
      return;
    }
    setState(() { _loading = true; _error = null; });
    final ok = await widget.onConfirm(name);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      setState(() { _loading = false; _error = 'Could not create folder. Try a different name.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoAlertDialog(
      title: const Text('New Folder'),
      content: Column(
        children: [
          const SizedBox(height: 8),
          CupertinoTextField(
            controller: _controller,
            placeholder: 'Folder name',
            autofocus: true,
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(_error!,
                style: const TextStyle(
                    color: CupertinoColors.systemRed, fontSize: 12)),
          ],
        ],
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const CupertinoActivityIndicator()
              : const Text('Create'),
        ),
      ],
    );
  }
}

// ── Media tile ─────────────────────────────────────────────────────────────────

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
      onTap: () => Navigator.push(
        context,
        CupertinoPageRoute(
          builder: (_) => MediaViewer(file: file, bandId: bandId),
        ),
      ),
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
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
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

// ── Upload progress banner ─────────────────────────────────────────────────────

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
                        Container(
                            color: CupertinoColors.systemBlue
                                .resolveFrom(context)
                                .withValues(alpha: 0.2)),
                        FractionallySizedBox(
                          widthFactor: progress.clamp(0.0, 1.0),
                          child: Container(
                              color: CupertinoColors.systemBlue.resolveFrom(context)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text('${(progress * 100).toInt()}%',
              style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

// ── Error banner ───────────────────────────────────────────────────────────────

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
                    color: CupertinoColors.systemRed.resolveFrom(context),
                    fontSize: 12)),
          ),
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: onDismiss,
            child: Icon(CupertinoIcons.xmark,
                size: 18,
                color: CupertinoColors.systemRed.resolveFrom(context)),
          ),
        ],
      ),
    );
  }
}
