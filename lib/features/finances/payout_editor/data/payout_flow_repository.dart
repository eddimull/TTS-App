import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tts_bandmate/core/providers/core_providers.dart';

/// Lightweight summary of a payout config (the list response — no flow_diagram).
class PayoutConfigSummary {
  const PayoutConfigSummary({
    required this.id,
    required this.name,
    required this.isActive,
  });

  final int id;
  final String name;
  final bool isActive;

  factory PayoutConfigSummary.fromJson(Map<String, dynamic> json) {
    return PayoutConfigSummary(
      id: json['id'] as int,
      name: (json['name'] ?? '') as String,
      isActive: (json['is_active'] ?? false) as bool,
    );
  }
}

/// A full payout config including its flow_diagram (the show/update response).
class PayoutConfigDetail {
  const PayoutConfigDetail({
    required this.id,
    required this.name,
    required this.isActive,
    required this.flowDiagram,
  });

  final int id;
  final String name;
  final bool isActive;

  /// The TTS `flow_diagram` JSON ({nodes, edges, version}); may be null/empty.
  final Map<String, dynamic> flowDiagram;

  factory PayoutConfigDetail.fromJson(Map<String, dynamic> json) {
    return PayoutConfigDetail(
      id: json['id'] as int,
      name: (json['name'] ?? '') as String,
      isActive: (json['is_active'] ?? false) as bool,
      flowDiagram:
          (json['flow_diagram'] as Map?)?.cast<String, dynamic>() ??
              const {'nodes': [], 'edges': []},
    );
  }
}

/// A starter template the user can create a config from.
class PayoutTemplate {
  const PayoutTemplate({
    required this.key,
    required this.name,
    required this.description,
  });

  final String key;
  final String name;
  final String description;

  factory PayoutTemplate.fromJson(Map<String, dynamic> json) {
    return PayoutTemplate(
      key: json['key'] as String,
      name: (json['name'] ?? '') as String,
      description: (json['description'] ?? '') as String,
    );
  }
}

class PayoutFlowRepository {
  PayoutFlowRepository(this._dio);

  final Dio _dio;

  /// Lists a band's payout configs (summaries, no flow payload).
  Future<List<PayoutConfigSummary>> listConfigs(int bandId) async {
    final res = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobilePayoutFlowConfigs(bandId),
    );
    final raw = res.data!['configs'] as List<dynamic>;
    return raw
        .cast<Map<String, dynamic>>()
        .map(PayoutConfigSummary.fromJson)
        .toList();
  }

  /// Fetches one config including its flow_diagram.
  Future<PayoutConfigDetail> getConfig(int bandId, int configId) async {
    final res = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobilePayoutFlowConfig(bandId, configId),
    );
    return PayoutConfigDetail.fromJson(res.data!);
  }

  /// Saves an edited flow_diagram (owner-only on the backend).
  Future<PayoutConfigDetail> updateFlow(
    int bandId,
    int configId,
    Map<String, dynamic> flowDiagram, {
    bool? isActive,
  }) async {
    final res = await _dio.patch<Map<String, dynamic>>(
      ApiEndpoints.mobilePayoutFlowConfig(bandId, configId),
      data: {
        'flow_diagram': flowDiagram,
        if (isActive != null) 'is_active': isActive,
      },
    );
    return PayoutConfigDetail.fromJson(res.data!);
  }

  /// Previews a payout calculation for a flow + test amount (no persistence).
  Future<Map<String, dynamic>> preview(
    int bandId,
    Map<String, dynamic> flowDiagram,
    num testAmount,
  ) async {
    final res = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobilePayoutFlowPreview(bandId),
      data: {
        'nodes': flowDiagram['nodes'] ?? const [],
        'edges': flowDiagram['edges'] ?? const [],
        'test_amount': testAmount,
      },
    );
    return res.data!;
  }

  /// The starter templates offered when creating a config.
  Future<List<PayoutTemplate>> listTemplates(int bandId) async {
    final res = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobilePayoutFlowTemplates(bandId),
    );
    final raw = res.data!['templates'] as List<dynamic>;
    return raw.cast<Map<String, dynamic>>().map(PayoutTemplate.fromJson).toList();
  }

  /// Creates a config from a template (created inactive on the backend).
  /// The create response nests the config under a `config` key.
  Future<PayoutConfigDetail> createConfig(
    int bandId,
    String name,
    String template,
  ) async {
    final res = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobilePayoutFlowConfigs(bandId),
      data: {'name': name, 'template': template},
    );
    return PayoutConfigDetail.fromJson(
      (res.data!['config'] as Map).cast<String, dynamic>(),
    );
  }

  /// Marks a config active (the backend deactivates the others). Sends only
  /// is_active — no flow payload — so it can't clobber the saved flow.
  Future<void> setActive(int bandId, int configId) async {
    await _dio.patch<Map<String, dynamic>>(
      ApiEndpoints.mobilePayoutFlowConfig(bandId, configId),
      data: {'is_active': true},
    );
  }

  /// Deletes a config (owner-only on the backend).
  Future<void> deleteConfig(int bandId, int configId) async {
    await _dio.delete<void>(
      ApiEndpoints.mobilePayoutFlowConfig(bandId, configId),
    );
  }
}

final payoutFlowRepositoryProvider = Provider<PayoutFlowRepository>((ref) {
  return PayoutFlowRepository(ref.watch(apiClientProvider).dio);
});
