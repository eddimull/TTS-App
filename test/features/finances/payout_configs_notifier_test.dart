import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/finances/payout_editor/data/payout_flow_repository.dart';
import 'package:tts_bandmate/features/finances/payout_editor/providers/payout_flow_provider.dart';

class _FakeRepo implements PayoutFlowRepository {
  _FakeRepo(this._configs);
  List<PayoutConfigSummary> _configs;
  final calls = <String>[];

  @override
  Future<List<PayoutConfigSummary>> listConfigs(int bandId) async => _configs;

  @override
  Future<PayoutConfigDetail> createConfig(int bandId, String name, String template) async {
    calls.add('create:$name:$template');
    final id = _configs.length + 1;
    _configs = [..._configs, PayoutConfigSummary(id: id, name: name, isActive: false)];
    return PayoutConfigDetail(id: id, name: name, isActive: false, flowDiagram: const {'nodes': [], 'edges': []});
  }

  @override
  Future<void> setActive(int bandId, int configId) async {
    calls.add('setActive:$configId');
    _configs = _configs
        .map((c) => PayoutConfigSummary(id: c.id, name: c.name, isActive: c.id == configId))
        .toList();
  }

  @override
  Future<void> deleteConfig(int bandId, int configId) async {
    calls.add('deleteConfig:$configId');
    _configs = _configs.where((c) => c.id != configId).toList();
  }

  @override
  Future<List<PayoutTemplate>> listTemplates(int bandId) async => const [];

  @override
  Future<PayoutConfigDetail> getConfig(int bandId, int configId) => throw UnimplementedError();
  @override
  Future<PayoutConfigDetail> updateFlow(int bandId, int configId, Map<String, dynamic> flowDiagram, {bool? isActive}) => throw UnimplementedError();
  @override
  Future<Map<String, dynamic>> preview(int bandId, Map<String, dynamic> flowDiagram, num testAmount) => throw UnimplementedError();
}

void main() {
  ProviderContainer containerWith(_FakeRepo repo) => ProviderContainer(
        overrides: [payoutFlowRepositoryProvider.overrideWithValue(repo)],
      );

  test('createConfig calls the repo and refreshes the list', () async {
    final repo = _FakeRepo([]);
    final c = containerWith(repo);
    addTearDown(c.dispose);

    await c.read(payoutConfigsProvider(1).future);
    final detail = await c.read(payoutConfigsProvider(1).notifier).createConfig('My Config', 'blank');

    expect(detail.id, 1);
    expect(repo.calls, contains('create:My Config:blank'));
    final list = await c.read(payoutConfigsProvider(1).future);
    expect(list.map((e) => e.name), contains('My Config'));
  });

  test('setActive calls the repo and refreshes', () async {
    final repo = _FakeRepo([
      const PayoutConfigSummary(id: 1, name: 'A', isActive: true),
      const PayoutConfigSummary(id: 2, name: 'B', isActive: false),
    ]);
    final c = containerWith(repo);
    addTearDown(c.dispose);

    await c.read(payoutConfigsProvider(1).future);
    await c.read(payoutConfigsProvider(1).notifier).setActive(2);

    expect(repo.calls, contains('setActive:2'));
    final list = await c.read(payoutConfigsProvider(1).future);
    expect(list.firstWhere((e) => e.id == 2).isActive, isTrue);
    expect(list.firstWhere((e) => e.id == 1).isActive, isFalse);
  });

  test('deleteConfig calls the repo and refreshes (config removed)', () async {
    final repo = _FakeRepo([
      const PayoutConfigSummary(id: 1, name: 'A', isActive: false),
      const PayoutConfigSummary(id: 2, name: 'B', isActive: false),
    ]);
    final c = containerWith(repo);
    addTearDown(c.dispose);

    await c.read(payoutConfigsProvider(1).future);
    await c.read(payoutConfigsProvider(1).notifier).deleteConfig(1);

    expect(repo.calls, contains('deleteConfig:1'));
    final list = await c.read(payoutConfigsProvider(1).future);
    expect(list.map((e) => e.id), [2]);
  });
}
