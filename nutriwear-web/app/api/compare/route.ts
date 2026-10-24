import { NextRequest, NextResponse } from "next/server";
import { compareConsumption, type StartItem } from "@/lib/groq";

export const dynamic = "force-dynamic";
export const maxDuration = 40;

/**
 * POST /api/compare
 * Body: { before: dataURL, after: dataURL, startItems: StartItem[] }
 * Anchored to the already-recognized startItems: the model only estimates how
 * much is LEFT, and eaten amounts are derived from the known start values. This
 * keeps the result consistent with what was shown at meal start.
 */
export async function POST(req: NextRequest) {
  let body: { before?: string; after?: string; startItems?: StartItem[] };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: "invalid json" }, { status: 400 });
  }
  if (!body.before?.startsWith("data:image") || !body.after?.startsWith("data:image")) {
    return NextResponse.json({ error: "missing before/after images" }, { status: 400 });
  }
  const startItems = Array.isArray(body.startItems) ? body.startItems : [];
  const result = await compareConsumption(body.before, body.after, startItems);
  return NextResponse.json(result);
}
