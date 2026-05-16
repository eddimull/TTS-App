# Configurable Booking Deposit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the booking deposit configurable per booking — either a percent of the total price or an exact dollar amount — and surface it consistently across the Laravel backend, the Vue/Inertia web app, the Flutter mobile app, the contract PDF, the contact portal, and the automated payment reminder emails.

**Architecture:** Add `deposit_type` ∈ {percent, amount} and `deposit_value` decimal columns to the `bookings` table. Rewrite the existing `expected_deposit_amount` accessor on the `Bookings` model so all downstream consumers (PDF, mobile preview, reminders, portal) read the new computed value with no changes to their flow. Lock the deposit via FormRequest rule when the contract is signed (`contract.status === 'completed'`). Existing bookings are backfilled to `('percent', 50.00)`, preserving current behavior.

**Tech Stack:** Laravel 11 (PHP), Vue 3 + Inertia + Tailwind (web), Flutter + Riverpod (mobile), MySQL.

**Two repos:**
- `tts_bandmate/` — Flutter mobile app
- `TTS/` — Laravel backend + Vue/Inertia web

**Spec reference:** `tts_bandmate/docs/superpowers/specs/2026-05-13-configurable-deposit-design.md`

---

## File Structure

### Created
- `TTS/database/migrations/2026_05_13_000001_add_deposit_to_bookings.php`
- `TTS/app/Http/Requests/Rules/DepositNotLocked.php` (reusable validation rule)
- `tts_bandmate/lib/features/bookings/data/models/deposit.dart` (`DepositType` enum + resolved helper)
- `TTS/resources/js/composables/useDeposit.js`
- `TTS/tests/Feature/BookingContractPdfTest.php`

### Modified
- `TTS/app/Models/Bookings.php` — `$fillable`, casts, `getExpectedDepositAmountAttribute()`
- `TTS/app/Http/Requests/UpdateBookingsRequest.php` — web validation rules
- `TTS/app/Http/Requests/StoreBookingsRequest.php` — web validation rules
- `TTS/app/Http/Requests/Mobile/UpdateBookingRequest.php` — mobile validation rules
- `TTS/app/Http/Requests/Mobile/StoreBookingRequest.php` — mobile validation rules
- `TTS/app/Services/Mobile/BookingFormatter.php` — append the three new JSON fields
- `TTS/app/Http/Controllers/Contact/ContactPortalController.php` — append portal payload fields
- `TTS/app/Http/Controllers/BookingsController.php` — web Inertia booking response (`update`/`store` already pass through the model)
- `TTS/resources/views/pdf/bookingContract.blade.php`
- `TTS/resources/js/Pages/Bookings/Components/BookingForm.vue`
- `TTS/resources/js/Pages/Bookings/Components/EditableContractWYSIWYG.vue`
- `TTS/resources/js/Pages/Contact/Dashboard.vue`
- `TTS/resources/js/Pages/Contact/Payment.vue`
- `tts_bandmate/lib/features/bookings/data/models/booking_detail.dart`
- `tts_bandmate/lib/features/bookings/data/bookings_repository.dart` — `updateBooking` signature + payload
- `tts_bandmate/lib/features/bookings/screens/booking_form_screen.dart`
- `tts_bandmate/lib/features/bookings/widgets/contract/contract_fixed_header.dart`

### Tests
- `TTS/tests/Feature/BookingsControllerTest.php` — extend
- `TTS/tests/Unit/Models/BookingsTest.php` — create or extend
- `TTS/tests/Feature/PaymentReminderNotificationsTest.php` — extend
- `TTS/tests/Feature/ContactPortalControllerTest.php` — extend
- `TTS/tests/Feature/BookingContractPdfTest.php` — new
- `TTS/resources/js/tests/composables/useDeposit.test.js` — new
- `TTS/resources/js/tests/components/bookingform.test.js` — new (or extend if exists)
- `TTS/resources/js/tests/components/editablecontract.test.js` — new
- `tts_bandmate/test/features/bookings/data/booking_detail_test.dart` — extend or new
- `tts_bandmate/test/features/bookings/screens/booking_form_screen_deposit_test.dart` — new

---

## Conventions

- **TTS repo** is at `/home/eddie/github/TTS/`. PHP/artisan commands run via `docker compose exec app …`. (See memory: never run php on the host.)
- **tts_bandmate repo** is at `/home/eddie/github/tts_bandmate/`. Flutter commands run on the host.
- Commits are made in the repo whose files changed. Most tasks below modify one repo only; cross-repo tasks call this out.
- TDD: each task writes the failing test first, runs it to confirm failure, then makes it pass.

---

## Task 1: Backend — Migration adds deposit columns and backfills

**Files:**
- Create: `TTS/database/migrations/2026_05_13_000001_add_deposit_to_bookings.php`
- Test: `TTS/tests/Unit/Models/BookingsTest.php`

- [ ] **Step 1: Write the failing test**

If `TTS/tests/Unit/Models/BookingsTest.php` does not exist, create it with this content; if it does exist, append the test method.

```php
<?php

namespace Tests\Unit\Models;

use App\Models\Bookings;
use App\Models\Bands;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class BookingsTest extends TestCase
{
    use RefreshDatabase;

    /** @test */
    public function existing_bookings_default_to_50_percent_deposit_after_migration(): void
    {
        // BookingsFactory::definition() creates a Bands::factory()->withOwners()
        // for us — no manual band/owner setup needed for this assertion.
        $booking = Bookings::factory()->create(['price' => '1000.00']);

        $this->assertSame('percent', $booking->fresh()->deposit_type);
        $this->assertSame('50.00', (string) $booking->fresh()->deposit_value);
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `docker compose exec app php artisan test --filter=existing_bookings_default_to_50_percent_deposit_after_migration`
Expected: FAIL — column `deposit_type` does not exist.

- [ ] **Step 3: Write the migration**

Create `TTS/database/migrations/2026_05_13_000001_add_deposit_to_bookings.php`:

```php
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::table('bookings', function (Blueprint $table) {
            $table->string('deposit_type', 16)->default('percent')->after('price');
            $table->decimal('deposit_value', 10, 2)->default(50.00)->after('deposit_type');
        });

        DB::table('bookings')->update([
            'deposit_type'  => 'percent',
            'deposit_value' => 50.00,
        ]);
    }

    public function down(): void
    {
        Schema::table('bookings', function (Blueprint $table) {
            $table->dropColumn(['deposit_type', 'deposit_value']);
        });
    }
};
```

- [ ] **Step 4: Run the migration**

Run: `docker compose exec app php artisan migrate`
Expected: migration runs cleanly, ends with `2026_05_13_000001_add_deposit_to_bookings ........... DONE`.

- [ ] **Step 5: Run the test to verify it passes**

Run: `docker compose exec app php artisan test --filter=existing_bookings_default_to_50_percent_deposit_after_migration`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
cd /home/eddie/github/TTS
git add database/migrations/2026_05_13_000001_add_deposit_to_bookings.php tests/Unit/Models/BookingsTest.php
git commit -m "feat(bookings): add deposit_type and deposit_value columns

Backfills existing rows to ('percent', 50.00) — preserves current
hardcoded behavior for every existing booking."
```

---

## Task 2: Backend — Bookings model fillable, casts, and `expected_deposit_amount` rewrite

**Files:**
- Modify: `TTS/app/Models/Bookings.php`
- Test: `TTS/tests/Unit/Models/BookingsTest.php`

- [ ] **Step 1: Write the failing tests**

Append to `TTS/tests/Unit/Models/BookingsTest.php`, inside the class:

```php
/** @test */
public function expected_deposit_amount_uses_percent_mode(): void
{
    $booking = Bookings::factory()->create([
        'price'         => '1000.00',
        'deposit_type'  => 'percent',
        'deposit_value' => '25.00',
    ]);
    $this->assertSame('250.00', $booking->expected_deposit_amount);
}

/** @test */
public function expected_deposit_amount_uses_amount_mode(): void
{
    $booking = Bookings::factory()->create([
        'price'         => '1000.00',
        'deposit_type'  => 'amount',
        'deposit_value' => '300.00',
    ]);
    $this->assertSame('300.00', $booking->expected_deposit_amount);
}

/** @test */
public function expected_deposit_amount_returns_zero_when_price_is_null(): void
{
    $booking = Bookings::factory()->create([
        'price'         => null,
        'deposit_type'  => 'percent',
        'deposit_value' => '50.00',
    ]);
    $this->assertSame('0.00', $booking->expected_deposit_amount);
}

/** @test */
public function legacy_50_percent_default_produces_same_number_as_before(): void
{
    $booking = Bookings::factory()->create([
        'price'         => '800.00',
        'deposit_type'  => 'percent',
        'deposit_value' => '50.00',
    ]);
    $this->assertSame('400.00', $booking->expected_deposit_amount);
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `docker compose exec app php artisan test --filter=BookingsTest`
Expected: the four new tests FAIL (model doesn't yet allow `deposit_type`/`deposit_value` as fillable, accessor still hardcoded to 50%).

- [ ] **Step 3: Update the model**

In `TTS/app/Models/Bookings.php`:

1. Add `'deposit_type'` and `'deposit_value'` to the `$fillable` array (around line 36 where `'price'` already is).
2. Add the cast in `$casts` (around line 46):

```php
'deposit_value' => 'decimal:2',
```

3. Replace the body of `getExpectedDepositAmountAttribute()` (lines ~340–348):

```php
public function getExpectedDepositAmountAttribute(): string
{
    $price = is_string($this->price) ? floatval($this->price) : (float) $this->price;
    if ($price <= 0) {
        return '0.00';
    }
    if ($this->deposit_type === 'amount') {
        return number_format((float) $this->deposit_value, 2, '.', '');
    }
    $percent = (float) $this->deposit_value / 100;
    return number_format($price * $percent, 2, '.', '');
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `docker compose exec app php artisan test --filter=BookingsTest`
Expected: all four new tests PASS. The other deposit-related tests (`is_deposit_paid`, `deposit_due`, etc.) should also still pass — confirm with `docker compose exec app php artisan test --filter=Booking`.

- [ ] **Step 5: Commit**

```bash
cd /home/eddie/github/TTS
git add app/Models/Bookings.php tests/Unit/Models/BookingsTest.php
git commit -m "feat(bookings): compute expected_deposit_amount from deposit_type/value

Removes hardcoded 50% deposit. Percent and amount modes both work.
Returns 0.00 when price is null/0."
```

---

## Task 3: Backend — Reusable `DepositNotLocked` validation rule

**Files:**
- Create: `TTS/app/Http/Requests/Rules/DepositNotLocked.php`
- Test: `TTS/tests/Unit/Rules/DepositNotLockedTest.php`

- [ ] **Step 1: Write the failing test**

Create `TTS/tests/Unit/Rules/DepositNotLockedTest.php`:

```php
<?php

namespace Tests\Unit\Rules;

use App\Http\Requests\Rules\DepositNotLocked;
use App\Models\Bookings;
use App\Models\Contracts;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class DepositNotLockedTest extends TestCase
{
    use RefreshDatabase;

    /** @test */
    public function rule_passes_when_booking_has_no_contract(): void
    {
        $booking = Bookings::factory()->create();
        $rule = new DepositNotLocked($booking);
        $failed = false;
        $rule->validate('deposit_type', 'amount', function () use (&$failed) {
            $failed = true;
        });
        $this->assertFalse($failed);
    }

    /** @test */
    public function rule_passes_when_contract_is_unsigned(): void
    {
        $booking = Bookings::factory()->create();
        Contracts::factory()->create([
            'contractable_id'   => $booking->id,
            'contractable_type' => Bookings::class,
            'status'            => 'pending',
        ]);
        $booking->load('contract');
        $rule = new DepositNotLocked($booking);
        $failed = false;
        $rule->validate('deposit_type', 'amount', function () use (&$failed) {
            $failed = true;
        });
        $this->assertFalse($failed);
    }

    /** @test */
    public function rule_fails_when_contract_is_signed(): void
    {
        $booking = Bookings::factory()->create();
        Contracts::factory()->create([
            'contractable_id'   => $booking->id,
            'contractable_type' => Bookings::class,
            'status'            => 'completed',
        ]);
        $booking->load('contract');
        $rule = new DepositNotLocked($booking);
        $message = null;
        $rule->validate('deposit_type', 'amount', function ($m) use (&$message) {
            $message = $m;
        });
        $this->assertNotNull($message);
        $this->assertStringContainsString('locked', strtolower($message));
    }
}
```

> If `Contracts::factory()` doesn't exist, create the contract directly via `\App\Models\Contracts::create([...])` with whatever fields the table requires (check the contracts migration first). The factory pattern is preferred but not required.

- [ ] **Step 2: Run tests to verify they fail**

Run: `docker compose exec app php artisan test --filter=DepositNotLockedTest`
Expected: all three FAIL — class does not exist.

- [ ] **Step 3: Create the rule**

Create `TTS/app/Http/Requests/Rules/DepositNotLocked.php`:

```php
<?php

namespace App\Http\Requests\Rules;

use App\Models\Bookings;
use Closure;
use Illuminate\Contracts\Validation\ValidationRule;

class DepositNotLocked implements ValidationRule
{
    public function __construct(private ?Bookings $booking) {}

    public function validate(string $attribute, mixed $value, Closure $fail): void
    {
        if ($this->booking === null) {
            return;
        }
        if ($this->booking->contract_signed_date !== null) {
            $fail('Deposit is locked because the contract is signed.');
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `docker compose exec app php artisan test --filter=DepositNotLockedTest`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /home/eddie/github/TTS
git add app/Http/Requests/Rules/DepositNotLocked.php tests/Unit/Rules/DepositNotLockedTest.php
git commit -m "feat(bookings): DepositNotLocked validation rule

Rejects writes to deposit fields once contract.status === 'completed'."
```

---

## Task 4: Backend — Web FormRequest rules (`UpdateBookingsRequest` and `StoreBookingsRequest`)

**Files:**
- Modify: `TTS/app/Http/Requests/UpdateBookingsRequest.php`
- Modify: `TTS/app/Http/Requests/StoreBookingsRequest.php`
- Test: `TTS/tests/Feature/BookingsControllerTest.php`

- [ ] **Step 1: Write the failing tests**

Append to `TTS/tests/Feature/BookingsControllerTest.php` (inside the existing class — match the auth/setup pattern of existing tests):

```php
/** @test */
public function update_accepts_valid_deposit_percent(): void
{
    $owner = \App\Models\User::factory()->create();
    $band  = \App\Models\Bands::factory()->create(); $band->owners()->create(["user_id" => $owner->id]);
    $booking = \App\Models\Bookings::factory()->create(['band_id' => $band->id, 'price' => '1000.00']);

    $this->actingAs($owner)
        ->put(route('bookings.update', ['band' => $band->id, 'booking' => $booking->id]), [
            'name'            => $booking->name,
            'event_type_id'   => $booking->event_type_id,
            'price'           => '1000.00',
            'contract_option' => 'default',
            'deposit_type'    => 'percent',
            'deposit_value'   => '25',
        ])
        ->assertRedirect();

    $this->assertSame('percent', $booking->fresh()->deposit_type);
    $this->assertSame('25.00', (string) $booking->fresh()->deposit_value);
}

/** @test */
public function update_rejects_deposit_percent_above_100(): void
{
    $owner = \App\Models\User::factory()->create();
    $band  = \App\Models\Bands::factory()->create(); $band->owners()->create(["user_id" => $owner->id]);
    $booking = \App\Models\Bookings::factory()->create(['band_id' => $band->id, 'price' => '1000.00']);

    $this->actingAs($owner)
        ->put(route('bookings.update', ['band' => $band->id, 'booking' => $booking->id]), [
            'name'            => $booking->name,
            'event_type_id'   => $booking->event_type_id,
            'price'           => '1000.00',
            'contract_option' => 'default',
            'deposit_type'    => 'percent',
            'deposit_value'   => '125',
        ])
        ->assertSessionHasErrors('deposit_value');
}

/** @test */
public function update_rejects_deposit_amount_exceeding_price(): void
{
    $owner = \App\Models\User::factory()->create();
    $band  = \App\Models\Bands::factory()->create(); $band->owners()->create(["user_id" => $owner->id]);
    $booking = \App\Models\Bookings::factory()->create(['band_id' => $band->id, 'price' => '1000.00']);

    $this->actingAs($owner)
        ->put(route('bookings.update', ['band' => $band->id, 'booking' => $booking->id]), [
            'name'            => $booking->name,
            'event_type_id'   => $booking->event_type_id,
            'price'           => '1000.00',
            'contract_option' => 'default',
            'deposit_type'    => 'amount',
            'deposit_value'   => '1500',
        ])
        ->assertSessionHasErrors('deposit_value');
}

/** @test */
public function update_rejects_deposit_change_when_contract_is_signed(): void
{
    $owner = \App\Models\User::factory()->create();
    $band  = \App\Models\Bands::factory()->create(); $band->owners()->create(["user_id" => $owner->id]);
    $booking = \App\Models\Bookings::factory()->create(['band_id' => $band->id, 'price' => '1000.00']);
    \App\Models\Contracts::factory()->create([
        'contractable_id'   => $booking->id,
        'contractable_type' => \App\Models\Bookings::class,
        'status'            => 'completed',
    ]);

    $this->actingAs($owner)
        ->put(route('bookings.update', ['band' => $band->id, 'booking' => $booking->id]), [
            'name'            => $booking->name,
            'event_type_id'   => $booking->event_type_id,
            'price'           => '1000.00',
            'contract_option' => 'default',
            'deposit_type'    => 'amount',
            'deposit_value'   => '600',
        ])
        ->assertSessionHasErrors('deposit_type');
}
```

> If existing tests in the file use a `setUp()` to create the user/band, reuse that pattern instead of inlining. Match style.

- [ ] **Step 2: Run tests to verify they fail**

Run: `docker compose exec app php artisan test --filter=BookingsControllerTest`
Expected: the four new tests FAIL.

- [ ] **Step 3: Update `UpdateBookingsRequest`**

Replace the `rules()` method in `TTS/app/Http/Requests/UpdateBookingsRequest.php` with:

```php
public function rules()
{
    return [
        'name' => 'required|string|max:255',
        'author_id' => 'exclude',
        'event_type_id' => 'required|in:' . implode(',', EventTypes::all()->pluck('id')->toArray()),
        'date'          => 'prohibited',
        'start_time'    => 'prohibited',
        'end_time'      => 'prohibited',
        'price' => [
            'required',
            'regex:/^\d+(\.\d{1,2})?$/',
            'min:0',
            'decimal:0,2'
        ],
        'venue_name'    => 'prohibited',
        'venue_address' => 'prohibited',
        'contract_option' => 'required|in:default,none,external',
        'status' => 'nullable|in:draft,pending,confirmed,cancelled',
        'notes' => 'nullable|string',
        'deposit_type' => [
            'sometimes', 'required', 'in:percent,amount',
            new \App\Http\Requests\Rules\DepositNotLocked($this->route('booking')),
        ],
        'deposit_value' => [
            'sometimes', 'required', 'numeric', 'min:0',
            'regex:/^\d+(\.\d{1,2})?$/',
            new \App\Http\Requests\Rules\DepositNotLocked($this->route('booking')),
            function ($attribute, $value, $fail) {
                $type = $this->input('deposit_type');
                if ($type === 'percent' && (float) $value > 100) {
                    $fail('Deposit percent must be between 0 and 100.');
                }
                if ($type === 'amount' && (float) $value > (float) $this->input('price')) {
                    $fail('Deposit amount cannot exceed the booking price.');
                }
            },
        ],
    ];
}
```

> `$this->route('booking')` returns the `Bookings` model bound by route-model binding. If route binding isn't used here, swap for `\App\Models\Bookings::find($this->route('booking'))`.

- [ ] **Step 4: Update `StoreBookingsRequest`**

Open `TTS/app/Http/Requests/StoreBookingsRequest.php` and append the same two rules to its `rules()` method (Store has no locked booking, so pass `null`):

```php
'deposit_type'  => 'sometimes|required|in:percent,amount',
'deposit_value' => [
    'sometimes', 'required', 'numeric', 'min:0',
    'regex:/^\d+(\.\d{1,2})?$/',
    function ($attribute, $value, $fail) {
        $type = $this->input('deposit_type');
        if ($type === 'percent' && (float) $value > 100) {
            $fail('Deposit percent must be between 0 and 100.');
        }
        if ($type === 'amount' && (float) $value > (float) $this->input('price')) {
            $fail('Deposit amount cannot exceed the booking price.');
        }
    },
],
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `docker compose exec app php artisan test --filter=BookingsControllerTest`
Expected: all four new tests PASS. Re-run existing `BookingsControllerTest` tests as well — none should regress.

- [ ] **Step 6: Commit**

```bash
cd /home/eddie/github/TTS
git add app/Http/Requests/UpdateBookingsRequest.php app/Http/Requests/StoreBookingsRequest.php tests/Feature/BookingsControllerTest.php
git commit -m "feat(bookings): web FormRequest validation for deposit

Percent 0-100, amount <= price, lock once contract is signed."
```

---

## Task 5: Backend — Mobile FormRequest rules

**Files:**
- Modify: `TTS/app/Http/Requests/Mobile/UpdateBookingRequest.php`
- Modify: `TTS/app/Http/Requests/Mobile/StoreBookingRequest.php`
- Test: extend an appropriate mobile test file (or create `TTS/tests/Feature/Api/Mobile/BookingDepositTest.php`)

- [ ] **Step 1: Write the failing tests**

Find the existing mobile booking test file — `grep -rn "PATCH.*bookings\|api/mobile.*booking" TTS/tests` will show the pattern. If none focuses on update, create `TTS/tests/Feature/Api/Mobile/BookingDepositTest.php`:

```php
<?php

namespace Tests\Feature\Api\Mobile;

use App\Models\Bands;
use App\Models\Bookings;
use App\Models\Contracts;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class BookingDepositTest extends TestCase
{
    use RefreshDatabase;

    private function authedRequest(User $user, Bands $band): self
    {
        Sanctum::actingAs($user);
        return $this->withHeader('X-Band-ID', (string) $band->id);
    }

    /** @test */
    public function mobile_update_accepts_valid_deposit_amount(): void
    {
        $owner = User::factory()->create();
        $band  = Bands::factory()->create(); $band->owners()->create(["user_id" => $owner->id]);
        $booking = Bookings::factory()->create(['band_id' => $band->id, 'price' => '1000.00']);

        $this->authedRequest($owner, $band)
            ->patchJson("/api/mobile/bands/{$band->id}/bookings/{$booking->id}", [
                'deposit_type'  => 'amount',
                'deposit_value' => '450.00',
            ])
            ->assertOk();

        $this->assertSame('amount', $booking->fresh()->deposit_type);
        $this->assertSame('450.00', (string) $booking->fresh()->deposit_value);
    }

    /** @test */
    public function mobile_update_rejects_percent_above_100(): void
    {
        $owner = User::factory()->create();
        $band  = Bands::factory()->create(); $band->owners()->create(["user_id" => $owner->id]);
        $booking = Bookings::factory()->create(['band_id' => $band->id, 'price' => '1000.00']);

        $this->authedRequest($owner, $band)
            ->patchJson("/api/mobile/bands/{$band->id}/bookings/{$booking->id}", [
                'deposit_type'  => 'percent',
                'deposit_value' => '150',
            ])
            ->assertStatus(422)
            ->assertJsonValidationErrors('deposit_value');
    }

    /** @test */
    public function mobile_update_rejects_amount_above_price(): void
    {
        $owner = User::factory()->create();
        $band  = Bands::factory()->create(); $band->owners()->create(["user_id" => $owner->id]);
        $booking = Bookings::factory()->create(['band_id' => $band->id, 'price' => '1000.00']);

        $this->authedRequest($owner, $band)
            ->patchJson("/api/mobile/bands/{$band->id}/bookings/{$booking->id}", [
                'deposit_type'  => 'amount',
                'deposit_value' => '2000',
            ])
            ->assertStatus(422)
            ->assertJsonValidationErrors('deposit_value');
    }

    /** @test */
    public function mobile_update_rejects_deposit_when_contract_signed(): void
    {
        $owner = User::factory()->create();
        $band  = Bands::factory()->create(); $band->owners()->create(["user_id" => $owner->id]);
        $booking = Bookings::factory()->create(['band_id' => $band->id, 'price' => '1000.00']);
        Contracts::factory()->create([
            'contractable_id'   => $booking->id,
            'contractable_type' => Bookings::class,
            'status'            => 'completed',
        ]);

        $this->authedRequest($owner, $band)
            ->patchJson("/api/mobile/bands/{$band->id}/bookings/{$booking->id}", [
                'deposit_type'  => 'amount',
                'deposit_value' => '600',
            ])
            ->assertStatus(422)
            ->assertJsonValidationErrors('deposit_type');
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `docker compose exec app php artisan test --filter=BookingDepositTest`
Expected: FAIL — rules don't accept the new fields.

- [ ] **Step 3: Update mobile FormRequest rules**

In `TTS/app/Http/Requests/Mobile/UpdateBookingRequest.php`, add to the returned array:

```php
'deposit_type' => [
    'sometimes', 'required', 'in:percent,amount',
    new \App\Http\Requests\Rules\DepositNotLocked($this->route('booking')),
],
'deposit_value' => [
    'sometimes', 'required', 'numeric', 'min:0',
    new \App\Http\Requests\Rules\DepositNotLocked($this->route('booking')),
    function ($attribute, $value, $fail) {
        $type  = $this->input('deposit_type');
        $price = $this->input('price') ?? optional($this->route('booking'))->price;
        if ($type === 'percent' && (float) $value > 100) {
            $fail('Deposit percent must be between 0 and 100.');
        }
        if ($type === 'amount' && (float) $value > (float) $price) {
            $fail('Deposit amount cannot exceed the booking price.');
        }
    },
],
```

In `TTS/app/Http/Requests/Mobile/StoreBookingRequest.php`, append the same two rules but without the `DepositNotLocked` rule (no existing booking to lock against).

- [ ] **Step 4: Run tests to verify they pass**

Run: `docker compose exec app php artisan test --filter=BookingDepositTest`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /home/eddie/github/TTS
git add app/Http/Requests/Mobile/UpdateBookingRequest.php app/Http/Requests/Mobile/StoreBookingRequest.php tests/Feature/Api/Mobile/BookingDepositTest.php
git commit -m "feat(bookings): mobile FormRequest validation for deposit

Same rules as web. Lock applies once contract is signed."
```

---

## Task 6: Backend — Append deposit fields to mobile API formatter

**Files:**
- Modify: `TTS/app/Services/Mobile/BookingFormatter.php`
- Test: `TTS/tests/Feature/Api/Mobile/BookingDepositTest.php`

- [ ] **Step 1: Write the failing test**

Append to the test class created in Task 5:

```php
/** @test */
public function mobile_booking_show_response_includes_deposit_fields(): void
{
    $owner = User::factory()->create();
    $band  = Bands::factory()->create(); $band->owners()->create(["user_id" => $owner->id]);
    $booking = Bookings::factory()->create([
        'band_id'       => $band->id,
        'price'         => '1000.00',
        'deposit_type'  => 'percent',
        'deposit_value' => '30.00',
    ]);

    $response = $this->authedRequest($owner, $band)
        ->getJson("/api/mobile/bands/{$band->id}/bookings/{$booking->id}")
        ->assertOk();

    $response->assertJsonPath('booking.deposit_type', 'percent');
    $response->assertJsonPath('booking.deposit_value', '30.00');
    $response->assertJsonPath('booking.expected_deposit_amount', '300.00');
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `docker compose exec app php artisan test --filter=mobile_booking_show_response_includes_deposit_fields`
Expected: FAIL — keys missing.

- [ ] **Step 3: Update the formatter**

In `TTS/app/Services/Mobile/BookingFormatter.php`, inside the `$base = [...]` array (after the `'amount_due'` line, around line 28), insert:

```php
'deposit_type'             => $booking->deposit_type,
'deposit_value'            => (string) $booking->deposit_value,
'expected_deposit_amount'  => (string) $booking->expected_deposit_amount,
```

- [ ] **Step 4: Run test to verify it passes**

Run: `docker compose exec app php artisan test --filter=mobile_booking_show_response_includes_deposit_fields`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /home/eddie/github/TTS
git add app/Services/Mobile/BookingFormatter.php tests/Feature/Api/Mobile/BookingDepositTest.php
git commit -m "feat(bookings/api): expose deposit fields in mobile booking payload"
```

---

## Task 7: Backend — Update contract PDF Blade template

**Files:**
- Modify: `TTS/resources/views/pdf/bookingContract.blade.php`
- Create: `TTS/tests/Feature/BookingContractPdfTest.php`

- [ ] **Step 1: Write the failing test**

Create `TTS/tests/Feature/BookingContractPdfTest.php`:

```php
<?php

namespace Tests\Feature;

use App\Models\Bands;
use App\Models\Bookings;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class BookingContractPdfTest extends TestCase
{
    use RefreshDatabase;

    /** @test */
    public function rendered_contract_view_uses_configurable_deposit(): void
    {
        $owner = User::factory()->create();
        $band  = Bands::factory()->create([
            'address'  => '123 Main',
            'city'     => 'New Orleans',
            'state'    => 'LA',
            'zip'      => '70112',
        ]);
        $band->owners()->create(['user_id' => $owner->id]);
        $booking = Bookings::factory()->create([
            'band_id'       => $band->id,
            'price'         => '1000.00',
            'deposit_type'  => 'amount',
            'deposit_value' => '250.00',
        ]);

        $rendered = view('pdf.bookingContract', [
            'booking'     => $booking,
            'logoDataUri' => 'data:image/png;base64,',
            'signer'      => null,
        ])->render();

        $this->assertStringContainsString('$250.00', $rendered);
        // Remaining balance = price - deposit = 1000 - 250 = 750
        $this->assertStringContainsString('$750.00', $rendered);
        // Should NOT print the old 50% number anymore for these inputs
        $this->assertStringNotContainsString('$500.00', $rendered);
    }

    /** @test */
    public function rendered_contract_view_uses_percent_mode_correctly(): void
    {
        $owner = User::factory()->create();
        $band  = Bands::factory()->create([
            'address'  => '123 Main', 'city' => 'NOLA', 'state' => 'LA', 'zip' => '70112',
        ]);
        $band->owners()->create(['user_id' => $owner->id]);
        $booking = Bookings::factory()->create([
            'band_id'       => $band->id,
            'price'         => '2000.00',
            'deposit_type'  => 'percent',
            'deposit_value' => '25.00',
        ]);

        $rendered = view('pdf.bookingContract', [
            'booking'     => $booking,
            'logoDataUri' => 'data:image/png;base64,',
            'signer'      => null,
        ])->render();

        $this->assertStringContainsString('$500.00', $rendered);   // 25% of 2000
        $this->assertStringContainsString('$1,500.00', $rendered); // remainder
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `docker compose exec app php artisan test --filter=BookingContractPdfTest`
Expected: FAIL — Blade still uses `price / 2`.

- [ ] **Step 3: Update the Blade template**

In `TTS/resources/views/pdf/bookingContract.blade.php` line 64:

Replace:
```blade
${{ number_format($booking->price/2,2) }}
```
With:
```blade
${{ number_format((float) $booking->expected_deposit_amount, 2) }}
```

Find the matching "remaining gross compensation" line (similar `$booking->price/2` usage on a later line) and replace it with:
```blade
${{ number_format((float) $booking->price - (float) $booking->expected_deposit_amount, 2) }}
```

> If you only find one `$booking->price/2` in the Blade, check whether the second money line uses a different expression — search with `grep -n "price" TTS/resources/views/pdf/bookingContract.blade.php` and replace any "half price" computation.

- [ ] **Step 4: Run tests to verify they pass**

Run: `docker compose exec app php artisan test --filter=BookingContractPdfTest`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /home/eddie/github/TTS
git add resources/views/pdf/bookingContract.blade.php tests/Feature/BookingContractPdfTest.php
git commit -m "feat(contracts/pdf): use configurable deposit in contract template"
```

---

## Task 8: Backend — Web `BookingsController` Inertia response carries deposit fields

The web booking endpoint already returns the full Booking model to Inertia via `$booking->load(...)` patterns. Confirm the model serializes the new columns; the `Bookings` model defaults to including all fillable attributes. Inertia uses array casting from the model's `toArray()`, so the new columns appear automatically. The accessor `expected_deposit_amount` is NOT in `$appends`, so it must be explicitly added.

**Files:**
- Modify: `TTS/app/Models/Bookings.php`
- Test: extend `BookingsControllerTest.php`

- [ ] **Step 1: Write the failing test**

Append to `TTS/tests/Feature/BookingsControllerTest.php`:

```php
/** @test */
public function inertia_booking_response_includes_expected_deposit_amount(): void
{
    $owner = \App\Models\User::factory()->create();
    $band  = \App\Models\Bands::factory()->create(); $band->owners()->create(["user_id" => $owner->id]);
    $booking = \App\Models\Bookings::factory()->create([
        'band_id'       => $band->id,
        'price'         => '1000.00',
        'deposit_type'  => 'percent',
        'deposit_value' => '40.00',
    ]);

    $array = $booking->fresh()->append('expected_deposit_amount')->toArray();
    $this->assertSame('400.00', $array['expected_deposit_amount']);
    $this->assertSame('percent', $array['deposit_type']);
    $this->assertSame('40.00', (string) $array['deposit_value']);
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `docker compose exec app php artisan test --filter=inertia_booking_response_includes_expected_deposit_amount`
Expected: FAIL or pass with `expected_deposit_amount` missing.

- [ ] **Step 3: Append `expected_deposit_amount` to the model's `$appends`**

In `TTS/app/Models/Bookings.php`, find the `$appends` array (if it doesn't exist, add it near `$fillable`):

```php
protected $appends = [
    // ...existing entries...
    'expected_deposit_amount',
];
```

If existing entries like `amount_paid`, `amount_due` are already appended, add `expected_deposit_amount` alongside them. If `$appends` doesn't exist, grep for `protected $appends` first; if truly absent, only add it if needed for the Inertia response — first check the test output to see whether the field is missing.

- [ ] **Step 4: Run test to verify it passes**

Run: `docker compose exec app php artisan test --filter=inertia_booking_response_includes_expected_deposit_amount`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /home/eddie/github/TTS
git add app/Models/Bookings.php tests/Feature/BookingsControllerTest.php
git commit -m "feat(bookings): append expected_deposit_amount for Inertia responses"
```

---

## Task 9: Backend — Contact Portal payload includes deposit fields

**Files:**
- Modify: `TTS/app/Http/Controllers/Contact/ContactPortalController.php`
- Test: `TTS/tests/Feature/ContactPortalControllerTest.php`

- [ ] **Step 1: Write the failing test**

Append to `TTS/tests/Feature/ContactPortalControllerTest.php` (match existing auth/setup pattern — the file already has working test scaffolding):

```php
/** @test */
public function portal_dashboard_includes_deposit_fields_for_signed_booking(): void
{
    // Reuse helper from setUp() to make booking + contact + signed contract.
    // If no helper exists, inline the factory calls following existing tests' pattern.
    $contact = $this->makeContactWithBooking([
        'price'         => '1000.00',
        'deposit_type'  => 'amount',
        'deposit_value' => '400.00',
    ], contractStatus: 'completed');

    $this->actingAsContact($contact)
        ->get(route('portal.dashboard'))
        ->assertInertia(fn ($page) => $page
            ->where('bookings.0.expected_deposit_amount', '400.00')
            ->where('bookings.0.is_deposit_paid', false)
            ->whereNot('bookings.0.deposit_due_date', null)
        );
}

/** @test */
public function portal_dashboard_deposit_due_date_is_null_when_contract_unsigned(): void
{
    $contact = $this->makeContactWithBooking([
        'price'         => '1000.00',
        'deposit_type'  => 'percent',
        'deposit_value' => '50.00',
    ]); // no contract

    $this->actingAsContact($contact)
        ->get(route('portal.dashboard'))
        ->assertInertia(fn ($page) => $page
            ->where('bookings.0.deposit_due_date', null)
        );
}

/** @test */
public function portal_payment_page_includes_deposit_fields(): void
{
    $contact = $this->makeContactWithBooking([
        'price'         => '1000.00',
        'deposit_type'  => 'percent',
        'deposit_value' => '25.00',
    ], contractStatus: 'completed');

    $booking = $contact->bookings()->first();

    $this->actingAsContact($contact)
        ->get(route('portal.booking.payment', $booking->id))
        ->assertInertia(fn ($page) => $page
            ->where('booking.expected_deposit_amount', '250.00')
            ->where('booking.is_deposit_paid', false)
            ->whereNot('booking.deposit_due_date', null)
        );
}
```

> If helpers like `makeContactWithBooking` and `actingAsContact` don't exist in the test class, look at the existing tests in the file for how they set up a contact + booking and inline that. The test patterns above describe the *behavior* — adapt the setup style.

- [ ] **Step 2: Run tests to verify they fail**

Run: `docker compose exec app php artisan test --filter=ContactPortalControllerTest`
Expected: the three new tests FAIL.

- [ ] **Step 3: Update the controller payload**

In `TTS/app/Http/Controllers/Contact/ContactPortalController.php`:

In the `index()` method's per-booking mapping (around lines 140–177), inside the returned array, add **after** `'amount_due'`:

```php
'expected_deposit_amount' => (string) $booking->expected_deposit_amount,
'is_deposit_paid'         => (bool) $booking->is_deposit_paid,
'deposit_due_date'        => $booking->deposit_due_date?->format('M j, Y'),
```

In the `showPayment()` method's `booking` payload (around lines 204–214), inside the array, add **after** `'amount_due'`:

```php
'expected_deposit_amount' => (string) $booking->expected_deposit_amount,
'is_deposit_paid'         => (bool) $booking->is_deposit_paid,
'deposit_due_date'        => $booking->deposit_due_date?->format('M j, Y'),
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `docker compose exec app php artisan test --filter=ContactPortalControllerTest`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /home/eddie/github/TTS
git add app/Http/Controllers/Contact/ContactPortalController.php tests/Feature/ContactPortalControllerTest.php
git commit -m "feat(portal): expose deposit amount and due date to contact portal"
```

---

## Task 10: Backend — Verify deposit reminder uses resolved amount

**Files:**
- Test: `TTS/tests/Feature/PaymentReminderNotificationsTest.php`

This is verification only — no code change is expected. The `DepositPaymentReminder` notification reads `$booking->deposit_due`, which routes through `expected_deposit_amount`, which we already rewrote in Task 2.

- [ ] **Step 1: Add coverage for both modes**

Append to `TTS/tests/Feature/PaymentReminderNotificationsTest.php` (match existing notification test patterns):

```php
/** @test */
public function deposit_reminder_renders_resolved_amount_for_percent_mode(): void
{
    $booking = \App\Models\Bookings::factory()->create([
        'price'         => '1200.00',
        'deposit_type'  => 'percent',
        'deposit_value' => '20.00',
    ]);

    $notification = new \App\Notifications\DepositPaymentReminder($booking);
    $array = $notification->toArray($booking->contacts->first() ?? new \App\Models\BookingContacts());

    $this->assertSame('240.00', $array['deposit_due']);
}

/** @test */
public function deposit_reminder_renders_resolved_amount_for_amount_mode(): void
{
    $booking = \App\Models\Bookings::factory()->create([
        'price'         => '1200.00',
        'deposit_type'  => 'amount',
        'deposit_value' => '350.00',
    ]);

    $notification = new \App\Notifications\DepositPaymentReminder($booking);
    $array = $notification->toArray($booking->contacts->first() ?? new \App\Models\BookingContacts());

    $this->assertSame('350.00', $array['deposit_due']);
}
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `docker compose exec app php artisan test --filter=PaymentReminderNotificationsTest`
Expected: PASS without any code changes (the model accessor already routes correctly).

- [ ] **Step 3: Commit**

```bash
cd /home/eddie/github/TTS
git add tests/Feature/PaymentReminderNotificationsTest.php
git commit -m "test(reminders): cover deposit reminder for percent and amount modes"
```

---

## Task 11: Web — `useDeposit` composable

**Files:**
- Create: `TTS/resources/js/composables/useDeposit.js`
- Test: `TTS/resources/js/tests/composables/useDeposit.test.js`

- [ ] **Step 1: Write the failing test**

Create `TTS/resources/js/tests/composables/useDeposit.test.js`:

```javascript
import { describe, it, expect } from 'vitest';
import { ref } from 'vue';
import { useDeposit } from '../../composables/useDeposit';

describe('useDeposit', () => {
  it('prefers backend expected_deposit_amount when present', () => {
    const booking = ref({
      price: '1000.00',
      deposit_type: 'percent',
      deposit_value: '50.00',
      expected_deposit_amount: '500.00',
    });
    const { depositAmount, remainingAmount } = useDeposit(booking);
    expect(depositAmount.value).toBe('500.00');
    expect(remainingAmount.value).toBe('500.00');
  });

  it('computes percent client-side when expected_deposit_amount missing', () => {
    const booking = ref({
      price: '1000.00',
      deposit_type: 'percent',
      deposit_value: '25.00',
    });
    const { depositAmount, remainingAmount } = useDeposit(booking);
    expect(depositAmount.value).toBe('250.00');
    expect(remainingAmount.value).toBe('750.00');
  });

  it('computes amount client-side when expected_deposit_amount missing', () => {
    const booking = ref({
      price: '1000.00',
      deposit_type: 'amount',
      deposit_value: '300.00',
    });
    const { depositAmount, remainingAmount } = useDeposit(booking);
    expect(depositAmount.value).toBe('300.00');
    expect(remainingAmount.value).toBe('700.00');
  });

  it('returns 0.00 when price is empty or zero', () => {
    const booking = ref({
      price: '0',
      deposit_type: 'percent',
      deposit_value: '50.00',
    });
    const { depositAmount, remainingAmount } = useDeposit(booking);
    expect(depositAmount.value).toBe('0.00');
    expect(remainingAmount.value).toBe('0.00');
  });

  it('reactively updates when booking ref changes', () => {
    const booking = ref({
      price: '1000.00',
      deposit_type: 'percent',
      deposit_value: '50.00',
    });
    const { depositAmount } = useDeposit(booking);
    expect(depositAmount.value).toBe('500.00');
    booking.value = { ...booking.value, deposit_value: '25.00' };
    expect(depositAmount.value).toBe('250.00');
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /home/eddie/github/TTS && npx vitest run resources/js/tests/composables/useDeposit.test.js`
Expected: FAIL — module not found.

- [ ] **Step 3: Create the composable**

Create `TTS/resources/js/composables/useDeposit.js`:

```javascript
import { computed } from 'vue';

const fmt = (n) => Number(n).toFixed(2);

export function useDeposit(bookingRef) {
  const depositAmount = computed(() => {
    const b = bookingRef.value || {};
    const price = parseFloat(b.price) || 0;
    if (price <= 0) return '0.00';

    if (b.expected_deposit_amount !== undefined && b.expected_deposit_amount !== null) {
      return fmt(b.expected_deposit_amount);
    }
    const value = parseFloat(b.deposit_value) || 0;
    if (b.deposit_type === 'amount') {
      return fmt(value);
    }
    return fmt(price * (value / 100));
  });

  const remainingAmount = computed(() => {
    const b = bookingRef.value || {};
    const price = parseFloat(b.price) || 0;
    return fmt(price - parseFloat(depositAmount.value));
  });

  return { depositAmount, remainingAmount };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /home/eddie/github/TTS && npx vitest run resources/js/tests/composables/useDeposit.test.js`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /home/eddie/github/TTS
git add resources/js/composables/useDeposit.js resources/js/tests/composables/useDeposit.test.js
git commit -m "feat(web): useDeposit composable

Returns { depositAmount, remainingAmount }. Prefers the backend
expected_deposit_amount; falls back to client-side computation."
```

---

## Task 12: Web — `EditableContractWYSIWYG.vue` uses configurable deposit

**Files:**
- Modify: `TTS/resources/js/Pages/Bookings/Components/EditableContractWYSIWYG.vue`
- Test: `TTS/resources/js/tests/components/editablecontract.test.js`

- [ ] **Step 1: Write the failing test**

Create `TTS/resources/js/tests/components/editablecontract.test.js`:

```javascript
import { describe, it, expect } from 'vitest';
import { mount } from '@vue/test-utils';
import EditableContractWYSIWYG from '../../Pages/Bookings/Components/EditableContractWYSIWYG.vue';

const baseBand = { name: 'Test Band', address: '123 Main', city: 'NOLA', state: 'LA', zip: '70112' };
const baseBooking = (overrides = {}) => ({
  price: '1000.00',
  deposit_type: 'percent',
  deposit_value: '50.00',
  expected_deposit_amount: '500.00',
  name: 'Test',
  ...overrides,
});

describe('EditableContractWYSIWYG deposit', () => {
  it('renders the resolved deposit and remaining-balance numbers', () => {
    const wrapper = mount(EditableContractWYSIWYG, {
      props: { booking: baseBooking(), band: baseBand },
    });
    const html = wrapper.html();
    expect(html).toContain('$500.00');
    // Remaining = 1000 - 500
    expect(html.match(/\$500\.00/g).length).toBeGreaterThanOrEqual(2);
  });

  it('reflects amount mode correctly', () => {
    const wrapper = mount(EditableContractWYSIWYG, {
      props: {
        booking: baseBooking({
          deposit_type: 'amount',
          deposit_value: '300.00',
          expected_deposit_amount: '300.00',
        }),
        band: baseBand,
      },
    });
    const html = wrapper.html();
    expect(html).toContain('$300.00');
    expect(html).toContain('$700.00'); // remaining
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /home/eddie/github/TTS && npx vitest run resources/js/tests/components/editablecontract.test.js`
Expected: FAIL — component still prints `price / 2 = 500.00` for both modes (the percent test may pass by coincidence; the amount test will fail).

- [ ] **Step 3: Update `EditableContractWYSIWYG.vue`**

At the top of the `<script setup>` block, import the composable and create the toRef:

```javascript
import { toRef } from 'vue';
import { useDeposit } from '@/composables/useDeposit';
// existing imports...

const props = defineProps({ booking: Object, band: Object });
const bookingRef = toRef(props, 'booking');
const { depositAmount, remainingAmount } = useDeposit(bookingRef);
```

In the template, replace both occurrences of `${{ (booking.price / 2).toFixed(2) }}`:
- Deposit line (around line 107): `${{ depositAmount }}`
- Remaining-balance line (around line 120): `${{ remainingAmount }}`

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /home/eddie/github/TTS && npx vitest run resources/js/tests/components/editablecontract.test.js`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /home/eddie/github/TTS
git add resources/js/Pages/Bookings/Components/EditableContractWYSIWYG.vue resources/js/tests/components/editablecontract.test.js
git commit -m "feat(web/contracts): use configurable deposit in WYSIWYG editor"
```

---

## Task 13: Web — `BookingForm.vue` deposit input

**Files:**
- Modify: `TTS/resources/js/Pages/Bookings/Components/BookingForm.vue`
- Test: `TTS/resources/js/tests/components/bookingform.test.js`

- [ ] **Step 1: Write the failing tests**

Create `TTS/resources/js/tests/components/bookingform.test.js`:

```javascript
import { describe, it, expect } from 'vitest';
import { mount } from '@vue/test-utils';
import BookingForm from '../../Pages/Bookings/Components/BookingForm.vue';

const baseProps = (overrides = {}) => ({
  booking: {
    id: 1,
    name: 'Test',
    price: '1000.00',
    deposit_type: 'percent',
    deposit_value: '50.00',
    expected_deposit_amount: '500.00',
    contract_option: 'default',
    contract: null,
    event_type_id: 1,
    notes: '',
    ...overrides.booking,
  },
  eventTypes: [{ id: 1, name: 'Wedding' }],
  ...overrides,
});

describe('BookingForm deposit', () => {
  it('renders the deposit field with computed counterpart', () => {
    const wrapper = mount(BookingForm, { props: baseProps() });
    const html = wrapper.html();
    expect(html).toContain('Deposit');
    // Computed counterpart visible
    expect(html).toMatch(/\$500\.00|= \$500/);
  });

  it('clears the deposit value when toggling modes', async () => {
    const wrapper = mount(BookingForm, { props: baseProps() });
    const depositInput = wrapper.find('[data-test="deposit-value-input"]');
    expect(depositInput.element.value).toBe('50.00');

    const amountToggle = wrapper.find('[data-test="deposit-mode-amount"]');
    await amountToggle.trigger('click');
    expect(depositInput.element.value).toBe('');
  });

  it('disables deposit inputs when contract is signed', () => {
    const wrapper = mount(BookingForm, {
      props: baseProps({ booking: { contract: { status: 'completed' } } }),
    });
    expect(wrapper.find('[data-test="deposit-value-input"]').attributes('disabled')).toBeDefined();
    expect(wrapper.find('[data-test="deposit-mode-percent"]').attributes('disabled')).toBeDefined();
    expect(wrapper.html()).toContain('Locked');
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /home/eddie/github/TTS && npx vitest run resources/js/tests/components/bookingform.test.js`
Expected: FAIL — no deposit fields in the form yet.

- [ ] **Step 3: Update `BookingForm.vue`**

This adds the deposit field group below the price input. The existing file uses `form.price` and a Tailwind layout. Add (style to match the surrounding fields):

In `<script setup>`:

```javascript
// Add to existing props/setup
const isContractSigned = computed(() => props.booking.contract?.status === 'completed');

const setDepositMode = (mode) => {
  if (form.deposit_type === mode) return;
  form.deposit_type = mode;
  form.deposit_value = '';
};

const computedDepositCounterpart = computed(() => {
  const price = parseFloat(form.price) || 0;
  const value = parseFloat(form.deposit_value) || 0;
  if (price <= 0) return null;
  if (form.deposit_type === 'percent') {
    return `= $${(price * value / 100).toFixed(2)}`;
  }
  if (value > 0) {
    return `= ${(value / price * 100).toFixed(1)}%`;
  }
  return null;
});

const depositError = computed(() => {
  const value = parseFloat(form.deposit_value);
  if (isNaN(value)) return null;
  if (form.deposit_type === 'percent' && value > 100) return 'Percent must be between 0 and 100.';
  if (form.deposit_type === 'amount' && value > parseFloat(form.price)) return 'Deposit cannot exceed the booking price.';
  return null;
});
```

Update `form` initializer (around line 195) to include:
```javascript
deposit_type:  props.booking.deposit_type || 'percent',
deposit_value: props.booking.deposit_value || '50.00',
```

In `<template>`, immediately below the Price input block (around line 44), add:

```html
<div class="mb-4">
  <label class="block text-sm font-medium text-gray-700">Deposit</label>
  <div class="mt-1 flex">
    <input
      data-test="deposit-value-input"
      v-model="form.deposit_value"
      type="number"
      step="0.01"
      :disabled="isContractSigned || (form.deposit_type === 'percent' && (!form.price || form.price === '0'))"
      class="block w-full rounded-l border-gray-300"
    />
    <div class="inline-flex" role="group">
      <button
        type="button"
        data-test="deposit-mode-amount"
        :disabled="isContractSigned"
        :aria-pressed="form.deposit_type === 'amount'"
        @click="setDepositMode('amount')"
        :class="form.deposit_type === 'amount' ? 'bg-indigo-600 text-white' : 'bg-white text-gray-700'"
        class="border border-gray-300 px-3"
      >$</button>
      <button
        type="button"
        data-test="deposit-mode-percent"
        :disabled="isContractSigned || !form.price || form.price === '0'"
        :aria-pressed="form.deposit_type === 'percent'"
        @click="setDepositMode('percent')"
        :class="form.deposit_type === 'percent' ? 'bg-indigo-600 text-white' : 'bg-white text-gray-700'"
        class="border border-l-0 border-gray-300 rounded-r px-3"
      >%</button>
    </div>
  </div>
  <p v-if="isContractSigned" class="mt-1 text-sm text-gray-500">Locked — contract is signed.</p>
  <p v-else-if="form.deposit_type === 'percent' && (!form.price || form.price === '0')" class="mt-1 text-sm text-gray-500">Enter a price above to use percent.</p>
  <p v-else-if="computedDepositCounterpart" class="mt-1 text-sm text-gray-500">{{ computedDepositCounterpart }}</p>
  <p v-if="depositError" class="mt-1 text-sm text-red-600">{{ depositError }}</p>
</div>
```

Update the submit handler (around line 320) to include `deposit_type` and `deposit_value` in the submitted payload alongside `price`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /home/eddie/github/TTS && npx vitest run resources/js/tests/components/bookingform.test.js`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /home/eddie/github/TTS
git add resources/js/Pages/Bookings/Components/BookingForm.vue resources/js/tests/components/bookingform.test.js
git commit -m "feat(web/bookings): configurable deposit field on booking form

Single numeric input with \$/% toggle. Clears on mode switch.
Disabled when contract is signed or when price is 0 in percent mode.
Shows computed counterpart inline."
```

---

## Task 14: Web — Contact portal Dashboard + Payment pages display deposit info

**Files:**
- Modify: `TTS/resources/js/Pages/Contact/Dashboard.vue`
- Modify: `TTS/resources/js/Pages/Contact/Payment.vue`

The backend (Task 9) already supplies `expected_deposit_amount`, `is_deposit_paid`, `deposit_due_date`. This task is presentation only.

- [ ] **Step 1: Read existing structure**

Read both files to find where the booking summary is rendered (`booking.amount_due`, `booking.price` are good landmarks).

```bash
grep -n "amount_due\|amount_paid\|deposit" TTS/resources/js/Pages/Contact/Dashboard.vue TTS/resources/js/Pages/Contact/Payment.vue
```

- [ ] **Step 2: Add a `DepositLine.vue` shared component**

Create `TTS/resources/js/Pages/Contact/Components/DepositLine.vue`:

```vue
<template>
  <div v-if="depositDueDate" class="text-sm">
    <template v-if="isDepositPaid">
      <span class="text-green-700 font-medium">Deposit paid</span>
    </template>
    <template v-else>
      Deposit of <span class="font-semibold">${{ Number(amount).toFixed(2) }}</span>
      due <span class="font-semibold">{{ depositDueDate }}</span>
    </template>
  </div>
</template>

<script setup>
defineProps({
  amount: { type: [String, Number], required: true },
  isDepositPaid: { type: Boolean, required: true },
  depositDueDate: { type: String, default: null },
});
</script>
```

- [ ] **Step 3: Use it in Dashboard.vue**

Inside each booking card's summary area (find where `booking.amount_due` is rendered and insert nearby), add:

```html
<DepositLine
  :amount="booking.expected_deposit_amount"
  :is-deposit-paid="booking.is_deposit_paid"
  :deposit-due-date="booking.deposit_due_date"
/>
```

Import the component at the top of `<script setup>`:
```javascript
import DepositLine from './Components/DepositLine.vue';
```

- [ ] **Step 4: Use it in Payment.vue**

In the booking-summary section of `Pages/Contact/Payment.vue` (around line 96, after the `amount_due` row), insert the same `<DepositLine>` block and import.

- [ ] **Step 5: Add a smoke test**

Create `TTS/resources/js/tests/components/depositline.test.js`:

```javascript
import { describe, it, expect } from 'vitest';
import { mount } from '@vue/test-utils';
import DepositLine from '../../Pages/Contact/Components/DepositLine.vue';

describe('DepositLine', () => {
  it('renders nothing when depositDueDate is null', () => {
    const wrapper = mount(DepositLine, {
      props: { amount: '500.00', isDepositPaid: false, depositDueDate: null },
    });
    expect(wrapper.html().trim()).toBe('<!--v-if-->');
  });

  it('renders amount and due date when unpaid', () => {
    const wrapper = mount(DepositLine, {
      props: { amount: '500.00', isDepositPaid: false, depositDueDate: 'Jun 3, 2026' },
    });
    const html = wrapper.html();
    expect(html).toContain('$500.00');
    expect(html).toContain('Jun 3, 2026');
  });

  it('renders "Deposit paid" when paid', () => {
    const wrapper = mount(DepositLine, {
      props: { amount: '500.00', isDepositPaid: true, depositDueDate: 'Jun 3, 2026' },
    });
    expect(wrapper.html()).toContain('Deposit paid');
  });
});
```

- [ ] **Step 6: Run tests and verify**

Run: `cd /home/eddie/github/TTS && npx vitest run resources/js/tests/components/depositline.test.js`
Expected: PASS.

Also run the existing portal tests to make sure nothing broke:
`docker compose exec app php artisan test --filter=ContactPortalControllerTest`

- [ ] **Step 7: Commit**

```bash
cd /home/eddie/github/TTS
git add resources/js/Pages/Contact/Components/DepositLine.vue \
       resources/js/Pages/Contact/Dashboard.vue \
       resources/js/Pages/Contact/Payment.vue \
       resources/js/tests/components/depositline.test.js
git commit -m "feat(portal): show deposit amount and due date

Dashboard cards and the payment page now display the deposit value
and the 3-weeks-after-signing due date. Customer never sees the
percent/amount mode toggle — only the resolved dollar amount."
```

---

## Task 15: Mobile — `BookingDetail` model parses deposit fields

**Files:**
- Modify: `tts_bandmate/lib/features/bookings/data/models/booking_detail.dart`
- Test: `tts_bandmate/test/features/bookings/data/booking_detail_test.dart`

- [ ] **Step 1: Write the failing test**

Either extend an existing `booking_detail_test.dart` or create one:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_detail.dart';

void main() {
  group('BookingDetail.fromJson deposit fields', () {
    test('parses depositType, depositValue, expectedDepositAmount', () {
      final detail = BookingDetail.fromJson({
        'id': 1,
        'name': 'Test',
        'start_date': '2026-06-01',
        'end_date': '2026-06-01',
        'event_count': 1,
        'is_multi_event': false,
        'is_paid': false,
        'contacts': [],
        'events': [],
        'payments': [],
        'price': '1000.00',
        'deposit_type': 'amount',
        'deposit_value': '250.00',
        'expected_deposit_amount': '250.00',
      });

      expect(detail.depositType, 'amount');
      expect(detail.depositValue, '250.00');
      expect(detail.expectedDepositAmount, '250.00');
    });

    test('falls back to "percent" / "50.00" when fields absent (legacy responses)', () {
      final detail = BookingDetail.fromJson({
        'id': 1,
        'name': 'Test',
        'start_date': '2026-06-01',
        'end_date': '2026-06-01',
        'event_count': 1,
        'is_multi_event': false,
        'is_paid': false,
        'contacts': [],
        'events': [],
        'payments': [],
        'price': '1000.00',
      });

      expect(detail.depositType, 'percent');
      expect(detail.depositValue, '50.00');
      expect(detail.expectedDepositAmount, null);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /home/eddie/github/tts_bandmate && flutter test test/features/bookings/data/booking_detail_test.dart`
Expected: FAIL — fields don't exist on `BookingDetail`.

- [ ] **Step 3: Update `BookingDetail`**

In `tts_bandmate/lib/features/bookings/data/models/booking_detail.dart`:

1. Add to the constructor:

```dart
this.depositType = 'percent',
this.depositValue = '50.00',
this.expectedDepositAmount,
```

2. Add the fields:

```dart
/// 'percent' or 'amount'. Defaults to 'percent' for legacy responses.
final String depositType;

/// Raw value: 0-100 for percent mode, 0+ for amount mode.
final String depositValue;

/// Resolved dollar amount as a formatted string ("250.00"). Computed by
/// the backend from depositType + depositValue + price. Null on legacy
/// responses that pre-date the deposit-config feature.
final String? expectedDepositAmount;
```

3. In `fromJson`, parse the three new fields:

```dart
final depositType = (json['deposit_type'] as String?) ?? 'percent';
final depositValue = json['deposit_value']?.toString() ?? '50.00';
final expectedDepositAmount = json['expected_deposit_amount']?.toString();
```

And include them in the constructor call.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /home/eddie/github/tts_bandmate && flutter test test/features/bookings/data/booking_detail_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /home/eddie/github/tts_bandmate
git add lib/features/bookings/data/models/booking_detail.dart test/features/bookings/data/booking_detail_test.dart
git commit -m "feat(mobile/bookings): parse deposit fields in BookingDetail

Defaults to ('percent', '50.00') when fields are absent in legacy
backend responses."
```

---

## Task 16: Mobile — `Deposit` resolver and `DepositType` enum

**Files:**
- Create: `tts_bandmate/lib/features/bookings/data/models/deposit.dart`
- Test: `tts_bandmate/test/features/bookings/data/deposit_test.dart`

- [ ] **Step 1: Write the failing test**

Create `tts_bandmate/test/features/bookings/data/deposit_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_detail.dart';
import 'package:tts_bandmate/features/bookings/data/models/deposit.dart';

void main() {
  group('Deposit.resolve', () {
    test('prefers backend expectedDepositAmount when present', () {
      final resolved = Deposit.resolve(_booking(
        price: '1000.00',
        depositType: 'percent',
        depositValue: '50.00',
        expectedDepositAmount: '500.00',
      ));
      expect(resolved.depositAmount, '500.00');
      expect(resolved.remainingAmount, '500.00');
    });

    test('computes percent client-side when expectedDepositAmount absent', () {
      final resolved = Deposit.resolve(_booking(
        price: '1000.00',
        depositType: 'percent',
        depositValue: '25.00',
        expectedDepositAmount: null,
      ));
      expect(resolved.depositAmount, '250.00');
      expect(resolved.remainingAmount, '750.00');
    });

    test('computes amount client-side when expectedDepositAmount absent', () {
      final resolved = Deposit.resolve(_booking(
        price: '1000.00',
        depositType: 'amount',
        depositValue: '300.00',
        expectedDepositAmount: null,
      ));
      expect(resolved.depositAmount, '300.00');
      expect(resolved.remainingAmount, '700.00');
    });

    test('returns 0.00 when price is null or zero', () {
      final resolved = Deposit.resolve(_booking(
        price: null,
        depositType: 'percent',
        depositValue: '50.00',
      ));
      expect(resolved.depositAmount, '0.00');
      expect(resolved.remainingAmount, '0.00');
    });
  });
}

BookingDetail _booking({
  String? price,
  String depositType = 'percent',
  String depositValue = '50.00',
  String? expectedDepositAmount,
}) =>
    BookingDetail.fromJson({
      'id': 1,
      'name': 'Test',
      'start_date': '2026-06-01',
      'end_date': '2026-06-01',
      'event_count': 1,
      'is_multi_event': false,
      'is_paid': false,
      'contacts': [],
      'events': [],
      'payments': [],
      'price': price,
      'deposit_type': depositType,
      'deposit_value': depositValue,
      if (expectedDepositAmount != null)
        'expected_deposit_amount': expectedDepositAmount,
    });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /home/eddie/github/tts_bandmate && flutter test test/features/bookings/data/deposit_test.dart`
Expected: FAIL — `deposit.dart` doesn't exist.

- [ ] **Step 3: Create the resolver**

Create `tts_bandmate/lib/features/bookings/data/models/deposit.dart`:

```dart
import 'booking_detail.dart';

enum DepositType { percent, amount }

class ResolvedDeposit {
  const ResolvedDeposit({
    required this.depositAmount,
    required this.remainingAmount,
  });

  final String depositAmount;
  final String remainingAmount;
}

class Deposit {
  static ResolvedDeposit resolve(BookingDetail booking) {
    final price = double.tryParse(booking.price ?? '') ?? 0;
    if (price <= 0) {
      return const ResolvedDeposit(depositAmount: '0.00', remainingAmount: '0.00');
    }

    double depositDollars;
    if (booking.expectedDepositAmount != null) {
      depositDollars = double.tryParse(booking.expectedDepositAmount!) ?? 0;
    } else {
      final value = double.tryParse(booking.depositValue) ?? 0;
      depositDollars = booking.depositType == 'amount'
          ? value
          : price * (value / 100);
    }

    return ResolvedDeposit(
      depositAmount: depositDollars.toStringAsFixed(2),
      remainingAmount: (price - depositDollars).toStringAsFixed(2),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /home/eddie/github/tts_bandmate && flutter test test/features/bookings/data/deposit_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /home/eddie/github/tts_bandmate
git add lib/features/bookings/data/models/deposit.dart test/features/bookings/data/deposit_test.dart
git commit -m "feat(mobile/bookings): Deposit resolver helper

Returns { depositAmount, remainingAmount }. Prefers backend
expectedDepositAmount; falls back to client-side computation."
```

---

## Task 17: Mobile — `contract_fixed_header.dart` uses configurable deposit

**Files:**
- Modify: `tts_bandmate/lib/features/bookings/widgets/contract/contract_fixed_header.dart`

- [ ] **Step 1: Read the current implementation**

```bash
grep -n "_halfPrice\|_parsePrice\|deposit" /home/eddie/github/tts_bandmate/lib/features/bookings/widgets/contract/contract_fixed_header.dart
```

Note both deposit (line ~230) and remaining-balance (line ~259) uses of `_halfPrice`.

- [ ] **Step 2: Replace `_halfPrice` with `Deposit.resolve(...)`**

In `contract_fixed_header.dart`:

1. Add import:
```dart
import '../../data/models/deposit.dart';
```

2. Delete the `_parsePrice()` helper and `_halfPrice` getter.

3. Inside the build method (or wherever `_halfPrice` was referenced), compute:
```dart
final resolved = Deposit.resolve(booking);
```

4. Replace `\$$_halfPrice` at line ~230 with `\$${resolved.depositAmount}`.
5. Replace `\$$_halfPrice` at line ~259 with `\$${resolved.remainingAmount}`.

- [ ] **Step 3: Visual check**

Run the app:
```bash
cd /home/eddie/github/tts_bandmate
flutter run -d linux --dart-define=BASE_URL=http://localhost:8715
```

Open a booking with a contract. Verify the deposit and remaining-balance numbers in the contract header reflect the new configurable values (use a fresh seeded booking with `deposit_type='amount'`, `deposit_value='300.00'`, `price='1000.00'` to verify both sides).

If you can't easily seed that — confirm the existing 50% bookings still render `$500.00` for a $1000 price.

- [ ] **Step 4: Commit**

```bash
cd /home/eddie/github/tts_bandmate
git add lib/features/bookings/widgets/contract/contract_fixed_header.dart
git commit -m "feat(mobile/bookings/ui): use configurable deposit in contract header"
```

---

## Task 18: Mobile — `BookingsRepository.updateBooking` sends deposit fields

**Files:**
- Modify: `tts_bandmate/lib/features/bookings/data/bookings_repository.dart`

- [ ] **Step 1: Extend the method signature**

In `tts_bandmate/lib/features/bookings/data/bookings_repository.dart`, update `updateBooking` (lines 137–160):

```dart
Future<BookingDetail> updateBooking(
  int bandId,
  int bookingId, {
  String? name,
  int? eventTypeId,
  String? price,
  String? status,
  String? contractOption,
  String? notes,
  String? depositType,
  String? depositValue,
}) async {
  final body = <String, dynamic>{
    if (name != null) 'name': name,
    if (eventTypeId != null) 'event_type_id': eventTypeId,
    if (price != null) 'price': price,
    if (status != null) 'status': status,
    if (contractOption != null) 'contract_option': contractOption,
    if (notes != null) 'notes': notes,
    if (depositType != null) 'deposit_type': depositType,
    if (depositValue != null) 'deposit_value': depositValue,
  };

  final response = await _dio.patch(
      ApiEndpoints.mobileBookingById(bandId, bookingId),
      data: body);
  return BookingDetail.fromJson(response.data['booking']);
}
```

- [ ] **Step 2: Verify analyzer is clean**

Run: `cd /home/eddie/github/tts_bandmate && flutter analyze`
Expected: no new warnings or errors.

- [ ] **Step 3: Commit**

```bash
cd /home/eddie/github/tts_bandmate
git add lib/features/bookings/data/bookings_repository.dart
git commit -m "feat(mobile/bookings): BookingsRepository.updateBooking sends deposit fields"
```

---

## Task 19: Mobile — `booking_form_screen.dart` deposit row UI

**Files:**
- Modify: `tts_bandmate/lib/features/bookings/screens/booking_form_screen.dart`
- Test: `tts_bandmate/test/features/bookings/screens/booking_form_screen_deposit_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `tts_bandmate/test/features/bookings/screens/booking_form_screen_deposit_test.dart`:

> This is a widget test. The exact pump/setup pattern should mirror existing booking-form widget tests in the repo. If none exist, the test below describes the assertions; adapt the harness to the project's `pumpScreen` helper or `ProviderScope` setup. If a true widget-mount is impractical (e.g., the screen requires deep router/provider context), reduce to a smaller widget extracted from the form's deposit row.

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Booking form deposit row', () {
    testWidgets('shows the deposit field with computed counterpart', (tester) async {
      // pump a fixture booking with price=1000, depositType=percent, depositValue=50
      // assert: a text containing "= \$500.00" appears
    }, skip: 'wire pump harness following existing booking-form widget tests');

    testWidgets('clears value when toggling mode', (tester) async {
      // toggle from % to $; the input should clear.
    }, skip: 'wire pump harness following existing booking-form widget tests');

    testWidgets('disables deposit fields when contract is signed', (tester) async {
      // contract.status = 'completed'; assert input + segmented control disabled
    }, skip: 'wire pump harness following existing booking-form widget tests');
  });
}
```

> The `skip:` markers acknowledge that the project may not yet have a widget-test harness for full booking-form screens. The implementer should remove the skips if the harness exists; otherwise, the manual visual-test step in this task is the primary verification.

- [ ] **Step 2: Write the implementation**

In `tts_bandmate/lib/features/bookings/screens/booking_form_screen.dart`:

1. Add controllers and state (alongside `_price`):

```dart
late final TextEditingController _depositValue;
final FocusNode _depositValueFocus = FocusNode();
DepositType _depositType = DepositType.percent;
```

2. In `initState`, initialize from `e?.depositType` and `e?.depositValue`:

```dart
_depositType = (e?.depositType == 'amount') ? DepositType.amount : DepositType.percent;
_depositValue = TextEditingController(text: e?.depositValue ?? '50.00');
```

3. Add a `_isContractSigned` getter:

```dart
bool get _isContractSigned =>
    widget.booking?.contract?.status == 'completed';
```

4. In `dispose`, dispose the new controller and focus node.

5. Below the price `CupertinoTextFormFieldRow` in the form (around line 536–544), insert a new row:

```dart
CupertinoTextFormFieldRow(
  controller: _depositValue,
  focusNode: _depositValueFocus,
  keyboardType: const TextInputType.numberWithOptions(decimal: true),
  enabled: !_isContractSigned &&
      !(_depositType == DepositType.percent && _priceIsZeroOrEmpty),
  prefix: const Text('Deposit'),
  placeholder: _depositType == DepositType.percent ? '50' : '500.00',
),
Padding(
  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
  child: Row(
    children: [
      Expanded(
        child: Semantics(
          label: 'Deposit type: dollar amount or percent',
          child: CupertinoSlidingSegmentedControl<DepositType>(
            groupValue: _depositType,
            onValueChanged: _isContractSigned
                ? null
                : (val) {
                    if (val == null || val == _depositType) return;
                    setState(() {
                      _depositType = val;
                      _depositValue.text = '';
                    });
                  },
            children: const {
              DepositType.amount: Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('\$'),
              ),
              DepositType.percent: Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('%'),
              ),
            },
          ),
        ),
      ),
    ],
  ),
),
Padding(
  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
  child: Text(
    _depositCaption(),
    style: TextStyle(
      color: CupertinoColors.secondaryLabel.resolveFrom(context),
      fontSize: 13,
    ),
  ),
),
```

6. Add helpers:

```dart
bool get _priceIsZeroOrEmpty {
  final p = double.tryParse(_price.text) ?? 0;
  return p <= 0;
}

String _depositCaption() {
  if (_isContractSigned) return 'Locked — contract is signed.';
  if (_depositType == DepositType.percent && _priceIsZeroOrEmpty) {
    return 'Enter a price above to use percent.';
  }
  final value = double.tryParse(_depositValue.text) ?? 0;
  final price = double.tryParse(_price.text) ?? 0;
  if (price <= 0) return '';
  if (_depositType == DepositType.percent) {
    if (value > 100) return 'Percent must be between 0 and 100.';
    return '= \$${(price * value / 100).toStringAsFixed(2)}';
  } else {
    if (value > price) return 'Deposit cannot exceed the booking price.';
    if (value <= 0) return '';
    return '= ${(value / price * 100).toStringAsFixed(1)}%';
  }
}
```

7. In the submit handler (around lines 321–330 and 369–375), include the deposit fields in the update call when they differ from the original:

```dart
final originalDepositType = orig.depositType;
final originalDepositValue = orig.depositValue;
final newDepositType = _depositType == DepositType.amount ? 'amount' : 'percent';
final newDepositValue = _depositValue.text.trim();

await repo.updateBooking(
  bandId,
  bookingId,
  // ... existing args ...
  depositType: newDepositType != originalDepositType ? newDepositType : null,
  depositValue: newDepositValue != originalDepositValue ? newDepositValue : null,
);
```

8. Add the import at the top:

```dart
import '../data/models/deposit.dart';
```

- [ ] **Step 3: Verify analyzer is clean**

Run: `cd /home/eddie/github/tts_bandmate && flutter analyze`
Expected: no new warnings.

- [ ] **Step 4: Manual visual verification**

Run on Linux desktop or web:
```bash
cd /home/eddie/github/tts_bandmate
flutter run -d linux --dart-define=BASE_URL=http://localhost:8715
```

Verify:
1. The deposit row appears below price with a `$` / `%` toggle.
2. Toggling the segmented control clears the input.
3. With price empty/0 and mode = `%`, the input is disabled and shows the "Enter a price" caption.
4. With a price entered and mode = `%`, typing `25` shows `= $XXX.XX` beneath.
5. With price set and mode = `$`, typing `300` shows `= XX.X%` beneath.
6. Open a booking whose contract has `status='completed'`: the row is fully disabled and caption reads "Locked — contract is signed."

- [ ] **Step 5: Run tests**

Run: `cd /home/eddie/github/tts_bandmate && flutter test test/features/bookings/screens/booking_form_screen_deposit_test.dart`
Expected: tests pass (or skipped per Step 1's harness limitation).

- [ ] **Step 6: Commit**

```bash
cd /home/eddie/github/tts_bandmate
git add lib/features/bookings/screens/booking_form_screen.dart test/features/bookings/screens/booking_form_screen_deposit_test.dart
git commit -m "feat(mobile/bookings/ui): configurable deposit on booking form

Cupertino segmented \$/% toggle next to a numeric input. Disabled
when contract is signed or when price is 0 in percent mode. Shows
computed counterpart inline. Clears on mode switch."
```

---

## Task 20: Cross-cutting — End-to-end smoke

**Files:** none (verification only)

- [ ] **Step 1: Run full backend test suite**

```bash
cd /home/eddie/github/TTS
docker compose exec app php artisan test
```

Expected: all tests pass. Pay special attention to anything in `tests/Feature/PaymentReminderNotificationsTest.php`, `BookingsControllerTest.php`, `ContactPortalControllerTest.php`, `BookingContractPdfTest.php`, and `Unit/Models/BookingsTest.php`.

- [ ] **Step 2: Run web Vitest suite**

```bash
cd /home/eddie/github/TTS
npx vitest run
```

Expected: all tests pass.

- [ ] **Step 3: Run mobile Flutter tests**

```bash
cd /home/eddie/github/tts_bandmate
flutter test
```

Expected: all tests pass.

- [ ] **Step 4: Manual end-to-end check (web)**

1. Run the web app (`docker compose up` or whatever the local-dev command is).
2. Log in as a band owner, navigate to a booking with no contract yet.
3. Edit it: change deposit to `amount` $250 on a $1000 booking. Save.
4. Verify in the WYSIWYG contract preview: deposit reads `$250.00`, remaining reads `$750.00`.
5. Sign the contract.
6. Re-open the edit form: deposit fields are disabled, "Locked" message visible.
7. Log out, log into the contact portal as that booking's contact.
8. Verify the portal Dashboard card shows "Deposit of $250.00 due [date]".
9. Open the payment page: same line visible.
10. Trigger the deposit-reminder cron (`docker compose exec app php artisan tts:send-deposit-reminders` or equivalent) against a booking whose `deposit_due_date` is today. Verify the email body shows `$250.00`.

- [ ] **Step 5: Manual end-to-end check (mobile)**

1. Run the Flutter app pointed at the same backend.
2. Open a booking, edit deposit to `percent` 30%.
3. Verify the mobile contract preview header reflects the new resolved amount.
4. Sign the contract via the mobile flow (if supported) or web (then re-open on mobile).
5. Re-open edit: deposit fields are disabled with "Locked" caption.

- [ ] **Step 6: No commit needed** (verification only).

---

## Summary

After all 20 tasks:
- `bookings` table has `deposit_type` and `deposit_value`.
- Existing bookings unchanged (50% backfill).
- Backend computes `expected_deposit_amount` from the new columns; all downstream consumers (PDF, reminders, portal, web preview, mobile preview) read it.
- Both clients can set deposit as percent or amount; both clients see the same locked behavior after contract signing.
- Customer portal shows the deposit amount and due date.
- Customer-facing surfaces show resolved dollars only — never the mode toggle.
