/// A band-scoped attire chip, persisted on the backend.
///
/// Chips with [id] == null are local placeholders (the six hardcoded defaults)
/// shown when the band has no backend chips yet. They become real rows on the
/// first POST.
class AttireChip {
  const AttireChip({
    this.id,
    required this.label,
    this.position = 0,
  });

  final int? id;
  final String label;
  final int position;

  /// True when this chip has not yet been saved to the backend (i.e. it is one
  /// of the six hardcoded fallbacks displayed before the band has any chips).
  bool get isPlaceholder => id == null;

  factory AttireChip.fromJson(Map<String, dynamic> json) {
    return AttireChip(
      id: (json['id'] as num?)?.toInt(),
      label: (json['label'] as String?) ?? '',
      position: (json['position'] as num?)?.toInt() ?? 0,
    );
  }

  AttireChip copyWith({int? id, String? label, int? position}) {
    return AttireChip(
      id: id ?? this.id,
      label: label ?? this.label,
      position: position ?? this.position,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AttireChip &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          label == other.label;

  @override
  int get hashCode => Object.hash(id, label);

  @override
  String toString() => 'AttireChip(id: $id, label: $label, position: $position)';
}
