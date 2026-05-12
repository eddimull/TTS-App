import 'contract_term.dart';

class BookingContract {
  final int id;
  final String? status;
  final String? assetUrl;
  final String? envelopeId;
  final List<ContractTerm>? customTerms;
  final DateTime? updatedAt;

  const BookingContract({
    required this.id,
    this.status,
    this.assetUrl,
    this.envelopeId,
    this.customTerms,
    this.updatedAt,
  });

  factory BookingContract.fromJson(Map<String, dynamic> json) {
    final rawTerms = json['custom_terms'];
    final terms = rawTerms is List
        ? rawTerms
            .cast<Map<String, dynamic>>()
            .map(ContractTerm.fromJson)
            .toList()
        : null;

    final rawUpdated = json['updated_at'] as String?;
    final updated = rawUpdated == null ? null : DateTime.tryParse(rawUpdated);

    return BookingContract(
      id: json['id'] as int,
      status: json['status'] as String?,
      assetUrl: json['asset_url'] as String?,
      envelopeId: json['envelope_id'] as String?,
      customTerms: terms,
      updatedAt: updated,
    );
  }
}
