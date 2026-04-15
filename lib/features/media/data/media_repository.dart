import 'dart:io';
import 'package:dio/dio.dart';
import '../../../core/config/app_config.dart';
import 'models/media_file.dart';

class MediaPage {
  const MediaPage({
    required this.files,
    required this.folders,
    required this.currentPage,
    required this.lastPage,
    required this.total,
  });

  final List<MediaFile> files;
  final List<String> folders;
  final int currentPage;
  final int lastPage;
  final int total;

  bool get hasMore => currentPage < lastPage;
}

class MediaRepository {
  MediaRepository(this._dio);

  final Dio _dio;

  // ── Browse ─────────────────────────────────────────────────────────────────

  Future<MediaPage> getMedia(
    int bandId, {
    int page = 1,
    String? folderPath,
    String? mediaType,
    String? search,
  }) async {
    final resp = await _dio.get('/api/mobile/bands/$bandId/media', queryParameters: {
      'page': page,
      if (folderPath != null) 'folder_path': folderPath,
      if (mediaType != null) 'media_type': mediaType,
      if (search != null && search.isNotEmpty) 'search': search,
    });

    final data = resp.data as Map<String, dynamic>;
    final meta = data['meta'] as Map<String, dynamic>;

    return MediaPage(
      files: (data['data'] as List<dynamic>)
          .map((e) => MediaFile.fromJson(e as Map<String, dynamic>))
          .toList(),
      folders: (data['folders'] as List<dynamic>? ?? [])
          .map((f) => f.toString())
          .toList(),
      currentPage: meta['current_page'] as int,
      lastPage: meta['last_page'] as int,
      total: meta['total'] as int,
    );
  }

  Future<MediaFile> getFile(int bandId, int mediaId) async {
    final resp = await _dio.get('/api/mobile/bands/$bandId/media/$mediaId');
    return MediaFile.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<void> deleteFile(int bandId, int mediaId) async {
    await _dio.delete('/api/mobile/bands/$bandId/media/$mediaId');
  }

  /// Returns the full URL for inline serving. The token must be passed as
  /// an Authorization header by the caller (e.g. AuthThumbnail).
  String serveUrl(int bandId, int mediaId) =>
      '${AppConfig.baseUrl}/media/$mediaId/serve';

  // ── Folder management ──────────────────────────────────────────────────────

  /// Validates a folder name on the server and returns the canonical
  /// folder_path string to use when uploading files into that folder.
  Future<String> createFolder(int bandId, String name) async {
    final resp = await _dio.post(
      '/api/mobile/bands/$bandId/media/folders',
      data: {'name': name},
    );
    return resp.data['folder_path'] as String;
  }

  // ── Chunked upload ─────────────────────────────────────────────────────────

  static const int chunkSize = 2 * 1024 * 1024; // 2 MB

  Future<MediaFile> uploadFile(
    int bandId,
    File file, {
    String? folderPath,
    int? eventId,
    void Function(double progress)? onProgress,
  }) async {
    final filename = file.path.split('/').last;
    final filesize = await file.length();
    final mimeType = _mimeTypeFromPath(filename);
    final totalChunks = (filesize / chunkSize).ceil().clamp(1, 999999);

    // 1. Initiate
    final initiateResp = await _dio.post(
      '/api/mobile/bands/$bandId/media/upload/initiate',
      data: {
        'filename': filename,
        'filesize': filesize,
        'mime_type': mimeType,
        'total_chunks': totalChunks,
        if (folderPath != null) 'folder_path': folderPath,
        if (eventId != null) 'event_id': eventId,
      },
    );
    final uploadId = initiateResp.data['upload_id'] as String;

    // 2. Upload chunks
    final raf = await file.open();
    try {
      for (int i = 0; i < totalChunks; i++) {
        final start = i * chunkSize;
        final end =
            (start + chunkSize < filesize) ? start + chunkSize : filesize;
        final length = end - start;

        await raf.setPosition(start);
        final bytes = await raf.read(length);

        final formData = FormData.fromMap({
          'chunk': MultipartFile.fromBytes(bytes, filename: 'chunk_$i'),
          'chunk_index': i,
        });

        await _dio.post(
          '/api/mobile/bands/$bandId/media/upload/$uploadId/chunk',
          data: formData,
        );

        onProgress?.call((i + 1) / totalChunks);
      }
    } finally {
      await raf.close();
    }

    // 3. Complete
    final completeResp = await _dio.post(
      '/api/mobile/bands/$bandId/media/upload/$uploadId/complete',
    );

    return MediaFile.fromJson(
        completeResp.data['media'] as Map<String, dynamic>);
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _mimeTypeFromPath(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'heic' => 'image/heic',
      'mp4' => 'video/mp4',
      'mov' => 'video/quicktime',
      'mp3' => 'audio/mpeg',
      'wav' => 'audio/wav',
      'm4a' => 'audio/mp4',
      'pdf' => 'application/pdf',
      'doc' => 'application/msword',
      'docx' =>
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      _ => 'application/octet-stream',
    };
  }
}
