import { NextRequest, NextResponse } from "next/server";
import { detectFoodPresence } from "@/lib/groq";

export const dynamic = "force-dynamic";
export const maxDuration = 20;

/**
 * POST /api/detect
 * Body: { image: "data:image/jpeg;base64,..." }
 * Fast yes/no food-presence check used to confirm auto-start. Food can be
 * anywhere in the frame — it doesn't need to be centered.
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

  const result = await detectFoodPresence(body.image);
  return NextResponse.json(result);
}
