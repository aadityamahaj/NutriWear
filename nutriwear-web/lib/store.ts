import { Redis } from "@upstash/redis";
import { ChannelState, EatingSession } from "./types";

/**
 * Sync hub keyed by pairing code. The "wearable" (web camera) writes session
 * state here and subscribers (web dashboard, iOS companion) read it over SSE.
 *
 * Two backends, chosen automatically:
 *  - Upstash Redis when UPSTASH_REDIS_REST_URL / _TOKEN are set (production /
 *    Vercel). State is shared across all serverless instances, so the phone and
 *    the wearable always see each other regardless of which instance serves a
 *    request. This is what makes live sync work in deployment.
 *  - In-memory (stashed on globalThis) for local dev with zero config.
 *
 * Delivery to clients is handled by the /api/stream route, which polls
 * `getChannel` and emits a full `state` event whenever `updatedAt` changes.
 * Polling is used (rather than Redis pub/sub) because it's robust on
 * serverless, where connections are short-lived and instances don't share
 * memory. Both clients already handle the `state` event, so no client change
 * is needed.
 */

const EMPTY = (code: string): ChannelState => ({
  code,
  current: null,
  history: [],
  updatedAt: Date.now(),
});

// Channel state expires after this many seconds of inactivity (keeps Redis
// tidy; a pairing is a short-lived eating session, not permanent storage).
const TTL_SECONDS = 60 * 60 * 6; // 6 hours

// ---------------------------------------------------------------------------
// Redis backend (production)
// ---------------------------------------------------------------------------

let redis: Redis | null = null;
function getRedis(): Redis | null {
  if (redis) return redis;
  const url = process.env.UPSTASH_REDIS_REST_URL;
  const token = process.env.UPSTASH_REDIS_REST_TOKEN;
  if (!url || !token) return null;
  redis = new Redis({ url, token });
  return redis;
}

const key = (code: string) => `nutriwear:channel:${code}`;

// ---------------------------------------------------------------------------
// In-memory backend (local dev fallback)
// ---------------------------------------------------------------------------

const g = globalThis as unknown as { __nutriChannels?: Map<string, ChannelState> };
function memory(): Map<string, ChannelState> {
  if (!g.__nutriChannels) g.__nutriChannels = new Map();
  return g.__nutriChannels;
}

// ---------------------------------------------------------------------------
// Public API (async — both backends)
// ---------------------------------------------------------------------------

export async function getChannel(code: string): Promise<ChannelState> {
  const r = getRedis();
  if (r) {
    const stored = await r.get<ChannelState>(key(code));
    return stored ?? EMPTY(code);
  }
  const mem = memory();
  let channel = mem.get(code);
  if (!channel) {
    channel = EMPTY(code);
    mem.set(code, channel);
  }
  return channel;
}

async function saveChannel(channel: ChannelState): Promise<void> {
  const r = getRedis();
  if (r) {
    await r.set(key(channel.code), channel, { ex: TTL_SECONDS });
    return;
  }
  memory().set(channel.code, channel);
}

export async function setCurrent(code: string, session: EatingSession | null): Promise<ChannelState> {
  const channel = await getChannel(code);
  channel.current = session;
  channel.updatedAt = Date.now();
  await saveChannel(channel);
  return channel;
}

export async function pushToHistory(code: string, session: EatingSession): Promise<ChannelState> {
  const channel = await getChannel(code);
  // De-dupe by id, newest first, cap at 50.
  channel.history = [session, ...channel.history.filter((s) => s.id !== session.id)].slice(0, 50);
  channel.current = session;
  channel.updatedAt = Date.now();
  await saveChannel(channel);
  return channel;
}
