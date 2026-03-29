import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../../../shared/providers/selected_band_provider.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../core/providers/core_providers.dart';
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

    return AppScaffold(
      child: Scaffold(
      appBar: AppBar(
        title: _folderPath != null
            ? Text(_folderPath!.split('/').last)
            : const Text('Media'),
        leading: _folderPath != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _folderPath = null),
              )
            : null,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            onSelected: (v) => setState(
              () => _mediaTypeFilter = _mediaTypeFilter == v ? null : v,
            ),
            itemBuilder: (_) => [
              _filterItem('All', null),
              _filterItem('Images', 'image'),
              _filterItem('Videos', 'video'),
              _filterItem('Audio', 'audio'),
              _filterItem('Documents', 'document'),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search…',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _search.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _search = '');
                        },
                      )
                    : null,
                isDense: true,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showUploadSheet(context, bandId),
        child: const Icon(Icons.upload),
      ),
      body: Column(
        children: [
          // Upload progress banner.
          if (uploadState.isUploading)
            _UploadProgressBanner(progress: uploadState.progress),
          if (uploadState.error != null)
            _ErrorBanner(
              message: uploadState.error!,
              onDismiss: () => ref.read(uploadProvider.notifier).reset(),
            ),
          // Content.
          Expanded(child: _buildBody(listState, bandId)),
        ],
      ),
    ));
  }

  Widget _buildBody(MediaListState state, int bandId) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null && state.files.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(state.error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () =>
                  ref.read(mediaListProvider(_params).notifier).load(),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (state.folders.isEmpty && state.files.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.perm_media_outlined, size: 48),
            SizedBox(height: 12),
            Text('No media yet.'),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(mediaListProvider(_params).notifier).load(),
      child: NotificationListener<ScrollNotification>(
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
          // Subfolders.
          if (state.folders.isNotEmpty)
            SliverToBoxAdapter(
              child: _FolderRow(
                folders: state.folders,
                onTap: (f) => setState(() => _folderPath = f),
              ),
            ),
          // File grid.
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
          // Loading more indicator.
          if (state.isLoadingMore)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    ));
  }

  PopupMenuItem<String> _filterItem(String label, String? value) =>
      PopupMenuItem(
        value: value ?? '',
        child: Row(
          children: [
            if (_mediaTypeFilter == value)
              const Icon(Icons.check, size: 16)
            else
              const SizedBox(width: 16),
            const SizedBox(width: 8),
            Text(label),
          ],
        ),
      );

  Future<void> _showUploadSheet(BuildContext context, int bandId) async {
    await showModalBottomSheet(
      context: context,
      builder: (_) => _UploadSheet(
        bandId: bandId,
        currentFolderPath: _folderPath,
      ),
    );
  }
}

// ── Folder row ─────────────────────────────────────────────────────────────────

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
          return ActionChip(
            avatar: const Icon(Icons.folder_outlined, size: 16),
            label: Text(name),
            onPressed: () => onTap(folders[i]),
          );
        },
      ),
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
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () => _showDetail(context, ref),
      onLongPress: () => _showOptions(context, ref),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Thumbnail / icon.
            if (file.isImage && file.thumbnailUrl != null)
              _ThumbnailImage(url: file.thumbnailUrl!, bandId: bandId, ref: ref)
            else
              Container(
                color: theme.colorScheme.surfaceContainerHighest,
                child: Center(
                  child: Icon(
                    _iconForType(file.mediaType),
                    size: 32,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            // Type badge for non-images.
            if (!file.isImage)
              Positioned(
                bottom: 4,
                right: 4,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    file.mediaType.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
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
        'video' => Icons.videocam_outlined,
        'audio' => Icons.audiotrack_outlined,
        'document' => Icons.description_outlined,
        _ => Icons.insert_drive_file_outlined,
      };

  void _showDetail(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _MediaDetailSheet(
        file: file,
        bandId: bandId,
        onDeleted: onDeleted,
      ),
    );
  }

  Future<void> _showOptions(BuildContext context, WidgetRef ref) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete',
                  style: TextStyle(color: Colors.red)),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );

    if (action == 'delete' && context.mounted) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Delete file?'),
          content: Text('Delete "${file.title}"?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style:
                  FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        try {
          await ref
              .read(mediaRepositoryProvider)
              .deleteFile(bandId, file.id);
          onDeleted();
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Delete failed: $e')),
            );
          }
        }
      }
    }
  }
}

// ── Thumbnail with auth header ─────────────────────────────────────────────────

class _ThumbnailImage extends StatefulWidget {
  const _ThumbnailImage(
      {required this.url, required this.bandId, required this.ref});

  final String url;
  final int bandId;
  final WidgetRef ref;

  @override
  State<_ThumbnailImage> createState() => _ThumbnailImageState();
}

class _ThumbnailImageState extends State<_ThumbnailImage> {
  String? _token;

  @override
  void initState() {
    super.initState();
    widget.ref.read(secureStorageProvider).readToken().then((t) {
      if (mounted) setState(() => _token = t);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_token == null) {
      return const SizedBox.shrink();
    }
    return CachedNetworkImage(
      imageUrl: widget.url,
      httpHeaders: {'Authorization': 'Bearer $_token'},
      fit: BoxFit.cover,
      errorWidget: (_, __, ___) => const Icon(Icons.broken_image_outlined),
    );
  }
}

// ── Media detail sheet ─────────────────────────────────────────────────────────

class _MediaDetailSheet extends StatelessWidget {
  const _MediaDetailSheet({
    required this.file,
    required this.bandId,
    required this.onDeleted,
  });

  final MediaFile file;
  final int bandId;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.all(16),
        children: [
          // Handle.
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Title.
          Text(file.title, style: theme.textTheme.titleMedium),
          if (file.description != null && file.description!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(file.description!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                )),
          ],
          const SizedBox(height: 16),
          // Meta.
          _DetailRow(label: 'Type', value: file.mediaType),
          _DetailRow(label: 'Size', value: file.formattedSize),
          if (file.folderPath != null)
            _DetailRow(label: 'Folder', value: file.folderPath!),
          if (file.uploaderName != null)
            _DetailRow(label: 'Uploaded by', value: file.uploaderName!),
          // Tags.
          if (file.tags.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              children: file.tags
                  .map((t) => Chip(
                        label: Text(t.name,
                            style: const TextStyle(fontSize: 12)),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                      ))
                  .toList(),
            ),
          ],
          const SizedBox(height: 24),
          // Actions.
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
            label: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                )),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}

// ── Upload sheet ───────────────────────────────────────────────────────────────

class _UploadSheet extends ConsumerWidget {
  const _UploadSheet({required this.bandId, this.currentFolderPath});

  final int bandId;
  final String? currentFolderPath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Upload Media',
                style: Theme.of(context).textTheme.titleMedium),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Photo / Video from Library'),
            onTap: () async {
              Navigator.pop(context);
              await _pickAndUpload(
                context,
                ref,
                ImageSource.gallery,
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined),
            title: const Text('Take Photo'),
            onTap: () async {
              Navigator.pop(context);
              await _pickAndUpload(context, ref, ImageSource.camera);
            },
          ),
          ListTile(
            leading: const Icon(Icons.attach_file_outlined),
            title: const Text('Document / Audio file'),
            onTap: () async {
              Navigator.pop(context);
              await _pickDocument(context, ref);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndUpload(
    BuildContext context,
    WidgetRef ref,
    ImageSource source,
  ) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 85);
    if (picked == null) return;

    await ref.read(uploadProvider.notifier).upload(
          bandId,
          File(picked.path),
          folderPath: currentFolderPath,
        );

    if (context.mounted) {
      final uploadState = ref.read(uploadProvider);
      if (uploadState.error == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Upload complete.')),
        );
      }
    }
  }

  Future<void> _pickDocument(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.any,
    );
    if (result == null || result.files.single.path == null) return;

    await ref.read(uploadProvider.notifier).upload(
          bandId,
          File(result.files.single.path!),
          folderPath: currentFolderPath,
        );

    if (context.mounted) {
      final uploadState = ref.read(uploadProvider);
      if (uploadState.error == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Upload complete.')),
        );
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
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.primaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Uploading…',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    )),
                const SizedBox(height: 4),
                LinearProgressIndicator(value: progress),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${(progress * 100).toInt()}%',
            style: theme.textTheme.labelMedium,
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
      color: Colors.red.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: const TextStyle(color: Colors.red, fontSize: 12)),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: onDismiss,
            color: Colors.red,
          ),
        ],
      ),
    );
  }
}
