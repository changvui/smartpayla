/**
 * SmartPayLA AI proxy — Cloudflare Worker
 *
 * Two jobs, one endpoint base:
 *
 *   POST /reminder  → DeepSeek chat model (text-only) writes a payment reminder
 *   POST /scan      → vision model reads a photo of a cash bill
 *
 * /scan tries, in order:
 *   1. any OpenAI-compatible vision API (default: OpenRouter free Qwen2.5-VL-72B)
 *   2. Workers AI (no key at all, weaker on small text)
 *
 * Variables / secrets in Cloudflare (Settings -> Variables and Secrets):
 *   DEEPSEEK_API_KEY = sk-...     (secret, required for /reminder)
 *   GEMINI_API_KEY   = AIza... (secret, the only engine for /scan)
 *   VISION_BASE_URL  = https://openrouter.ai/api/v1        (default)
 *   VISION_MODEL     = qwen/qwen2.5-vl-72b-instruct:free   (default)
 *
 * Bindings (Settings -> Bindings):
 *   AI               = Workers AI  (optional fallback for /scan)
 *
 * Keeping the keys here means the Flutter web build never contains them —
 * important because anyone can read a key shipped in a browser bundle.
 */

const DEEPSEEK_URL = "https://api.deepseek.com/v1/chat/completions";
const MODEL = "deepseek-chat";
const MAX_BODY_BYTES = 4096;
const MAX_REQUESTS_PER_HOUR = 30;

// Receipt scanning (vision) — separate model, separate quota.
const MAX_SCAN_BASE64 = 2_000_000; // ~1.5 MB image
const MAX_SCANS_PER_HOUR = 20;

// Gemini vision — free tier, strong on handwriting. The model name is
// configurable because Google retires model ids; the list is tried in order and
// a 404 moves on to the next one instead of failing the scan.
const GEMINI_MODEL_DEFAULT = "gemini-2.5-flash";
const GEMINI_MODEL_FALLBACKS = [
  "gemini-2.5-flash",
  "gemini-2.0-flash",
  "gemini-flash-lite-latest",
];

// Stripe Checkout (test mode by default). Cards and FPX only: GrabPay and
// Touch 'n Go are not available through Stripe Malaysia, and they need a local
// acquirer (Curlec, iPay88 or HitPay) instead.
const STRIPE_API = "https://api.stripe.com/v1";
const MAX_PAYMENTS_PER_HOUR = 30;

// Generic chat (partner module) — one prompt in, one reply out.
const MAX_CHAT_PROMPT = 4_000;
const MAX_CHATS_PER_HOUR = 40;
const DEFAULT_CHAT_SYSTEM =
  "You are a concise assistant inside a small-business bookkeeping app for " +
  "Malaysian sales agents. Answer in the language the user writes in. Be " +
  "practical and short: at most 120 words unless the user asks for more.";

const ALLOWED_ORIGINS = new Set([
  "https://changvui.github.io",
  "http://localhost:8080",
  "http://127.0.0.1:8080",
  "http://localhost:8081",
  "http://127.0.0.1:8081",
]);

function corsHeaders(origin) {
  return {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "content-type",
    "Access-Control-Max-Age": "86400",
    Vary: "Origin",
    "Cache-Control": "no-store",
  };
}

function json(body, status, origin) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      ...corsHeaders(origin),
    },
  });
}

function clean(value, maxLength) {
  return String(value ?? "").trim().slice(0, maxLength);
}

// ---------------------------------------------------------------------------
// /reminder — DeepSeek
// ---------------------------------------------------------------------------

function buildPrompt(data, tone, language) {
  const toneText = {
    formal: "formal, polite and businesslike",
    friendly: "warm, friendly and conversational",
    urgent: "firm and urgent but still respectful",
  }[tone];

  const languageText = {
    en: "English",
    ms: "Bahasa Malaysia (Malay)",
    zh: "Simplified Chinese",
  }[language] || "English";

  return {
    system:
      "You write short payment reminder messages for a Malaysian sales agent. " +
      `The tone must be ${toneText}. Write the whole message in ${languageText}, ` +
      "even if the customer or item names are in another language. Include the " +
      "customer name, the outstanding amount, the item, how many days overdue, " +
      "and the bill reference when one is given. Do not threaten or shame the " +
      "customer. Keep it under 75 words. Return only the message, with no " +
      "headings or quotation marks.",
    user:
      `Customer: ${data.customerName}\n` +
      `Item: ${data.item || "the recent purchase"}\n` +
      `Outstanding amount: RM ${Number(data.amount).toFixed(2)}\n` +
      `Due date: ${data.dueDate}\n` +
      `Days overdue: ${Number(data.daysOverdue) || 0}\n` +
      (data.reference ? `Bill reference: ${data.reference}\n` : "") +
      "Write the reminder now.",
  };
}

async function handleReminder(request, env, origin) {
  const deepseekKey = String(env.DEEPSEEK_API_KEY ?? "").trim();
  if (!deepseekKey) {
    return json({ error: "AI is not configured" }, 503, origin);
  }

  const ip = request.headers.get("CF-Connecting-IP") || "unknown";
  if (await rateLimited(env, ip, "reminder", MAX_REQUESTS_PER_HOUR)) {
    return json({ error: "Too many requests. Try again later." }, 429, origin);
  }

  let data;
  try {
    data = await request.json();
  } catch {
    return json({ error: "Invalid JSON" }, 400, origin);
  }

  const tone = clean(data.tone, 20).toLowerCase();
  if (!["formal", "friendly", "urgent"].includes(tone)) {
    return json({ error: "Invalid tone" }, 400, origin);
  }

  const customerName = clean(data.customerName, 80);
  const item = clean(data.item, 120);
  const amount = Number(data.amount);
  const daysOverdue = Number(data.daysOverdue);
  const dueDate = clean(data.dueDate, 40);

  if (!customerName || !Number.isFinite(amount) || amount < 0) {
    return json({ error: "Invalid reminder data" }, 400, origin);
  }

  const language = ["ms", "zh"].includes(String(data.language ?? "").toLowerCase())
    ? String(data.language).toLowerCase()
    : "en";
  const reference = clean(data.reference, 40);

  const prompt = buildPrompt(
    { customerName, item, amount, daysOverdue, dueDate, reference },
    tone,
    language,
  );

  try {
    const response = await fetch(DEEPSEEK_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${deepseekKey}`,
      },
      body: JSON.stringify({
        model: MODEL,
        temperature: 0.7,
        max_tokens: 220,
        messages: [
          { role: "system", content: prompt.system },
          { role: "user", content: prompt.user },
        ],
      }),
    });

    if (!response.ok) {
      // 402 means the prepaid balance is exhausted; make that readable so the
      // client can say "quota" instead of surfacing a raw 402.
      if (response.status === 402) {
        return json({ error: "AI quota exhausted" }, 503, origin);
      }
      return json({ error: `DeepSeek error ${response.status}` }, 502, origin);
    }

    const result = await response.json();
    const text = result?.choices?.[0]?.message?.content;
    if (typeof text !== "string" || !text.trim()) {
      return json({ error: "Empty AI response" }, 502, origin);
    }

    return json(
      { text: text.trim().replace(/^"|"$/g, "") },
      200,
      origin,
    );
  } catch {
    return json({ error: "AI service unavailable" }, 502, origin);
  }
}


// ---------------------------------------------------------------------------
// /chat — general prompt for the partner module
// ---------------------------------------------------------------------------

async function handleChat(request, env, origin) {
  const key = String(env.DEEPSEEK_API_KEY ?? "").trim();
  if (!key) {
    return json({ error: "AI is not configured" }, 503, origin);
  }

  const ip = request.headers.get("CF-Connecting-IP") || "unknown";
  if (await rateLimited(env, ip, "chat", MAX_CHATS_PER_HOUR)) {
    return json({ error: "Too many requests. Try again later." }, 429, origin);
  }

  let data;
  try {
    data = await request.json();
  } catch {
    return json({ error: "Invalid JSON" }, 400, origin);
  }

  const prompt = clean(data.prompt, MAX_CHAT_PROMPT);
  if (!prompt) {
    return json({ error: "prompt is required" }, 400, origin);
  }
  const system = clean(data.system, 2_000) || DEFAULT_CHAT_SYSTEM;

  try {
    const response = await fetchWithTimeout(
      DEEPSEEK_URL,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${key}`,
        },
        body: JSON.stringify({
          model: MODEL,
          temperature: 0.6,
          max_tokens: 600,
          messages: [
            { role: "system", content: system },
            { role: "user", content: prompt },
          ],
        }),
      },
      25_000,
    );

    if (!response.ok) {
      // 402 means the prepaid balance is exhausted; make that readable so the
      // client can say "quota" instead of surfacing a raw 402.
      if (response.status === 402) {
        return json({ error: "AI quota exhausted" }, 503, origin);
      }
      return json({ error: `DeepSeek error ${response.status}` }, 502, origin);
    }

    const result = await response.json();
    const text = result?.choices?.[0]?.message?.content;
    if (typeof text !== "string" || !text.trim()) {
      return json({ error: "Empty AI response" }, 502, origin);
    }

    return json({ text: text.trim().replace(/^"|"$/g, "") }, 200, origin);
  } catch (error) {
    const timedOut = String(error).toLowerCase().includes("timeout");
    return json(
      { error: timedOut ? "AI timed out" : "AI service unavailable" },
      504,
      origin,
    );
  }
}


// ---------------------------------------------------------------------------
// /pay — Stripe Checkout (card + FPX)
// ---------------------------------------------------------------------------

function stripeKey(env) {
  return String(env.STRIPE_SECRET_KEY ?? "").trim();
}

async function stripeRequest(env, path, form, method = "POST") {
  const body = new URLSearchParams();
  for (const [key, value] of Object.entries(form)) body.append(key, value);

  let response;
  try {
    response = await fetchWithTimeout(
      `${STRIPE_API}${path}`,
      {
        method,
        headers: {
          Authorization: `Bearer ${stripeKey(env)}`,
          "Content-Type": "application/x-www-form-urlencoded",
        },
        body: method === "GET" ? undefined : body.toString(),
      },
      25_000,
    );
  } catch (error) {
    // A failed subrequest used to surface as an empty 502 with no clue why.
    return {
      ok: false,
      status: 0,
      data: { error: { message: `subrequest failed: ${String(error)}` } },
    };
  }

  const text = await response.text();
  let data = {};
  try {
    data = JSON.parse(text);
  } catch {
    data = { raw: text };
  }
  return { ok: response.ok, status: response.status, data };
}

/// Creates a Checkout Session and returns the hosted page URL.
async function handlePayCreate(request, env, origin) {
  if (!stripeKey(env)) {
    return json({ error: "Stripe is not configured" }, 503, origin);
  }

  const ip = request.headers.get("CF-Connecting-IP") || "unknown";
  if (await rateLimited(env, ip, "pay", MAX_PAYMENTS_PER_HOUR)) {
    return json({ error: "Too many attempts. Try again later." }, 429, origin);
  }

  let data;
  try {
    data = await request.json();
  } catch {
    return json({ error: "Invalid JSON" }, 400, origin);
  }

  const token = clean(data.token, 80);
  const returnBase = clean(data.returnUrl, 400);
  const description = clean(data.description, 120) || "Bill payment";
  const amount = Number(data.amount);

  if (!token || !returnBase) {
    return json({ error: "Missing token or return URL" }, 400, origin);
  }
  if (!Number.isFinite(amount) || amount <= 0) {
    return json({ error: "Invalid amount" }, 400, origin);
  }

  const cents = Math.round(amount * 100);
  const separator = returnBase.includes("?") ? "&" : "?";
  const successUrl =
    `${returnBase}${separator}s=${encodeURIComponent(token)}` +
    "&paid=1&popup=1&session_id={CHECKOUT_SESSION_ID}";

  // Stripe renders a "Back" arrow only when `cancel_url` is set. That arrow
  // leaves the hosted page and lands on whatever the tab had before, which for a
  // customer on a borrowed phone is the agent's login screen. The checkout runs
  // in its own tab, so cancelling means closing the tab; leaving cancel_url out
  // removes the arrow entirely. Set STRIPE_SHOW_CANCEL=true to bring it back.
  const showCancel = String(env.STRIPE_SHOW_CANCEL ?? "").toLowerCase() === "true";
  const cancelUrl = `${returnBase}${separator}s=${encodeURIComponent(token)}`;

  // Stripe removed `payment_method_types` from Checkout Sessions; a session is
  // limited with `allowed_payment_method_types` instead, and anything left out
  // falls back to the Dashboard defaults. FPX and GrabPay only become available
  // once the Stripe account is verified, so the list is a variable: set
  // STRIPE_METHODS="card,fpx" after verification, no redeploy of the app.
  const allowed = String(env.STRIPE_METHODS ?? "card")
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean);

  const form = {
    mode: "payment",
    success_url: successUrl,
    locale: "en",
    "line_items[0][quantity]": "1",
    "line_items[0][price_data][currency]": "myr",
    "line_items[0][price_data][unit_amount]": String(cents),
    "line_items[0][price_data][product_data][name]": description,
    "metadata[statement_token]": token,
    // Shown in the Stripe dashboard, so a refund can be traced to the bill
    // without opening this application.
    "metadata[bill]": clean(data.billNo, 60) || "not specified",
    "metadata[customer]": clean(data.customerName, 80) || "not specified",
    // Stripe echoes this back on the session, so a redirect that loses the query
    // can still be tied to the statement it belongs to.
    client_reference_id: token,
  };
  if (showCancel) form.cancel_url = cancelUrl;
  allowed.forEach((method, index) => {
    form[`allowed_payment_method_types[${index}]`] = method;
  });

  const result = await stripeRequest(env, "/checkout/sessions", form);

  if (!result.ok) {
    return json(
      { error: `Stripe ${result.status}`, detail: result.data?.error?.message ?? "" },
      502,
      origin,
    );
  }

  return json(
    {
      id: result.data.id,
      url: result.data.url,
      amount: cents / 100,
      currency: "myr",
      // Diagnostic only: confirms the redirect carries the statement token.
      returnHasToken: successUrl.includes("s="),
    },
    200,
    origin,
  );
}

/// Reports whether the secret is present, without revealing it. Used while
/// wiring the gateway up: 200 means the Worker can see a key at all.
async function handlePayHealth(env, origin) {
  const key = stripeKey(env);
  return json(
    {
      configured: key.length > 0,
      prefix: key.length >= 8 ? `${key.slice(0, 8)}…` : "",
      mode: key.startsWith("sk_test_") ? "test" : key.startsWith("sk_live_") ? "live" : "unknown",
    },
    200,
    origin,
  );
}

/// Reports whether a session was paid, how much, and with which method.
async function handlePayVerify(request, env, origin) {
  if (!stripeKey(env)) {
    return json({ error: "Stripe is not configured" }, 503, origin);
  }

  let data;
  try {
    data = await request.json();
  } catch {
    return json({ error: "Invalid JSON" }, 400, origin);
  }

  const sessionId = clean(data.sessionId, 120);
  if (!sessionId.startsWith("cs_")) {
    return json({ error: "Invalid session id" }, 400, origin);
  }

  const result = await stripeRequest(
    env,
    `/checkout/sessions/${encodeURIComponent(sessionId)}`,
    {},
    "GET",
  );
  if (!result.ok) {
    return json({ error: `Stripe ${result.status}` }, 502, origin);
  }

  const session = result.data;
  const methods = Array.isArray(session.payment_method_types)
    ? session.payment_method_types
    : [];
  return json(
    {
      paid: session.payment_status === "paid",
      status: session.payment_status,
      amount: (Number(session.amount_total) || 0) / 100,
      currency: session.currency || "myr",
      method: methods.includes("fpx") ? "FPX" : "Card",
      token: session.client_reference_id || "",
      reference: session.payment_intent
        ? String(session.payment_intent).slice(-12).toUpperCase()
        : sessionId.slice(-12).toUpperCase(),
    },
    200,
    origin,
  );
}

// ---------------------------------------------------------------------------
// /scan — Workers AI vision
// ---------------------------------------------------------------------------

const SCAN_PROMPT = `You are reading a photo of a Malaysian cash bill, invoice or receipt.

Reply with JSON only, no markdown, using exactly these keys. For every printed line return one item with its quantity, its unit price and its line amount; if the bill prints only a line amount, set unit_price to "amount" divided by "qty".
{
  "is_bill": true|false,
  "customer": "the party the bill is issued to, or null",
  "vendor": "the business issuing the bill, or null",
  "items": [{"description": "printed line", "qty": number, "unit_price": number or null, "amount": number}],
  "total": number or null,
  "date": "YYYY-MM-DD" or null,
  "reference": "invoice or cash-bill number, or null",
  "note": "one short line summarising the bill, or null"
}

How to read the fields:
- "customer" is who bought on credit: the name after "M/s", "Customer",
  "Pelanggan" or "Bill To". It is often a person, sometimes a company.
  Example: "M/s Bryant Gan (Walk-in Customer)" -> "Bryant Gan".
- "vendor" is the shop or company that ISSUES the bill, normally in the
  letterhead. A brand pre-printed on the bill book itself (e.g. the "YOMAX"
  logo on a pre-printed cash-bill pad) is NOT the vendor and must not be used
  as the customer either - set them null if the real names are not printed.
- "total" is the cell printed at the BOTTOM RIGHT and labelled "TOTAL",
  "總計", "Jumlah" or "Grand Total". It is the sum of every line, NOT one line
  item. A single row's amount must never be reported as the total.
- Copy every printed line into "items" with the value in its AMOUNT / 金額
  column (quantity x unit price). This lets the caller check the sum.
- "reference" is the number next to "No." at the top (often 3-5 digits).
- "date" is next to "Date:" / "日期" and may be written "11 November 2026" or
  "11/11/2026". The year has four digits - read each digit carefully, a 6 is
  not a 1.
- Sample: a YOMAX pad, "M/s Bryant Gan (Walk-in Customer)", No. 2828,
  11 November 2026, lines 2x15.00 + 25.00 + 25.00. Expect:
  customer "Bryant Gan", vendor null, total 80.00 (not 25.00),
  reference "2828", date "2026-11-11".

Rules:
- If the image is not a bill/invoice/receipt, set "is_bill" to false and the
  other keys to null.
- Never invent numbers. If a value is unreadable, use null.
- Malaysian bills may be in Malay or Chinese ("Jumlah", "Tarikh", "No. Resit",
  "總計", "日期", "Pelanggan").
- If you cannot produce JSON, answer with exactly one line and nothing else:
  TOTAL: <number> DATE: <YYYY-MM-DD>`;

function stripFences(text) {
  let value = String(text ?? "").trim();
  if (value.startsWith("```")) {
    value = value.replace(/^```[a-zA-Z]*\s*/, "");
    if (value.endsWith("```")) value = value.slice(0, -3);
  }
  const start = value.indexOf("{");
  const end = value.lastIndexOf("}");
  if (start >= 0 && end > start) value = value.slice(start, end + 1);
  return value.trim();
}

/**
 * Small vision models often answer with a sentence instead of JSON. Rather than
 * failing the whole scan, pull the total and the date out of the prose — the
 * agent still reviews every field before saving.
 */
function parseLoose(text) {
  const prose = String(text ?? "");
  if (!prose.trim()) return null;

  const total =
    prose.match(
      /(?:grand\s*total|total|jumlah|amount|bayaran)[^\d]{0,15}(\d+(?:[.,]\d{1,2})?)/i,
    ) || prose.match(/rm\s*(\d+(?:[.,]\d{1,2})?)/i);

  if (!total) return null;

  const amount = Number(String(total[1]).replace(",", "."));
  if (!Number.isFinite(amount) || amount <= 0) return null;

  let date = null;
  const iso = prose.match(/(20\d{2})-(\d{2})-(\d{2})/);
  if (iso) {
    date = `${iso[1]}-${iso[2]}-${iso[3]}`;
  } else {
    const dmy = prose.match(/(\d{1,2})[/.-](\d{1,2})[/.-](20\d{2}|\d{2})/);
    if (dmy) {
      const year = dmy[3].length === 2 ? `20${dmy[3]}` : dmy[3];
      date = `${year}-${dmy[2].padStart(2, "0")}-${dmy[1].padStart(2, "0")}`;
    }
  }

  return {
    is_bill: true,
    vendor: null,
    amount,
    date,
    reference: null,
    note: prose.replace(/\s+/g, " ").trim().slice(0, 140),
  };
}

function parseBill(text) {
  try {
    const value = JSON.parse(stripFences(text));
    if (value && typeof value === "object") return normaliseBill(value);
  } catch {
    // fall through to the lenient parser
  }
  const loose = parseLoose(text);
  return loose ? normaliseBill(loose) : null;
}

/**
 * Small vision models love to report one line item as the total (a RM 80 bill
 * came back as 25.00). The prompt asks for every printed line so the sum can
 * cross-check the total: if they disagree and the sum is larger, the sum wins.
 */
function normaliseBill(bill) {
  const items = Array.isArray(bill.items) ? bill.items : [];
  const sum = items.reduce((acc, item) => {
    const value = Number(item?.amount);
    return Number.isFinite(value) ? acc + value : acc;
  }, 0);
  const rounded = Math.round(sum * 100) / 100;

  const printed = Number(bill.total ?? bill.amount);
  const hasPrinted = Number.isFinite(printed) && printed > 0;

  if (rounded > 0) {
    bill.amount = hasPrinted && Math.abs(printed - rounded) <= 0.01
      ? printed
      : Math.max(hasPrinted ? printed : 0, rounded);
  } else {
    bill.amount = hasPrinted ? printed : null;
  }

  if (bill.is_bill === undefined) bill.is_bill = bill.amount != null;
  return bill;
}

/**
 * Cloudflare Workers AI — same platform as this Worker, so there is no API key
 * and no shared queue with the rest of the internet.
 *
 * Enable it with a binding: Settings -> Bindings -> Workers AI, variable `AI`.
 *
 * Workers AI rotates its model catalogue, so try the caller's SCAN_MODEL first
 * (if set) and then a couple of well-known vision models; the first one that
 * answers wins. This keeps the demo working when a model is retired.
 */
async function fetchWithTimeout(url, options, timeoutMs = 30000) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { ...options, signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Primary engine: any OpenAI-compatible vision endpoint, defaulting to
 * OpenRouter's free Qwen2.5-VL-72B — a document/table model, which is exactly
 * what a cash bill is.
 *
 * Variables (Cloudflare -> Settings -> Variables):
 *   GEMINI_API_KEY   AIza...                                       (required)
 *   VISION_BASE_URL  https://openrouter.ai/api/v1                  (default)
 *   VISION_MODEL     qwen/qwen2.5-vl-72b-instruct:free             (default)
 *
 * Because it is OpenAI-compatible, the same code also drives Groq, Mistral,
 * Together, a self-hosted vLLM, etc. — only the three variables change.
 */
async function scanViaGemini(env, imageBase64, mimeType) {
  const key = String(env.GEMINI_API_KEY ?? "").trim();
  if (!key) throw new Error("gemini: no key");

  const configured = String(env.GEMINI_MODEL ?? "").trim();
  const models = configured
    ? [configured, ...GEMINI_MODEL_FALLBACKS.filter((m) => m !== configured)]
    : GEMINI_MODEL_FALLBACKS.slice();

  let lastError = "gemini: unavailable";
  for (const model of models) {
    const url =
      `https://generativelanguage.googleapis.com/v1beta/models/${model}` +
      `:generateContent?key=${encodeURIComponent(key)}`;

    const response = await fetchWithTimeout(
      url,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          contents: [
            {
              parts: [
                { text: SCAN_PROMPT },
                { inline_data: { mime_type: mimeType, data: imageBase64 } },
              ],
            },
          ],
          generationConfig: {
            temperature: 0,
            maxOutputTokens: 800,
            responseMimeType: "application/json",
          },
        }),
      },
      30_000,
    );

    if (response.status === 404) {
      lastError = `gemini ${model}: not found`;
      continue;
    }
    if (response.status === 429) {
      throw new Error("gemini: quota exhausted");
    }
    if (!response.ok) {
      const detail = (await response.text()).slice(0, 140);
      throw new Error(`gemini ${model}: ${response.status} ${detail}`);
    }

    const data = await response.json();
    const text = data?.candidates?.[0]?.content?.parts
      ?.map((part) => part?.text ?? "")
      .join("");
    if (typeof text !== "string" || !text.trim()) {
      lastError = `gemini ${model}: empty response`;
      continue;
    }
    return { model, text };
  }

  throw new Error(lastError);
}

async function handleScan(request, env, origin) {
  const hasGemini = Boolean(String(env.GEMINI_API_KEY ?? "").trim());
  if (!hasGemini) {
    return json(
      { error: "Scan is not configured: set GEMINI_API_KEY." },
      503,
      origin,
    );
  }

  const ip = request.headers.get("CF-Connecting-IP") || "unknown";
  if (await rateLimited(env, ip, "scan", MAX_SCANS_PER_HOUR)) {
    return json({ error: "Too many scans. Try again later." }, 429, origin);
  }

  let data;
  try {
    data = await request.json();
  } catch {
    return json({ error: "Invalid JSON" }, 400, origin);
  }

  const image = data.image;
  if (typeof image !== "string" || image.length < 100) {
    return json({ error: "Missing image" }, 400, origin);
  }
  if (image.length > MAX_SCAN_BASE64) {
    return json({ error: "Image too large" }, 413, origin);
  }

  const mimeType = clean(data.mimeType, 40) || "image/jpeg";
  if (!/^image\/(jpeg|jpg|png|webp|heic)$/.test(mimeType)) {
    return json({ error: "Unsupported image type" }, 415, origin);
  }

  // Gemini Flash is the only vision engine: free tier, strongest of the
  // models evaluated on handwritten Malaysian bills.
  try {
    const { model, text } = await scanViaGemini(env, image, mimeType);
    const bill = parseBill(text);
    if (bill) return json({ bill, engine: `gemini (${model})` }, 200, origin);
    return json(
      { error: "The image could not be read as a bill. Try a clearer photo." },
      422,
      origin,
    );
  } catch (error) {
    const message = String(error);
    const quota = message.includes("quota");
    return json(
      {
        error: quota
          ? "AI quota exhausted for today. Try again later."
          : `Scan failed: ${message.slice(0, 200)}`,
      },
      quota ? 429 : 502,
      origin,
    );
  }
}

// ---------------------------------------------------------------------------
// Rate limiting + router
// ---------------------------------------------------------------------------

async function rateLimited(env, ip, bucketName, limit) {
  if (!env.RATE_LIMIT) return false;
  const bucket = Math.floor(Date.now() / 3600000);
  const key = `rl:${bucketName}:${ip}:${bucket}`;
  const current = Number((await env.RATE_LIMIT.get(key)) || "0");
  if (current >= limit) return true;
  await env.RATE_LIMIT.put(key, String(current + 1), { expirationTtl: 3700 });
  return false;
}

export default {
  async fetch(request, env) {
    const origin = request.headers.get("Origin") || "";
    // The allow-list only protects browsers, which always send Origin. Native
    // Android/iOS builds send no Origin at all, so an empty value must be
    // accepted or every call from the app would be rejected with 403.
    // Any localhost port is accepted so a partner can run the app locally.
    const isLocalDev = /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin);
    const allowed = origin === "" || ALLOWED_ORIGINS.has(origin) || isLocalDev;
    const path = new URL(request.url).pathname.replace(/\/+$/, "");

    const isScan = path.endsWith("/scan");
    const isChat = path.endsWith("/chat");
    const isPayHealth = path.endsWith("/pay/health");
    const isPayCreate = path.endsWith("/pay/create");
    const isPayVerify = path.endsWith("/pay/verify");
    const maxLength = isScan ? MAX_SCAN_BASE64 + 100_000 : MAX_BODY_BYTES;

    if (request.method === "OPTIONS") {
      if (!allowed) return new Response("Forbidden", { status: 403 });
      return new Response(null, { status: 204, headers: corsHeaders(origin) });
    }

    if (!allowed) return new Response("Forbidden origin", { status: 403 });
    if (isPayHealth) return handlePayHealth(env, origin);
    if (request.method !== "POST") {
      return json({ error: "Method not allowed" }, 405, origin);
    }

    const length = Number(request.headers.get("content-length") || "0");
    if (length > maxLength) {
      return json({ error: "Request too large" }, 413, origin);
    }

    if (isScan) return handleScan(request, env, origin);
    if (isChat) return handleChat(request, env, origin);
    if (isPayHealth) return handlePayHealth(env, origin);
    if (isPayCreate) return handlePayCreate(request, env, origin);
    if (isPayVerify) return handlePayVerify(request, env, origin);
    return handleReminder(request, env, origin);
  },
};
