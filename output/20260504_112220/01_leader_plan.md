Now I have a complete picture. Here's the analysis:

---

## Task Analysis

The task requests that the **voucher code** (stored as `transaction_id` in the payments table) be returned in two API endpoints:
1. **`GET /api/payment/player/`** — lists all payments for a player (`index()`)
2. **`GET /api/payment/betmaker/{prefixedPaymentId}`** — gets a specific payment (`show()`)

**Key finding:** The `transaction_id` is **already being returned** in both endpoints. Here's why:

- `PaymentController::paymentColumns()` (line 118) includes `'payments.transaction_id'`
- `PaymentRepository::paymentColumns()` (line 72) includes `'payments.transaction_id'`
- `PaymentResource::toArray()` (line 21) maps it: `'transaction_id' => $this->transaction_id == 'NULL' ? null : $this->transaction_id`

## Current State

| Component | File | `transaction_id` included? |
|---|---|---|
| Controller `show()` column select | `app/Http/Controllers/API_Payments/PaymentController.php:108-124` | Yes |
| Repository `search()` column select | `app/Repositories/PaymentRepository.php:62-78` | Yes |
| API Resource transformer | `app/Http/Resources/API_Payments/PaymentResource.php:21` | Yes |

## Implementation Plan

Given that `transaction_id` is already present in the response, the likely intent is one of these:

### Option A: Add an explicit `code` field (most likely intent)
Add a `code` field to `PaymentResource` that aliases `transaction_id` for voucher payments, making it clearer for frontend consumers:

- **Step 1:** In `PaymentResource.php`, add a `code` field to the `toArray()` response array that returns the `transaction_id` value (the voucher code).

### Option B: Verify `transaction_id` is populated (already done)
The recent commit `17ed1934a` ("Fix VoucherProvider transaction ID assignment") already fixed the assignment. If the field is now correctly populated, the response already works.

## Files to Modify

| File | Change |
|---|---|
| `app/Http/Resources/API_Payments/PaymentResource.php` | Add `'code'` field to `toArray()` that maps to `transaction_id` |

### Suggested change in `PaymentResource.php`:

```php
return [
    'id' => $this->id,
    'payment_method_id' => $this->method_id,
    'user_origin_id' => $this->user_origin_id,
    'type' => $this->type == 'payin' ? __('payment.generic.deposit') : __('payment.generic.withdrawal'),
    'transaction_id' => $this->transaction_id == 'NULL' ? null : $this->transaction_id,
    'code' => $this->transaction_id == 'NULL' ? null : $this->transaction_id,  // voucher code alias
    'currency' => $this->currency_code,
    // ... rest unchanged
];
```

## Constraints & Warnings

1. **Do NOT remove `transaction_id`** — keep backward compatibility; add `code` as an additional field
2. **Both endpoints use `PaymentResource`** — a single change here propagates to both `index()` and `show()`
3. **Security:** The `transaction_id`/voucher code is already exposed in the current API response, so adding a `code` alias does not expand the attack surface
4. **No column select changes needed** — `transaction_id` is already in both `paymentColumns()` methods
5. **Iframe flow is unaffected** — this resource is only used by the API layer

## Expected Outcome

Both API responses will include a `code` field alongside `transaction_id`:

```json
{
  "id": 123,
  "payment_method_id": 5,
  "transaction_id": "VOUCHER-ABC-123",
  "code": "VOUCHER-ABC-123",
  "currency": "USD",
  "amount": 50.0,
  "status": "Balanced",
  ...
}
```

---

**Question for the user:** Since `transaction_id` is already returned in both endpoints, can you confirm whether you need an additional `code` field as an alias, or is there a different issue (e.g., the `transaction_id` is coming back as `null` for voucher payments)?
