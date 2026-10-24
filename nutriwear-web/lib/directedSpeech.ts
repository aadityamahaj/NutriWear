// Decides whether an always-on transcript is actually directed at the coach.
//
// When the mic is always listening it hears ambient conversation too, so we
// only act on speech that is EITHER:
//   1. an explicit session command ("I'm done", "let's eat"), or
//   2. prefixed with a wake word ("hey NutriWear", "coach, ...").
// Everything else is ignored. In manual tap-to-talk mode the tap is the signal,
// so no wake word is required.

export type DirectedIntent =
  | { kind: "start" }
  | { kind: "done" }
  | { kind: "question"; text: string }
  | { kind: "ignore" };

const START_RE = /\b(let'?s eat|start eating|time to eat|i'?m eating|begin eating)\b/;
const DONE_RE = /\b(i'?m done|i am done|i'?m finished|i'?m full|all done|that'?s it|stop eating|done eating|finished eating)\b/;

// Wake words / phrases that mean "I'm talking to you now".
const WAKE_RE =
  /\b(hey +)?(nutri ?wear|nutri|the coach|coach|assistant|hey +coach)\b[\s,:-]*/;

/**
 * Classify an always-on transcript.
 * @param requireWake  true in always-on mode (needs a wake word for questions),
 *                     false in manual mode (any speech is a question).
 */
export function classifyDirected(transcript: string, requireWake: boolean): DirectedIntent {
  const t = transcript.toLowerCase().trim();
  if (!t) return { kind: "ignore" };

  // Explicit session commands always act, wake word or not — they're
  // unambiguous intents, not ambient chatter.
  if (DONE_RE.test(t)) return { kind: "done" };
  if (START_RE.test(t)) return { kind: "start" };

  if (!requireWake) {
    // Manual tap: the whole utterance is the question.
    return { kind: "question", text: transcript.trim() };
  }

  // Always-on: only respond to questions addressed to the coach.
  const wake = t.match(WAKE_RE);
  if (!wake) return { kind: "ignore" };

  // Strip the wake prefix and everything before it; keep what was actually asked.
  const idx = (wake.index ?? 0) + wake[0].length;
  const remainder = transcript.trim().slice(transcriptOffset(transcript, t, idx)).trim();
  if (!remainder) {
    // Bare "hey coach" with nothing after it → acknowledge, don't call the LLM.
    return { kind: "question", text: "" };
  }
  return { kind: "question", text: remainder };
}

// Map a lowercase-string index back onto the original-cased transcript. The
// lowercase transform here is 1:1 in length for the Latin text we handle, so
// the index lines up; this helper keeps intent explicit and guards length.
function transcriptOffset(original: string, lower: string, lowerIdx: number): number {
  if (original.length === lower.length) return lowerIdx;
  return Math.min(lowerIdx, original.length);
}
