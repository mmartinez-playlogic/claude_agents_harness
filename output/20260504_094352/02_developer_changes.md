Both changes are in place and correct.

## Changes Made

| File | Change |
|---|---|
| `app/Http/Controllers/API_Payments/PlayerPaymentController.php:682` | Added `$paymentResponse['code'] = $voucherCode;` in the `WithdrawalValidationException` VoucherProvider path, before the JSON response is returned |
| `app/Http/Controllers/API_Payments/PlayerPaymentController.php:744-749` | Restructured the success path VoucherProvider check to also include `$paymentResponse['code'] = $payment->transaction_id;` alongside the existing `redirect_url` logic |

## Verification Notes

- **WithdrawalValidationException path** (line 682): Uses `$voucherCode` which is the locally generated code at line 671, same value already stored in `$payment->transaction_id` at line 672 and embedded in `redirect_url` at lines 678/680.
- **Success path** (line 748): Uses `$payment->transaction_id` which is set by `VoucherProvider::payout_init()` via `$out['payment_data']['transaction_id']`.
- **Backward compatibility preserved**: `redirect_url` is still set in both paths — `code` is an additive field.
- **No changes to VoucherProvider field methods**: `get_payin_required_fields()` (returns `voucher_code`) and `get_payout_required_fields()` (returns `amount`) already match their respective blade templates.
