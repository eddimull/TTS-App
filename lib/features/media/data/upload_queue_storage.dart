import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PersistedUploadTask {
  const PersistedUploadTask({
    required this.id,
    required this.filePath,
    required this.filename,
    required this.bandId,
    required this.eventId,
    this.uploadId,
    this.nextChunk = 0,
  });

  final String id;
  final String filePath;
  final String filename;
  final int bandId;
  final int? eventId;
  final String? uploadId;
  final int nextChunk;

  Map<String, dynamic> toJson() => {
        'id': id,
        'filePath': filePath,
        'filename': filename,
        'bandId': bandId,
        'eventId': eventId,
        'uploadId': uploadId,
        'nextChunk': nextChunk,
      };

  factory PersistedUploadTask.fromJson(Map<String, dynamic> json) =>
      PersistedUploadTask(
        id: json['id'] as String,
        filePath: json['filePath'] as String,
        filename: json['filename'] as String,
        bandId: (json['bandId'] as num).toInt(),
        eventId: (json['eventId'] as num?)?.toInt(),
        uploadId: json['uploadId'] as String?,
        nextChunk: (json['nextChunk'] as num?)?.toInt() ?? 0,
      );
}

class UploadQueueStorage {
  UploadQueueStorage(this._prefs);
  final SharedPreferences _prefs;
  static const String _key = 'media_upload_queue';

  List<PersistedUploadTask> read() {
    final raw = _prefs.getString(_key);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .cast<Map<String, dynamic>>()
          .map(PersistedUploadTask.fromJson)
          .toList();
    } catch (_) {
      _prefs.remove(_key);
      return [];
    }
  }

  void write(List<PersistedUploadTask> tasks) {
    _prefs.setString(_key, jsonEncode(tasks.map((t) => t.toJson()).toList()));
  }

  void clear() => _prefs.remove(_key);
}

final uploadQueueStorageProvider = Provider<UploadQueueStorage>((ref) {
  throw UnimplementedError(
    'uploadQueueStorageProvider must be overridden in main()',
  );
});
