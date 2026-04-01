class ChartUpload {
  final int id;
  final int chartId;
  final String displayName;
  final String notes;
  final String url;
  final String fileType;
  final String typeName;

  const ChartUpload({
    required this.id,
    required this.chartId,
    required this.displayName,
    required this.notes,
    required this.url,
    required this.fileType,
    required this.typeName,
  });

  factory ChartUpload.fromJson(Map<String, dynamic> json) => ChartUpload(
        id: json['id'] as int,
        chartId: json['chart_id'] as int,
        displayName: json['display_name'] as String? ?? '',
        notes: json['notes'] as String? ?? '',
        url: json['url'] as String? ?? '',
        fileType: json['file_type'] as String? ?? '',
        typeName: json['type_name'] as String? ?? '',
      );
}

class Chart {
  final int id;
  final int bandId;
  final String title;
  final String composer;
  final String description;
  final double price;
  final bool isPublic;
  final int uploadsCount;
  final List<ChartUpload> uploads;

  const Chart({
    required this.id,
    required this.bandId,
    required this.title,
    required this.composer,
    required this.description,
    required this.price,
    required this.isPublic,
    required this.uploadsCount,
    required this.uploads,
  });

  factory Chart.fromJson(Map<String, dynamic> json) => Chart(
        id: json['id'] as int,
        bandId: json['band_id'] as int,
        title: json['title'] as String? ?? '',
        composer: json['composer'] as String? ?? '',
        description: json['description'] as String? ?? '',
        price: (json['price'] as num?)?.toDouble() ?? 0.0,
        isPublic: json['public'] as bool? ?? false,
        uploadsCount: json['uploads_count'] as int? ?? 0,
        uploads: (json['uploads'] as List<dynamic>?)
                ?.map((u) => ChartUpload.fromJson(u as Map<String, dynamic>))
                .toList() ??
            [],
      );
}
