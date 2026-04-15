import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tts_bandmate/core/providers/core_providers.dart';
import 'models/chart.dart';

class LibraryRepository {
  LibraryRepository(this._dio);

  final Dio _dio;

  /// Fetches the list of charts for [bandId].
  Future<List<Chart>> getCharts(int bandId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileBandCharts(bandId),
    );

    final data = response.data!;
    final rawList = data['charts'] as List<dynamic>;
    return rawList
        .cast<Map<String, dynamic>>()
        .map(Chart.fromJson)
        .toList();
  }

  /// Fetches the full detail for a single chart identified by [chartId].
  Future<Chart> getChart(int bandId, int chartId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileBandChart(bandId, chartId),
    );

    final data = response.data!;
    return Chart.fromJson(data['chart'] as Map<String, dynamic>);
  }

  /// Creates a new chart for [bandId].
  Future<Chart> createChart(
    int bandId, {
    required String title,
    String? composer,
    String? description,
    double? price,
    bool isPublic = false,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobileBandCharts(bandId),
      data: {
        'title': title,
        if (composer != null && composer.isNotEmpty) 'composer': composer,
        if (description != null && description.isNotEmpty)
          'description': description,
        if (price != null) 'price': price,
        'public': isPublic,
      },
    );

    final data = response.data!;
    return Chart.fromJson(data['chart'] as Map<String, dynamic>);
  }

  /// Deletes the chart identified by [chartId].
  Future<void> deleteChart(int bandId, int chartId) async {
    await _dio.delete(ApiEndpoints.mobileBandChart(bandId, chartId));
  }

  /// Uploads a file to the given chart.
  ///
  /// [file] comes from the file_picker package — its [PlatformFile.bytes]
  /// and [PlatformFile.name] are used to build the multipart request.
  /// [uploadTypeId]: 1 = Audio, 2 = Video, 3 = Sheet Music.
  /// [onProgress] fires with values 0.0–1.0 as bytes are sent.
  Future<ChartUpload> uploadChartFile(
    int bandId,
    int chartId, {
    required PlatformFile file,
    required String displayName,
    required int uploadTypeId,
    String? notes,
    void Function(double progress)? onProgress,
  }) async {
    final bytes = file.bytes;
    if (bytes == null) {
      throw StateError('File bytes are unavailable for "${file.name}".');
    }

    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: file.name),
      'display_name': displayName,
      'upload_type_id': uploadTypeId,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
    });

    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobileBandChartUploads(bandId, chartId),
      data: formData,
      onSendProgress: onProgress != null
          ? (sent, total) {
              if (total > 0) onProgress(sent / total);
            }
          : null,
    );

    final data = response.data!;
    return ChartUpload.fromJson(data['upload'] as Map<String, dynamic>);
  }

  /// Downloads a chart upload through the API and returns the raw bytes
  /// along with the MIME type and filename from the response headers.
  Future<({Uint8List bytes, String mimeType, String filename})>
      downloadChartUpload(int bandId, int chartId, int uploadId) async {
    final response = await _dio.get<List<int>>(
      ApiEndpoints.mobileBandChartUploadDownload(bandId, chartId, uploadId),
      options: Options(responseType: ResponseType.bytes),
    );
    final contentType =
        response.headers.value('content-type') ?? 'application/octet-stream';
    final mimeType = contentType.split(';').first.trim();
    final disposition = response.headers.value('content-disposition') ?? '';
    final filenameMatch =
        RegExp(r'filename="?([^"]+)"?').firstMatch(disposition);
    var filename = filenameMatch?.group(1) ?? 'download';
    // If the filename has no extension, append one based on the MIME type so
    // the OS can open it with the correct app (e.g. PDF reader).
    if (!filename.contains('.')) {
      final ext = _extensionFromMimeType(mimeType);
      if (ext.isNotEmpty) filename = '$filename.$ext';
    }
    return (
      bytes: Uint8List.fromList(response.data!),
      mimeType: mimeType,
      filename: filename,
    );
  }

  /// Deletes a single upload from a chart.
  Future<void> deleteChartUpload(
    int bandId,
    int chartId,
    int uploadId,
  ) async {
    await _dio.delete(
      ApiEndpoints.mobileBandChartUpload(bandId, chartId, uploadId),
    );
  }

  String _extensionFromMimeType(String mimeType) => switch (mimeType) {
        'application/pdf' => 'pdf',
        'audio/mpeg' => 'mp3',
        'audio/wav' => 'wav',
        'audio/mp4' => 'm4a',
        'video/mp4' => 'mp4',
        'video/quicktime' => 'mov',
        _ => '',
      };
}

final libraryRepositoryProvider = Provider<LibraryRepository>((ref) {
  return LibraryRepository(ref.watch(apiClientProvider).dio);
});
