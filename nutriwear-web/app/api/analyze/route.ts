import { NextRequest, NextResponse } from "next/server";
import { coachTip, recognizeFood } from "@/lib/groq";

export const dynamic = "force-dynamic";
export const maxDuration = 30;

/**
 * POST /api/analyze
 * Body: { image: "data:image/jpeg;base64,...", tip?: boolean }
 * Returns recognized foods, and (when tip !== false) a coaching tip.
 *
 * Mid-meal auto-scans pass tip:false to skip the extra coach-tip AI call —
 * that halves latency/tokens and avoids function timeouts on the hot path.
 */
export async function POST(req: NextRequest) {
  let body: { image?: string; tip?: boolean };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: "invalid json" }, { status: 400 });
  }

  if (!body.image || !body.image.startsWith("data:image")) {
    return NextResponse.json({ error: "missing image data url" }, { status: 400 });
  }

  const result = await recognizeFood(body.image);

  // Only generate a coaching tip when asked (meal start), and only if there's
  // real food to comment on.
  let tip: string | null = null;
  if (body.tip !== false && result.usedLiveAI && result.items.length) {
    const summary = result.items.map((i) => i.name).join(", ") || "a meal";
    tip = await coachTip(summary);
  }

  return NextResponse.json({ ...result, coachTip: tip });
}
