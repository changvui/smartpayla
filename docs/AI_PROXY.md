# Shared AI proxy (no user API keys)

The app is meant for **all users**, so it must not ask each person to buy a DeepSeek key. The key belongs to the app owner and lives in a small **Cloudflare Worker**; the Flutter app calls the Worker.

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
