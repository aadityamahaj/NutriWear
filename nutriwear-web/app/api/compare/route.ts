import { NextRequest, NextResponse } from "next/server";
import { compareConsumption } from "@/lib/groq";

export const dynamic = "force-dynamic";
export const maxDuration = 40;

/**
 * POST /api/compare
 * Body: { before: dataURL, after: dataURL }
 * Returns per-item start calories, leftover fraction, and eaten amounts.
 */
export async function POST(req: NextRequest) {
  let body: { before?: string; after?: string };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: "invalid json" }, { status: 400 });
  }
  if (!body.before?.startsWith("data:image") || !body.after?.startsWith("data:image")) {
    return NextResponse.json({ error: "missing before/after images" }, { status: 400 });
  }
  const result = await compareConsumption(body.before, body.after);
  return NextResponse.json(result);
}
