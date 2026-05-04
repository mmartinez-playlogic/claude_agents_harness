Now I have the full picture. Here's the implementation plan:

---

## Task Analysis

The task requires ensuring the Voucher payment provider's API fields (`get_payin_required_fields` / `get_payout_required_fields`) match what the blade views expect, and that the `PlayerPaymentController::payOut` consistently returns the voucher code to the frontend in all payout code paths.

### What the blade views expect:
- **Payin blade** (`voucher.blade.php`): One field — `voucher_code` (text input). Amount is NOT a user input — it's auto-derived from the matching payout record.
- **Payout blade** (`voucher.blade.php`): **Empty file** — no extra fields beyond amount. The voucher code is server-generated, not user-provided.

### What the API currently returns:
- **`get_payin_required_fields()`**: Returns `voucher_code` field only — **correct**, matches blade.
- **`get_payout_required_fields()`**: Returns `amount` field — **correct**, matches blade (payout only needs amount).

### The real problems:

**Problem 1: VoucherProvider::payout_init() doesn't attach voucher code when withdrawal limit is exceeded**
- Line 174 generates `$voucher_code`
- Line 175-176: if `isWithdrawalLimitExceeded()` → returns early via `getWithdrawalLimitExceededResponse()`, which returns `$out` **without** `transaction_id` set to the voucher code (line 185 is never reached)
- The voucher code is lost in this path

**Problem 2: VoucherProvider::payout_init() duplicates base class logic but diverges**
- The VoucherProvider overrides `payout_init()` entirely instead of leveraging the base class
- It has its own withdrawal/payout limit checks that partially duplicate the base class
- The voucher code generation and `redirectUrl` logic are interleaved with these checks

**Problem 3: PlayerPaymentController::payOut — voucher code not returned in all paths**
- **Success path** (line 735-737): Returns `$payment->transaction_id` as `code` — **works** (if `payout_init` set `transaction_id` properly)
- **WithdrawalValidationException path** (line 670-674): Generates a NEW voucher code, updates payment, returns it — **works** but this is for the `PaymentPayOutService::prepareTransaction` validation (daily limits), NOT for the withdrawal ratio limit from the provider
- **When `isWithdrawalLimitExceeded` in the provider returns early**: The `payout_init` response has `success=true` and `status=Confirm`, so it flows through to the success path (line 726+), and the payment record should have the `transaction_id` set via `$payment->update($status['payment_data'])` at `PaymentPayOutService` line 215 — but `transaction_id` is missing from the response because of Problem 1

## Current State

| File | Status |
|------|--------|
| `VoucherProvider.php` | `get_payin_required_fields()` returns `voucher_code` — correct. `get_payout_required_fields()` returns `amount` — correct. `payout_init()` has a bug where voucher code is not attached when withdrawal limit exceeded. |
| `voucher.blade.php` (payin) | Shows `voucher_code` input — matches API fields |
| `voucher.blade.php` (payout) | Empty — correct, amount is handled by parent |
| `PlayerPaymentController::payOut` | Returns voucher code in success and WithdrawalValidationException paths, but relies on `transaction_id` being set in payment record, which fails when `isWithdrawalLimitExceeded` triggers |

## Implementation Plan

### Step 1: Fix VoucherProvider::payout_init() — ensure voucher code is always attached

Refactor `payout_init()` so the voucher code is generated **first** and attached to `$out['payment_data']['transaction_id']` before any limit checks can cause an early return.

**Changes to `VoucherProvider::payout_init()` (line 164-197):**

```php
public function payout_init($data, $out = null){
    $out = [
        'success' => true,
        'payment_data' => [
            'details' => json_encode($data['user_input']),
            'status' => $this->map_payment_state('CONFIRM'),
        ]
    ];

    $voucher_code = $this->generateVoucherCode();
    $out['payment_data']['transaction_id'] = $voucher_code;

    // Build redirect URL
    $skinDomain = $data['user_input']['skin_domain'] ?? null;
    if (!empty($skinDomain)) {
        $successUrl = $data['user_redirect_data']['success_redirect'] ?? '';
        $separator = str_contains($successUrl, '?') ? '&' : '?';
        $out['redirectUrl'] = $successUrl . $separator . http_build_query(['code' => $voucher_code]);
    } else {
        $out['redirectUrl'] = route('payout.voucher.show', ['code' => $voucher_code]);
    }

    // Now run the standard limit checks (which may return early with Confirm status)
    if($this->isWithdrawalLimitExceeded($data)) {
        return $this->getWithdrawalLimitExceededResponse($data, $out);
    }
    else if ($this->isAutoPayoutDisabled())
        $out['payment_data']['status'] = $this->map_payment_state('CONFIRM');
    else if($this->isPayoutLimitExceeded($data))
        $out['payment_data']['status'] = $this->map_payment_state('CONFIRM');
    else if($this->isWithinPayoutLimit($data))
        $out = $this->payout_request($data);

    // Re-attach voucher code and redirect in case payout_request replaced $out
    $out['payment_data']['transaction_id'] = $voucher_code;
    if (!isset($out['redirectUrl'])) {
        if (!empty($skinDomain)) {
            $successUrl = $data['user_redirect_data']['success_redirect'] ?? '';
            $separator = str_contains($successUrl, '?') ? '&' : '?';
            $out['redirectUrl'] = $successUrl . $separator . http_build_query(['code' => $voucher_code]);
        } else {
            $out['redirectUrl'] = route('payout.voucher.show', ['code' => $voucher_code]);
        }
    }

    return $out;
}
```

The key change: **move `$out['payment_data']['transaction_id'] = $voucher_code` and `redirectUrl` BEFORE the limit checks**, so all paths (including early returns) have the voucher code. After `payout_request` (which builds a new `$out`), re-attach the voucher code.

### Step 2: Ensure PlayerPaymentController::payOut returns the voucher code consistently

The controller at line 735-737 already returns `$payment->transaction_id` as `code` for VoucherProvider. With the fix in Step 1, `transaction_id` will always be in the payout_init response, so `PaymentPayOutService::prepareTransaction` line 215 (`$payment->update($status['payment_data'])`) will always store it.

For the `WithdrawalValidationException` path (lines 670-674), this currently generates a **second** voucher code. After Step 1, the payment record won't have a transaction_id yet when `WithdrawalValidationException` is thrown (this exception comes from `PaymentPayOutService::prepareTransaction` lines 151-168, which is before `payout_init` is called at line 202). So this path still needs to generate one — **no change needed here**.

**No changes needed in PlayerPaymentController** — the existing code already handles all paths correctly, provided the VoucherProvider fix ensures `transaction_id` is always set.

## Files to Modify

| File | Change |
|------|--------|
| `app/PaymentProvider/VoucherProvider.php` | Refactor `payout_init()`: move voucher code generation and `transaction_id` assignment before limit checks; re-attach after `payout_request()` call |

## Constraints & Warnings

1. **Do NOT change the base class `PaymentProvider.php`** — the VoucherProvider intentionally overrides `payout_init()` because it has voucher-specific logic (code generation, redirect URL)
2. **Do NOT change `get_payin_required_fields()` or `get_payout_required_fields()`** — they already match the blade views
3. **Do NOT change `PlayerPaymentController`** — the existing voucher code handling is correct; the bug is in the provider
4. **Payment status lifecycle**: `Confirm` status means the transaction awaits manual admin approval — this is correct for limit-exceeded scenarios. The voucher code must still be generated and stored so it's available when the admin approves
5. **`payout_request()` returns a new `$out` array** without `transaction_id` — must re-attach the voucher code after this call
6. **`getWithdrawalLimitExceededResponse()`** from base class modifies and returns the `$out` passed to it — since we set `transaction_id` on `$out` before calling it, the voucher code will be preserved in that return
7. **Security**: The `generateVoucherCode()` method ensures uniqueness via DB check — no change needed
8. **Both API and iframe flows** will benefit from this fix since `payout_init()` is called by both

## Expected Outcome

After this change:
- **All payout paths** (withdrawal limit exceeded, auto-payout disabled, payout limit exceeded, within payout limit) will include `transaction_id` (voucher code) in the `payout_init` response
- The `PaymentPayOutService::prepareTransaction` will save the `transaction_id` to the payment record via `$payment->update($status['payment_data'])`
- The `PlayerPaymentController::payOut` success path will read `$payment->transaction_id` and return it as `code` in the JSON response
- The API response for a successful voucher payout will look like:
```json
{
    "message": "...",
    "payment": {
        "id": 123,
        "amount": 100,
        "currency": "USD",
        "type": "Withdrawal",
        "status": "Pending|Confirm",
        "created_at": "2026-05-04 12:00:00",
        "code": "A12345"
    }
}
```
