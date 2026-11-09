export interface Env {
  AI: Ai;
}

type Language = "zh" | "ru";
type Style = "natural" | "formal" | "polite";

interface TranslationRequest {
  text: string;
  sourceLanguage: Language;
  targetLanguage: Language;
  style: Style;
}

const MODEL = "@cf/zai-org/glm-4.7-flash";
const MAX_TEXT_LENGTH = 5000;

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store"
    }
  });
}

function languageName(code: Language): string {
  return code === "zh" ? "Simplified Chinese" : "Russian";
}

function styleInstruction(style: Style): string {
  switch (style) {
    case "formal":
      return "Use a formal, professional register appropriate for school, work, institutions, and official communication.";
    case "polite":
      return "Use a polite, natural register suitable for speaking respectfully to another person. Preserve normal native phrasing rather than sounding overly ceremonial.";
    case "natural":
    default:
      return "Use natural, everyday native phrasing. Prefer clear expressions that a local speaker would actually use.";
  }
}

function cleanModelText(value: unknown): string {
  let text = typeof value === "string" ? value.trim() : "";
  if (!text) return "";

  text = text
    .replace(/^\`\`\`(?:text|json)?\s*/i, "")
    .replace(/\s*\`\`\`$/i, "")
    .trim();

  const prefixes = [
    "translation:",
    "translated text:",
    "перевод:",
    "翻译：",
    "译文：",
    "翻译:"
  ];

  const lower = text.toLowerCase();
  for (const prefix of prefixes) {
    if (lower.startsWith(prefix.toLowerCase())) {
      text = text.slice(prefix.length).trim();
      break;
    }
  }

  if (
    (text.startsWith('"') && text.endsWith('"')) ||
    (text.startsWith("“") && text.endsWith("”"))
  ) {
    text = text.slice(1, -1).trim();
  }

  return text;
}

async function translate(request: TranslationRequest, env: Env): Promise<Response> {
  const input = request.text.trim();

  if (!input) {
    return json({ error: "empty_input" }, 400);
  }

  if (input.length > MAX_TEXT_LENGTH) {
    return json({ error: "text_too_long", maxCharacters: MAX_TEXT_LENGTH }, 413);
  }

  if (
    !["zh", "ru"].includes(request.sourceLanguage) ||
    !["zh", "ru"].includes(request.targetLanguage) ||
    request.sourceLanguage === request.targetLanguage
  ) {
    return json({ error: "invalid_language_pair" }, 400);
  }

  if (!["natural", "formal", "polite"].includes(request.style)) {
    return json({ error: "invalid_style" }, 400);
  }

  const systemPrompt = [
    "You are the translation engine for RussianWords, a Chinese-Russian language-learning app.",
    `Translate from ${languageName(request.sourceLanguage)} to ${languageName(request.targetLanguage)}.`,
    styleInstruction(request.style),
    "Preserve the original meaning, names, numbers, punctuation intent, and level of certainty.",
    "Do not explain, annotate, transliterate, or add alternatives.",
    "Return only the final translated text. Do not add labels, quotation marks, markdown, or commentary."
  ].join("\n");

  try {
    const result = await env.AI.run(MODEL, {
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user", content: input }
      ],
      temperature: 0.15,
      max_tokens: 1200
    });

    const raw =
      typeof result === "string"
        ? result
        : (result as { response?: unknown })?.response;

    const translation = cleanModelText(raw);

    if (!translation) {
      return json({ error: "empty_model_response" }, 502);
    }

    return json({
      translation,
      explanation: null
    });
  } catch (error) {
    console.error("Workers AI translation failed", error);
    return json({ error: "translation_provider_failed" }, 502);
  }
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === "GET" && url.pathname === "/health") {
      return json({
        ok: true,
        service: "RussianWords Translation Gateway",
        model: MODEL
      });
    }

    if (request.method !== "POST" || url.pathname !== "/translate") {
      return json({ error: "not_found" }, 404);
    }

    const contentType = request.headers.get("content-type") ?? "";
    if (!contentType.toLowerCase().includes("application/json")) {
      return json({ error: "content_type_must_be_json" }, 415);
    }

    let body: TranslationRequest;
    try {
      body = (await request.json()) as TranslationRequest;
    } catch {
      return json({ error: "invalid_json" }, 400);
    }

    if (
      typeof body?.text !== "string" ||
      typeof body?.sourceLanguage !== "string" ||
      typeof body?.targetLanguage !== "string" ||
      typeof body?.style !== "string"
    ) {
      return json({ error: "invalid_request" }, 400);
    }

    return translate(body, env);
  }
} satisfies ExportedHandler<Env>;
