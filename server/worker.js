/**
 * SmartPayLA AI proxy — Cloudflare Worker
 *
 * The DeepSeek API key lives only in this Worker as a secret. The Flutter app
 * calls this endpoint without any key, so every user can use AI reminders
 * without buying their own DeepSeek account.
 *
 * Secret to configure in Cloudflare:
 *   DEEPSEEK_API_KEY = sk-...
 *
 * Optional KV binding for a simple per-IP rate limit:
 *   RATE_LIMIT (KV namespace)
 */

const DEEPSEEK_URL = "https://api.deepseek.com/v1/chat/completions";
const MODEL = "deepseek-chat";
const MAX_BODY_BYTES = 4096;
const MAX_REQUESTS_PER_HOUR = 30;

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

async function rateLimited(env, ip) {
  if (!env.RATE_LIMIT) return false;
  const bucket = Math.floor(Date.now() / 3600000);
  const key = `rl:${ip}:${bucket}`;
  const current = Number((await env.RATE_LIMIT.get(key)) || "0");
  if (current >= MAX_REQUESTS_PER_HOUR) return true;
  await env.RATE_LIMIT.put(key, String(current + 1), { expirationTtl: 3700 });
  return false;
}

export default {
  async fetch(request, env) {
    const origin = request.headers.get("Origin") || "";
    const allowed = ALLOWED_ORIGINS.has(origin);

    if (request.method === "OPTIONS") {
      if (!allowed) return new Response("Forbidden", { status: 403 });
      return new Response(null, { status: 204, headers: corsHeaders(origin) });
    }

    if (!allowed) return new Response("Forbidden origin", { status: 403 });
    if (request.method !== "POST") {
      return json({ error: "Method not allowed" }, 405, origin);
    }

    const length = Number(request.headers.get("content-length") || "0");
    if (length > MAX_BODY_BYTES) {
      return json({ error: "Request too large" }, 413, origin);
    }

    if (!env.DEEPSEEK_API_KEY) {
      return json({ error: "AI is not configured" }, 503, origin);
    }

    const ip = request.headers.get("CF-Connecting-IP") || "unknown";
    if (await rateLimited(env, ip)) {
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
          Authorization: `Bearer ${env.DEEPSEEK_API_KEY}`,
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
  },
};
