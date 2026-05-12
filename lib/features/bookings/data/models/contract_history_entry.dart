class ContractHistoryEntry {
  const ContractHistoryEntry({
    required this.id,
    required this.createdAt,
    required this.action,
    required this.actionCode,
    required this.userEmail,
    required this.description,
    required this.status,
    this.reason,
    this.ipAddress,
  });

  final String id;
  final DateTime? createdAt;
  final String action;
  final int actionCode;
  final String userEmail;
  final String description;
  final String? reason;
  final String status;
  final String? ipAddress;

  factory ContractHistoryEntry.fromJson(Map<String, dynamic> json) {
    final rawCreated = json['created_at'] as String?;
    return ContractHistoryEntry(
      id: (json['id'] as String?) ?? '',
      createdAt: rawCreated == null ? null : DateTime.tryParse(rawCreated),
      action: (json['action'] as String?) ?? '',
      actionCode: (json['action_code'] as num?)?.toInt() ?? 0,
      userEmail: (json['user_email'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
      reason: json['reason'] as String?,
      status: (json['status'] as String?) ?? '',
      ipAddress: json['ip_address'] as String?,
    );
  }
}
