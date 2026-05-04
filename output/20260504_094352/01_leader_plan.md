Now I have a complete picture. Here's the implementation plan:

---

## Task Analysis

The task has two parts:
1. **VoucherProvider fields**: The `get_payin_required_fields()` and `get_payout_required_fields()` methods should return fields matching what the blade templates expect (the blade payin template has `voucher_code`, the payout blade is empty — meaning only `amount` is needed).
2. **PlayerPaymentController payout response**: When a voucher payout succeeds (normal path, not just `WithdrawalValidationException`), the response should include the generated voucher code so the frontend can display it.

## Current State

**VoucherProvider fields** (current):
- `get_payin_required_fields()`: returns `voucher_code` field only — **matches blade** ✅
- `get_payout_required_fields()`: returns `amount` field only — **matches blade** (empty blade = only amount needed) ✅

**VoucherProvider `payout_init()`** (current):
- Generates a voucher code, sets `$out['payment_data']['transaction_id']` to it
- Sets `$out['redirectUrl']` with the code appended as query param
- This `redirectUrl` is already passed through to the controller response at line 743-745

**PlayerPaymentController `payOut()` success path** (current):
- Lines 743-745: Already checks for `redirectUrl` specifically for VoucherProvider and adds it to response
- **However**, the `redirectUrl` contains the code embedded in a URL — the frontend may need just the raw `code` value directly in the response

**PlayerPaymentController `payOut()` WithdrawalValidationException path** (current):
- Lines 670-682: Has special VoucherProvider handling — generates a new voucher code, updates payment, builds redirect URL with code
- **Problem**: This generates a *second* voucher code separate from `payout_init()`, because the exception is thrown *before* `payout_init()` runs (it's thrown in `prepareTransaction` at the validation stage)

## Implementation Plan

### Step 1: Add voucher `code` to the payout success response in PlayerPaymentController

In the success path (after line 743-745), when the provider is VoucherProvider, also include the raw voucher `code` in the `paymentResponse` array so the frontend doesn't have to parse it from a URL.

**File**: `app/Http/Controllers/API_Payments/PlayerPaymentController.php`
**Change**: After the existing `redirectUrl` logic for VoucherProvider (line 743-745), also add:
```php
if ($payment_provider instanceof \App\PaymentProvider\VoucherProvider) {
    $paymentResponse['code'] = $payment->transaction_id;
}
```

### Step 2: Add voucher `code` to the WithdrawalValidationException path response

The `WithdrawalValidationException` handler at line 670-682 already has voucher code logic. Add the raw `code` field to the response as well.

**File**: `app/Http/Controllers/API_Payments/PlayerPaymentController.php`  
**Change**: Inside the VoucherProvider block (around line 672-681), add `$paymentResponse['code'] = $voucherCode;`

### Step 3: Verify VoucherProvider required fields match blade

The current state already matches:
- **Payin**: blade has `voucher_code` field → `get_payin_required_fields()` returns `voucher_code` ✅
- **Payout**: blade is empty (no extra fields) → `get_payout_required_fields()` returns only `amount` ✅

No changes needed to VoucherProvider field methods.

## Files to Modify

| File | Change |
|---|---|
| `app/Http/Controllers/API_Payments/PlayerPaymentController.php` | Add `code` field to payout response in both success and WithdrawalValidationException paths |

## Constraints & Warnings

1. **Do NOT change `payout_init()` logic** — the voucher code generation and `redirectUrl` construction work correctly
2. **Do NOT remove `redirectUrl`** — keep backward compatibility; `code` is an additional field
3. **Both paths must return `code`**: the normal success path (line 743+) and the `WithdrawalValidationException` path (line 670+)
4. **The `code` value source differs by path**:
   - Success path: `$payment->transaction_id` (set by `payout_init` via `payment_data['transaction_id']`)
   - Exception path: `$voucherCode` (generated locally in the catch block)
5. **Security**: The voucher code is already generated server-side with uniqueness checks — no user input involved
6. **Do NOT modify VoucherProvider `get_payin_required_fields()` or `get_payout_required_fields()`** — they already match the blade templates

## Expected Outcome

**Payout success response** (202):
```json
{
  "message": "...",
  "payment": {
    "id": 123,
    "amount": 100,
    "currency": "KES",
    "type": "Withdrawal",
    "status": "Pending",
    "created_at": "2026-05-04 12:00:00",
    "redirect_url": "https://...?code=A12345",
    "code": "A12345"
  }
}
```

**Payout WithdrawalValidationException response** (202):
```json
{
  "message": "...",
  "payment": {
    "id": 123,
    "amount": 100,
    "currency": "KES",
    "type": "Withdrawal",
    "status": "Confirm",
    "created_at": "2026-05-04 12:00:00",
    "redirect_url": "https://...?code=B67890",
    "code": "B67890"
  }
}
```

The frontend receives the voucher `code` directly without needing to parse URLs, while `redirect_url` is preserved for backward compatibility.
