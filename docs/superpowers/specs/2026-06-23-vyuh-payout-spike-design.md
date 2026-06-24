# Spike: vyuh_node_flow as the mobile payout flow editor

**Date:** 2026-06-23
**Status:** Design — pending approval
**Type:** Throwaway technical spike (not for merge)

## Purpose

Decide whether the web app's n8n-style payout **flow editor** can be ported to the
Flutter mobile app on top of the [`vyuh_node_flow`](https://pub.dev/packages/vyuh_node_flow)
package, instead of rebuilding a node-graph canvas from scratch.

Prior research (both schemas extracted from source) established that an adapter between
the TTS `flow_diagram` JSON and Vyuh's `NodeGraph` JSON is low-friction. The **one
question research could not answer** is whether Vyuh's canvas is usable with **touch on a
real phone** — pub.dev lists iOS/Android, but touch gestures are neither documented nor
demonstrated, and the package is pre-1.0 (0.27.3).

**This spike exists to answer exactly one question:**

> Can a band member, on a physical phone, comfortably drag nodes and wire ports
> (including a conditional node's `true`/`false` outputs) with a thumb — and does the
> adapter round-trip a real saved flow through Vyuh without losing payout logic?

Everything built here is **disposable**. We optimize for answering the question fast, not
for production quality.

## Background (established facts)

The TTS `flow_diagram` column serves two consumers with different contracts:

- **Logic contract (must be exact):** `BandPayoutConfig::calculatePayouts()` reads only
  `nodes:[{id, type, data}]` + `edges:[{source, target}]`. It ignores `position`, ignores
  handles (except — eventually — conditional branching, which is **not yet implemented in
  the backend**), and validates only "exactly one `income` node" + "no orphan nodes".
- **Layout contract (mobile owns it):** node positions, port geometry, edge styling — all
  derivable/regenerable, none of it sacred to the backend.

Vyuh's `Node.data` is an arbitrary `Map<String,dynamic>` passed through serialization by an
identity function, so the deeply-nested `payoutGroup` config (tier arrays, member
allocation lists, nested config objects) rides through untouched.

## Scope

**Node types covered:** `income`, `payoutGroup`, `conditional`.
- `income` — simplest node (one output), baseline drag test.
- `payoutGroup` — the deeply-nested-`data` node; proves the config payload round-trips.
- `conditional` — the two-output (`true`/`false`) node; proves Vyuh's multi-named-port
  model handles branch wiring. (Backend doesn't calculate it yet — that's fine, this is a
  UI/round-trip test.)

`bandCut` is **excluded**: structurally identical to `income` (one in, one out), adds build
time without new touch insight.

**Success bar (all three must hold, on a physical device):**
1. The real fixture renders and nodes are **draggable by thumb**.
2. Ports can be **wired by touch**, including connecting a conditional's `true` and `false`
   outputs to two different targets.
3. The adapter **round-trips** the real fixture: TTS JSON → Vyuh `NodeGraph` → back to TTS
   JSON, with the **logic contract preserved** (every node's `id`/`type`/`data` and every
   edge's `source`/`target` unchanged). Layout fields may differ — they're regenerated.

**Explicitly out of scope:** mobile API endpoints, saving to the backend, payout
calculation on device, pinch-zoom/multi-select/edge-deletion polish, `bandCut`, and any
production wiring into the `finances` feature.

## Seed data

The spike is seeded from the real backend test fixture
`tests/Feature/PayoutFlowCalculationTest.php::test_multiple_outputs_with_percentage_allocations`
(TTS repo): one `income` node fanning out to two `payoutGroup` nodes at 50% each. We add a
`conditional` node by hand to the seed so the branch-wiring path is exercised on-device.

The fixture JSON is copied into the spike as a Dart string/asset — the spike does **not**
reach into the TTS repo or any live API.

## Design

### Components

1. **`PayoutFlowAdapter`** (the only piece with lasting value)
   - `vyuhFromTts(Map ttsFlow) -> Map vyuhGraph`
   - `ttsFromVyuh(Map vyuhGraph) -> Map ttsFlow`
   - Pure functions over `Map<String,dynamic>`. No Flutter/Vyuh imports — keeps it unit-testable headlessly.
   - **Node mapping:** `id`→`id` (passthrough), `type`→`type` (identity), `position:{x,y}`↔flat `x`/`y`, `data`→`data` (verbatim passthrough). On the Vyuh side, synthesize `width`/`height` and a `ports` list from a **static per-type port table** (below). On the way back, drop the synthesized layout fields.
   - **Edge mapping:** `source`↔`sourceNodeId`, `target`↔`targetNodeId`, `sourceHandle`↔`sourcePortId`, `targetHandle`↔`targetPortId`. When TTS edges lack handles (as the real fixture does), derive the port id from the static table by node type.
   - **Static port table:**
     - `income`: out `income-out` (right)
     - `payoutGroup`: in `payoutgroup-in` (left), out `payoutgroup-out` (right)
     - `conditional`: in `conditional-in` (left), out `true` (right ~33%), out `false` (right ~66%)

2. **Round-trip test** (`test/`) — feeds the fixture through `vyuhFromTts` then
   `ttsFromVyuh` and asserts the logic contract is byte-identical (sorted nodes by id,
   compare `id`/`type`/`data`; sorted edges, compare `source`/`target`). Runs headless via
   `flutter test`.

3. **Throwaway editor screen** — a single route not wired into nav. Loads the seed via the
   adapter into a `NodeFlowController`, renders `NodeFlowEditor` with a `nodeBuilder` that
   switches on `node.type` to draw three minimal custom node widgets (just enough to read
   the node and grab its ports). A "dump JSON" button runs `ttsFromVyuh` on the current
   graph and prints it, so the round-trip can be eyeballed live on-device.

### Data flow

```
TTS fixture JSON
   │  PayoutFlowAdapter.vyuhFromTts
   ▼
Vyuh NodeGraph JSON ──► NodeGraph.fromJsonStringMap ──► NodeFlowController
   │                                                          │
   │  (user drags / wires on device)                          │
   ▼                                                          ▼
controller.graph.toJson ──► PayoutFlowAdapter.ttsFromVyuh ──► TTS JSON (eyeball + assert)
```

### File layout (all throwaway except where noted)

```
lib/features/finances/_spike/
  payout_flow_adapter.dart        # the reusable bit — pure Map<->Map
  spike_seed.dart                 # the fixture JSON as a Dart const + a hand-added conditional
  payout_flow_spike_screen.dart   # throwaway NodeFlowEditor screen
test/features/finances/
  payout_flow_adapter_test.dart   # round-trip logic-contract assertion
```

An `_spike/` prefix marks the disposable code; deleting the folder + the test + the pubspec
line fully reverts the experiment.

### Error handling / testing

This is a spike, so error handling is minimal: the adapter asserts its invariants (exactly
one income, every edge endpoint resolves to a known node) and throws on violation rather
than defending against malformed input. The only automated test is the round-trip
logic-contract test — that is the spike's correctness gate. Touch feel is assessed manually
on-device.

## Risks

- **Touch quality (the whole point):** if dragging/wiring feels bad on a phone, the verdict
  is "no native port — fall back to WebView." That is a successful spike outcome, not a
  failure.
- **0.x churn:** pin `vyuh_node_flow: 0.27.3` exactly. Port-model and plugin APIs have moved
  across recent minors.
- **Vyuh API drift from research:** the research read source, but the exact constructor/
  loader names may differ slightly at 0.27.3. The adapter is insulated (pure JSON); only the
  screen touches Vyuh's live API, and it's throwaway.

## On-device findings (2026-06-24, Galaxy S21 Ultra / Android 15)

Tested iteratively on a physical device. Three issues found and addressed:

1. **Worktree build gap** — fresh git worktree lacked the gitignored
   `android/app/google-services.json`; the Google Services Gradle plugin failed
   the build. Copied from the main repo. (Setup quirk, not a spike finding.)

2. **Node hit-testing broke (fixed).** Nodes weren't draggable at all — canvas
   panned but nodes didn't respond. Root cause: the adapter computed `Port.offset`
   as an absolute box coordinate (`x = node width`) instead of vyuh's
   **edge-relative nudge** convention (`x ≈ ±2`, `y` = absolute pixel within node
   height), confirmed against the library's own `simple.dart`/`controlling_nodes.dart`.
   Wrong offsets mis-size the node's interactive/spatial-index bounds, so touches
   miss the node silently (no error). Fixed in `_portsJsonFor`; guarded by a test.

3. **Single-finger node drag needs two fingers (worked around).** After the
   hit-test fix, hit-detection was solid but moving a node required two fingers —
   the canvas `InteractiveViewer` wins the single-finger gesture-arena
   competition before the node's drag lock engages on touch. This is a **known,
   unresolved upstream bug**: open issue
   [#24](https://github.com/vyuh-tech/vyuh_node_flow/issues/24) "Node Drag Not
   Working on Mobile", with an in-flight, unmerged, third-party-fork fix in PR
   [#31](https://github.com/vyuh-tech/vyuh_node_flow/pulls/31).

   **Workaround chosen (first-party, no external code):** a **long-press-to-move**
   overlay. A normal one-finger drag pans the canvas (the library's default); a
   long-press grabs the node under the finger and subsequent movement repositions
   it via `controller.moveNode(id, screenDelta / zoom)`, hit-tested with
   `node.containsPoint` in graph space. Ports/taps fall through to the editor.
   This sidesteps the gesture-arena race entirely and is arguably a better mobile
   pattern (explicit grab, like rearranging home-screen icons).

## Decision output

**Verdict: GO.** On a physical Galaxy S21 Ultra (Android 15), after the two fixes
above, the editor is usable: hit-testing is solid, port wiring works (including
the conditional's true/false outputs), and **long-press-to-move (200ms hold) with
an on-node lift cue (scale + accent border + glow) feels natural** — the user
confirmed it "looks perfect." The adapter round-trips the real backend fixture
with the payout logic contract intact (6/6 tests green).

Recommended path: native port on `vyuh_node_flow` at ~3–6 weeks, carrying forward
`PayoutFlowAdapter` (the durable artifact) and the long-press-to-move pattern.
Caveats to budget for:
- **Pin `vyuh_node_flow` exactly** (spiked on 0.27.3); pre-1.0, breaking changes
  across minors.
- Single-finger node drag depends on upstream issue
  [#24](https://github.com/vyuh-tech/vyuh_node_flow/issues/24) / PR
  [#31](https://github.com/vyuh-tech/vyuh_node_flow/pulls/31). Our long-press
  workaround makes this moot, but if that fix lands we can reassess.
- Backend work (mobile API endpoints to fetch/save/preview configs) is still
  required and was out of scope here.
- `conditional` nodes render/edit but the backend doesn't calculate branches yet —
  same limitation as web.
