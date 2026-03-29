class BandSummary {
  const BandSummary({
    required this.id,
    required this.name,
    required this.isOwner,
  });

  final int id;
  final String name;
  final bool isOwner;

  factory BandSummary.fromJson(Map<String, dynamic> json) {
    return BandSummary(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
      isOwner: (json['is_owner'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'is_owner': isOwner,
      };

  @override
  String toString() =>
      'BandSummary(id: $id, name: $name, isOwner: $isOwner)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BandSummary &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
