import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/core_providers.dart';
import '../data/media_repository.dart';
import '../data/models/media_file.dart';

// ── Repository provider ────────────────────────────────────────────────────────

final mediaRepositoryProvider = Provider<MediaRepository>((ref) {
  return MediaRepository(ref.read(apiClientProvider).dio);
});

// ── Media list ─────────────────────────────────────────────────────────────────

class MediaListParams {
  const MediaListParams({
    required this.bandId,
    this.folderPath,
    this.mediaType,
    this.search,
  });

  final int bandId;
  final String? folderPath;
  final String? mediaType;
  final String? search;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaListParams &&
          bandId == other.bandId &&
          folderPath == other.folderPath &&
          mediaType == other.mediaType &&
          search == other.search;

  @override
  int get hashCode => Object.hash(bandId, folderPath, mediaType, search);
}

class MediaListState {
  const MediaListState({
    this.files = const [],
    this.folders = const [],
    this.currentPage = 0,
    this.lastPage = 1,
    this.total = 0,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
  });

  final List<MediaFile> files;
  final List<String> folders;
  final int currentPage;
  final int lastPage;
  final int total;
  final bool isLoading;
  final bool isLoadingMore;
  final String? error;

  bool get hasMore => currentPage < lastPage;

  MediaListState copyWith({
    List<MediaFile>? files,
    List<String>? folders,
    int? currentPage,
    int? lastPage,
    int? total,
    bool? isLoading,
    bool? isLoadingMore,
    String? Function()? error,
  }) =>
      MediaListState(
        files: files ?? this.files,
        folders: folders ?? this.folders,
        currentPage: currentPage ?? this.currentPage,
        lastPage: lastPage ?? this.lastPage,
        total: total ?? this.total,
        isLoading: isLoading ?? this.isLoading,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        error: error != null ? error() : this.error,
      );
}

class MediaListNotifier extends Notifier<MediaListState> {
  MediaListNotifier(this._arg);
  final MediaListParams _arg;

  @override
  MediaListState build() {
    Future.microtask(load);
    return const MediaListState(isLoading: true);
  }

  MediaRepository get _repo => ref.read(mediaRepositoryProvider);

  Future<void> load() async {
    state = state.copyWith(isLoading: true, error: () => null);
    try {
      final page = await _repo.getMedia(
        _arg.bandId,
        folderPath: _arg.folderPath,
        mediaType: _arg.mediaType,
        search: _arg.search,
      );
      state = state.copyWith(
        files: page.files,
        folders: page.folders,
        currentPage: page.currentPage,
        lastPage: page.lastPage,
        total: page.total,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: () => e.toString(),
      );
    }
  }

  Future<void> loadMore() async {
    if (!state.hasMore || state.isLoadingMore) return;
    state = state.copyWith(isLoadingMore: true);
    try {
      final page = await _repo.getMedia(
        _arg.bandId,
        page: state.currentPage + 1,
        folderPath: _arg.folderPath,
        mediaType: _arg.mediaType,
        search: _arg.search,
      );
      state = state.copyWith(
        files: [...state.files, ...page.files],
        currentPage: page.currentPage,
        lastPage: page.lastPage,
        isLoadingMore: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoadingMore: false,
        error: () => e.toString(),
      );
    }
  }

  void removeFile(int mediaId) {
    state = state.copyWith(
      files: state.files.where((f) => f.id != mediaId).toList(),
      total: state.total - 1,
    );
  }

  Future<String?> createFolder(int bandId, String name) async {
    try {
      final folderPath = await _repo.createFolder(bandId, name);
      await load();
      return folderPath;
    } catch (e) {
      return null;
    }
  }
}

final mediaListProvider = NotifierProvider.family<MediaListNotifier,
    MediaListState, MediaListParams>((arg) => MediaListNotifier(arg));

// ── Upload state ───────────────────────────────────────────────────────────────

class UploadState {
  const UploadState({
    this.isUploading = false,
    this.progress = 0,
    this.error,
    this.lastUploaded,
  });

  final bool isUploading;
  final double progress; // 0.0 – 1.0
  final String? error;
  final MediaFile? lastUploaded;

  UploadState copyWith({
    bool? isUploading,
    double? progress,
    String? Function()? error,
    MediaFile? Function()? lastUploaded,
  }) =>
      UploadState(
        isUploading: isUploading ?? this.isUploading,
        progress: progress ?? this.progress,
        error: error != null ? error() : this.error,
        lastUploaded:
            lastUploaded != null ? lastUploaded() : this.lastUploaded,
      );
}

class UploadNotifier extends Notifier<UploadState> {
  @override
  UploadState build() => const UploadState();

  MediaRepository get _repo => ref.read(mediaRepositoryProvider);

  Future<void> upload(
    int bandId,
    File file, {
    String? folderPath,
    int? eventId,
  }) async {
    state = const UploadState(isUploading: true, progress: 0);
    try {
      final media = await _repo.uploadFile(
        bandId,
        file,
        folderPath: folderPath,
        eventId: eventId,
        onProgress: (p) => state = state.copyWith(progress: p),
      );
      state = UploadState(lastUploaded: media);
    } catch (e) {
      state = UploadState(error: e.toString());
    }
  }

  void reset() => state = const UploadState();
}

final uploadProvider =
    NotifierProvider<UploadNotifier, UploadState>(
  UploadNotifier.new,
);
