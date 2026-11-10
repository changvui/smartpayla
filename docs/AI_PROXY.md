# Shared AI proxy (no user API keys)

The app is meant for **all users**, so it must not ask each person to buy a DeepSeek key. The key belongs to the app owner and lives in a small **Cloudflare Worker**; the Flutter app calls the Worker.

Current deployment:

```text
https://smartpayla-ai.changvui12.workers.dev
```

```text
Flutter app  →  Cloudflare Worker (holds DEEPSEEK_API_KEY)  →  DeepSeek
```

- The app has no key field and no DeepSeek secret.
- The Worker is free on Cloudflare's Workers free plan (100,000 requests/day).
- The Worker receives only reminder fields, builds the prompt itself, and returns `{ "text": "..." }`.
- If the Worker is unavailable, the app automatically uses its built-in templates.

## 1. Create the Worker

1. Open <https://dash.cloudflare.com> → **Workers & Pages**.
2. **Create application → Create Worker**.
3. Name it `smartpayla-ai` (the URL becomes `https://smartpayla-ai.<your-subdomain>.workers.dev`).
4. Deploy the Hello World worker, then **Edit code**.
5. Replace the code with the contents of `server/worker.js`.
6. Deploy.

## 2. Add the DeepSeek secret

Worker → **Settings → Variables and Secrets**:

- Name: `DEEPSEEK_API_KEY`
- Value: the **new** DeepSeek key (revoke the one that was ever pasted into chat)
- Type: **Secret**
- Save and deploy.

Never put this key in `worker.js`, GitHub, the Flutter app, or a public repository.

## 3. Optional rate limit

The Worker supports an optional KV binding for a simple per-IP hourly limit (30 requests/hour):

1. Cloudflare → **Storage & Databases → KV** → create namespace `smartpayla-rate-limit`.
2. Worker → **Settings → Bindings → Add binding → KV namespace**:
   - Variable name: `RATE_LIMIT`
   - Namespace: `smartpayla-rate-limit`
3. Redeploy.

Without the binding, the Worker still validates input and caps output size, but has no per-IP counter.

## 4. CORS

`server/worker.js` allows:

```text
https://changvui.github.io
http://localhost:8081
http://127.0.0.1:8081
```

If you use a custom domain or a different local port, add it to `ALLOWED_ORIGINS` and redeploy.

## 5. Point the app at the Worker

Local run:

```powershell
.\tools\run_firebase.cmd -ProxyUrl "https://smartpayla-ai.<your-subdomain>.workers.dev"
```

Or add the define manually:

```powershell
flutter run -d chrome `
  --dart-define=REMINDER_PROXY_URL=https://smartpayla-ai.<your-subdomain>.workers.dev
```

Production build:

```powershell
flutter build web --release `
  --dart-define=REMINDER_PROXY_URL=https://smartpayla-ai.<your-subdomain>.workers.dev
```

For GitHub Pages, add the same `--dart-define=REMINDER_PROXY_URL=...` to the `flutter build web` step in `.github/workflows/deploy.yml`.

## 6. Test the Worker

PowerShell:

```powershell
$body = @{
  customerName = "Ahmad Faizal"
  item = "Catering order"
  amount = 400
  dueDate = "2026-10-17"
  daysOverdue = 12
  tone = "formal"
} | ConvertTo-Json

Invoke-RestMethod `
  -Uri "https://smartpayla-ai.<your-subdomain>.workers.dev/reminder" `
  -Method Post `
  -ContentType "application/json" `
  -Body $body
```

Expected:

```json
{ "text": "Dear Ahmad Faizal, ..." }
```

Then in the app: Reminders → Generate. The preview badge should show **AI**, not **Fallback**.

## 7. Security notes

- The Worker only accepts reminder fields, not arbitrary prompts, so it cannot be used as a general LLM API.
- It caps body size, validates tone/amount, limits output tokens, and optionally rate-limits per IP.
- The DeepSeek key is a Worker secret; it is never shipped to browsers.
- For a real product, add authentication and a stronger per-user quota.

## 8. Receipt scanning

The "Scan a cash bill" button sits at the top of the **New transaction** form.
Two engines share one interface (`lib/services/receipt_scanner.dart` picks at
compile time):

| Platform | Engine | Why |
|---|---|---|
| Android / iOS | **Google ML Kit** (`google_mlkit_text_recognition`) | on-device, offline, no key — the approach described in the report (§2.2.5) |
| Web | SmartPayLA Worker → vision model | ML Kit has no browser implementation |

ML Kit only returns lines of text, so the fields (customer, total, date,
reference) are recovered by the heuristics in `lib/services/scanned_bill.dart`.
The web engine returns structured JSON and uses the same parser as a fallback.

Install the dependency once:

```powershell
flutter pub add google_mlkit_text_recognition
```

### Web engine setup (only needed for the browser build)

`/scan` tries two engines in order:

1. **Any OpenAI-compatible vision API** — default is OpenRouter's **free
   Qwen2.5-VL-72B**, a document/table model that reads printed invoices well.
2. **Workers AI** — no key at all, useful fallback, weaker on small text.

### Setup (free, no card)

1. <https://openrouter.ai> → sign in with Google → **Keys → Create Key** →
   copy `sk-or-v1-...`.
2. Cloudflare → Worker `smartpayla-ai` → **Settings → Variables and Secrets** →
   add **`VISION_API_KEY`** (type: *Secret*).
3. Optional overrides (plain text): `VISION_BASE_URL`
   (`https://openrouter.ai/api/v1`), `VISION_MODEL`
   (`qwen/qwen2.5-vl-72b-instruct:free`).
4. Re-deploy `server/worker.js`, then build the app with only:

```powershell
flutter build web --release `
  --base-href "/smartpayla/" `
  --dart-define=DEMO=true `
  --dart-define=REMINDER_PROXY_URL=https://smartpayla-ai.changvui12.workers.dev
```

No scan credential ever reaches the browser: the key lives in the Worker.

### Swapping providers

Because the call is OpenAI-compatible, `VISION_BASE_URL` + `VISION_MODEL` also
drive Groq, Mistral, Together, or a self-hosted vLLM. Only those two variables
change — no code edit, no app rebuild.

### Model selection tips

| Model | Notes |
|---|---|
| `qwen/qwen2.5-vl-72b-instruct:free` | best free option for bills/tables |
| `meta-llama/llama-4-scout-17b-16e-instruct` (Groq) | faster, slightly weaker |
| Workers AI `llama-3.2-11b-vision` | no key, needs one-off `prompt: "agree"` |

### Behaviour when things are missing

| Situation | Result |
|---|---|
| No `REMINDER_PROXY_URL` in the build | "Receipt scanning is not configured…" — nothing filled |
| Photo is not a bill | `is_bill: false` → "That does not look like a cash bill" |
| No `VISION_API_KEY` and no `AI` binding | 503 "Scan is not configured…" |
| Primary engine fails | falls through to Workers AI automatically |
| Both fail | 502 with each engine's reason, e.g. `openrouter: 429 … | workers-ai: …` |

The parsed values only fill **empty** fields, the total is cross-checked against
the sum of the printed line items, and the agent still presses Save — so a
misread bill can always be corrected.

**Note on scope:** the FYP report currently says the OCR uses *Google ML Kit*
(§2.2.5). This implementation uses a server-side vision model instead — update
that paragraph, or switch to `google_mlkit_text_recognition` if the report must
stay as written (ML Kit is on-device, Android/iOS only, and has no web support).
