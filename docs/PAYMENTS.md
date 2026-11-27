# Payments

How money moves through SmartPayLA, and what the ledger records.

## 1. The rule the ledger is built around

**One payment settles exactly one bill.**

Every bill has a unique number (invoice number, cash-bill number, or a generated
`CB-yyMMdd-NNNN`). The number is printed on the reminder, shown on the statement as the
transfer reference, and carried by the payment claim. Reconciliation therefore never has
to decide how to split an amount.

## 2. Append-only ledger

`users/{uid}/payments/{paymentId}`

| Field | Meaning |
|---|---|
| `amount` | money received by this entry |
| `method` | `cash`, `duitnow`, `bank`, `writeOff` |
| `state` | `confirmed` or `voided` |
| `receiptNo` | `RCP-yyMMdd-XXXX`, generated on the device |
| `proofImage` | screenshot, photo of the cash, or a generated receipt |
| `declaredByCustomer` | true when the customer started it |
| `note` / `reference` | free text / gateway or statement reference |

`advancePaid` and `status` on the transaction are a **cache** recomputed from these rows;
nothing in the interface may write them. A mistake is corrected by voiding the payment
with a mandatory reason, which keeps the history.

## 3. Two ways money arrives

### 3.1 The customer pays on the hosted checkout (card)

```
statement tab                         Worker                    Stripe
  Pay now ─────────────────────────▶ /pay/create ─────────────▶ Checkout Session
  open checkout tab (blank tab, then pointed at the URL) ◀────── { id, url }
  poll /pay/verify every 3 s ──────▶ /pay/verify ──────────────▶ session lookup
                                        { paid, amount, method, token }
  paid ─▶ write claim(autoConfirm) ─▶ agent client confirms ─▶ payment + receipt
```

Details that matter:

- The checkout tab is opened **inside the click** (`window.open` before any `await`),
  because a popup opened after a network call is blocked.
- The statement tab polls the session id it already holds, so a redirect that loses its
  query, is blocked, or lands in another tab cannot lose the payment.
- `client_reference_id` carries the statement token, so the return can be tied back to
  the right statement even with no query string.
- `/pay/verify` is the trust anchor: `paid=1` in a URL is not evidence; only the Stripe
  session status is.
- The session carries `metadata[bill]`, `metadata[customer]` and
  `metadata[statement_token]`, so a payment can be traced from the Stripe dashboard
  without opening this application.

### 3.2 The customer transfers directly (DuitNow, bank, cash)

Available when the build has no gateway keys. The statement shows the QR, the bill number
to use as the transfer reference, and "I have paid"; the customer attaches a screenshot
and the agent confirms it. Because the reference is the bill number, the payment can also
be matched from a bank statement.

## 4. Confirmation

Gateway payments are written with `autoConfirm: true`. A notifier at the application root
watches `paymentClaims` and, for any claim carrying that flag, writes the payment, reloads
the ledger and republishes the statement. This runs in whichever context the signed-in
agent session is — dashboard, or the agent's own phone showing a statement.

Why the client and not the server: the Worker has no Firestore service account (that
requires a paid project), so it can verify a payment but not record it. The trade-off is
that the agent must be online; if they are not, the claim waits and is confirmed the next
time the app runs.

## 5. Evidence

| Situation | Evidence required |
|---|---|
| Sale on credit | bill photograph, or a recorded reason why none exists |
| Sale with money received (partial or paid) | **both** the bill photograph and the proof of payment |
| Customer declares a transfer | screenshot |
| Agent records a cash payment | photo of the cash or the receipt |
| Gateway payment | generated receipt (the gateway leaves a receipt, not a photograph) |

## 6. Receipts

Two receipts exist and they answer different questions.

| Receipt | Issued by | Answers |
|---|---|---|
| Stripe receipt | Stripe, by email if the customer typed one | "did the card network see this?" |
| Merchant receipt (PDF) | this app, on the customer's device | "which bill, how much was already paid, what is left" |

The PDF is written by a small hand-rolled writer (`lib/services/receipt_pdf.dart`), so
there is no PDF dependency and no network call. It states the bill number, what had been
paid before, this payment, and what remains.

## 7. Salesman-side evidence

The payment history shows the proof as a thumbnail for every entry, and "no proof"
explicitly when a payment has none. Gateway payments show the receipt that was generated
for them, so the audit trail has no gaps.

## 8. Refunds

Refunds are issued in the Stripe dashboard (the payment's metadata names the bill). The
ledger is **not** notified: the agent voids the payment with a reason, which restores the
balance and keeps the history. Automating the second step requires the
`charge.refunded` webhook plus a server credential, which is future work.

## 9. Failure modes seen in practice

| Symptom | Cause | Fix in place |
|---|---|---|
| `payment_method_types` rejected | Stripe removed the parameter | `allowed_payment_method_types`, or dashboard defaults |
| "invalid payment method" for small bills | MYR minimum is RM 2.00 | use a larger amount to test |
| Redirect lands on the login page | query string lost | `client_reference_id` + local token + verification resolver |
| Payment seen but balance unchanged | agent offline, or claim not written | polling path, auto-confirm, diagnostic strip on the statement |
| Receipt not downloaded | browser blocked the automatic download | the "Download receipt (PDF)" button |
