# SmartPayLA

A field ledger for sales agents who sell on credit. An agent records a sale once and
everything else is derived from that record: the balance, the debt aging, the commission,
a reminder written in the customer's language, and a payment link the customer can open
without an account.

This repository is the final-year project implementation (Tiong Chang Vui, 25WMR00499),
combining the core transaction engine and AI reminder module with the partner's
authentication, customer-profile and receipt-capture module.

---

## What works

### Transactions and aging
- Create, edit and delete a sale: customer (chosen from the customer list, never typed),
  item lines with quantity and unit price, due date, finish date, claim expiry, and a
  **mandatory unique bill/invoice number**.
- **Derived, never stored**: balance, payment status and aging bucket
  (`0–30`, `31–60`, `60+`) are getters, so a record that says Paid while carrying a
  balance cannot exist.
- **Evidence is mandatory**: a sale carries either a bill photograph or a recorded
  reason. A sale that records money (**Partial or Paid**) requires **both** the bill
  photograph and the proof of payment.
- Bill photos are compressed to 900 px and embedded as a data URI, so they follow the
  account to another device.
- Status colour encodes urgency: slate on time, amber due within a week, red overdue,
  blue partial, green settled; every pill also carries an icon.

### Dashboard
- Month-scoped collections and commission; outstanding is all-time because it is a
  stock, not a flow. A month/year picker moves the period.
- Aging donut (`fl_chart`), per-bucket bars, recent activity, pending-claims banner.

### Commission
- Pure-Dart engine (`lib/services/commission_engine.dart`): earned on settled sales,
  potential on open ones, bucketed by bill month.

### AI reminders
- The tab is a **ranked worklist**: customers are ordered by overdue days and by how long
  since they were last contacted, with filters (all / never reminded / 30+ days).
- **Three tones × three languages** (English, Bahasa Malaysia, 中文); the local template
  fallback exists in all three.
- The message carries the **bill number** and a **payment link**.
- Every send is written to a local log (200 entries), which is what "last reminded"
  reads.
- Degrades to the template on timeout (12 s), quota exhaustion or an empty reply, and the
  interface says which path produced the text.

### Payment ledger and gateway
- Append-only payments with a receipt number (`RCP-yyMMdd-XXXX`), method, evidence photo
  and a mandatory reason when voided.
- **Stripe Checkout** (test mode) for card payments: a session is created server-side,
  the customer pays on the hosted page, and the session is **verified** before anything
  is written. The statement tab polls the session, so a lost or blocked redirect cannot
  lose a payment.
- Gateway payments are recorded with `autoConfirm`, so the agent does not approve the
  same money twice; the agent client performs the write it is already allowed to perform.
- A gateway payment produces a **PDF receipt** drawn on the client (no PDF dependency)
  and downloaded automatically, with a manual button as fallback.

### Customer statement
- A 20-character token grants read access to **one** customer's snapshot; the customer
  never signs in.
- The page shows the open bills, the amount to pay (pay in full or a partial amount),
  and **Pay now**.
- Opening a statement link signs the device out and absorbs the browser Back button, so a
  link opened on a borrowed phone cannot reveal an agent dashboard.
- After payment the page shows the payment immediately (oldest bill first) and the
  agent's ledger catches up.

### Offline sync and security
- Local cache first, Firestore second; merge by `updatedAt`; a sync badge reports
  Local / Syncing / Synced / Error.
- Customers are offline-first too, with a queued write that is retried, scoped per
  account.
- Firestore rules scope every document to its owner; a statement is readable by token
  only; a customer can create exactly one thing — a **pending** payment claim.

### Partner integration
- Read-only Riverpod providers and payload helpers for transactions, commission, overdue
  accounts and reminder history (see `docs/INTEGRATION.md`).

---

## Run it

```powershell
cd C:\Users\user\Desktop\DSH\FYP\smartpayla-kerry
flutter pub get
flutter run -d web-server --web-port=8080 `
  --dart-define=DEMO=true `
  --dart-define=APP_ORIGIN=http://localhost:8080/ `
  --dart-define=REMINDER_PROXY_URL=https://smartpayla-ai.changvui12.workers.dev
```

Then open <http://localhost:8080>.

`.\tools\run_web.cmd` runs the same command.

| Define | Purpose |
|---|---|
| `DEMO=true` | seeds sample data when the ledger is empty |
| `APP_ORIGIN` | origin used when building customer links |
| `REMINDER_PROXY_URL` | Worker base URL for AI reminders, scanning and payments |
| `STRIPE_CHECKOUT=true` | enables the Stripe checkout instead of the built-in simulated one |
| `GOOGLE_SERVER_CLIENT_ID` | web OAuth client id for native Google sign-in |

### Build for Android

```powershell
flutter build apk --release `
  --dart-define=DEMO=true `
  --dart-define=REMINDER_PROXY_URL=https://smartpayla-ai.changvui12.workers.dev `
  --dart-define=GOOGLE_SERVER_CLIENT_ID=<web-client-id>.apps.googleusercontent.com
```

### Deploy

- Web: GitHub Actions builds and publishes to GitHub Pages on every push to `main`
  (`.github/workflows/deploy.yml`).
- Worker: paste `server/worker.js` into the Cloudflare dashboard and set the secrets —
  `DEEPSEEK_API_KEY`, `GEMINI_API_KEY`, `STRIPE_SECRET_KEY`, optional `GEMINI_MODEL`,
  `STRIPE_METHODS`. See `docs/AI_PROXY.md` and `docs/PAYMENTS.md`.

---

## Tests

```powershell
flutter test        # 34 tests
dart analyze lib    # no issues
```

| File | Covers |
|---|---|
| `transaction_test.dart` | balance, overdue, buckets, JSON round-trip, bill-date precedence |
| `commission_test.dart` | settled-only commission, month filter |
| `reminder_test.dart` | template fallback, proxy passthrough, error fallback |
| `scanned_bill_test.dart` | scanned items, quantity/unit price, malformed rows |
| `payment_receipt_test.dart` | the generated receipt image |
| `receipt_pdf_test.dart` | the PDF receipt document |
| `status_pill_test.dart` | urgency palette and the colour-blind icon |
| `month_filter_test.dart`, `reminder_screen_test.dart`, `widget_test.dart` | screens |

---

## Documentation

| File | Contents |
|---|---|
| `docs/DEPLOY.md` | web and Android deployment, GitHub Pages |
| `docs/FIREBASE.md` | Firestore layout and the complete security rules |
| `docs/AI_PROXY.md` | Worker routes: `/reminder`, `/scan`, `/chat`, `/pay/*` |
| `docs/PAYMENTS.md` | payment ledger, Stripe checkout, verification, refunds |
| `docs/INTEGRATION.md` | the partner contract |
| `docs/UI_DESIGN.md` | design language and status semantics |

---

## Known limitations

- **Refunds are two steps**: refund in the Stripe dashboard, then void the payment in the
  ledger with a reason. Automating the second step needs a webhook.
- **The agent must be online** for a gateway payment to reach the ledger: the write is
  performed by the signed-in agent client, because the server has no Firestore service
  account on the free tier.
- **No FPX/GrabPay/Touch n Go**: Stripe exposes local methods only to verified merchant
  accounts; the acquirers that offer them (Curlec, iPay88, HitPay) need business
  registration.
- Sync is last-write-wins; there is no field-level merge.
- iOS builds in principle but has never been built (needs macOS and Xcode).
