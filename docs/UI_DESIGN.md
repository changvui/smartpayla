# SmartPayLA — UI design

This document is the working UI specification for the prototype. It covers the screens a sales agent uses, the screens that belong to the partner module, and the visual system shared by both.

## 1. Who the app is for

| User | What they need | Where it lives |
|---|---|---|
| Sales agent / micro-merchant | Record a credit sale, see who still owes money, update payment status, check commission | Home, Transactions, Transaction form/detail, Settings |
| Sales agent | Send a polite payment reminder | Reminders (Increment 4) |
| Partner module (Kerry) | Sign in, manage customers, scan receipts, view reminder history, configure API key/tone/rate | Auth, Customers, Receipts, Reminder management, Settings (separate module) |
| Supervisor / examiner | Understand the flow in a demo | The same screens, using **Load demo data** |

Increment 1 implements the first row and leaves clearly labelled placeholders for the rest.

## 2. Navigation map

```text
HomeShell (bottom navigation)
├── Home
│   ├── New transaction  → Transaction form
│   ├── Generate reminder → Reminders (placeholder)
│   ├── Recent row        → Transaction detail
│   └── See all           → Transactions tab
├── Transactions
│   ├── Search + status filter
│   ├── Bill month picker
│   ├── Row               → Transaction detail
│   ├── Row menu          → Edit / Delete
│   └── FAB "New"         → Transaction form
├── Reminders (Increment 4)
└── Settings
    ├── Commission rate
    ├── Load demo data
    ├── Clear all transactions
    └── About / increment status
```

`Transaction detail` → **Update payment** opens a bottom sheet:

- Mark as fully paid → status Paid, advance = total.
- Record a partial payment → amount dialog, status Partial or Paid.
- Mark as unpaid → status Unpaid, advance = 0.

## 3. Visual system

| Token | Value | Use |
|---|---|---|
| Primary | `#0B6B5B` deep teal | brand, primary buttons, selected nav |
| Primary dark | `#064A40` | hero gradient |
| Background | `#F4F7F6` | app background |
| Surface | `#FFFFFF` | cards, navigation bar |
| Ink | `#14201D` | headings, amounts |
| Muted | `#667873` | labels, hints, secondary text |
| Border | `#E1EAE6` | card and field borders |
| Green | `#1E7B4F` | paid, positive |
| Amber | `#B26A00` | partial payment |
| Red | `#B3261E` | overdue, destructive action |
| Blue | `#2B5F9E` | unpaid, informational |

- **Shape:** 18 px cards, 12–14 px fields/buttons, 999 px pills.
- **Type:** system sans (Roboto on Android, SF on iOS). Section titles 16–24 px / 700–800; body 12.5–14 px; captions 10.5–12 px.
- **Elevation:** flat cards with a 1 px border; one soft shadow only on the home hero.
- **Spacing:** 20 px page padding, 10–16 px between cards, 8–12 px inside forms.
- **Feedback:** floating snackbars; confirmation dialogs for delete; inline validation messages.
- **Empty states:** icon in a tinted circle, short title, one sentence, one primary action (and “Load demo data” on the empty ledger).

## 4. Screen specifications

### 4.1 Home

**Purpose:** answer “how much am I owed, how old is the debt, and what did I earn?” in one screen.

- Greeting + “Your field ledger”.
- Hero card: total outstanding (largest number), open transaction count, MYR badge.
- Two stat cards: commission earned (rate applied to paid sales), collected (sum of paid totals).
- Debt aging: three labelled bars (0–30, 31–60, 60+), each with amount; the bar is the share of outstanding.
- Quick actions: **New transaction** (filled), **Generate reminder** (outlined; opens the Reminders tab).
- Recent transactions: three rows; tap for detail; “See all” goes to the Transactions tab.

### 4.2 Transactions

**Purpose:** find a customer/debt fast and act on it.

- Search field (customer, item, invoice, cash-bill number).
- **Bill month selector:** “All bill months” by default; tapping opens a year/month sheet. Selecting a month shows only bills in that month; the X clears it.
- Filter chips: All, Unpaid, Partial, Paid, Overdue.
- Count + outstanding for the current filter.
- Rows sorted by bill date, newest first (cash-bill date → invoice date → record date).
- Row: initials avatar, customer, item, balance, status pill, due/overdue label, overflow menu (Edit/Delete).
- FAB: **New**.
- Empty state differs for “no data yet” vs “no search results” vs “no bills in this month”.

### 4.3 Transaction form

**Purpose:** record a handwritten cash bill or invoice with the minimum friction.

Sections, in order:

1. **Customer & item** — customer name (required), item/service.
2. **Amounts** — total (required), advance (enabled only for Partial), live **Balance due** card.
3. **Payment status** — segmented Unpaid / Partial / Paid; the advance field is automatic for Unpaid/Paid.
4. **Dates** — due date (required), finish/delivery date, claim expiry.
5. **Reference documents (optional)** — invoice number/date, cash-bill number/date.

Validation:

- Customer required.
- Total > 0.
- Partial: 0 < advance < total.
- Dates use native date pickers; optional dates can be cleared.
- Save button stays at the bottom; shows a spinner while writing.

### 4.4 Transaction detail

**Purpose:** explain the balance and let the agent update it without editing the whole form.

- Header: customer, item, status, total, paid fraction bar, paid/balance labels.
- Balance breakdown: total, paid, balance (red if > 0, green if 0).
- Details: status, aging, due date, finish date, claim expiry, invoice/cash-bill references, last updated.
- Actions: **Update payment** (bottom sheet), **Edit transaction**, **Delete transaction**.

### 4.5 Reminders

**Purpose:** generate a payment reminder for an open/overdue transaction with as little typing as possible.

- Hero: “AI payment reminders” with the fallback promise.
- If the AI proxy is not configured: amber banner explaining that the built-in templates are being used.
- Customer dropdown: open transactions, sorted by days overdue and balance.
- Tone segmented control: **Formal / Friendly / Urgent**.
- **Generate reminder** button with spinner; an 8-second API timeout.
- Preview card: generated text, AI/Fallback badge, copy button, fallback reason.
- History: last reminders with customer, tone, timestamp and a three-line preview; clear action.
- The partner module owns WhatsApp sharing and the cross-device history list.

### 4.6 Commission

**Purpose:** answer “how much commission did I earn, and from which sales?”.

- Hero: commission earned at the current rate, paid-sale count.
- Mini stats: potential commission from open sales, paid-sale count.
- Month dropdown: All time plus every month that has a transaction.
- Per-sale lines: customer, sale amount, bill date, commission amount, rate.
- Empty state explains that commission is counted only when a transaction is fully paid.
- The rate itself is edited in Settings; every view recalculates immediately.

### 4.7 Settings

- Profile card (name, student ID, local/sync status).
- Commission rate field (percent) with save.
- AI reminders: SmartPayLA AI status (shared DeepSeek proxy, no user key), default tone, save.
- Cloud sync: status badge, connected user, Sync now, or a local-only explanation.
- Data: Load demo data, Clear all transactions.
- About: build, framework, currency, cloud sync, AI reminders.
- Note that auth/customers/OCR/reminder delivery belong to the partner module.

## 5. Partner-module screens (future)

These are not implemented in this module but are reserved in the navigation model:

- **Auth:** login, register, forgot password (Firebase Authentication).
- **Customers:** list, profile, add/edit, transaction history.
- **Receipts:** camera/gallery, OCR extraction, attach image to a transaction.
- **Reminder management:** message history, copy, share to WhatsApp.
- **Settings (shared):** default tone, commission rate, theme.

The integration contract is the read-only Riverpod state in `lib/integration/partner_bridge.dart`: transactions, commission report, overdue accounts, reminder history and payload helpers.

## 6. Responsive behaviour

- Phone-first single column.
- Content is capped at 560 px and centred on tablets/browsers; no two-column desktop layout in this module.
- Forms and lists remain scrollable at 320 px width; buttons use ellipsis/flexible labels.
- Web build is a PWA: standalone display, portrait orientation, teal theme colour.

## 7. Increment mapping

| Increment | UI delivered |
|---|---|
| 1 | Home, Transactions, Form, Detail, Settings; local data; bill-month filter |
| 2 | Sync badge, cloud sync card, Firestore-backed repository, pull-to-refresh |
| 3 | Commission screen, month view, per-sale lines, rate-driven recalculation |
| 4 | Reminder composer, tone selection, preview, copy, fallback banner, history |
| 5 | Partner contract providers and integration documentation |
