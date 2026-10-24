import { FoodItem, Macros } from "./types";

// Server-side Groq client (OpenAI-compatible). The key never reaches the browser.

const GROQ_URL = "https://api.groq.com/openai/v1/chat/completions";
// Models verified against the live Groq account:
//  - Qwen3 is multimodal (vision). gpt-oss-120b is fast text (text-only).
const VISION_MODEL = "qwen/qwen3.8-27b";
const TEXT_MODEL = "openai/gpt-oss-120b";

export function isConfigured(): boolean {
  const key = process.env.GROQ_API_KEY?.trim();
  return !!key && key !== "gsk_your_key_here";
}

interface RecognizeResult {
  items: FoodItem[];
  usedLiveAI: boolean;
  note: string | null;
}

const RECOGNIZE_SYSTEM = `You are NutriWear's food vision engine for a wearable camera.
Look at the photo and return STRICT JSON describing the distinct foods you see.
Rules:
- Only report foods actually visible. Do not invent items. Merge duplicates.
- Estimate realistic portions from visual cues.
- Numbers are approximate; set confidence accordingly.
- If no food is visible, return an empty items array.
Return ONLY this JSON (no markdown):
{"items":[{"name":"string","portion":"short portion estimate","calories":number,"protein_g":number,"carbs_g":number,"fat_g":number,"confidence":"high|medium|low"}],"note":"one short sentence or empty"}`;

/** Recognize foods from a base64 data URL using Groq vision. */
export async function recognizeFood(imageDataURL: string): Promise<RecognizeResult> {
  if (!isConfigured()) {
    return offlineRecognition("no API key");
  }
  try {
    const raw = await chat({
      model: VISION_MODEL,
      temperature: 0.2,
      // Qwen3 is a reasoning model and may spend tokens thinking; give headroom.
      maxTokens: 2000,
      jsonMode: true,
      messages: [
        { role: "system", content: RECOGNIZE_SYSTEM },
        {
          role: "user",
          content: [
            { type: "text", text: "Identify the foods in this meal. Return only the JSON object." },
            { type: "image_url", image_url: { url: imageDataURL } },
          ],
        },
      ],
    });
    const items = parseItems(raw);
    return { items: dedupe(items), usedLiveAI: true, note: parseNote(raw) };
  } catch (e) {
    return offlineRecognition(e instanceof Error ? e.message : "error");
  }
}

// MARK: - Before / after consumption comparison

export interface ConsumptionItem {
  name: string;
  startCalories: number;
  leftoverFraction: number; // 0 = ate all, 1 = ate none
  eatenCalories: number;
  protein: number; // eaten grams
  carbs: number;
  fat: number;
  confidence: "high" | "medium" | "low";
}

export interface ConsumptionResult {
  items: ConsumptionItem[];
  startCalories: number;
  eatenCalories: number;
  leftoverCalories: number;
  usedLiveAI: boolean;
  note: string | null;
}

const COMPARE_SYSTEM = `You are NutriWear's food vision engine. You are given TWO photos of the SAME meal:
the FIRST is BEFORE eating (full plate) and the SECOND is AFTER eating (leftovers).

Your job:
1. Identify each distinct food on the BEFORE plate and estimate its full-portion calories and macros.
2. Compare BEFORE vs AFTER to estimate what fraction of EACH food is still left (0 = all eaten, 1 = untouched).
3. Compute how much was actually EATEN = full portion * (1 - leftoverFraction).

Numbers are approximate; set confidence per item. If the AFTER plate looks empty, leftoverFraction is ~0.

Return ONLY this JSON (no markdown, no reasoning text):
{"items":[{"name":"string","start_calories":number,"leftover_fraction":number,"eaten_calories":number,"eaten_protein_g":number,"eaten_carbs_g":number,"eaten_fat_g":number,"confidence":"high|medium|low"}],"note":"one short sentence"}`;

/** Compare a before/after pair and estimate what was actually eaten. */
export async function compareConsumption(
  beforeDataURL: string,
  afterDataURL: string
): Promise<ConsumptionResult> {
  if (!isConfigured()) return offlineConsumption("no API key");
  try {
    const raw = await chat({
      model: VISION_MODEL,
      temperature: 0.2,
      maxTokens: 2200,
      jsonMode: true,
      messages: [
        { role: "system", content: COMPARE_SYSTEM },
        {
          role: "user",
          content: [
            { type: "text", text: "FIRST image = BEFORE (full plate):" },
            { type: "image_url", image_url: { url: beforeDataURL } },
            { type: "text", text: "SECOND image = AFTER (leftovers). Compare and return only the JSON." },
            { type: "image_url", image_url: { url: afterDataURL } },
          ],
        },
      ],
    });
    return parseConsumption(raw);
  } catch (e) {
    return offlineConsumption(e instanceof Error ? e.message : "error");
  }
}

function parseConsumption(raw: string): ConsumptionResult {
  try {
    const obj = JSON.parse(extractJSON(raw));
    const rawItems = Array.isArray(obj.items) ? obj.items : [];
    const items: ConsumptionItem[] = rawItems
      .filter((it: { name?: string }) => it && typeof it.name === "string" && it.name.trim())
      .map((it: Record<string, unknown>): ConsumptionItem => {
        const start = num(it.start_calories);
        const leftover = Math.min(1, Math.max(0, num(it.leftover_fraction)));
        const eaten = it.eaten_calories != null ? num(it.eaten_calories) : start * (1 - leftover);
        const conf = String(it.confidence ?? "medium").toLowerCase();
        return {
          name: String(it.name),
          startCalories: start,
          leftoverFraction: leftover,
          eatenCalories: eaten,
          protein: num(it.eaten_protein_g),
          carbs: num(it.eaten_carbs_g),
          fat: num(it.eaten_fat_g),
          confidence: (["high", "medium", "low"].includes(conf) ? conf : "medium") as ConsumptionItem["confidence"],
        };
      });
    const startCalories = items.reduce((a, i) => a + i.startCalories, 0);
    const eatenCalories = items.reduce((a, i) => a + i.eatenCalories, 0);
    return {
      items,
      startCalories,
      eatenCalories,
      leftoverCalories: Math.max(0, startCalories - eatenCalories),
      usedLiveAI: true,
      note: typeof obj.note === "string" && obj.note.trim() ? obj.note.trim() : null,
    };
  } catch {
    return offlineConsumption("parse error");
  }
}

function offlineConsumption(reason: string): ConsumptionResult {
  const items: ConsumptionItem[] = [
    { name: "Slice of pepperoni pizza", startCalories: 285, leftoverFraction: 0.25, eatenCalories: 214, protein: 9, carbs: 27, fat: 8, confidence: "medium" },
  ];
  return {
    items,
    startCalories: 285,
    eatenCalories: 214,
    leftoverCalories: 71,
    usedLiveAI: false,
    note: `Offline sample (${reason}). Add a Groq key for a live before/after comparison.`,
  };
}

const COACH_SYSTEM = `You are NutriWear's real-time eating coach — a friendly voice assistant the user talks to while eating.
Answer their question directly and conversationally in 1-3 short sentences (this is spoken aloud).
You can answer general nutrition questions (e.g. calories in common foods), give eating-pace and balance tips, and comment on what they're eating.
Be warm, encouraging, nonjudgmental, evidence-informed. You are not a doctor; avoid medical claims.
If given context about the current meal/session, use it. Do NOT use markdown, bullet points, or emojis — plain spoken sentences only.`;

/** Answer a free-form voice/text question from the user. */
export async function askCoach(question: string, context: string): Promise<string> {
  const fallback =
    "I can help with that once a Groq key is set. In general, aim to start meals with protein or veggies and eat slowly.";
  if (!isConfigured()) return fallback;
  try {
    const userMsg = context
      ? `Context about right now:\n${context}\n\nUser asked: "${question}"`
      : `User asked: "${question}"`;
    const raw = await chat({
      model: TEXT_MODEL,
      temperature: 0.5,
      maxTokens: 220,
      messages: [
        { role: "system", content: COACH_SYSTEM },
        { role: "user", content: userMsg },
      ],
    });
    return raw.trim() || fallback;
  } catch {
    return fallback;
  }
}

/** A short proactive tip for a just-detected meal. */
export async function coachTip(foodSummary: string): Promise<string> {
  const fallback =
    "Start with protein or veggies to feel fuller sooner, and enjoy it slowly.";
  if (!isConfigured()) return fallback;
  try {
    const raw = await chat({
      model: TEXT_MODEL,
      temperature: 0.6,
      maxTokens: 120,
      messages: [
        { role: "system", content: COACH_SYSTEM },
        {
          role: "user",
          content: `I'm about to eat: ${foodSummary}. Give me ONE short coaching tip.`,
        },
      ],
    });
    return raw.trim() || fallback;
  } catch {
    return fallback;
  }
}

// MARK: - Low-level chat call

interface ChatArgs {
  model: string;
  messages: unknown[];
  temperature?: number;
  maxTokens?: number;
  jsonMode?: boolean;
}

async function chat(args: ChatArgs, attempt = 0): Promise<string> {
  const key = process.env.GROQ_API_KEY!.trim();
  const body: Record<string, unknown> = {
    model: args.model,
    temperature: args.temperature ?? 0.4,
    max_tokens: args.maxTokens ?? 800,
    messages: args.messages,
  };
  if (args.jsonMode) body.response_format = { type: "json_object" };

  const res = await fetch(GROQ_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${key}`,
    },
    body: JSON.stringify(body),
  });

  // On a rate limit, honor Retry-After once before giving up.
  if (res.status === 429 && attempt < 1) {
    const retryAfter = parseFloat(res.headers.get("retry-after") || "2");
    const waitMs = Math.min(8000, Math.max(1000, (isNaN(retryAfter) ? 2 : retryAfter) * 1000));
    await new Promise((r) => setTimeout(r, waitMs));
    return chat(args, attempt + 1);
  }

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Groq ${res.status}: ${text.slice(0, 200)}`);
  }
  const json = await res.json();
  return json?.choices?.[0]?.message?.content ?? "";
}

// MARK: - Parsing helpers

function extractJSON(raw: string): string {
  const start = raw.indexOf("{");
  const end = raw.lastIndexOf("}");
  if (start === -1 || end === -1 || start >= end) return raw;
  return raw.slice(start, end + 1);
}

function num(v: unknown): number {
  const n = typeof v === "string" ? parseFloat(v) : (v as number);
  return Number.isFinite(n) && n > 0 ? n : 0;
}

function parseItems(raw: string): FoodItem[] {
  try {
    const obj = JSON.parse(extractJSON(raw));
    const items = Array.isArray(obj.items) ? obj.items : [];
    return items
      .filter((it: { name?: string }) => it && typeof it.name === "string" && it.name.trim())
      .map((it: Record<string, unknown>): FoodItem => {
        const macros: Macros = {
          calories: num(it.calories),
          protein: num(it.protein_g),
          carbs: num(it.carbs_g),
          fat: num(it.fat_g),
        };
        const conf = String(it.confidence ?? "medium").toLowerCase();
        return {
          name: String(it.name),
          portion: String(it.portion ?? "estimated portion"),
          macros,
          confidence: (["high", "medium", "low"].includes(conf) ? conf : "medium") as FoodItem["confidence"],
        };
      });
  } catch {
    return [];
  }
}

function parseNote(raw: string): string | null {
  try {
    const obj = JSON.parse(extractJSON(raw));
    const note = typeof obj.note === "string" ? obj.note.trim() : "";
    return note || null;
  } catch {
    return null;
  }
}

function dedupe(items: FoodItem[]): FoodItem[] {
  const seen = new Map<string, FoodItem>();
  for (const it of items) {
    const key = it.name.toLowerCase().trim();
    if (!seen.has(key)) seen.set(key, it);
  }
  return [...seen.values()];
}

function offlineRecognition(reason: string): RecognizeResult {
  return {
    items: [
      {
        name: "Slice of pepperoni pizza",
        portion: "1 slice",
        macros: { calories: 285, protein: 12, carbs: 36, fat: 10 },
        confidence: "medium",
      },
    ],
    usedLiveAI: false,
    note: `Offline sample (${reason}). Add a Groq key for live recognition.`,
  };
}
