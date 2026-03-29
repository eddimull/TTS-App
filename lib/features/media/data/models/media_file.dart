class MediaTag {
  const MediaTag({required this.id, required this.name, this.color});

  final int id;
  final String name;
  final String? color;

  factory MediaTag.fromJson(Map<String, dynamic> json) => MediaTag(
        id: json['id'] as int,
        name: json['name'] as String,
        color: json['color'] as String?,
      );
}

class MediaFile {
  const MediaFile({
    required this.id,
    required this.filename,
    required this.title,
    this.description,
    required this.mediaType,
    required this.mimeType,
    required this.fileSize,
    required this.formattedSize,
    this.folderPath,
    this.thumbnailUrl,
    this.createdAt,
    this.tags = const [],
    this.uploaderName,
  });

  final int id;
  final String filename;
  final String title;
  final String? description;
  final String mediaType; // 'image' | 'video' | 'audio' | 'document'
  final String mimeType;
  final int fileSize;
  final String formattedSize;
  final String? folderPath;
  final String? thumbnailUrl;
  final String? createdAt;
  final List<MediaTag> tags;
  final String? uploaderName;

  bool get isImage => mediaType == 'image';
  bool get isVideo => mediaType == 'video';
  bool get isAudio => mediaType == 'audio';
  bool get isDocument => mediaType == 'document';

  factory MediaFile.fromJson(Map<String, dynamic> json) => MediaFile(
        id: json['id'] as int,
        filename: json['filename'] as String,
        title: json['title'] as String? ?? json['filename'] as String,
        description: json['description'] as String?,
        mediaType: json['media_type'] as String? ?? 'document',
        mimeType: json['mime_type'] as String? ?? 'application/octet-stream',
        fileSize: json['file_size'] as int? ?? 0,
        formattedSize: json['formatted_size'] as String? ?? '',
        folderPath: json['folder_path'] as String?,
        thumbnailUrl: json['thumbnail_url'] as String?,
        createdAt: json['created_at'] as String?,
        tags: (json['tags'] as List<dynamic>? ?? [])
            .map((t) => MediaTag.fromJson(t as Map<String, dynamic>))
            .toList(),
        uploaderName:
            (json['uploader'] as Map<String, dynamic>?)?['name'] as String?,
      );
}
