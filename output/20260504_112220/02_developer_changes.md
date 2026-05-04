## Changes Made
| File | Change |
|---|---|
| `app/Http/Resources/API_Payments/PaymentResource.php:22` | Added `code` field as an alias for `transaction_id` (the voucher code) |

## Verification Notes
- `transaction_id` is already included in both `PaymentController::paymentColumns()` and `PaymentRepository::paymentColumns()`, so no column select changes were needed.
- Both the `index()` (list all payments) and `show()` (get specific payment) endpoints use `PaymentResource`, so both will now return the `code` field.
- The existing `transaction_id` field is preserved for backward compatibility.
- No other files were modified — the single change in the resource propagates to both endpoints.
