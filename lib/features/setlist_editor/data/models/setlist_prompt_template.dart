class SetlistPromptTemplate {
  const SetlistPromptTemplate({
    required this.id,
    required this.name,
    required this.prompt,
  });

  final int id;
  final String name;
  final String prompt;

  factory SetlistPromptTemplate.fromJson(Map<String, dynamic> json) =>
      SetlistPromptTemplate(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String? ?? '',
        prompt: json['prompt'] as String? ?? '',
      );
}
