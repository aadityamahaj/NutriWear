import {
  ChannelState,
  EatingSession,
  SyncEvent,
} from "./types";

/**
 * In-memory sync hub keyed by pairing code. Good enough for a hackathon demo:
 * the "wearable" (web camera) writes session events here and subscribers
 * (web dashboard, iOS companion) receive them over SSE. Resets on restart.
 *
 * Stashed on globalThis so Next.js hot-reload / route modules share one instance.
 */

type Subscriber = (event: SyncEvent) => void;

interface Hub {
  channels: Map<string, ChannelState>;
  subscribers: Map<string, Set<Subscriber>>;
}

const g = globalThis as unknown as { __nutriHub?: Hub };

function hub(): Hub {
  if (!g.__nutriHub) {
    g.__nutriHub = { channels: new Map(), subscribers: new Map() };
  }
  return g.__nutriHub;
}

export function getChannel(code: string): ChannelState {
  const h = hub();
  let channel = h.channels.get(code);
  if (!channel) {
    channel = { code, current: null, history: [], updatedAt: Date.now() };
    h.channels.set(code, channel);
  }
  return channel;
}

export function setCurrent(code: string, session: EatingSession | null): ChannelState {
  const channel = getChannel(code);
  channel.current = session;
  channel.updatedAt = Date.now();
  return channel;
}

export function pushToHistory(code: string, session: EatingSession): ChannelState {
  const channel = getChannel(code);
  // De-dupe by id, newest first.
  channel.history = [session, ...channel.history.filter((s) => s.id !== session.id)].slice(0, 50);
  channel.current = session;
  channel.updatedAt = Date.now();
  return channel;
}

export function subscribe(code: string, fn: Subscriber): () => void {
  const h = hub();
  if (!h.subscribers.has(code)) h.subscribers.set(code, new Set());
  h.subscribers.get(code)!.add(fn);
  return () => {
    h.subscribers.get(code)?.delete(fn);
  };
}

export function publish(code: string, event: SyncEvent): void {
  const subs = hub().subscribers.get(code);
  if (!subs) return;
  for (const fn of subs) {
    try {
      fn(event);
    } catch {
      // Ignore individual subscriber failures.
    }
  }
}
