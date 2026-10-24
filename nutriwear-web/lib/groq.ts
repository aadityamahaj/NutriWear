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

// MARK: - Lightweight "is there food?" check (auto-start confirmation)

const PRESENCE_SYSTEM = `You are NutriWear's food presence detector for a wearable camera.
Look at the photo. Decide if there is a MEAL or FOOD that a person is about to eat
(a plate/bowl/tray of food, a sandwich, a snack in hand, etc.) ANYWHERE in the frame —
it does NOT need to be centered.
Ignore: empty tables, packaging only, drinks alone, faces, rooms, screens.
Return ONLY this JSON: {"food": true|false, "confidence": 0-1, "label": "short name of the food or empty"}`;

export interface FoodPresence {
  food: boolean;
  confidence: number;
  label: string;
  usedLiveAI: boolean;
}

/** Fast yes/no: is there food anywhere in this frame? Used to confirm auto-start. */
export async function detectFoodPresence(imageDataURL: string): Promise<FoodPresence> {
  if (!isConfigured()) {
    // Without a key we can't confirm; let the client heuristic decide.
    return { food: false, confidence: 0, label: "", usedLiveAI: false };
  }
  try {
    const raw = await chat({
      model: VISION_MODEL,
      temperature: 0,
      maxTokens: 600,
      jsonMode: true,
      messages: [
        { role: "system", content: PRESENCE_SYSTEM },
        {
          role: "user",
          content: [
            { type: "text", text: "Is there food anywhere in this image? Return only the JSON." },
            { type: "image_url", image_url: { url: imageDataURL } },
          ],
        },
      ],
    });
    const obj = JSON.parse(extractJSON(raw));
    return {
      food: obj.food === true,
      confidence: Math.min(1, Math.max(0, num(obj.confidence))),
      label: typeof obj.label === "string" ? obj.label.trim() : "",
      usedLiveAI: true,
    };
  } catch {
    return { food: false, confidence: 0, label: "", usedLiveAI: false };
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

// The "before" plate was ALREADY recognized at the start of the meal. To keep
// the numbers consistent, the comparison must NOT re-estimate the plate — it
// only estimates how much of each known item is LEFT. Eaten amounts are then
// computed from the known start values, so "ate 100%" exactly equals the
// originally detected calories.
const COMPARE_SYSTEM = `You are NutriWear's food vision engine for before/after eating comparison.
You are given a list of the foods that were on the plate at the START (already
measured, with calories and macros), the BEFORE photo, and the AFTER photo.

Do NOT re-estimate portions or calories. Your ONLY job is to look at the AFTER
photo and judge, for each START item, what fraction is still LEFT:
  0.0 = fully eaten, 1.0 = untouched.
If the AFTER plate looks empty/clean, every leftover_fraction is 0.

Match each item by name to the START list. Return ONLY this JSON (no markdown):
{"items":[{"name":"string","leftover_fraction":number}],"note":"one short sentence"}`;

/** An already-recognized start item (full-portion macros known). */
export interface StartItem {
  name: string;
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
  confidence?: "high" | "medium" | "low";
}

/**
 * Compare before/after, anchored to the known start items. The model only
 * returns leftover fractions; eaten amounts are derived from the KNOWN start
 * values, guaranteeing consistency with what was shown at meal start (and that
 * eating everything yields exactly the start calories).
 */
export async function compareConsumption(
  beforeDataURL: string,
  afterDataURL: string,
  startItems: StartItem[]
): Promise<ConsumptionResult> {
  // Can't anchor without known start items, or without a key → fall back.
  if (!isConfigured()) return consumptionFromStart(startItems, "no API key");
  if (startItems.length === 0) return consumptionFromStart(startItems, "no start items");

  try {
    const startList = startItems
      .map((i) => `- ${i.name}: ${Math.round(i.calories)} kcal, ${Math.round(i.protein)}p ${Math.round(i.carbs)}c ${Math.round(i.fat)}f`)
      .join("\n");
    const raw = await chat({
      model: VISION_MODEL,
      temperature: 0.2,
      maxTokens: 1200,
      jsonMode: true,
      messages: [
        { role: "system", content: COMPARE_SYSTEM },
        {
          role: "user",
          content: [
            { type: "text", text: `START items on the plate:\n${startList}\n\nBEFORE photo (full plate):` },
            { type: "image_url", image_url: { url: beforeDataURL } },
            { type: "text", text: "AFTER photo (leftovers). For each START item, return only its leftover_fraction as JSON." },
            { type: "image_url", image_url: { url: afterDataURL } },
          ],
        },
      ],
    });
    return applyLeftovers(raw, startItems);
  } catch (e) {
    return consumptionFromStart(startItems, e instanceof Error ? e.message : "error");
  }
}

/** Build a consistent result from KNOWN start items + model leftover fractions. */
function applyLeftovers(raw: string, startItems: StartItem[]): ConsumptionResult {
  let fractions: Record<string, number> = {};
  let note: string | null = null;
  try {
    const obj = JSON.parse(extractJSON(raw));
    note = typeof obj.note === "string" && obj.note.trim() ? obj.note.trim() : null;
    for (const it of (Array.isArray(obj.items) ? obj.items : [])) {
      if (it && typeof it.name === "string") {
        fractions[it.name.toLowerCase().trim()] = Math.min(1, Math.max(0, num(it.leftover_fraction)));
      }
    }
  } catch {
    // If parsing fails, assume everything was eaten (consistent with start).
    fractions = {};
  }

  const items: ConsumptionItem[] = startItems.map((s) => {
    const left = fractions[s.name.toLowerCase().trim()] ?? 0;
    const eatenRatio = 1 - left;
    return {
      name: s.name,
      startCalories: s.calories,
      leftoverFraction: left,
      eatenCalories: s.calories * eatenRatio,
      protein: s.protein * eatenRatio,
      carbs: s.carbs * eatenRatio,
      fat: s.fat * eatenRatio,
      confidence: s.confidence ?? "medium",
    };
  });
  return summarize(items, true, note);
}

/** No usable comparison → assume the start items were fully eaten (consistent). */
function consumptionFromStart(startItems: StartItem[], reason: string): ConsumptionResult {
  if (startItems.length === 0) return offlineConsumption(reason);
  const items: ConsumptionItem[] = startItems.map((s) => ({
    name: s.name,
    startCalories: s.calories,
    leftoverFraction: 0,
    eatenCalories: s.calories,
    protein: s.protein,
    carbs: s.carbs,
    fat: s.fat,
    confidence: s.confidence ?? "medium",
  }));
  return summarize(items, true, "Assumed you finished the plate.");
}

function summarize(items: ConsumptionItem[], usedLiveAI: boolean, note: string | null): ConsumptionResult {
  const startCalories = items.reduce((a, i) => a + i.startCalories, 0);
  const eatenCalories = items.reduce((a, i) => a + i.eatenCalories, 0);
  return {
    items,
    startCalories,
    eatenCalories,
    leftoverCalories: Math.max(0, startCalories - eatenCalories),
    usedLiveAI,
    note,
  };
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
    note: friendlyReason(reason),
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
      // gpt-oss-120b is a reasoning model and spends tokens thinking before the
      // visible answer, so a tight cap truncates the reply. Give headroom.
      maxTokens: 800,
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
      // Headroom for the reasoning model so the short tip isn't truncated.
      maxTokens: 500,
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

  // On a rate limit (429), honor Retry-After and retry with exponential
  // backoff. Groq's per-minute token window clears quickly, so a couple of
  // short waits usually recovers instead of dropping to the offline fallback.
  if (res.status === 429 && attempt < 3) {
    const retryAfter = parseFloat(res.headers.get("retry-after") || "");
    const backoff = 1000 * Math.pow(2, attempt); // 1s, 2s, 4s
    const waitMs = Math.min(
      9000,
      Math.max(1000, isNaN(retryAfter) ? backoff : retryAfter * 1000)
    );
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

/** Turn a raw internal error reason into a short, user-friendly note. */
function friendlyReason(reason: string): string {
  const r = reason.toLowerCase();
  if (r.includes("429") || r.includes("rate limit")) {
    return "The AI is busy right now (rate limit). Give it a few seconds and try again.";
  }
  if (r.includes("no api key")) {
    return "Add a Groq key to enable live AI.";
  }
  if (r.includes("timeout") || r.includes("network") || r.includes("fetch")) {
    return "Couldn't reach the AI service. Check your connection and try again.";
  }
  return "The AI couldn't respond just now — showing an estimate instead.";
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
    note: friendlyReason(reason),
  };
}
