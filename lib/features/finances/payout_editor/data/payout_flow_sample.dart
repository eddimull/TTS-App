// Sample payout flows used as test fixtures and as a fallback/demo seed for the
// editor before a real config is loaded from the API.
//
// The base (`kFixtureFlow`) is the real backend fixture
// `PayoutFlowCalculationTest::test_multiple_outputs_with_percentage_allocations`
// (TTS repo): one income node fanning out to two payoutGroup nodes at 50% each.
//
// `kSeedFlowWithConditional` adds a `conditional` node to exercise the
// two-output (true/false) branch-wiring path. Note: the backend doesn't yet
// evaluate conditional branches — it passes the amount through to all outputs.

/// The real fixture, verbatim from the backend test (edges carry no handles,
/// nodes carry no position — exactly as the calculation engine consumes them).
const Map<String, dynamic> kFixtureFlow = {
  'nodes': [
    {
      'id': 'income-1',
      'type': 'income',
      'data': {'amount': 1000, 'label': 'Income'},
    },
    {
      'id': 'payout-1',
      'type': 'payoutGroup',
      'data': {
        'label': 'Group A',
        'sourceType': 'allMembers',
        'allMembersConfig': {
          'includeOwners': true,
          'includeMembers': false,
          'includeProduction': false,
        },
        'incomingAllocationType': 'percentage',
        'incomingAllocationValue': 50,
        'distributionMode': 'equal_split',
      },
    },
    {
      'id': 'payout-2',
      'type': 'payoutGroup',
      'data': {
        'label': 'Group B',
        'sourceType': 'allMembers',
        'allMembersConfig': {
          'includeOwners': true,
          'includeMembers': false,
          'includeProduction': false,
        },
        'incomingAllocationType': 'percentage',
        'incomingAllocationValue': 50,
        'distributionMode': 'equal_split',
      },
    },
  ],
  'edges': [
    {'source': 'income-1', 'target': 'payout-1'},
    {'source': 'income-1', 'target': 'payout-2'},
  ],
};

/// The fixture plus a hand-added conditional node wired into the flow, so the
/// on-device test can wire the true/false outputs. Branch edges carry explicit
/// `sourceHandle` values ('true' / 'false') — the convention the Vue editor uses.
const Map<String, dynamic> kSeedFlowWithConditional = {
  'nodes': [
    {
      'id': 'income-1',
      'type': 'income',
      'position': {'x': 40.0, 'y': 200.0},
      'data': {'amount': 1000, 'label': 'Income'},
    },
    {
      'id': 'conditional-1',
      'type': 'conditional',
      'position': {'x': 280.0, 'y': 200.0},
      'data': {
        'label': 'High-value booking?',
        'conditionType': 'bookingPrice',
        'operator': '>=',
        'value': 5000,
      },
    },
    {
      'id': 'payout-1',
      'type': 'payoutGroup',
      'position': {'x': 560.0, 'y': 80.0},
      'data': {
        'label': 'Group A',
        'sourceType': 'allMembers',
        'allMembersConfig': {
          'includeOwners': true,
          'includeMembers': false,
          'includeProduction': false,
        },
        'incomingAllocationType': 'percentage',
        'incomingAllocationValue': 50,
        'distributionMode': 'equal_split',
      },
    },
    {
      'id': 'payout-2',
      'type': 'payoutGroup',
      'position': {'x': 560.0, 'y': 320.0},
      'data': {
        'label': 'Group B',
        'sourceType': 'allMembers',
        'allMembersConfig': {
          'includeOwners': true,
          'includeMembers': false,
          'includeProduction': false,
        },
        'incomingAllocationType': 'percentage',
        'incomingAllocationValue': 50,
        'distributionMode': 'equal_split',
      },
    },
  ],
  'edges': [
    {'source': 'income-1', 'target': 'conditional-1'},
    {'source': 'conditional-1', 'target': 'payout-1', 'sourceHandle': 'true'},
    {'source': 'conditional-1', 'target': 'payout-2', 'sourceHandle': 'false'},
  ],
};
