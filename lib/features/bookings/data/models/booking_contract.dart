class BookingContract {
  final int id;
  final String? status;
  final String? assetUrl;
  final String? envelopeId;

  const BookingContract({
    required this.id,
    this.status,
    this.assetUrl,
    this.envelopeId,
  });

  factory BookingContract.fromJson(Map<String, dynamic> json) => BookingContract(
        id: json['id'] as int,
        status: json['status'] as String?,
        assetUrl: json['asset_url'] as String?,
        envelopeId: json['envelope_id'] as String?,
      );
}
