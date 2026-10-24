import { NextRequest } from "next/server";
import { getChannel, subscribe } from "@/lib/store";
import { SyncEvent } from "@/lib/types";

export const dynamic = "force-dynamic";

// GET /api/stream?code=XXXX  → Server-Sent Events of sync events for that channel.
export async function GET(req: NextRequest) {
  const code = req.nextUrl.searchParams.get("code")?.toUpperCase();
  if (!code) {
    return new Response("missing code", { status: 400 });
  }

  const encoder = new TextEncoder();

  const stream = new ReadableStream({
    start(controller) {
      const send = (event: SyncEvent) => {
        controller.enqueue(encoder.encode(`data: ${JSON.stringify(event)}\n\n`));
      };

      // Immediately send the current full state so new subscribers sync up.
      send({ type: "state", state: getChannel(code) });

      const unsubscribe = subscribe(code, send);

      // Heartbeat to keep the connection alive through proxies.
      const heartbeat = setInterval(() => {
        controller.enqueue(encoder.encode(`: ping\n\n`));
      }, 15000);

      // Clean up when the client disconnects.
      req.signal.addEventListener("abort", () => {
        clearInterval(heartbeat);
        unsubscribe();
        try {
          controller.close();
        } catch {
          /* already closed */
        }
      });
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
