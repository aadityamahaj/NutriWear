import { NextRequest, NextResponse } from "next/server";
import { coachTip, recognizeFood } from "@/lib/groq";

export const dynamic = "force-dynamic";
export const maxDuration = 30;

/**
 * POST /api/analyze
 * Body: { image: "data:image/jpeg;base64,..." }
 * Returns recognized foods + a coaching tip.
 */
export async function POST(req: NextRequest) {
  let body: { image?: string };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: "invalid json" }, { status: 400 });
  }

  if (!body.image || !body.image.startsWith("data:image")) {
    return NextResponse.json({ error: "missing image data url" }, { status: 400 });
  }

  const result = await recognizeFood(body.image);
  const summary =
    result.items.map((i) => i.name).join(", ") || "a meal";
  const tip = await coachTip(summary);

  return NextResponse.json({ ...result, coachTip: tip });
}
