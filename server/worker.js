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

function buildPrompt(data, tone) {
  const toneText = {
    formal: "formal, polite and businesslike",
    friendly: "warm, friendly and conversational",
    urgent: "firm and urgent but still respectful",
  }[tone];

  return {
    system:
      "You write short payment reminder messages for a Malaysian sales agent. " +
      `The tone must be ${toneText}. Include the customer name, the outstanding ` +
      "amount, the item, and how many days overdue. Do not threaten or shame " +
      "the customer. Keep it under 75 words. Return only the message, with no " +
      "headings or quotation marks.",
    user:
      `Customer: ${data.customerName}\n` +
      `Item: ${data.item || "the recent purchase"}\n` +
      `Outstanding amount: RM ${Number(data.amount).toFixed(2)}\n` +
      `Due date: ${data.dueDate}\n` +
      `Days overdue: ${Number(data.daysOverdue) || 0}\n` +
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

  const prompt = buildPrompt(
    { customerName, item, amount, daysOverdue, dueDate },
    tone,
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
// /scan — Workers AI vision
// ---------------------------------------------------------------------------

const SCAN_PROMPT = `You are reading a photo of a Malaysian cash bill, invoice or receipt.

Reply with JSON only, no markdown, using exactly these keys:
{
  "is_bill": true|false,
  "customer": "the party the bill is issued to, or null",
  "vendor": "the business issuing the bill, or null",
  "items": [{"description": "printed line", "amount": number}],
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
    const maxLength = isScan ? MAX_SCAN_BASE64 + 100_000 : MAX_BODY_BYTES;

    if (request.method === "OPTIONS") {
      if (!allowed) return new Response("Forbidden", { status: 403 });
      return new Response(null, { status: 204, headers: corsHeaders(origin) });
    }

    if (!allowed) return new Response("Forbidden origin", { status: 403 });
    if (request.method !== "POST") {
      return json({ error: "Method not allowed" }, 405, origin);
    }

    const length = Number(request.headers.get("content-length") || "0");
    if (length > maxLength) {
      return json({ error: "Request too large" }, 413, origin);
    }

    if (isScan) return handleScan(request, env, origin);
    if (isChat) return handleChat(request, env, origin);
    return handleReminder(request, env, origin);
  },
};
