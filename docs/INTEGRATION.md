# Partner integration contract

This document describes the boundary between the **Core Transaction Engine + AI Reminder Generation** module (Tiong Chang Vui) and the partner module (Wong Kai Lit Kerry: authentication, customers, OCR/receipts, reminder history UI, settings).

The partner module should depend on the providers in `lib/integration/partner_bridge.dart`, not on this module's screens or widgets.

## 1. Ownership

| Area | Owner | Notes |
|---|---|---|
| Transaction CRUD, balance, payment status, aging | Transaction module | Firestore path `users/{userId}/transactions/{transactionId}` |
| Commission calculation | Transaction module | Rate comes from shared settings; engine is pure Dart |
| AI proxy + prompt + reminder text + fallback | Transaction module | The app-owned key lives in the Cloudflare Worker, never in the client |
| Authentication and UID | Partner module | Pass the UID into the transaction scope |
| Customer profiles | Partner module | Transaction stores a denormalised `customerName` for the ledger |
| OCR / receipt images | Partner module | Attach a receipt reference to a transaction if needed |
| Reminder history UI / WhatsApp share | Partner module | Consume the generated text |
| Default tone, commission rate settings | Shared | This build stores the tone locally; the integrated build can move it to the partner Settings screen |

## 2. Firestore data contract

```text
users/{userId}/transactions/{transactionId}
```

Each document is the same JSON as `Transaction.toJson()`:

```json
{
  "id": "f3b0...",
  "customerName": "Ahmad Faizal",
  "itemDescription": "Catering order — 80 pax",
  "totalAmount": 1200.0,
  "advancePaid": 400.0,
  "dueDate": "2026-10-17T00:00:00.000",
  "status": "partial",
  "createdAt": "2026-10-09T08:00:00.000",
  "updatedAt": "2026-10-27T08:00:00.000",
  "finishDate": null,
  "claimExpiry": null,
  "invoiceNumber": "INV-2026-041",
  "invoiceDate": null,
  "cashBillNumber": null,
  "cashBillDate": null
}
```

- `status` is one of `unpaid`, `partial`, `paid`. “Overdue” is derived from `dueDate`; it is not stored.
- `balanceDue` is derived (`totalAmount - advancePaid`) and is not stored.
- Dates are ISO 8601 strings so the same payload works in local storage and Firestore.
- `updatedAt` is the merge key. The latest value wins during sync.
- `billDate` = `cashBillDate ?? invoiceDate ?? createdAt`; use it for month filters and commission periods.

## 3. Read-only providers

Import `lib/integration/partner_bridge.dart` and watch:

```dart
final transactions = ref.watch(partnerTransactionsProvider);
final commission = ref.watch(partnerCommissionProvider);
final overdue = ref.watch(partnerOverdueProvider);
final reminders = ref.watch(partnerReminderHistoryProvider);
```

| Provider | Type | Purpose |
|---|---|---|
| `partnerTransactionsProvider` | `List<Transaction>` | Current ledger, newest first |
| `partnerCommissionProvider` | `CommissionReport` | Earned, potential, paid/open counts and per-sale lines |
| `partnerOverdueProvider` | `List<Transaction>` | Open transactions past their due date |
| `partnerReminderHistoryProvider` | `List<ReminderRecord>` | Generated reminder texts |

Payload helpers:

```dart
PartnerBridge.transaction(t);
PartnerBridge.commission(report);
PartnerBridge.reminder(record);
```

## 4. Reminder handoff

The transaction module generates a `ReminderResult`:

```dart
class ReminderResult {
  final String text;
  final ReminderTone tone;      // formal | friendly | urgent
  final bool usedFallback;      // true when the LLM was unavailable
  final String? error;          // diagnostic, not shown to the customer
}
```

The recipient for a reminder is the transaction's denormalised `customerName`; the partner module can replace it with the full customer profile from its own collection.

The partner's reminder UI should:

1. Show `text` in an editable field.
2. Show a “template fallback” badge when `usedFallback` is true.
3. Copy/share the final text; this module does not send WhatsApp messages.
4. Save the final text in its own history collection if it wants cross-device history.

## 5. Integration steps

1. Partner authentication signs the user in with Firebase Auth.
2. `FirebaseConfig.userId` reads `FirebaseAuth.instance.currentUser.uid` automatically, so the Firestore path becomes `users/{uid}/transactions/{id}`. No extra hand-off call is needed. `APP_USER_ID` is only the fallback when nobody is signed in.
3. Make sure Firestore rules allow the signed-in owner:

```javascript
match /users/{userId}/transactions/{transactionId} {
  allow read, write: if request.auth != null
                     && request.auth.uid == userId;
}
```

4. The partner Settings screen writes the commission rate and reminder settings through the shared settings provider, or passes them to this module.
5. The partner reminder screen consumes `partnerReminderHistoryProvider` / the generated text and handles sharing.
6. The partner customer screen can open a transaction list filtered by `customerName`; a future schema version should add `customerId`.

## 6. Compatibility notes

- The transaction module never imports partner screens or widgets.
- The partner module should not write directly to `transactions`; use the repository/service so local cache and sync stay consistent.
- If the partner needs a new field (for example `customerId` or `receiptUrl`), add it to `Transaction` and both serializers rather than writing an ad-hoc map.
- `APP_USER_ID=demo-agent` is only for the standalone prototype and test-mode Firestore rules.
