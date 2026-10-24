import { NextRequest } from "next/server";
import { getChannel } from "@/lib/store";
import { SyncEvent } from "@/lib/types";

export const dynamic = "force-dynamic";
// Keep the SSE connection open long enough to be useful on serverless.
export const maxDuration = 300;

/**
 * GET /api/stream?code=XXXX  → Server-Sent Events for a channel.
 *
 * Polls the shared store once a second and emits a full `state` event whenever
 * the channel's `updatedAt` changes. This works identically with the Redis
 * backend (production, cross-instance) and the in-memory backend (local dev),
 * which is why live sync now survives Vercel's serverless model.
 */
export async function GET(req: NextRequest) {
  const code = req.nextUrl.searchParams.get("code")?.toUpperCase();
  if (!code) {
    return new Response("missing code", { status: 400 });
  }

  const encoder = new TextEncoder();

  const stream = new ReadableStream({
    async start(controller) {
      let closed = false;
      const send = (event: SyncEvent) => {
        if (closed) return;
        try {
          controller.enqueue(encoder.encode(`data: ${JSON.stringify(event)}\n\n`));
        } catch {
          closed = true;
        }
      };

      // Send current state immediately so a new subscriber syncs up.
      let lastUpdatedAt = 0;
      try {
        const initial = await getChannel(code);
        lastUpdatedAt = initial.updatedAt;
        send({ type: "state", state: initial });
      } catch {
        /* ignore — the poll loop will retry */
      }

      // Poll for changes.
      const poll = setInterval(async () => {
        if (closed) return;
        try {
          const state = await getChannel(code);
          if (state.updatedAt !== lastUpdatedAt) {
            lastUpdatedAt = state.updatedAt;
            send({ type: "state", state });
          }
        } catch {
          /* transient store error — try again next tick */
        }
      }, 1000);

      // Heartbeat keeps the connection alive through proxies.
      const heartbeat = setInterval(() => {
        if (closed) return;
        try {
          controller.enqueue(encoder.encode(`: ping\n\n`));
        } catch {
          closed = true;
        }
      }, 15000);

      const cleanup = () => {
        closed = true;
        clearInterval(poll);
        clearInterval(heartbeat);
        try {
          controller.close();
        } catch {
          /* already closed */
        }
      };

      req.signal.addEventListener("abort", cleanup);
    },
  });

  return new Response(stream, {
    headers: {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache, no-transform",
      Connection: "keep-alive",
      "X-Accel-Buffering": "no",
    },
  });
}
