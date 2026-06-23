import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/media_repository.dart';
import '../data/upload_queue_storage.dart';
import 'media_provider.dart';

enum UploadStatus { queued, uploading, paused, done, failed }

class UploadTask {
  const UploadTask({
    required this.id,
    required this.file,
    required this.filename,
    required this.bandId,
    required this.eventId,
    this.status = UploadStatus.queued,
    this.progress = 0,
    this.uploadId,
    this.error,
  });

  final String id;
  final File file;
  final String filename;
  final int bandId;
  final int? eventId;
  final UploadStatus status;
  final double progress;
  final String? uploadId;
  final String? error;

  UploadTask copyWith({
    UploadStatus? status,
    double? progress,
    String? uploadId,
    String? Function()? error,
  }) =>
      UploadTask(
        id: id,
        file: file,
        filename: filename,
        bandId: bandId,
        eventId: eventId,
        status: status ?? this.status,
        progress: progress ?? this.progress,
        uploadId: uploadId ?? this.uploadId,
        error: error != null ? error() : this.error,
      );
}

class UploadQueueNotifier extends Notifier<List<UploadTask>> {
  final Map<String, CancelToken> _tokens = {};
  int _counter = 0;
  bool _disposed = false;

  @override
  List<UploadTask> build() {
    ref.onDispose(() => _disposed = true);
    final persisted = ref.read(uploadQueueStorageProvider).read();
    // Seed the counter past any restored ids ('task-<counter>-<hash>') so a
    // re-enqueued file cannot collide with a restored task from a prior session.
    for (final p in persisted) {
      final parts = p.id.split('-');
      if (parts.length >= 2 && parts.first == 'task') {
        final n = int.tryParse(parts[1]);
        if (n != null && n >= _counter) _counter = n + 1;
      }
    }
    return persisted
        .where((p) => File(p.filePath).existsSync())
        .map((p) => UploadTask(
              id: p.id,
              file: File(p.filePath),
              filename: p.filename,
              bandId: p.bandId,
              eventId: p.eventId,
              status: UploadStatus.paused,
              uploadId: p.uploadId,
            ))
        .toList();
  }

  MediaRepository get _repo => ref.read(mediaRepositoryProvider);

  void _persist() {
    if (_disposed) return;
    ref.read(uploadQueueStorageProvider).write(
          state
              .where((t) =>
                  t.status != UploadStatus.done &&
                  t.status != UploadStatus.failed)
              .map((t) => PersistedUploadTask(
                    id: t.id,
                    filePath: t.file.path,
                    filename: t.filename,
                    bandId: t.bandId,
                    eventId: t.eventId,
                    uploadId: t.uploadId,
                  ))
              .toList(),
        );
  }

  void _set(String id, UploadTask Function(UploadTask) f) {
    // An in-flight upload's async callbacks may fire after the notifier is
    // disposed (e.g. user navigated away). Assigning to `state` then throws.
    if (_disposed) return;
    state = [for (final t in state) if (t.id == id) f(t) else t];
  }

  Future<void> enqueue({
    required int bandId,
    required int? eventId,
    required File file,
  }) async {
    final id = 'task-${_counter++}-${file.path.hashCode}';
    final task = UploadTask(
      id: id,
      file: file,
      filename: file.path.split('/').last,
      bandId: bandId,
      eventId: eventId,
    );
    state = [...state, task];
    _persist();
    // Fire-and-forget: uploads run in the background and must outlive the
    // screen that enqueued them, so we do NOT await the run here. enqueue
    // resolves as soon as the task is queued.
    unawaited(_run(id));
  }

  Future<void> retry(String id) async {
    _set(id, (t) => t.copyWith(status: UploadStatus.queued, error: () => null));
    // Fire-and-forget (see enqueue): don't block the caller on the upload.
    unawaited(_run(id));
  }

  void cancel(String id) {
    _tokens[id]?.cancel('cancelled');
    _set(
        id,
        (t) => t.status == UploadStatus.done
            ? t
            : t.copyWith(status: UploadStatus.failed, error: () => 'Cancelled'));
    _persist();
  }

  void clearFinished() {
    state = state
        .where((t) =>
            t.status != UploadStatus.done && t.status != UploadStatus.failed)
        .toList();
    _persist();
  }

  Future<void> _run(String id) async {
    final current = state.firstWhere((t) => t.id == id);
    final token = CancelToken();
    _tokens[id] = token;
    _set(id, (t) => t.copyWith(status: UploadStatus.uploading, progress: 0));

    try {
      await _repo.uploadFile(
        current.bandId,
        current.file,
        eventId: current.eventId,
        existingUploadId: current.uploadId,
        cancelToken: token,
        onInitiated: (uploadId) =>
            _set(id, (t) => t.copyWith(uploadId: uploadId)),
        onProgress: (p) => _set(id, (t) => t.copyWith(progress: p)),
      );
      _set(id, (t) => t.copyWith(status: UploadStatus.done, progress: 1));
    } catch (e) {
      _set(id,
          (t) => t.copyWith(status: UploadStatus.failed, error: () => e.toString()));
    } finally {
      _tokens.remove(id);
      _persist();
    }
  }
}

final uploadQueueProvider =
    NotifierProvider<UploadQueueNotifier, List<UploadTask>>(
  UploadQueueNotifier.new,
);
