import { NextRequest, NextResponse } from "next/server";
import { getChannel, pushToHistory, setCurrent } from "@/lib/store";
import { EatingSession, emptySession } from "@/lib/types";

export const dynamic = "force-dynamic";

// GET /api/session?code=XXXX  → current channel state
export async function GET(req: NextRequest) {
  const code = req.nextUrl.searchParams.get("code")?.toUpperCase();
  if (!code) return NextResponse.json({ error: "missing code" }, { status: 400 });
  return NextResponse.json(await getChannel(code));
}

/**
 * POST /api/session  → record a session event.
 * Body: { code, action: "start" | "update" | "end", session?, detectedBy? }
 *
 * State is written to the shared store; the /api/stream pollers pick up the
 * change and push it to connected clients (phone + dashboard).
 */
export async function POST(req: NextRequest) {
  let body: {
    code?: string;
    action?: "start" | "update" | "end";
    session?: Partial<EatingSession>;
    detectedBy?: "auto" | "manual";
  };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: "invalid json" }, { status: 400 });
  }

  const code = body.code?.toUpperCase();
  if (!code || !body.action) {
    return NextResponse.json({ error: "missing code or action" }, { status: 400 });
  }

  const channel = await getChannel(code);

  if (body.action === "start") {
    const session: EatingSession = {
      ...emptySession(crypto.randomUUID()),
      status: "eating",
      startedAt: Date.now(),
      detectedBy: body.detectedBy ?? "manual",
    };
    await setCurrent(code, session);
    return NextResponse.json({ ok: true, session });
  }

  if (body.action === "update") {
    const base = channel.current ?? emptySession(crypto.randomUUID());
    const session: EatingSession = { ...base, ...body.session, status: "eating" };
    await setCurrent(code, session);
    return NextResponse.json({ ok: true, session });
  }

  // end
  const base = channel.current ?? emptySession(crypto.randomUUID());
  const session: EatingSession = {
    ...base,
    ...body.session,
    status: "ended",
    endedAt: Date.now(),
  };
  await pushToHistory(code, session);
  return NextResponse.json({ ok: true, session });
}
