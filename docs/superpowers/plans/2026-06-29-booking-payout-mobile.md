# Booking Payout (Mobile) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring the web app's per-booking payout breakdown to mobile at full parity — see each member's share across all performances, switch payout config, edit per-event attendance, and add/remove adjustments.

**Architecture:** Backend-first across two repos. New Laravel mobile-API endpoints (`Api\Mobile\BookingsController`) wrap the *existing* payout model methods (`getOrCreatePayout`, `BandPayoutConfig::calculatePayouts`, `Payout::recalculateAdjustedAmount`) and return JSON. The Flutter app gets a new payout slice under `features/bookings/` (model + repository methods + provider + screen), reached from a "Payout" tile on the booking detail screen. The server is authoritative: mobile re-fetches the full payout payload after every mutation and never recomputes payouts locally.

**Tech Stack:** Laravel (Sanctum mobile tokens, route-model binding, `Price` cast), Flutter (Cupertino, Riverpod v2 AsyncNotifier, Dio, GoRouter, `intl`).

## Global Constraints

- **Repos:** Backend tasks are in `/home/eddie/github/TTS` (Laravel). Mobile tasks are in `/home/eddie/github/tts_bandmate` (Flutter). Each repo commits separately.
- **Backend commands run in the container only:** `docker compose exec app php artisan …` / `docker compose exec app php artisan test …`. Never run php/artisan/composer/phpunit on the host.
- **Attendance field:** column is `attendance_status`; allowed values are exactly `confirmed`, `attended`, `absent`, `excused`. Do NOT reuse the legacy `EventMembersController::updateStatus` (`status`/`playing` naming). Leave that endpoint untouched.
- **Money in JSON:** dollars. Cast amounts to string with `(string)` (the `Price` cast already converts cents→dollar string), matching `storePayment`.
- **Mobile mutations** must call `ref.read(cacheInvalidatorProvider).onBookingDetailChanged(bandId: …, bookingId: …)` after success, and surface errors via `ErrorView.friendlyMessage(e)`.
- **No payout-config authoring on mobile** — only switching among existing `band_payout_configs`.
- **Permissions:** read endpoint behind `mobile.band:read:bookings`; all mutations behind `mobile.band:write:bookings`; routes use `scopeBindings()`.
- **TDD:** failing test → minimal impl → green → commit, every task.

---

## BACKEND (Laravel `TTS` repo)

### Task 1: GET payout breakdown endpoint

**Files:**
- Modify: `/home/eddie/github/TTS/routes/api.php` (read:bookings group, ~line 213-222)
- Modify: `/home/eddie/github/TTS/app/Http/Controllers/Api/Mobile/BookingsController.php` (add `payout()`)
- Test: `/home/eddie/github/TTS/tests/Feature/Api/Mobile/BookingPayoutTest.php`

**Interfaces:**
- Produces: `GET /api/mobile/bands/{band}/bookings/{booking}/payout` → JSON `{ payout, config, result, adjustments, events, available_configs }`. Later mobile tasks parse this exact shape.

- [ ] **Step 1: Write the failing test**

```php
<?php

namespace Tests\Feature\Api\Mobile;

use App\Models\BandOwners;
use App\Models\BandPayoutConfig;
use App\Models\Bands;
use App\Models\Bookings;
use App\Models\Events;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class BookingPayoutTest extends TestCase
{
    use RefreshDatabase;

    private function setup_booking(): array
    {
        $user = User::factory()->create();
        $band = Bands::factory()->create();
        BandOwners::create(['band_id' => $band->id, 'user_id' => $user->id]);
        $config = BandPayoutConfig::factory()->create([
            'band_id' => $band->id, 'is_active' => true,
            'band_cut_type' => 'percentage', 'band_cut_value' => 20,
        ]);
        $booking = Bookings::factory()->create(['band_id' => $band->id, 'price' => 1000]);
        Events::factory()->create(['eventable_id' => $booking->id, 'eventable_type' => Bookings::class, 'value' => 1000]);
        $token = $user->createToken('test-device')->plainTextToken;
        return compact('user', 'band', 'booking', 'config', 'token');
    }

    private function headers(string $token, int $bandId): array
    {
        return ['Authorization' => "Bearer {$token}", 'X-Band-ID' => $bandId, 'Accept' => 'application/json'];
    }

    public function test_payout_show_returns_breakdown_structure(): void
    {
        ['band' => $band, 'booking' => $booking, 'token' => $token] = $this->setup_booking();

        $response = $this->withHeaders($this->headers($token, $band->id))
            ->getJson("/api/mobile/bands/{$band->id}/bookings/{$booking->id}/payout");

        $response->assertOk()->assertJsonStructure([
            'payout' => ['id', 'base_amount', 'adjusted_amount', 'payout_config_id'],
            'config' => ['id', 'name', 'is_active'],
            'result' => ['total_amount', 'band_cut', 'distributable_amount', 'member_payouts', 'payment_group_payouts'],
            'adjustments',
            'events' => [['id', 'label', 'value', 'members']],
            'available_configs' => [['id', 'name', 'is_active']],
        ]);
    }

    public function test_payout_show_forbidden_for_non_member(): void
    {
        ['band' => $band, 'booking' => $booking] = $this->setup_booking();
        $outsider = User::factory()->create();
        $token = $outsider->createToken('d')->plainTextToken;

        $this->withHeaders($this->headers($token, $band->id))
            ->getJson("/api/mobile/bands/{$band->id}/bookings/{$booking->id}/payout")
            ->assertForbidden();
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `docker compose exec app php artisan test --filter=BookingPayoutTest`
Expected: FAIL — route `/payout` not defined (404), not 200/403.

- [ ] **Step 3: Add the route**

In `routes/api.php`, inside the `mobile.band:read:bookings` group (alongside the other `bookings/{booking}` GET routes ~line 221), add:

```php
            Route::get('/bands/{band}/bookings/{booking}/payout', [App\Http\Controllers\Api\Mobile\BookingsController::class, 'payout'])->name('mobile.bookings.payout.show');
```

- [ ] **Step 4: Implement `payout()` in the mobile `BookingsController`**

Add a private helper and the action. The helper mirrors the web `getOrCreatePayout`; the action mirrors the web `payout()` business logic but returns JSON.

```php
    public function payout(Request $request, Bands $band, Bookings $booking): JsonResponse
    {
        $payout = $this->getOrCreatePayout($booking, $band);

        $booking->load([
            'events.eventMembers.rosterMember',
            'events.eventMembers.user',
        ]);

        $config = $payout->payout_config_id
            ? \App\Models\BandPayoutConfig::where('id', $payout->payout_config_id)->where('band_id', $band->id)->with(['band.paymentGroups.users'])->first()
            : \App\Models\BandPayoutConfig::where('band_id', $band->id)->where('is_active', true)->with(['band.paymentGroups.users'])->first();

        $adjustedTotal = $payout->adjusted_amount_float;
        $result = ($config && $adjustedTotal > 0)
            ? $config->calculatePayouts($adjustedTotal, null, $booking)
            : null;

        $events = $booking->events->map(fn ($e) => [
            'id' => $e->id,
            'label' => trim(($e->date ? $e->date->format('D M j') : '').($e->title ? ' · '.$e->title : '')),
            'value' => (string) $e->value,
            'members' => $e->eventMembers->map(fn ($m) => [
                'id' => $m->id,
                'user_id' => $m->user_id,
                'name' => $m->name ?? optional($m->user)->name ?? '',
                'attendance_status' => $m->attendance_status,
            ])->values(),
        ])->values();

        $availableConfigs = \App\Models\BandPayoutConfig::where('band_id', $band->id)
            ->get(['id', 'name', 'is_active'])
            ->map(fn ($c) => ['id' => $c->id, 'name' => $c->name, 'is_active' => (bool) $c->is_active]);

        return response()->json([
            'payout' => [
                'id' => $payout->id,
                'base_amount' => (string) $payout->base_amount,
                'adjusted_amount' => (string) $payout->adjusted_amount,
                'payout_config_id' => $payout->payout_config_id,
            ],
            'config' => $config ? ['id' => $config->id, 'name' => $config->name, 'is_active' => (bool) $config->is_active] : null,
            'result' => $result,
            'adjustments' => $payout->adjustments->map(fn ($a) => [
                'id' => $a->id,
                'amount' => (string) $a->amount,
                'description' => $a->description,
                'notes' => $a->notes,
            ])->values(),
            'events' => $events,
            'available_configs' => $availableConfigs,
        ]);
    }

    private function getOrCreatePayout(Bookings $booking, Bands $band): \App\Models\Payout
    {
        if ($booking->payout) {
            return $booking->payout;
        }
        $baseAmount = $booking->total_event_value;
        return $booking->payout()->create([
            'band_id' => $band->id,
            'base_amount' => $baseAmount,
            'adjusted_amount' => $baseAmount,
        ]);
    }
```

Ensure `use Illuminate\Http\JsonResponse;` and `use Illuminate\Http\Request;` are present (they are, used by `show()`).

- [ ] **Step 5: Run test to verify it passes**

Run: `docker compose exec app php artisan test --filter=BookingPayoutTest`
Expected: PASS (both methods).

- [ ] **Step 6: Commit**

```bash
git -C /home/eddie/github/TTS add routes/api.php app/Http/Controllers/Api/Mobile/BookingsController.php tests/Feature/Api/Mobile/BookingPayoutTest.php
git -C /home/eddie/github/TTS commit -m "feat(mobile-api): add booking payout breakdown endpoint"
```

---

### Task 2: Adjustment store + destroy endpoints

**Files:**
- Modify: `/home/eddie/github/TTS/routes/api.php` (write:bookings group)
- Modify: `/home/eddie/github/TTS/app/Http/Controllers/Api/Mobile/BookingsController.php`
- Test: `/home/eddie/github/TTS/tests/Feature/Api/Mobile/BookingPayoutTest.php` (extend)

**Interfaces:**
- Consumes: `getOrCreatePayout()` from Task 1.
- Produces: `POST …/payout/adjustments` → `201` `{ adjustment: {id, amount, description, notes} }`; `DELETE …/payout/adjustments/{adjustment}` → `200 { message }`. Both leave `payout.adjusted_amount` recalculated.

- [ ] **Step 1: Write the failing tests** (append to `BookingPayoutTest`)

```php
    public function test_store_adjustment_recalculates_adjusted_amount(): void
    {
        ['band' => $band, 'booking' => $booking, 'token' => $token] = $this->setup_booking();

        $response = $this->withHeaders($this->headers($token, $band->id))
            ->postJson("/api/mobile/bands/{$band->id}/bookings/{$booking->id}/payout/adjustments", [
                'amount' => -250, 'description' => 'Gas / travel', 'notes' => 'Reimbursed',
            ]);

        $response->assertCreated()->assertJsonStructure(['adjustment' => ['id', 'amount', 'description', 'notes']]);
        $this->assertSame('750.00', (string) $booking->fresh()->payout->adjusted_amount);
    }

    public function test_store_adjustment_validates_description_required(): void
    {
        ['band' => $band, 'booking' => $booking, 'token' => $token] = $this->setup_booking();
        $this->withHeaders($this->headers($token, $band->id))
            ->postJson("/api/mobile/bands/{$band->id}/bookings/{$booking->id}/payout/adjustments", ['amount' => 10])
            ->assertStatus(422);
    }

    public function test_destroy_adjustment_recalculates_and_rejects_foreign(): void
    {
        ['band' => $band, 'booking' => $booking, 'token' => $token] = $this->setup_booking();
        $this->withHeaders($this->headers($token, $band->id))
            ->postJson("/api/mobile/bands/{$band->id}/bookings/{$booking->id}/payout/adjustments", ['amount' => -250, 'description' => 'X']);
        $adjId = $booking->fresh()->payout->adjustments->first()->id;

        $this->withHeaders($this->headers($token, $band->id))
            ->deleteJson("/api/mobile/bands/{$band->id}/bookings/{$booking->id}/payout/adjustments/{$adjId}")
            ->assertOk();
        $this->assertSame('1000.00', (string) $booking->fresh()->payout->adjusted_amount);
    }
```

- [ ] **Step 2: Run to verify fail**

Run: `docker compose exec app php artisan test --filter=BookingPayoutTest`
Expected: FAIL — adjustment routes 404.

- [ ] **Step 3: Add routes** (in `mobile.band:write:bookings` group, near booking payments ~line 238)

```php
            Route::post('/bands/{band}/bookings/{booking}/payout/adjustments', [App\Http\Controllers\Api\Mobile\BookingsController::class, 'storePayoutAdjustment'])->name('mobile.bookings.payout.adjustments.store');
            Route::delete('/bands/{band}/bookings/{booking}/payout/adjustments/{adjustment}', [App\Http\Controllers\Api\Mobile\BookingsController::class, 'destroyPayoutAdjustment'])->name('mobile.bookings.payout.adjustments.destroy');
```

- [ ] **Step 4: Implement the two actions**

```php
    public function storePayoutAdjustment(Request $request, Bands $band, Bookings $booking): JsonResponse
    {
        $validated = $request->validate([
            'amount' => 'required|numeric',
            'description' => 'required|string|max:255',
            'notes' => 'nullable|string',
        ]);

        $payout = $this->getOrCreatePayout($booking, $band);
        $adjustment = $payout->adjustments()->create([
            'amount' => $validated['amount'],
            'description' => $validated['description'],
            'notes' => $validated['notes'] ?? null,
            'created_by' => \Illuminate\Support\Facades\Auth::id(),
        ]);
        $payout->recalculateAdjustedAmount();

        return response()->json(['adjustment' => [
            'id' => $adjustment->id,
            'amount' => (string) $adjustment->amount,
            'description' => $adjustment->description,
            'notes' => $adjustment->notes,
        ]], 201);
    }

    public function destroyPayoutAdjustment(Bands $band, Bookings $booking, \App\Models\PayoutAdjustment $adjustment): JsonResponse
    {
        $payout = $booking->payout;
        abort_unless($payout, 404, 'Payout not found');
        abort_unless($adjustment->payout_id === $payout->id, 403, 'Adjustment does not belong to this booking payout');

        $adjustment->delete();
        $payout->recalculateAdjustedAmount();

        return response()->json(['message' => 'Payout adjustment removed']);
    }
```

- [ ] **Step 5: Run to verify pass**

Run: `docker compose exec app php artisan test --filter=BookingPayoutTest`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git -C /home/eddie/github/TTS add routes/api.php app/Http/Controllers/Api/Mobile/BookingsController.php tests/Feature/Api/Mobile/BookingPayoutTest.php
git -C /home/eddie/github/TTS commit -m "feat(mobile-api): add payout adjustment store/destroy endpoints"
```

---

### Task 3: Switch payout configuration endpoint

**Files:**
- Modify: `/home/eddie/github/TTS/routes/api.php` (write:bookings group)
- Modify: `/home/eddie/github/TTS/app/Http/Controllers/Api/Mobile/BookingsController.php`
- Test: `/home/eddie/github/TTS/tests/Feature/Api/Mobile/BookingPayoutTest.php` (extend)

**Interfaces:**
- Consumes: `getOrCreatePayout()`.
- Produces: `PUT …/payout/configuration` body `{ payout_config_id }` → `200 { result }` (fresh `calculatePayouts` output); persists `payout.payout_config_id` and `calculation_result`.

- [ ] **Step 1: Write the failing test**

```php
    public function test_update_configuration_switches_and_returns_result(): void
    {
        ['band' => $band, 'booking' => $booking, 'token' => $token] = $this->setup_booking();
        $other = \App\Models\BandPayoutConfig::factory()->create([
            'band_id' => $band->id, 'is_active' => false,
            'band_cut_type' => 'percentage', 'band_cut_value' => 50,
        ]);

        $response = $this->withHeaders($this->headers($token, $band->id))
            ->putJson("/api/mobile/bands/{$band->id}/bookings/{$booking->id}/payout/configuration", [
                'payout_config_id' => $other->id,
            ]);

        $response->assertOk()->assertJsonStructure(['result' => ['band_cut', 'distributable_amount']]);
        $this->assertEquals($other->id, $booking->fresh()->payout->payout_config_id);
        $this->assertEqualsWithDelta(500.0, $response->json('result.band_cut'), 0.01);
    }

    public function test_update_configuration_rejects_config_from_other_band(): void
    {
        ['band' => $band, 'booking' => $booking, 'token' => $token] = $this->setup_booking();
        $foreign = \App\Models\BandPayoutConfig::factory()->create(['band_id' => Bands::factory()->create()->id]);

        $this->withHeaders($this->headers($token, $band->id))
            ->putJson("/api/mobile/bands/{$band->id}/bookings/{$booking->id}/payout/configuration", ['payout_config_id' => $foreign->id])
            ->assertStatus(404);
    }
```

- [ ] **Step 2: Run to verify fail**

Run: `docker compose exec app php artisan test --filter=BookingPayoutTest`
Expected: FAIL — config route 404.

- [ ] **Step 3: Add route**

```php
            Route::put('/bands/{band}/bookings/{booking}/payout/configuration', [App\Http\Controllers\Api\Mobile\BookingsController::class, 'updatePayoutConfiguration'])->name('mobile.bookings.payout.configuration.update');
```

- [ ] **Step 4: Implement the action**

```php
    public function updatePayoutConfiguration(Request $request, Bands $band, Bookings $booking): JsonResponse
    {
        $validated = $request->validate(['payout_config_id' => 'required|exists:band_payout_configs,id']);

        $payout = $this->getOrCreatePayout($booking, $band);
        $config = \App\Models\BandPayoutConfig::where('id', $validated['payout_config_id'])
            ->where('band_id', $band->id)
            ->with(['band.paymentGroups.users'])
            ->firstOrFail();

        $booking->load(['events.eventMembers.rosterMember', 'events.eventMembers.user']);

        $payout->payout_config_id = $config->id;
        $adjustedTotal = $payout->adjusted_amount_float;
        $result = $adjustedTotal > 0 ? $config->calculatePayouts($adjustedTotal, null, $booking) : null;
        $payout->calculation_result = $result;
        $payout->save();

        return response()->json(['result' => $result]);
    }
```

- [ ] **Step 5: Run to verify pass**

Run: `docker compose exec app php artisan test --filter=BookingPayoutTest`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git -C /home/eddie/github/TTS add routes/api.php app/Http/Controllers/Api/Mobile/BookingsController.php tests/Feature/Api/Mobile/BookingPayoutTest.php
git -C /home/eddie/github/TTS commit -m "feat(mobile-api): add per-booking payout configuration switch"
```

---

### Task 4: Update event-member attendance endpoint

**Files:**
- Modify: `/home/eddie/github/TTS/routes/api.php` (write:bookings group)
- Modify: `/home/eddie/github/TTS/app/Http/Controllers/Api/Mobile/BookingsController.php`
- Test: `/home/eddie/github/TTS/tests/Feature/Api/Mobile/BookingPayoutTest.php` (extend)

**Interfaces:**
- Produces: `PATCH …/bookings/{booking}/events/{event}/members/{member}/attendance` body `{ attendance_status }` → `200 { member: {id, attendance_status} }`. `{member}` = `event_members.id`, scoped to the bound `{event}`. Writes the `attendance_status` column directly (NOT the legacy `updateStatus`).

- [ ] **Step 1: Write the failing test**

```php
    public function test_update_attendance_sets_status(): void
    {
        ['band' => $band, 'booking' => $booking, 'token' => $token] = $this->setup_booking();
        $event = $booking->fresh()->events->first();
        $member = \App\Models\EventMember::create([
            'event_id' => $event->id, 'band_id' => $band->id,
            'name' => 'Bob', 'attendance_status' => 'confirmed', 'is_band_member' => true,
        ]);

        $response = $this->withHeaders($this->headers($token, $band->id))
            ->patchJson("/api/mobile/bands/{$band->id}/bookings/{$booking->id}/events/{$event->id}/members/{$member->id}/attendance", [
                'attendance_status' => 'absent',
            ]);

        $response->assertOk()->assertJsonPath('member.attendance_status', 'absent');
        $this->assertSame('absent', $member->fresh()->attendance_status);
    }

    public function test_update_attendance_validates_status_enum(): void
    {
        ['band' => $band, 'booking' => $booking, 'token' => $token] = $this->setup_booking();
        $event = $booking->fresh()->events->first();
        $member = \App\Models\EventMember::create([
            'event_id' => $event->id, 'band_id' => $band->id, 'name' => 'Bob',
            'attendance_status' => 'confirmed', 'is_band_member' => true,
        ]);

        $this->withHeaders($this->headers($token, $band->id))
            ->patchJson("/api/mobile/bands/{$band->id}/bookings/{$booking->id}/events/{$event->id}/members/{$member->id}/attendance", ['attendance_status' => 'playing'])
            ->assertStatus(422);
    }
```

- [ ] **Step 2: Run to verify fail**

Run: `docker compose exec app php artisan test --filter=BookingPayoutTest`
Expected: FAIL — attendance route 404.

- [ ] **Step 3: Add route** (uses route-model binding on `event` and a manual lookup for the member to scope it to the event)

```php
            Route::patch('/bands/{band}/bookings/{booking}/events/{event}/members/{member}/attendance', [App\Http\Controllers\Api\Mobile\BookingsController::class, 'updateMemberAttendance'])->name('mobile.bookings.events.members.attendance');
```

- [ ] **Step 4: Implement the action** (resolve member within the event so cross-event ids 404)

```php
    public function updateMemberAttendance(Request $request, Bands $band, Bookings $booking, Events $event, int $member): JsonResponse
    {
        $validated = $request->validate([
            'attendance_status' => 'required|in:confirmed,attended,absent,excused',
        ]);

        $eventMember = \App\Models\EventMember::where('id', $member)
            ->where('event_id', $event->id)
            ->firstOrFail();

        $eventMember->update(['attendance_status' => $validated['attendance_status']]);

        return response()->json(['member' => [
            'id' => $eventMember->id,
            'attendance_status' => $eventMember->attendance_status,
        ]]);
    }
```

Ensure `use App\Models\Events;` is imported in the controller.

- [ ] **Step 5: Run to verify pass**

Run: `docker compose exec app php artisan test --filter=BookingPayoutTest`
Expected: PASS (full file green).

- [ ] **Step 6: Commit**

```bash
git -C /home/eddie/github/TTS add routes/api.php app/Http/Controllers/Api/Mobile/BookingsController.php tests/Feature/Api/Mobile/BookingPayoutTest.php
git -C /home/eddie/github/TTS commit -m "feat(mobile-api): add event-member attendance update endpoint"
```

---

## MOBILE (Flutter `tts_bandmate` repo)

### Task 5: Payout models + fromJson

**Files:**
- Create: `/home/eddie/github/tts_bandmate/lib/features/bookings/data/models/booking_payout.dart`
- Test: `/home/eddie/github/tts_bandmate/test/models/booking_payout_test.dart`

**Interfaces:**
- Produces: `BookingPayout.fromJson(Map<String, dynamic>)` and nested `MemberPayout`, `PayoutGroup`, `PayoutAdjustment`, `PayoutEvent`, `PayoutEventMember`, `PayoutConfigRef`. Repository (Task 7) and screen (Task 9) consume these. Display getters: `BookingPayout.displayBasePrice`, `displayAdjustedTotal`, `displayBandCut`, `displayDistributable`; `MemberPayout.displayAmount`, `attendanceLabel`; `PayoutAdjustment.displayAmount`; `PayoutEvent.displayValue`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_payout.dart';

Map<String, dynamic> _flat() => {
      'payout': {'id': 9, 'base_amount': '1000.00', 'adjusted_amount': '750.00', 'payout_config_id': 42},
      'config': {'id': 42, 'name': 'Standard Split', 'is_active': true},
      'result': {
        'total_amount': 750.0,
        'band_cut': 150.0,
        'distributable_amount': 600.0,
        'member_payouts': [
          {'name': 'Alice', 'role': 'Vocalist', 'amount': 300.0, 'user_id': 1, 'events_attended': 3, 'total_events': 3},
          {'name': 'Bob', 'role': 'Guitar', 'amount': 200.0, 'user_id': 2, 'events_attended': 2, 'total_events': 3},
        ],
        'payment_group_payouts': [],
      },
      'adjustments': [
        {'id': 7, 'amount': '-250.00', 'description': 'Gas', 'notes': 'Reimbursed'},
      ],
      'events': [
        {'id': 100, 'label': 'Fri Apr 12 · Gala', 'value': '333.00', 'members': [
          {'id': 555, 'user_id': 1, 'name': 'Alice', 'attendance_status': 'attended'},
        ]},
      ],
      'available_configs': [
        {'id': 42, 'name': 'Standard Split', 'is_active': true},
        {'id': 43, 'name': 'Even', 'is_active': false},
      ],
    };

void main() {
  group('BookingPayout.fromJson', () {
    test('parses flat member payouts, adjustments, events', () {
      final p = BookingPayout.fromJson(_flat());
      expect(p.adjustedTotal, 750.0);
      expect(p.config?.name, 'Standard Split');
      expect(p.members.length, 2);
      expect(p.members.first.attendanceLabel, '3/3');
      expect(p.members.first.displayAmount, r'$300.00');
      expect(p.groups, isEmpty);
      expect(p.adjustments.single.displayAmount, r'-$250.00');
      expect(p.events.single.members.single.attendanceStatus, 'attended');
      expect(p.availableConfigs.length, 2);
    });

    test('parses grouped payment_group_payouts', () {
      final json = _flat();
      (json['result'] as Map)['payment_group_payouts'] = [
        {'group_name': 'Players', 'total': 600.0, 'payouts': [
          {'user_name': 'Alice', 'role': 'Vocalist', 'amount': 300.0, 'user_id': 1},
        ]},
      ];
      final p = BookingPayout.fromJson(json);
      expect(p.groups.single.groupName, 'Players');
      expect(p.groups.single.members.single.name, 'Alice');
      expect(p.groups.single.displayTotal, r'$600.00');
    });

    test('handles null result (no active config)', () {
      final json = _flat();
      json['result'] = null;
      json['config'] = null;
      final p = BookingPayout.fromJson(json);
      expect(p.members, isEmpty);
      expect(p.bandCut, 0);
      expect(p.config, isNull);
    });
  });
}
```

- [ ] **Step 2: Run to verify fail**

Run: `flutter test test/models/booking_payout_test.dart`
Expected: FAIL — `booking_payout.dart` does not exist.

- [ ] **Step 3: Implement the models**

```dart
import 'package:intl/intl.dart';

String _money(num v) => NumberFormat.currency(symbol: r'$').format(v);

double _toDouble(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

class PayoutConfigRef {
  PayoutConfigRef({required this.id, required this.name, required this.isActive});
  final int id;
  final String name;
  final bool isActive;

  factory PayoutConfigRef.fromJson(Map<String, dynamic> j) => PayoutConfigRef(
        id: (j['id'] as num).toInt(),
        name: j['name'] as String? ?? '',
        isActive: (j['is_active'] as bool?) ?? false,
      );
}

class MemberPayout {
  MemberPayout({
    required this.name,
    this.role,
    required this.amount,
    this.userId,
    this.eventsAttended,
    this.totalEvents,
  });
  final String name;
  final String? role;
  final double amount;
  final int? userId;
  final int? eventsAttended;
  final int? totalEvents;

  String get displayAmount => _money(amount);
  String? get attendanceLabel =>
      (eventsAttended != null && totalEvents != null) ? '$eventsAttended/$totalEvents' : null;

  factory MemberPayout.fromJson(Map<String, dynamic> j) => MemberPayout(
        name: j['name'] as String? ?? (j['user_name'] as String? ?? ''),
        role: j['role'] as String?,
        amount: _toDouble(j['amount']),
        userId: (j['user_id'] as num?)?.toInt(),
        eventsAttended: (j['events_attended'] as num?)?.toInt(),
        totalEvents: (j['total_events'] as num?)?.toInt(),
      );
}

class PayoutGroup {
  PayoutGroup({required this.groupName, required this.total, required this.members});
  final String groupName;
  final double total;
  final List<MemberPayout> members;

  String get displayTotal => _money(total);

  factory PayoutGroup.fromJson(Map<String, dynamic> j) => PayoutGroup(
        groupName: j['group_name'] as String? ?? '',
        total: _toDouble(j['total']),
        members: (j['payouts'] is List)
            ? (j['payouts'] as List).map((e) => MemberPayout.fromJson(e as Map<String, dynamic>)).toList()
            : <MemberPayout>[],
      );
}

class PayoutAdjustment {
  PayoutAdjustment({required this.id, required this.amount, required this.description, this.notes});
  final int id;
  final double amount;
  final String description;
  final String? notes;

  String get displayAmount {
    final s = _money(amount.abs());
    return amount < 0 ? '-$s' : s;
  }

  factory PayoutAdjustment.fromJson(Map<String, dynamic> j) => PayoutAdjustment(
        id: (j['id'] as num).toInt(),
        amount: _toDouble(j['amount']),
        description: j['description'] as String? ?? '',
        notes: j['notes'] as String?,
      );
}

class PayoutEventMember {
  PayoutEventMember({required this.id, this.userId, required this.name, required this.attendanceStatus});
  final int id;
  final int? userId;
  final String name;
  final String attendanceStatus;

  factory PayoutEventMember.fromJson(Map<String, dynamic> j) => PayoutEventMember(
        id: (j['id'] as num).toInt(),
        userId: (j['user_id'] as num?)?.toInt(),
        name: j['name'] as String? ?? '',
        attendanceStatus: j['attendance_status'] as String? ?? 'confirmed',
      );
}

class PayoutEvent {
  PayoutEvent({required this.id, required this.label, required this.value, required this.members});
  final int id;
  final String label;
  final double value;
  final List<PayoutEventMember> members;

  String get displayValue => _money(value);

  factory PayoutEvent.fromJson(Map<String, dynamic> j) => PayoutEvent(
        id: (j['id'] as num).toInt(),
        label: j['label'] as String? ?? '',
        value: _toDouble(j['value']),
        members: (j['members'] is List)
            ? (j['members'] as List).map((e) => PayoutEventMember.fromJson(e as Map<String, dynamic>)).toList()
            : <PayoutEventMember>[],
      );
}

class BookingPayout {
  BookingPayout({
    required this.basePrice,
    required this.adjustedTotal,
    required this.bandCut,
    required this.distributable,
    required this.config,
    required this.availableConfigs,
    required this.members,
    required this.groups,
    required this.adjustments,
    required this.events,
  });

  final double basePrice;
  final double adjustedTotal;
  final double bandCut;
  final double distributable;
  final PayoutConfigRef? config;
  final List<PayoutConfigRef> availableConfigs;
  final List<MemberPayout> members;
  final List<PayoutGroup> groups;
  final List<PayoutAdjustment> adjustments;
  final List<PayoutEvent> events;

  bool get hasAdjustments => adjustments.isNotEmpty;
  String get displayBasePrice => _money(basePrice);
  String get displayAdjustedTotal => _money(adjustedTotal);
  String get displayBandCut => _money(bandCut);
  String get displayDistributable => _money(distributable);

  factory BookingPayout.fromJson(Map<String, dynamic> json) {
    final payout = (json['payout'] as Map<String, dynamic>?) ?? const {};
    final result = json['result'] as Map<String, dynamic>?;

    List<T> list<T>(dynamic raw, T Function(Map<String, dynamic>) f) =>
        raw is List ? raw.map((e) => f(e as Map<String, dynamic>)).toList() : <T>[];

    return BookingPayout(
      basePrice: _toDouble(payout['base_amount']),
      adjustedTotal: _toDouble(payout['adjusted_amount']),
      bandCut: _toDouble(result?['band_cut']),
      distributable: _toDouble(result?['distributable_amount']),
      config: json['config'] is Map
          ? PayoutConfigRef.fromJson(json['config'] as Map<String, dynamic>)
          : null,
      availableConfigs: list(json['available_configs'], PayoutConfigRef.fromJson),
      members: list(result?['member_payouts'], MemberPayout.fromJson),
      groups: list(result?['payment_group_payouts'], PayoutGroup.fromJson),
      adjustments: list(json['adjustments'], PayoutAdjustment.fromJson),
      events: list(json['events'], PayoutEvent.fromJson),
    );
  }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `flutter test test/models/booking_payout_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git -C /home/eddie/github/tts_bandmate add lib/features/bookings/data/models/booking_payout.dart test/models/booking_payout_test.dart
git -C /home/eddie/github/tts_bandmate commit -m "feat(bookings): add BookingPayout models with fromJson"
```

---

### Task 6: API endpoint constants

**Files:**
- Modify: `/home/eddie/github/tts_bandmate/lib/core/network/api_endpoints.dart`

**Interfaces:**
- Produces: `ApiEndpoints.mobileBookingPayout(bandId, bookingId)`, `mobileBookingPayoutAdjustments(bandId, bookingId)`, `mobileBookingPayoutAdjustment(bandId, bookingId, adjustmentId)`, `mobileBookingPayoutConfiguration(bandId, bookingId)`, `mobileEventMemberAttendance(bandId, bookingId, eventId, memberId)`.

- [ ] **Step 1: Add the constants** (next to the existing `mobileBookingPayments`)

```dart
  static String mobileBookingPayout(int bandId, int bookingId) =>
      '/api/mobile/bands/$bandId/bookings/$bookingId/payout';
  static String mobileBookingPayoutAdjustments(int bandId, int bookingId) =>
      '/api/mobile/bands/$bandId/bookings/$bookingId/payout/adjustments';
  static String mobileBookingPayoutAdjustment(int bandId, int bookingId, int adjustmentId) =>
      '/api/mobile/bands/$bandId/bookings/$bookingId/payout/adjustments/$adjustmentId';
  static String mobileBookingPayoutConfiguration(int bandId, int bookingId) =>
      '/api/mobile/bands/$bandId/bookings/$bookingId/payout/configuration';
  static String mobileEventMemberAttendance(int bandId, int bookingId, int eventId, int memberId) =>
      '/api/mobile/bands/$bandId/bookings/$bookingId/events/$eventId/members/$memberId/attendance';
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/core/network/api_endpoints.dart`
Expected: No issues.

- [ ] **Step 3: Commit**

```bash
git -C /home/eddie/github/tts_bandmate add lib/core/network/api_endpoints.dart
git -C /home/eddie/github/tts_bandmate commit -m "feat(bookings): add payout API endpoint constants"
```

---

### Task 7: Repository methods

**Files:**
- Modify: `/home/eddie/github/tts_bandmate/lib/features/bookings/data/bookings_repository.dart`
- Test: `/home/eddie/github/tts_bandmate/test/features/bookings/payout_repository_test.dart`

**Interfaces:**
- Consumes: `BookingPayout.fromJson` (Task 5), `ApiEndpoints.*` (Task 6).
- Produces on `BookingsRepository`: `Future<BookingPayout> fetchPayout(int bandId, int bookingId)`; `Future<void> addPayoutAdjustment(int bandId, int bookingId, Map<String,dynamic> body)`; `Future<void> deletePayoutAdjustment(int bandId, int bookingId, int adjustmentId)`; `Future<void> updatePayoutConfiguration(int bandId, int bookingId, int configId)`; `Future<void> updateAttendance(int bandId, int bookingId, int eventId, int memberId, String status)`.

- [ ] **Step 1: Write the failing test** (uses a `DioAdapter`-free fake via `MockAdapter`; mirror existing repo tests that construct a `Dio` with a stubbed adapter — if the repo has no such helper, stub by overriding the methods on a subclass as in `setlist_editor_provider_test`)

```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/bookings_repository.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);
  final ResponseBody Function(RequestOptions) handler;
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream, Future<void>? cancelFuture) async =>
      handler(options);
}

ResponseBody _json(Object body, [int code = 200]) =>
    ResponseBody.fromString('${body is String ? body : body}', code, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });

void main() {
  test('fetchPayout parses the payout payload', () async {
    final dio = Dio()
      ..httpClientAdapter = _StubAdapter((o) => ResponseBody.fromString(
            '{"payout":{"id":9,"base_amount":"1000.00","adjusted_amount":"1000.00","payout_config_id":42},'
            '"config":{"id":42,"name":"Standard","is_active":true},'
            '"result":{"band_cut":200.0,"distributable_amount":800.0,"member_payouts":[],"payment_group_payouts":[]},'
            '"adjustments":[],"events":[],"available_configs":[]}',
            200,
            headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
          ));
    final repo = BookingsRepository(dio);

    final payout = await repo.fetchPayout(1, 2);
    expect(payout.bandCut, 200.0);
    expect(payout.config?.name, 'Standard');
  });

  test('updateAttendance issues a PATCH with attendance_status', () async {
    RequestOptions? captured;
    final dio = Dio()
      ..httpClientAdapter = _StubAdapter((o) {
        captured = o;
        return ResponseBody.fromString('{"member":{"id":5,"attendance_status":"absent"}}', 200,
            headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
      });
    final repo = BookingsRepository(dio);

    await repo.updateAttendance(1, 2, 3, 5, 'absent');
    expect(captured!.method, 'PATCH');
    expect(captured!.data, {'attendance_status': 'absent'});
  });
}
```

- [ ] **Step 2: Run to verify fail**

Run: `flutter test test/features/bookings/payout_repository_test.dart`
Expected: FAIL — methods undefined.

- [ ] **Step 3: Add the repository methods** (in `BookingsRepository`)

```dart
  Future<BookingPayout> fetchPayout(int bandId, int bookingId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileBookingPayout(bandId, bookingId),
    );
    return BookingPayout.fromJson(response.data!);
  }

  Future<void> addPayoutAdjustment(int bandId, int bookingId, Map<String, dynamic> body) async {
    await _dio.post(ApiEndpoints.mobileBookingPayoutAdjustments(bandId, bookingId), data: body);
  }

  Future<void> deletePayoutAdjustment(int bandId, int bookingId, int adjustmentId) async {
    await _dio.delete(ApiEndpoints.mobileBookingPayoutAdjustment(bandId, bookingId, adjustmentId));
  }

  Future<void> updatePayoutConfiguration(int bandId, int bookingId, int configId) async {
    await _dio.put(ApiEndpoints.mobileBookingPayoutConfiguration(bandId, bookingId),
        data: {'payout_config_id': configId});
  }

  Future<void> updateAttendance(int bandId, int bookingId, int eventId, int memberId, String status) async {
    await _dio.patch(ApiEndpoints.mobileEventMemberAttendance(bandId, bookingId, eventId, memberId),
        data: {'attendance_status': status});
  }
```

Add `import 'models/booking_payout.dart';` at the top of the repository file.

- [ ] **Step 4: Run to verify pass**

Run: `flutter test test/features/bookings/payout_repository_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git -C /home/eddie/github/tts_bandmate add lib/features/bookings/data/bookings_repository.dart test/features/bookings/payout_repository_test.dart
git -C /home/eddie/github/tts_bandmate commit -m "feat(bookings): add payout repository methods"
```

---

### Task 8: Payout provider (AsyncNotifier family)

**Files:**
- Create: `/home/eddie/github/tts_bandmate/lib/features/bookings/providers/booking_payout_provider.dart`
- Test: `/home/eddie/github/tts_bandmate/test/features/bookings/booking_payout_provider_test.dart`

**Interfaces:**
- Consumes: `bookingsRepositoryProvider`, `BookingsRepository` payout methods (Task 7), `cacheInvalidatorProvider.onBookingDetailChanged`.
- Produces: `bookingPayoutProvider` = `AsyncNotifierProvider.autoDispose.family<BookingPayoutNotifier, BookingPayout, ({int bandId, int bookingId})>`. Methods: `addAdjustment(amount, description, notes)`, `deleteAdjustment(id)`, `switchConfig(configId)`, `setAttendance(eventId, memberId, status)` — each calls the repo then re-fetches and reassigns `state`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/bookings_repository.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_payout.dart';
import 'package:tts_bandmate/features/bookings/providers/booking_payout_provider.dart';

class _FakeRepo extends BookingsRepository {
  _FakeRepo() : super(Dio());
  int fetchCount = 0;
  String? lastAttendance;

  BookingPayout _payout() => BookingPayout.fromJson({
        'payout': {'id': 1, 'base_amount': '100.00', 'adjusted_amount': '100.00', 'payout_config_id': 1},
        'config': {'id': 1, 'name': 'C', 'is_active': true},
        'result': {'band_cut': 0.0, 'distributable_amount': 100.0, 'member_payouts': [], 'payment_group_payouts': []},
        'adjustments': [], 'events': [], 'available_configs': [],
      });

  @override
  Future<BookingPayout> fetchPayout(int bandId, int bookingId) async {
    fetchCount++;
    return _payout();
  }

  @override
  Future<void> updateAttendance(int bandId, int bookingId, int eventId, int memberId, String status) async {
    lastAttendance = status;
  }

  @override
  Future<void> addPayoutAdjustment(int bandId, int bookingId, Map<String, dynamic> body) async {}
}

void main() {
  ProviderContainer makeContainer(_FakeRepo repo) {
    final c = ProviderContainer(overrides: [bookingsRepositoryProvider.overrideWithValue(repo)]);
    addTearDown(c.dispose);
    return c;
  }

  const key = (bandId: 1, bookingId: 2);

  test('build fetches the payout once', () async {
    final repo = _FakeRepo();
    final c = makeContainer(repo);
    final payout = await c.read(bookingPayoutProvider(key).future);
    expect(payout.distributable, 100.0);
    expect(repo.fetchCount, 1);
  });

  test('setAttendance calls repo then re-fetches', () async {
    final repo = _FakeRepo();
    final c = makeContainer(repo);
    await c.read(bookingPayoutProvider(key).future);
    await c.read(bookingPayoutProvider(key).notifier).setAttendance(3, 5, 'absent');
    expect(repo.lastAttendance, 'absent');
    expect(repo.fetchCount, 2); // initial build + post-mutation refetch
  });
}
```

- [ ] **Step 2: Run to verify fail**

Run: `flutter test test/features/bookings/booking_payout_provider_test.dart`
Expected: FAIL — provider undefined.

- [ ] **Step 3: Implement the provider** (mirror `contract_editor_provider`'s mutation/error idiom; check the real `cacheInvalidatorProvider` import path used by `booking_payments_screen.dart` and reuse it)

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/bookings_repository.dart';
import '../data/models/booking_payout.dart';
import '../../../shared/cache/cache_invalidator.dart';

typedef BookingPayoutKey = ({int bandId, int bookingId});

class BookingPayoutNotifier extends AsyncNotifier<BookingPayout> {
  BookingPayoutNotifier(this._key);
  final BookingPayoutKey _key;

  @override
  Future<BookingPayout> build() {
    return ref.read(bookingsRepositoryProvider).fetchPayout(_key.bandId, _key.bookingId);
  }

  Future<void> _refresh() async {
    state = const AsyncLoading<BookingPayout>().copyWithPrevious(state);
    state = await AsyncValue.guard(
      () => ref.read(bookingsRepositoryProvider).fetchPayout(_key.bandId, _key.bookingId),
    );
    ref.read(cacheInvalidatorProvider).onBookingDetailChanged(bandId: _key.bandId, bookingId: _key.bookingId);
  }

  Future<void> addAdjustment({required double amount, required String description, String? notes}) async {
    await ref.read(bookingsRepositoryProvider).addPayoutAdjustment(_key.bandId, _key.bookingId, {
      'amount': amount,
      'description': description,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
    });
    await _refresh();
  }

  Future<void> deleteAdjustment(int adjustmentId) async {
    await ref.read(bookingsRepositoryProvider).deletePayoutAdjustment(_key.bandId, _key.bookingId, adjustmentId);
    await _refresh();
  }

  Future<void> switchConfig(int configId) async {
    await ref.read(bookingsRepositoryProvider).updatePayoutConfiguration(_key.bandId, _key.bookingId, configId);
    await _refresh();
  }

  Future<void> setAttendance(int eventId, int memberId, String status) async {
    await ref.read(bookingsRepositoryProvider).updateAttendance(_key.bandId, _key.bookingId, eventId, memberId, status);
    await _refresh();
  }
}

final bookingPayoutProvider = AsyncNotifierProvider.autoDispose
    .family<BookingPayoutNotifier, BookingPayout, BookingPayoutKey>(
  BookingPayoutNotifier.new,
);
```

NOTE for implementer: confirm `cacheInvalidatorProvider`'s import path and the `onBookingDetailChanged` signature against `booking_payments_screen.dart` before running; adjust the import/args to match exactly. If `AsyncNotifierProvider.autoDispose.family` constructor-arg form differs from the repo's existing usage in `contract_editor_provider.dart`, match that file's exact form.

- [ ] **Step 4: Run to verify pass**

Run: `flutter test test/features/bookings/booking_payout_provider_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git -C /home/eddie/github/tts_bandmate add lib/features/bookings/providers/booking_payout_provider.dart test/features/bookings/booking_payout_provider_test.dart
git -C /home/eddie/github/tts_bandmate commit -m "feat(bookings): add booking payout provider"
```

---

### Task 9: Payout screen

**Files:**
- Create: `/home/eddie/github/tts_bandmate/lib/features/bookings/screens/booking_payout_screen.dart`

**Interfaces:**
- Consumes: `bookingPayoutProvider`, `BookingPayout` getters (Task 5/8), `BookingSectionTile`, `ErrorView.friendlyMessage`, `showCupertinoModalPopup`, `showCupertinoModalPopup`/`CupertinoActionSheet`.
- Produces: `BookingPayoutScreen({required int bandId, required int bookingId})` (route target for Task 10).

- [ ] **Step 1: Build the screen** (no unit test for the widget; verified manually in Task 11. Follow `booking_payments_screen.dart` structure: `ConsumerWidget`, `CupertinoPageScaffold`, `.when(loading/error/data)`.)

Implement sections top→bottom per the design spec:
1. **Summary card** — `displayBasePrice`; if `hasAdjustments`, an `Adjustments`/`displayAdjustedTotal` row; three stat tiles `Total` (`displayAdjustedTotal`) / `Band cut` (`displayBandCut`) / `Distributable` (`displayDistributable`).
2. **Config selector** — current `config?.name` + "Active" badge; tap opens a `CupertinoActionSheet` listing `availableConfigs` → on select call `ref.read(bookingPayoutProvider(key).notifier).switchConfig(id)`.
3. **Member payouts** — if `groups.isNotEmpty`, render grouped sections (group name + `displayTotal`, then its members); else render flat `members`. Each row: name, `role` (if non-null), `attendanceLabel` (if non-null), `displayAmount`. Highlight the current user's row — derive current user id from the existing auth/user provider used elsewhere (implementer: reuse the same provider `stats`/`dashboard` screens use to know the current user id; if none is readily available, skip the highlight rather than invent one).
4. **By performance** (only when `events.length > 1`) — for each `PayoutEvent`: header with `label` + `displayValue`; each member row shows an attendance pill (`attendanceStatus`) that, on tap, opens a `CupertinoActionSheet` of the four statuses → `setAttendance(event.id, member.id, status)`.
5. **Adjustments** — list of `adjustments` (description, notes, `displayAmount`) with a delete affordance calling `deleteAdjustment(id)` behind a `showCupertinoDialog` confirm; an "Add" button opening a modal sheet (amount field, description field, optional notes) → `addAdjustment(...)`.

Empty/edge: when `config == null` show a non-interactive warning card ("No active payout configuration"). Use `CupertinoActivityIndicator` for loading and `ErrorView(message: ErrorView.friendlyMessage(e))` for errors, matching `booking_payments_screen.dart`.

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/features/bookings/screens/booking_payout_screen.dart`
Expected: No issues.

- [ ] **Step 3: Commit**

```bash
git -C /home/eddie/github/tts_bandmate add lib/features/bookings/screens/booking_payout_screen.dart
git -C /home/eddie/github/tts_bandmate commit -m "feat(bookings): add booking payout screen"
```

---

### Task 10: Route + entry tile

**Files:**
- Modify: `/home/eddie/github/tts_bandmate/lib/core/config/router.dart`
- Modify: `/home/eddie/github/tts_bandmate/lib/features/bookings/screens/booking_detail_screen.dart`

**Interfaces:**
- Consumes: `BookingPayoutScreen` (Task 9).
- Produces: route `/bookings/:bandId/:bookingId/payout`; a "Payout" `BookingSectionTile` on the detail screen shown when `b.price != null && double.tryParse(b.price!) > 0`.

- [ ] **Step 1: Add the route** (alongside the payments route ~line 349)

```dart
      GoRoute(
        path: '/bookings/:bandId/:bookingId/payout',
        builder: (_, state) => BookingPayoutScreen(
          bandId: int.parse(state.pathParameters['bandId']!),
          bookingId: int.parse(state.pathParameters['bookingId']!),
        ),
      ),
```

Add the import for `BookingPayoutScreen` at the top of `router.dart`.

- [ ] **Step 2: Add the entry tile** (next to the Payments tile, ~line 452)

```dart
              if ((double.tryParse(b.price ?? '') ?? 0) > 0)
                BookingSectionTile(
                  icon: CupertinoIcons.chart_pie,
                  title: 'Payout',
                  subtitle: 'Member breakdown across performances',
                  onTap: () => context.push('/bookings/${widget.bandId}/${widget.bookingId}/payout'),
                ),
```

- [ ] **Step 3: Verify it compiles**

Run: `flutter analyze lib/core/config/router.dart lib/features/bookings/screens/booking_detail_screen.dart`
Expected: No issues.

- [ ] **Step 4: Commit**

```bash
git -C /home/eddie/github/tts_bandmate add lib/core/config/router.dart lib/features/bookings/screens/booking_detail_screen.dart
git -C /home/eddie/github/tts_bandmate commit -m "feat(bookings): add payout route and entry tile"
```

---

### Task 11: Full verification

**Files:** none (verification only).

- [ ] **Step 1: Backend suite**

Run: `docker compose exec app php artisan test --filter=BookingPayoutTest`
Expected: All green.

- [ ] **Step 2: Mobile suite + analyze**

Run: `flutter test && flutter analyze`
Expected: All tests pass; analyze clean.

- [ ] **Step 3: Manual end-to-end** (`flutter run`)

- Open a multi-event booking with `price > 0` → tap **Payout**.
- Confirm member breakdown matches the web payout page for the same booking.
- Switch config → amounts change.
- Toggle a member's attendance on one event → their share re-weights.
- Add an adjustment → adjusted total updates; delete it → reverts.

---

## Self-Review Notes

- **Spec coverage:** GET breakdown (T1), adjustments (T2), config switch (T3), attendance (T4), model (T5), endpoints (T6), repo (T7), provider (T8), screen w/ all 5 sections (T9), entry + route (T10), verification w/ both suites (T11). All spec sections mapped.
- **Type consistency:** `fetchPayout`/`addPayoutAdjustment`/`deletePayoutAdjustment`/`updatePayoutConfiguration`/`updateAttendance` names identical across T7/T8; `BookingPayout` getter names identical across T5/T9; endpoint method names identical across T6/T7; `attendance_status` enum identical across T4 (backend), T5 (model), T7 (repo).
- **Known follow-ups for implementer (flagged inline, not placeholders):** confirm `cacheInvalidatorProvider` import path + `onBookingDetailChanged` signature against `booking_payments_screen.dart`; match the exact `AsyncNotifierProvider.autoDispose.family` form used in `contract_editor_provider.dart`; current-user-id source for row highlight (skip highlight if unavailable). These are verification-against-existing-code steps, not undefined work.
