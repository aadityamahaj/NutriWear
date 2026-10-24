import { NextRequest, NextResponse } from "next/server";
import { askCoach } from "@/lib/groq";

export const dynamic = "force-dynamic";
export const maxDuration = 30;

/**
 * POST /api/coach
 * Body: { question: string, context?: string }
 * Returns a short spoken-style coaching answer.
 */
export async function POST(req: NextRequest) {
  let body: { question?: string; context?: string };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: "invalid json" }, { status: 400 });
  }
  const question = (body.question ?? "").trim();
  if (!question) return NextResponse.json({ error: "missing question" }, { status: 400 });

  const answer = await askCoach(question, body.context ?? "");
  return NextResponse.json({ answer });
}
