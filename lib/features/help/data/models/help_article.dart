class HelpArticle {
  const HelpArticle({
    required this.slug,
    required this.title,
    required this.category,
    required this.platforms,
    required this.order,
    this.markdown,
    this.updatedAt,
  });

  final String slug;
  final String title;
  final String category;
  final List<String> platforms;
  final int order;
  final String? markdown;
  final DateTime? updatedAt;

  factory HelpArticle.fromJson(Map<String, dynamic> json) => HelpArticle(
        slug: json['slug'] as String? ?? '',
        title: json['title'] as String? ?? '',
        category: json['category'] as String? ?? '',
        platforms: (json['platforms'] as List?)?.cast<String>() ?? const [],
        order: (json['order'] as num?)?.toInt() ?? 0,
        markdown: json['markdown'] as String?,
        updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? ''),
      );
}

class HelpIndex {
  const HelpIndex({required this.articles, required this.categoryLabels});

  final List<HelpArticle> articles;
  final Map<String, String> categoryLabels;

  factory HelpIndex.fromJson(Map<String, dynamic> json) => HelpIndex(
        articles: (json['articles'] as List? ?? const [])
            .map((e) => HelpArticle.fromJson(e as Map<String, dynamic>))
            .toList(),
        categoryLabels:
            (json['category_labels'] as Map?)?.cast<String, String>() ??
                const {},
      );
}
