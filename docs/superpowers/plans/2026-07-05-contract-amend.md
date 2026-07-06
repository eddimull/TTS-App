# Contract Amendment Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One-tap "Amend contract" that recalls a sent-for-signature contract (voids the PandaDoc doc, unlocks the editor) on web + mobile, plus working `contract_option` editing on the mobile API.

**Architecture:** A shared `App\Services\ContractAmendmentService` owns guards + state reset; thin controller actions on web (`ContractsController`) and mobile API (`Api\Mobile\BookingsController`) expose it. Mobile adds a repository method, an Amend button on the locked contract view, and a functional contract-type picker. Web adds an Amend button to the pending dead-end banner.

**Tech Stack:** Laravel 10 (TTS repo), PandaDoc public API v1, Flutter/Riverpod (tts_bandmate), Vue 3 + Inertia (web).

## Global Constraints

- **TTS repo** (`/home/eddie/github/TTS`): never run php/artisan/phpunit on the host — always `docker compose exec -T app <cmd>` from the TTS repo root. Branch `feat/contract-amend` off `staging`; PR targets `staging` (auto-deploys on merge).
- **Mobile repo** (`/home/eddie/github/tts_bandmate`): branch `feat/contract-amend` already exists off `main`; PR targets `main`.
- PandaDoc void = `PATCH https://api.pandadoc.com/public/v1/documents/{id}/status/` with `{"status": 11}` (document.voided). HTTP 404 counts as success (doc hand-deleted); any other failure = abort, no DB writes.
- Amend guards (422 / redirect-with-errors when violated): `contract_option === 'default'`, contract exists with status `sent`, booking status `pending`.
- After amend: contract → status `pending`, `envelope_id` → null; booking → status `draft`. `custom_terms`, `buyer_name_override`, `asset_url` untouched.
- Dark-mode (mobile): use `context.secondaryText` etc. from `context_colors.dart`, never raw `CupertinoColors.*Label` in a `color:`.
- Vue tests: assert on `wrapper.text()` / `find()`, never on `<!--v-if-->` markers.
- Every commit ends with the Claude Code trailer used throughout this branch.

---

### Task 1: ContractAmendmentService + Signable::voidPandaDocDocument (TTS)

**Files:**
- Create: `app/Services/ContractAmendmentService.php`
- Modify: `app/Models/Traits/Signable.php` (add method after `sendToRecipients`)
- Test: `tests/Feature/ContractAmendmentServiceTest.php`

**Interfaces:**
- Consumes: `Contracts` model (Signable trait), `Bookings` model.
- Produces: `ContractAmendmentService::amend(Bookings $booking): void` (throws `InvalidArgumentException` on guard violation, `\Exception` on PandaDoc failure); `Signable::voidPandaDocDocument(): void`.

- [ ] **Step 1: Write the failing test**

```php
<?php

namespace Tests\Feature;

use App\Models\Bands;
use App\Models\Bookings;
use App\Models\User;
use App\Services\ContractAmendmentService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Config;
use Illuminate\Support\Facades\Http;
use InvalidArgumentException;
use Tests\TestCase;

class ContractAmendmentServiceTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        Config::set('services.pandadoc.api_key', 'fake-api-key');
    }

    /** Booking in the amendable state: default option, contract sent, booking pending. */
    private function amendableBooking(): Bookings
    {
        $user = User::factory()->create();
        $band = Bands::factory()->create();
        $band->owners()->create(['user_id' => $user->id]);

        $booking = Bookings::factory()->create([
            'band_id'         => $band->id,
            'status'          => 'pending',
            'contract_option' => 'default',
        ]);
        $booking->contract()->create([
            'author_id'   => $user->id,
            'status'      => 'sent',
            'envelope_id' => 'pd-doc-123',
            'custom_terms' => [['title' => 'T', 'content' => 'C']],
        ]);

        return $booking->fresh();
    }

    public function test_amend_voids_document_and_resets_state(): void
    {
        Http::fake(['api.pandadoc.com/*' => Http::response([], 200)]);

        $booking = $this->amendableBooking();
        app(ContractAmendmentService::class)->amend($booking);

        Http::assertSent(fn ($req) =>
            $req->url() === 'https://api.pandadoc.com/public/v1/documents/pd-doc-123/status/'
            && $req->method() === 'PATCH'
            && ($req['status'] ?? null) === 11
        );

        $booking->refresh();
        $this->assertSame('draft', $booking->status);
        $this->assertSame('pending', $booking->contract->status);
        $this->assertNull($booking->contract->envelope_id);
        $this->assertNotEmpty($booking->contract->custom_terms);
    }

    public function test_amend_tolerates_document_already_deleted(): void
    {
        Http::fake(['api.pandadoc.com/*' => Http::response(['detail' => 'Not found'], 404)]);

        $booking = $this->amendableBooking();
        app(ContractAmendmentService::class)->amend($booking);

        $this->assertSame('draft', $booking->fresh()->status);
    }

    public function test_amend_aborts_without_db_changes_when_void_fails(): void
    {
        Http::fake(['api.pandadoc.com/*' => Http::response(['detail' => 'boom'], 500)]);

        $booking = $this->amendableBooking();

        try {
            app(ContractAmendmentService::class)->amend($booking);
            $this->fail('Expected exception');
        } catch (\Exception $e) {
            $this->assertStringContainsString('void', strtolower($e->getMessage()));
        }

        $booking->refresh();
        $this->assertSame('pending', $booking->status);
        $this->assertSame('sent', $booking->contract->status);
        $this->assertSame('pd-doc-123', $booking->contract->envelope_id);
    }

    public function test_amend_rejects_external_option(): void
    {
        Http::fake();
        $booking = $this->amendableBooking();
        $booking->update(['contract_option' => 'external']);

        $this->expectException(InvalidArgumentException::class);
        app(ContractAmendmentService::class)->amend($booking->fresh());
    }

    public function test_amend_rejects_unsent_contract(): void
    {
        Http::fake();
        $booking = $this->amendableBooking();
        $booking->contract->update(['status' => 'pending']);

        $this->expectException(InvalidArgumentException::class);
        app(ContractAmendmentService::class)->amend($booking->fresh());
    }

    public function test_amend_rejects_completed_contract(): void
    {
        Http::fake();
        $booking = $this->amendableBooking();
        $booking->contract->update(['status' => 'completed']);
        $booking->update(['status' => 'confirmed']);

        $this->expectException(InvalidArgumentException::class);
        app(ContractAmendmentService::class)->amend($booking->fresh());
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /home/eddie/github/TTS && docker compose exec -T app ./vendor/bin/phpunit tests/Feature/ContractAmendmentServiceTest.php`
Expected: FAIL — `Class "App\Services\ContractAmendmentService" not found`

- [ ] **Step 3: Implement Signable::voidPandaDocDocument**

Add to `app/Models/Traits/Signable.php` after `sendToRecipients()`:

```php
    /**
     * Void the PandaDoc document for this contract so it can be amended.
     *
     * A 404 means the document was already deleted (e.g. by hand in the
     * PandaDoc dashboard) — treated as success so amendment is idempotent.
     * Any other failure throws and the caller must not mutate local state.
     */
    public function voidPandaDocDocument(): void
    {
        if (!$this->envelope_id)
        {
            return;
        }

        $apiKey = config('services.pandadoc.api_key');

        $response = Http::withHeaders([
            'Authorization' => 'API-Key ' . $apiKey,
            'Content-Type' => 'application/json',
        ])->patch("https://api.pandadoc.com/public/v1/documents/{$this->envelope_id}/status/", [
            'status' => 11, // document.voided
        ]);

        if ($response->successful() || $response->status() === 404)
        {
            return;
        }

        Log::error('Failed to void PandaDoc document: ' . $response->body());
        throw new \Exception('Failed to void the PandaDoc document: ' . $response->body());
    }
```

- [ ] **Step 4: Implement ContractAmendmentService**

Create `app/Services/ContractAmendmentService.php`:

```php
<?php

namespace App\Services;

use App\Models\Bookings;
use Illuminate\Support\Facades\DB;
use InvalidArgumentException;

class ContractAmendmentService
{
    /**
     * Recall a booking contract that is out for signature so it can be
     * edited and resent. Voids the PandaDoc document first (external call,
     * not rollback-able), then resets contract + booking state so the
     * contract editor unlocks. Resending later creates a fresh document.
     */
    public function amend(Bookings $booking): void
    {
        $contract = $booking->contract;

        if ($booking->contract_option !== 'default')
        {
            throw new InvalidArgumentException('Only Bandmate-generated contracts can be amended.');
        }

        if (!$contract || $contract->status !== 'sent')
        {
            throw new InvalidArgumentException('Only a contract that is out for signature can be amended.');
        }

        if ($booking->status !== 'pending')
        {
            throw new InvalidArgumentException('Only a pending booking can have its contract amended.');
        }

        $contract->voidPandaDocDocument();

        DB::transaction(function () use ($booking, $contract)
        {
            $contract->update(['status' => 'pending', 'envelope_id' => null]);
            $booking->update(['status' => 'draft']);
        });
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd /home/eddie/github/TTS && docker compose exec -T app ./vendor/bin/phpunit tests/Feature/ContractAmendmentServiceTest.php`
Expected: PASS (6 tests)

- [ ] **Step 6: Commit (TTS repo)**

```bash
cd /home/eddie/github/TTS
git add app/Services/ContractAmendmentService.php app/Models/Traits/Signable.php tests/Feature/ContractAmendmentServiceTest.php
git commit -m "feat(contracts): amendment service voids PandaDoc doc and unlocks editing"
```

---

### Task 2: Mobile API amend endpoint (TTS)

**Files:**
- Modify: `routes/api.php` (inside the `mobile.band:write:bookings` group, next to the `contract/send` route at ~line 256)
- Modify: `app/Http/Controllers/Api/Mobile/BookingsController.php` (add action after `sendContract`, ~line 572)
- Test: `tests/Feature/Api/Mobile/BookingContractAmendTest.php`

**Interfaces:**
- Consumes: `ContractAmendmentService::amend(Bookings $booking): void` (Task 1).
- Produces: `POST /api/mobile/bands/{band}/bookings/{booking}/contract/amend` → `{"booking": <formatted>}` on 200; `{"message": …}` on 422/500. Route name `mobile.bookings.contract.amend`.

- [ ] **Step 1: Write the failing test**

```php
<?php

namespace Tests\Feature\Api\Mobile;

use App\Models\Bands;
use App\Models\Bookings;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Config;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class BookingContractAmendTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        Config::set('services.pandadoc.api_key', 'fake-api-key');
    }

    private function makeBooking(User $user, string $bookingStatus = 'pending', string $contractStatus = 'sent'): Bookings
    {
        $band = Bands::factory()->create();
        $band->owners()->create(['user_id' => $user->id]);

        $booking = Bookings::factory()->create([
            'band_id'         => $band->id,
            'status'          => $bookingStatus,
            'contract_option' => 'default',
        ]);
        $booking->contract()->create([
            'author_id'   => $user->id,
            'status'      => $contractStatus,
            'envelope_id' => 'pd-doc-456',
        ]);

        return $booking;
    }

    public function test_amend_returns_booking_back_in_draft(): void
    {
        Http::fake(['api.pandadoc.com/*' => Http::response([], 200)]);

        $user    = User::factory()->create();
        $booking = $this->makeBooking($user);
        $token   = $user->createToken('test-device')->plainTextToken;

        $response = $this->withToken($token)
            ->withHeaders(['X-Band-ID' => $booking->band_id])
            ->postJson("/api/mobile/bands/{$booking->band_id}/bookings/{$booking->id}/contract/amend");

        $response->assertOk()
            ->assertJsonPath('booking.status', 'draft')
            ->assertJsonPath('booking.contract.status', 'pending')
            ->assertJsonPath('booking.contract.envelope_id', null);
    }

    public function test_amend_rejects_unsent_contract_with_422(): void
    {
        Http::fake();

        $user    = User::factory()->create();
        $booking = $this->makeBooking($user, bookingStatus: 'draft', contractStatus: 'pending');
        $token   = $user->createToken('test-device')->plainTextToken;

        $this->withToken($token)
            ->withHeaders(['X-Band-ID' => $booking->band_id])
            ->postJson("/api/mobile/bands/{$booking->band_id}/bookings/{$booking->id}/contract/amend")
            ->assertStatus(422);

        Http::assertNothingSent();
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /home/eddie/github/TTS && docker compose exec -T app ./vendor/bin/phpunit tests/Feature/Api/Mobile/BookingContractAmendTest.php`
Expected: FAIL — 404 (route not defined)

- [ ] **Step 3: Add route**

In `routes/api.php`, directly below the `mobile.bookings.contract.send` route:

```php
            Route::post('/bands/{band}/bookings/{booking}/contract/amend', [App\Http\Controllers\Api\Mobile\BookingsController::class, 'amendContract'])->name('mobile.bookings.contract.amend');
```

- [ ] **Step 4: Add controller action**

In `app/Http/Controllers/Api/Mobile/BookingsController.php`, after `sendContract()` (add `use App\Services\ContractAmendmentService;` to the imports):

```php
    public function amendContract(
        Request $request,
        Bands $band,
        Bookings $booking,
        ContractAmendmentService $amendmentService
    ): JsonResponse {
        try {
            $amendmentService->amend($booking);
        } catch (\InvalidArgumentException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        } catch (\Exception $e) {
            return response()->json(['message' => 'Failed to amend contract: ' . $e->getMessage()], 500);
        }

        return response()->json([
            'booking' => $this->formatter->format(
                $booking->fresh()->load(['contacts', 'events', 'contract', 'payments', 'band'])
            ),
        ]);
    }
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd /home/eddie/github/TTS && docker compose exec -T app ./vendor/bin/phpunit tests/Feature/Api/Mobile/BookingContractAmendTest.php`
Expected: PASS (2 tests)

- [ ] **Step 6: Commit (TTS repo)**

```bash
cd /home/eddie/github/TTS
git add routes/api.php app/Http/Controllers/Api/Mobile/BookingsController.php tests/Feature/Api/Mobile/BookingContractAmendTest.php
git commit -m "feat(mobile-api): POST bookings/{id}/contract/amend endpoint"
```

---

### Task 3: Web amend endpoint (TTS)

**Files:**
- Modify: `routes/booking.php` (after the `'Send Booking Contract'` route, ~line 79)
- Modify: `app/Http/Controllers/ContractsController.php` (add action after `sendBookingContract`)
- Test: `tests/Feature/BookingContractAmendWebTest.php`

**Interfaces:**
- Consumes: `ContractAmendmentService::amend` (Task 1).
- Produces: web route named `'Amend Booking Contract'` (`POST bands/{band}/booking/{booking}/contract/amend`, `booking.access` middleware) → redirect back; used by Task 6's Vue button.

- [ ] **Step 1: Write the failing test**

```php
<?php

namespace Tests\Feature;

use App\Models\Bands;
use App\Models\Bookings;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Config;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class BookingContractAmendWebTest extends TestCase
{
    use RefreshDatabase;

    public function test_web_amend_resets_booking_and_redirects_back(): void
    {
        Config::set('services.pandadoc.api_key', 'fake-api-key');
        Http::fake(['api.pandadoc.com/*' => Http::response([], 200)]);

        $user = User::factory()->create();
        $band = Bands::factory()->create();
        $band->owners()->create(['user_id' => $user->id]);

        $booking = Bookings::factory()->create([
            'band_id'         => $band->id,
            'status'          => 'pending',
            'contract_option' => 'default',
        ]);
        $booking->contract()->create([
            'author_id'   => $user->id,
            'status'      => 'sent',
            'envelope_id' => 'pd-doc-789',
        ]);

        $response = $this->actingAs($user)->post(
            route('Amend Booking Contract', ['band' => $band, 'booking' => $booking])
        );

        $response->assertRedirect();
        $this->assertSame('draft', $booking->fresh()->status);
        $this->assertSame('pending', $booking->fresh()->contract->status);
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /home/eddie/github/TTS && docker compose exec -T app ./vendor/bin/phpunit tests/Feature/BookingContractAmendWebTest.php`
Expected: FAIL — `Route [Amend Booking Contract] not defined`

- [ ] **Step 3: Add route**

In `routes/booking.php`, after the `'Send Booking Contract'` route block:

```php
    Route::post('bands/{band}/booking/{booking}/contract/amend', [ContractsController::class, 'amendBookingContract'])
        ->name('Amend Booking Contract')
        ->middleware('booking.access');
```

- [ ] **Step 4: Add controller action**

In `app/Http/Controllers/ContractsController.php`, after `sendBookingContract()` (add `use App\Services\ContractAmendmentService;` to imports). Match the redirect/flash conventions of the neighboring methods in this controller (the code below assumes `->withErrors(...)` for failures, which `sendBookingContract` uses — keep the success flash consistent with whatever key the controller's other success paths use):

```php
    public function amendBookingContract(Bands $band, Bookings $booking, ContractAmendmentService $amendmentService)
    {
        try {
            $amendmentService->amend($booking);
        } catch (\InvalidArgumentException $e) {
            return redirect()->back()->withErrors(['Cannot amend' => $e->getMessage()]);
        } catch (\Exception $e) {
            return redirect()->back()->withErrors(['Amend failed' => $e->getMessage()]);
        }

        return redirect()->back();
    }
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd /home/eddie/github/TTS && docker compose exec -T app ./vendor/bin/phpunit tests/Feature/BookingContractAmendWebTest.php`
Expected: PASS

- [ ] **Step 6: Commit (TTS repo)**

```bash
cd /home/eddie/github/TTS
git add routes/booking.php app/Http/Controllers/ContractsController.php tests/Feature/BookingContractAmendWebTest.php
git commit -m "feat(web): amend-contract route recalls a sent booking contract"
```

---

### Task 4: contract_option on mobile UpdateBookingRequest (TTS)

**Files:**
- Modify: `app/Http/Requests/Mobile/UpdateBookingRequest.php` (rules array, after `'status'`)
- Test: `tests/Feature/Api/Mobile/BookingContractOptionUpdateTest.php`

**Interfaces:**
- Produces: `PATCH /api/mobile/bands/{band}/bookings/{booking}` accepts `contract_option` (`default|none|external`) unless the booking's contract is `sent`/`completed`. Used by Task 8's mobile picker.

- [ ] **Step 1: Write the failing test**

```php
<?php

namespace Tests\Feature\Api\Mobile;

use App\Models\Bands;
use App\Models\Bookings;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class BookingContractOptionUpdateTest extends TestCase
{
    use RefreshDatabase;

    private function makeBooking(User $user, string $contractStatus = 'pending'): Bookings
    {
        $band = Bands::factory()->create();
        $band->owners()->create(['user_id' => $user->id]);

        $booking = Bookings::factory()->create([
            'band_id'         => $band->id,
            'status'          => 'draft',
            'contract_option' => 'default',
        ]);
        $booking->contract()->create(['author_id' => $user->id, 'status' => $contractStatus]);

        return $booking;
    }

    public function test_contract_option_updates_when_contract_not_sent(): void
    {
        $user    = User::factory()->create();
        $booking = $this->makeBooking($user);
        $token   = $user->createToken('test-device')->plainTextToken;

        $this->withToken($token)
            ->withHeaders(['X-Band-ID' => $booking->band_id])
            ->patchJson("/api/mobile/bands/{$booking->band_id}/bookings/{$booking->id}", [
                'contract_option' => 'external',
            ])
            ->assertOk()
            ->assertJsonPath('booking.contract_option', 'external');

        $this->assertSame('external', $booking->fresh()->contract_option);
    }

    public function test_contract_option_rejected_once_contract_sent(): void
    {
        $user    = User::factory()->create();
        $booking = $this->makeBooking($user, contractStatus: 'sent');
        $token   = $user->createToken('test-device')->plainTextToken;

        $this->withToken($token)
            ->withHeaders(['X-Band-ID' => $booking->band_id])
            ->patchJson("/api/mobile/bands/{$booking->band_id}/bookings/{$booking->id}", [
                'contract_option' => 'none',
            ])
            ->assertStatus(422)
            ->assertJsonValidationErrors(['contract_option']);

        $this->assertSame('default', $booking->fresh()->contract_option);
    }

    public function test_contract_option_value_validated(): void
    {
        $user    = User::factory()->create();
        $booking = $this->makeBooking($user);
        $token   = $user->createToken('test-device')->plainTextToken;

        $this->withToken($token)
            ->withHeaders(['X-Band-ID' => $booking->band_id])
            ->patchJson("/api/mobile/bands/{$booking->band_id}/bookings/{$booking->id}", [
                'contract_option' => 'verbal',
            ])
            ->assertStatus(422);
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /home/eddie/github/TTS && docker compose exec -T app ./vendor/bin/phpunit tests/Feature/Api/Mobile/BookingContractOptionUpdateTest.php`
Expected: FAIL — first test gets `booking.contract_option` still `default` (field silently dropped)

- [ ] **Step 3: Add the rule**

In `app/Http/Requests/Mobile/UpdateBookingRequest.php`, after the `'status'` rule:

```php
            'contract_option' => [
                'sometimes', 'in:default,none,external',
                function ($attribute, $value, $fail)
                {
                    $contract = $this->route('booking')?->contract;
                    if ($contract && in_array($contract->status, ['sent', 'completed'], true))
                    {
                        $fail('The contract type cannot be changed after the contract has been sent.');
                    }
                },
            ],
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /home/eddie/github/TTS && docker compose exec -T app ./vendor/bin/phpunit tests/Feature/Api/Mobile/BookingContractOptionUpdateTest.php`
Expected: PASS (3 tests)

- [ ] **Step 5: Run the full TTS suite and commit**

Run: `cd /home/eddie/github/TTS && docker compose exec -T app ./vendor/bin/phpunit`
Expected: PASS (memory: `band_roles` / `CalendarFeedTest` flakes are parallel-run artifacts — re-run those files sequentially if they fail).

```bash
cd /home/eddie/github/TTS
git add app/Http/Requests/Mobile/UpdateBookingRequest.php tests/Feature/Api/Mobile/BookingContractOptionUpdateTest.php
git commit -m "feat(mobile-api): accept contract_option on booking update until contract is sent"
```

---

### Task 5: Web Amend button on Contract.vue (TTS)

**Files:**
- Modify: `resources/js/Pages/Bookings/Contract.vue` (pending banner `<p v-if="booking.status === 'pending'">` block, ~lines 37-41, and the component script)
- Test: `resources/js/tests/` — place next to existing Bookings component tests (check `git ls-files 'resources/js/**/*.spec.*' 'resources/js/**/*.test.*'` for the exact directory + naming convention and mirror it): `ContractAmendButton` test.

**Interfaces:**
- Consumes: route `'Amend Booking Contract'` (Task 3).
- Produces: user-visible "Amend contract" button in the pending state.

- [ ] **Step 1: Write the failing test**

Adapt imports/mount helpers to the conventions found in the existing Bookings component tests (Contract.vue receives `booking` + `band` props from Inertia):

```js
import { describe, expect, it, vi } from 'vitest';
import { mount } from '@vue/test-utils';
import Contract from '@/Pages/Bookings/Contract.vue';
import { router } from '@inertiajs/vue3';

vi.mock('@inertiajs/vue3', async (importOriginal) => {
    const actual = await importOriginal();
    return { ...actual, router: { ...actual.router, post: vi.fn() } };
});

const pendingBooking = {
    id: 5,
    band_id: 1,
    status: 'pending',
    contract_option: 'default',
    contract: { asset_url: null },
};

const mountPage = (booking) =>
    mount(Contract, {
        props: { booking, band: { id: 1, name: 'Band' } },
        global: {
            mocks: { route: (name, params) => `/${name}/${JSON.stringify(params)}` },
            stubs: { ContractNone: true, ContractExternal: true, ContractEditor: true },
        },
    });

describe('Contract.vue amend button', () => {
    it('shows Amend contract on a pending default contract and posts on confirm', async () => {
        vi.spyOn(window, 'confirm').mockReturnValue(true);
        const wrapper = mountPage(pendingBooking);

        expect(wrapper.text()).toContain('Amend contract');
        await wrapper.find('[data-testid="amend-contract"]').trigger('click');

        expect(router.post).toHaveBeenCalledTimes(1);
    });

    it('does not post when the confirm dialog is cancelled', async () => {
        vi.spyOn(window, 'confirm').mockReturnValue(false);
        vi.mocked(router.post).mockClear();
        const wrapper = mountPage(pendingBooking);

        await wrapper.find('[data-testid="amend-contract"]').trigger('click');
        expect(router.post).not.toHaveBeenCalled();
    });

    it('hides the button when the booking is confirmed', () => {
        const wrapper = mountPage({ ...pendingBooking, status: 'confirmed' });
        expect(wrapper.text()).not.toContain('Amend contract');
    });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /home/eddie/github/TTS && npm run test -- ContractAmend`
Expected: FAIL — "Amend contract" not found

- [ ] **Step 3: Implement the button**

In `Contract.vue`, replace the pending `<p>` with a block that keeps the message and adds the button (Tailwind classes matching the page's existing button styling; the pending block only renders for `default`/`external` options, and amend must only show for `default`):

```vue
      <div
        v-if="booking.status === 'pending'"
        class="text-center bg-blue-100 py-3 px-4 rounded-lg shadow-sm space-y-3"
      >
        <p class="text-xl text-gray-700 font-semibold">
          This contract is pending. The contract is no longer editable.
        </p>
        <button
          v-if="booking.contract_option === 'default'"
          data-testid="amend-contract"
          type="button"
          class="inline-flex items-center px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white text-sm font-semibold rounded-md"
          @click="amendContract"
        >
          Amend contract
        </button>
      </div>
```

And in the component's script section (match its existing style — options API `methods` or `<script setup>`):

```js
import { router } from '@inertiajs/vue3';

const amendContract = () => {
    if (!window.confirm(
        'This voids the contract that is out for signature. ' +
        'You will be able to edit the terms and resend it.'
    )) {
        return;
    }
    router.post(route('Amend Booking Contract', {
        band: props.booking.band_id,
        booking: props.booking.id,
    }));
};
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /home/eddie/github/TTS && npm run test -- ContractAmend`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit (TTS repo)**

```bash
cd /home/eddie/github/TTS
git add resources/js/Pages/Bookings/Contract.vue resources/js/**/ContractAmend*
git commit -m "feat(web): Amend contract button on the pending contract page"
```

---

### Task 6: Mobile repository amendContract (tts_bandmate)

**Files:**
- Modify: `lib/core/network/api_endpoints.dart` (next to the other `mobileBookingContract*` helpers)
- Modify: `lib/features/bookings/data/bookings_repository.dart` (after `sendContract`)
- Test: `test/features/bookings/data/bookings_repository_amend_test.dart`

**Interfaces:**
- Consumes: Task 2's endpoint.
- Produces: `Future<BookingDetail> amendContract(int bandId, int bookingId)` on `BookingsRepository`; `ApiEndpoints.mobileBookingContractAmend(int bandId, int bookingId)`.

- [ ] **Step 1: Write the failing test**

Mirror the `_StubAdapter` pattern from `test/features/bookings/data/bookings_repository_contract_test.dart` (copy its imports/stub helper verbatim):

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/bookings_repository.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);
  final Future<ResponseBody> Function(RequestOptions) handler;
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(
          RequestOptions o, Stream<Uint8List>? s, Future<void>? c) =>
      handler(o);
}

ResponseBody _json(int status, Object body) => ResponseBody.fromBytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {
        'content-type': ['application/json'],
      },
    );

void main() {
  test('amendContract POSTs to the amend endpoint and parses the booking',
      () async {
    late RequestOptions captured;
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = _StubAdapter((req) async {
        captured = req;
        return _json(200, {
          'booking': {
            'id': 42,
            'name': 'Wedding',
            'start_date': '2026-08-01',
            'end_date': '2026-08-01',
            'event_count': 1,
            'is_multi_event': false,
            'is_paid': false,
            'status': 'draft',
            'contract_option': 'default',
            'contract': {'id': 9, 'status': 'pending', 'envelope_id': null},
            'contacts': [],
            'events': [],
          }
        });
      });

    final repo = BookingsRepository(dio);
    final detail = await repo.amendContract(1, 42);

    expect(captured.method, 'POST');
    expect(captured.path, '/api/mobile/bands/1/bookings/42/contract/amend');
    expect(detail.status, 'draft');
    expect(detail.contract?.status, 'pending');
    expect(detail.contract?.envelopeId, isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /home/eddie/github/tts_bandmate && flutter test test/features/bookings/data/bookings_repository_amend_test.dart`
Expected: FAIL — compile error, `amendContract` not defined

- [ ] **Step 3: Implement endpoint + repository method**

`lib/core/network/api_endpoints.dart` (match the exact formatting of the neighboring `mobileBookingContract*` helpers):

```dart
  static String mobileBookingContractAmend(int bandId, int bookingId) =>
      '/api/mobile/bands/$bandId/bookings/$bookingId/contract/amend';
```

`lib/features/bookings/data/bookings_repository.dart`, after `sendContract`:

```dart
  /// Recall a contract that is out for signature so it can be edited and
  /// resent. The backend voids the PandaDoc document and puts the booking
  /// back in draft; the returned detail reflects the unlocked state.
  Future<BookingDetail> amendContract(int bandId, int bookingId) async {
    final response = await _dio.post(
      ApiEndpoints.mobileBookingContractAmend(bandId, bookingId),
    );
    return BookingDetail.fromJson(response.data['booking']);
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /home/eddie/github/tts_bandmate && flutter test test/features/bookings/data/bookings_repository_amend_test.dart`
Expected: PASS

- [ ] **Step 5: Commit (mobile repo)**

```bash
cd /home/eddie/github/tts_bandmate
git add lib/core/network/api_endpoints.dart lib/features/bookings/data/bookings_repository.dart test/features/bookings/data/bookings_repository_amend_test.dart
git commit -m "feat(bookings): repository support for contract amendment"
```

---

### Task 7: Amend button on the locked mobile contract view (tts_bandmate)

**Files:**
- Modify: `lib/features/bookings/widgets/contract/contract_default_view.dart`
- Test: `test/features/bookings/widgets/contract_default_view_amend_test.dart`

**Interfaces:**
- Consumes: `BookingsRepository.amendContract` (Task 6), `cacheInvalidatorProvider.onBookingDetailChanged`.
- Produces: "Amend contract" button visible only when booking status `pending` **and** contract option `default`.

- [ ] **Step 1: Write the failing test**

Reuse the fake-repo + no-op invalidator patterns from `test/features/bookings/widgets/contract_send_dialog_test.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/bookings/data/bookings_repository.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_contract.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_detail.dart';
import 'package:tts_bandmate/features/bookings/widgets/contract/contract_default_view.dart';
import 'package:tts_bandmate/shared/cache/cache_invalidator.dart';

class _FakeRepo extends BookingsRepository {
  _FakeRepo() : super(Dio());
  int amendCalls = 0;

  @override
  Future<BookingDetail> amendContract(int bandId, int bookingId) async {
    amendCalls++;
    return _booking(status: 'draft', contractStatus: 'pending');
  }
}

class _NoopInvalidator extends CacheInvalidator {
  _NoopInvalidator(super.ref);
  @override
  void onBookingDetailChanged(
      {required int bandId,
      required int bookingId,
      String? contractEnvelopeId}) {}
}

BookingDetail _booking({
  String status = 'pending',
  String contractStatus = 'sent',
  String contractOption = 'default',
}) =>
    BookingDetail(
      id: 42,
      name: 'Wedding',
      startDate: '2026-08-01',
      endDate: '2026-08-01',
      eventCount: 1,
      isMultiEvent: false,
      isPaid: false,
      status: status,
      contractOption: contractOption,
      contract: BookingContract(
          id: 9, status: contractStatus, envelopeId: 'pd-1'),
      contacts: const [],
      events: const [],
      band: const BandSummary(id: 1, name: 'Band', isOwner: true),
    );

Widget _wrap(BookingDetail booking, _FakeRepo repo) => ProviderScope(
      overrides: [
        bookingsRepositoryProvider.overrideWithValue(repo),
        cacheInvalidatorProvider.overrideWith(_NoopInvalidator.new),
      ],
      child: CupertinoApp(home: ContractDefaultView(booking: booking)),
    );

void main() {
  testWidgets('locked pending view shows Amend contract', (tester) async {
    await tester.pumpWidget(_wrap(_booking(), _FakeRepo()));
    await tester.pump();
    expect(find.text('Amend contract'), findsOneWidget);
  });

  testWidgets('confirmed (signed) view has no Amend button', (tester) async {
    await tester.pumpWidget(_wrap(
        _booking(status: 'confirmed', contractStatus: 'completed'),
        _FakeRepo()));
    await tester.pump();
    expect(find.text('Amend contract'), findsNothing);
  });

  testWidgets('confirm dialog cancel does not call the repo', (tester) async {
    final repo = _FakeRepo();
    await tester.pumpWidget(_wrap(_booking(), repo));
    await tester.pump();

    await tester.tap(find.text('Amend contract'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(repo.amendCalls, 0);
  });

  testWidgets('confirming Amend calls the repository', (tester) async {
    final repo = _FakeRepo();
    await tester.pumpWidget(_wrap(_booking(), repo));
    await tester.pump();

    await tester.tap(find.text('Amend contract'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Amend'));
    await tester.pumpAndSettle();

    expect(repo.amendCalls, 1);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /home/eddie/github/tts_bandmate && flutter test test/features/bookings/widgets/contract_default_view_amend_test.dart`
Expected: FAIL — "Amend contract" not found (button missing)

- [ ] **Step 3: Implement the button**

In `contract_default_view.dart`:
- Add imports: `../../data/bookings_repository.dart`, `package:tts_bandmate/shared/cache/cache_invalidator.dart`.
- Add `bool _amending = false;` next to `_downloading`.
- Add below the `ContractLockBanner` `Padding` in `build()`:

```dart
            if (widget.booking.status == 'pending' &&
                (widget.booking.contractOption ?? 'default') == 'default')
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: CupertinoButton.filled(
                    onPressed: _amending ? null : _amendContract,
                    child: _amending
                        ? const CupertinoActivityIndicator()
                        : const Text('Amend contract'),
                  ),
                ),
              ),
```

- Add the handler:

```dart
  /// Recall the sent contract so it can be edited and resent. Confirms
  /// first — this voids the document the client already received.
  Future<void> _amendContract() async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Amend contract?'),
        content: const Text(
            'This voids the contract that is out for signature. '
            "You'll be able to edit the terms and resend it."),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Amend'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _amending = true);
    try {
      await ref.read(bookingsRepositoryProvider).amendContract(
          widget.booking.band!.id, widget.booking.id);
      // Refetch flips booking to draft, which rebuilds this view into the
      // unlocked ContractEditor.
      ref.read(cacheInvalidatorProvider).onBookingDetailChanged(
          bandId: widget.booking.band!.id, bookingId: widget.booking.id);
    } catch (e) {
      if (mounted) {
        showCupertinoDialog<void>(
          context: context,
          builder: (dialogContext) => CupertinoAlertDialog(
            title: const Text('Amend Failed'),
            content: Text(e.toString()),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _amending = false);
    }
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /home/eddie/github/tts_bandmate && flutter test test/features/bookings/widgets/contract_default_view_amend_test.dart`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit (mobile repo)**

```bash
cd /home/eddie/github/tts_bandmate
git add lib/features/bookings/widgets/contract/contract_default_view.dart test/features/bookings/widgets/contract_default_view_amend_test.dart
git commit -m "feat(bookings): Amend contract action on the locked contract view"
```

---

### Task 8: Functional contract-type picker (tts_bandmate)

**Files:**
- Modify: `lib/features/bookings/screens/booking_contract_screen.dart` (`_openContractOptionPicker`, ~line 48, and its call site in `_NoneView`)
- Test: `test/features/bookings/screens/booking_contract_option_picker_test.dart`

**Interfaces:**
- Consumes: `BookingsRepository.updateBooking(bandId, bookingId, contractOption: …)` (already exists), Task 4's backend rule.
- Produces: working "Change to a contract type" flow on the `none` view; same labels as the create form.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/bookings/data/bookings_repository.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_detail.dart';
import 'package:tts_bandmate/features/bookings/providers/bookings_provider.dart';
import 'package:tts_bandmate/features/bookings/screens/booking_contract_screen.dart';
import 'package:tts_bandmate/shared/cache/cache_invalidator.dart';

// The "Change to a contract type" action on the verbal-agreement view was a
// "(coming soon)" stub. It now PATCHes contract_option with the same
// vocabulary as the create form.

class _FakeRepo extends BookingsRepository {
  _FakeRepo() : super(Dio());

  int updateCalls = 0;
  String? capturedContractOption;

  @override
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
    updateCalls++;
    capturedContractOption = contractOption;
    return _detail(contractOption: contractOption ?? 'none');
  }
}

class _NoopInvalidator extends CacheInvalidator {
  _NoopInvalidator(super.ref);

  @override
  void onBookingDetailChanged(
      {required int bandId,
      required int bookingId,
      String? contractEnvelopeId}) {}
}

BookingDetail _detail({String contractOption = 'none'}) => BookingDetail(
      id: 1,
      name: 'Test Booking',
      startDate: '2026-06-01',
      endDate: '2026-06-01',
      eventCount: 1,
      isMultiEvent: false,
      isPaid: false,
      contacts: const [],
      events: const [],
      contractOption: contractOption,
      status: 'confirmed',
      band: const BandSummary(id: 1, name: 'Band', isOwner: true),
    );

Future<_FakeRepo> _pumpNoneScreen(WidgetTester tester) async {
  final repo = _FakeRepo();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        bookingDetailProvider.overrideWith((ref, args) async => _detail()),
        bookingsRepositoryProvider.overrideWithValue(repo),
        cacheInvalidatorProvider.overrideWith(_NoopInvalidator.new),
      ],
      child: const CupertinoApp(
        home: BookingContractScreen(bandId: 1, bookingId: 1),
      ),
    ),
  );
  await tester.pump();
  return repo;
}

void main() {
  testWidgets('picker offers the create-form vocabulary, no coming-soon',
      (tester) async {
    await _pumpNoneScreen(tester);

    await tester.tap(find.text('Change to a contract type'));
    await tester.pumpAndSettle();

    expect(find.text('Generated by Bandmate'), findsOneWidget);
    expect(find.text('Upload my own'), findsOneWidget);
    expect(find.text('No contract'), findsOneWidget);
    expect(find.textContaining('coming soon'), findsNothing);
  });

  testWidgets('choosing Generated by Bandmate PATCHes contract_option',
      (tester) async {
    final repo = await _pumpNoneScreen(tester);

    await tester.tap(find.text('Change to a contract type'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Generated by Bandmate'));
    await tester.pumpAndSettle();

    expect(repo.updateCalls, 1);
    expect(repo.capturedContractOption, 'default');
  });

  testWidgets('cancel and re-picking the current option make no call',
      (tester) async {
    final repo = await _pumpNoneScreen(tester);

    await tester.tap(find.text('Change to a contract type'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Change to a contract type'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No contract'));
    await tester.pumpAndSettle();

    expect(repo.updateCalls, 0);
  });
}
```

(Verify the exact named-parameter list of `updateBooking` against `bookings_repository.dart` before running — the override must match the real signature.)

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /home/eddie/github/tts_bandmate && flutter test test/features/bookings/screens/booking_contract_option_picker_test.dart`
Expected: FAIL — finds "(coming soon)" labels / no repo call

- [ ] **Step 3: Implement the picker**

Replace `_openContractOptionPicker` in `booking_contract_screen.dart`:

```dart
  /// Change the booking's contract type. Only reachable from states where
  /// the contract is not sent/completed (the backend enforces the same).
  Future<void> _openContractOptionPicker(
      BuildContext context, String currentOption) async {
    final picked = await showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Contract type'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(ctx).pop('default'),
            child: const Text('Generated by Bandmate'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(ctx).pop('external'),
            child: const Text('Upload my own'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(ctx).pop('none'),
            child: const Text('No contract'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (picked == null || picked == currentOption || !mounted) return;

    try {
      await ref.read(bookingsRepositoryProvider).updateBooking(
            widget.bandId,
            widget.bookingId,
            contractOption: picked,
          );
      _invalidate();
    } catch (e) {
      if (mounted) {
        showCupertinoDialog<void>(
          context: context,
          builder: (dialogContext) => CupertinoAlertDialog(
            title: const Text('Change Failed'),
            content: Text(e.toString()),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }
```

Update the `_NoneView` call site to pass the current option:

```dart
                child: _NoneView(
                  onChangeType: () =>
                      _openContractOptionPicker(context, option),
                ),
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /home/eddie/github/tts_bandmate && flutter test test/features/bookings/screens/booking_contract_option_picker_test.dart`
Expected: PASS

- [ ] **Step 5: Commit (mobile repo)**

```bash
cd /home/eddie/github/tts_bandmate
git add lib/features/bookings/screens/booking_contract_screen.dart test/features/bookings/screens/booking_contract_option_picker_test.dart
git commit -m "feat(bookings): functional contract-type picker replaces coming-soon stub"
```

---

### Task 9: Full suites, on-device verification, PRs

**Files:** none new.

- [ ] **Step 1: Full mobile suite + analyze**

Run: `cd /home/eddie/github/tts_bandmate && flutter analyze && flutter test`
Expected: analyze shows only the 3 pre-existing issues (main.dart ×2, secure_storage.dart); all tests pass.

- [ ] **Step 2: Full TTS suite**

Run: `cd /home/eddie/github/TTS && docker compose exec -T app ./vendor/bin/phpunit`
Expected: PASS (re-run known flaky files sequentially if needed) plus `npm run test` green.

- [ ] **Step 3: Verify end-to-end (use the `verify` skill / run-on-device)**

Drive on the physical device against local backend (see reference_on_device_driving memory: grant permissions first, `%s` for spaces): send a contract on a test booking → confirm the locked view shows "Amend contract" → amend → editor unlocks → confirm booking is draft; check PandaDoc call in Laravel logs (`docker compose exec -T app tail storage/logs/laravel.log`). Delete the test booking afterward.

- [ ] **Step 4: PRs**

- TTS: push `feat/contract-amend`, `gh pr create --base staging` (title: "Contract amendment: recall a sent contract for editing"; body summarizes service, endpoints, web button, contract_option rule; standard footer).
- Mobile: push `feat/contract-amend`, `gh pr create --base main` (title: "Amend a sent contract from the app"; standard footer).
- Wait for Copilot review on **both** PRs and address comments before calling done (memory: feedback_wait_for_copilot_pr_review). Check whether a release is in store review — if so, bump pubspec version in this PR (memory: feedback_manual_version_bump).
