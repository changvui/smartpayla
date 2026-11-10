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
 *   VISION_API_KEY   = sk-or-v1-... (secret, preferred engine for /scan)
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
function scanModels(env) {
  const custom = String(env.SCAN_MODEL ?? "").trim();
  const fallbacks = [
    "@cf/meta/llama-3.2-11b-vision-instruct",
    "@cf/llava-hf/llava-1.5-7b-hf",
  ];
  return [...new Set([...(custom ? [custom] : []), ...fallbacks])];
}

async function scanWithWorkersAi(env, imageBytes) {
  const errors = [];

  for (const model of scanModels(env)) {
    try {
      const result = await env.AI.run(model, {
        prompt: SCAN_PROMPT,
        image: Array.from(imageBytes),
        max_tokens: 512,
      });

      // Different Workers AI vision models name the field differently:
      // llama/llava -> response, others -> result / description.
      const text =
        typeof result === "string"
          ? result
          : result?.response ?? result?.result ?? result?.description;

      if (typeof text === "string" && text.trim()) {
        return { model, text };
      }
      errors.push(`${model}: empty response`);
    } catch (error) {
      errors.push(`${model}: ${String(error).slice(0, 90)}`);
    }
  }

  throw new Error(errors.join(" | ").slice(0, 320));
}

/** One request, hard-capped so a stuck upstream cannot hang the Worker. */
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
 *   VISION_API_KEY   sk-or-v1-...                                  (required)
 *   VISION_BASE_URL  https://openrouter.ai/api/v1                  (default)
 *   VISION_MODEL     qwen/qwen2.5-vl-72b-instruct:free             (default)
 *
 * Because it is OpenAI-compatible, the same code also drives Groq, Mistral,
 * Together, a self-hosted vLLM, etc. — only the three variables change.
 */
async function scanViaOpenRouter(env, imageBase64, mimeType) {
  const key = String(env.VISION_API_KEY ?? "").trim();
  if (!key) return null;

  const base = (
    String(env.VISION_BASE_URL ?? "").trim() || "https://openrouter.ai/api/v1"
  ).replace(/\/+$/, "");
  const model =
    String(env.VISION_MODEL ?? "").trim() ||
    "qwen/qwen2.5-vl-72b-instruct:free";

  const body = {
    model,
    temperature: 0.1,
    messages: [
      {
        role: "user",
        content: [
          { type: "text", text: SCAN_PROMPT },
          {
            type: "image_url",
            image_url: { url: `data:${mimeType};base64,${imageBase64}` },
          },
        ],
      },
    ],
  };

  const response = await fetchWithTimeout(
    `${base}/chat/completions`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${key}`,
        "HTTP-Referer": "https://smartpayla-kerry.app",
        "X-Title": "SmartPayLA",
      },
      body: JSON.stringify(body),
    },
    30000,
  );

  if (!response.ok) {
    const detail = (await response.text()).slice(0, 140);
    throw new Error(`openrouter ${response.status}: ${detail}`);
  }

  const data = await response.json();
  const text = data?.choices?.[0]?.message?.content;
  if (typeof text !== "string" || !text.trim()) {
    throw new Error("openrouter: empty response");
  }
  return { model, text };
}

async function handleScan(request, env, origin) {
  const hasOpenRouter = Boolean(String(env.VISION_API_KEY ?? "").trim());
  const hasWorkersAi = Boolean(env.AI) && typeof env.AI.run === "function";

  if (!hasOpenRouter && !hasWorkersAi) {
    return json(
      {
        error:
          "Scan is not configured: set VISION_API_KEY, or bind Workers AI " +
          "as `AI`.",
      },
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

  const notes = [];

  // 1) Qwen2.5-VL via OpenRouter — accurate on documents and tables.
  if (hasOpenRouter) {
    try {
      const { model, text } = await scanViaOpenRouter(env, image, mimeType);
      const bill = parseBill(text);
      if (bill) return json({ bill, engine: `openrouter (${model})` }, 200, origin);
      notes.push(`openrouter: unreadable output`);
    } catch (error) {
      notes.push(String(error).slice(0, 120));
    }
  }

  // 2) Workers AI — no key, always available, weaker on small text.
  if (hasWorkersAi) {
    try {
      const imageBytes = Uint8Array.from(atob(image), (ch) => ch.charCodeAt(0));
      const { model, text } = await scanWithWorkersAi(env, imageBytes);
      const bill = parseBill(text);
      if (bill) {
        return json({ bill, engine: `workers-ai (${model})` }, 200, origin);
      }
      notes.push("workers-ai: unreadable output");
    } catch (error) {
      notes.push(String(error).slice(0, 120));
    }
  }

  return json(
    { error: `Scan failed — ${notes.join(" | ").slice(0, 340)}` },
    502,
    origin,
  );
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

/**
 * One-shot licence acceptance for the Llama vision model.
 *
 * Meta requires `{ prompt: "agree" }` once per account before the model can be
 * used. Open https://<worker>/scan/agree in a browser to accept; the request
 * runs under this Worker's own Cloudflare account, so no API token is needed.
 * Safe to leave in place: it only forwards the word "agree".
 */
async function handleAgree(env, origin) {
  if (!env.AI || typeof env.AI.run !== "function") {
    return json({ error: "No Workers AI binding named `AI`" }, 503, origin);
  }

  const model = "@cf/meta/llama-3.2-11b-vision-instruct";
  try {
    const response = await env.AI.run(model, { prompt: "agree" });
    return json(
      {
        model,
        ok: true,
        response: String(response?.response ?? response ?? "").slice(0, 120),
      },
      200,
      origin,
    );
  } catch (error) {
    return json({ model, ok: false, error: String(error).slice(0, 200) }, 502, origin);
  }
}

export default {
  async fetch(request, env) {
    const origin = request.headers.get("Origin") || "";
    const allowed = ALLOWED_ORIGINS.has(origin);
    const path = new URL(request.url).pathname.replace(/\/+$/, "");

    // Browser-friendly, no Origin header, GET is fine.
    if (path.endsWith("/scan/agree")) {
      return handleAgree(env, origin);
    }

    const isScan = path.endsWith("/scan");
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

    return isScan
      ? handleScan(request, env, origin)
      : handleReminder(request, env, origin);
  },
};
