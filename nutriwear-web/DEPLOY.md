# Deploying the NutriWear web companion

Deploying serves the app over **HTTPS**, which is what makes the **microphone
and camera work on phones and laptops**. Browsers only grant `getUserMedia`
(camera/mic) and the Web Speech API (`SpeechRecognition`) in a *secure context*:
`https://` or `http://localhost`. The LAN dev setup (`http://192.168.x.x:3000`)
is neither, so the browser silently blocks the mic there. On an HTTPS URL it
works everywhere.

## 1. Create a free Upstash Redis database

Live sync between the phone and the web wearable needs a store that every
serverless instance can see (Vercel spreads requests across instances that
don't share memory). Upstash Redis is the simplest option.

1. Sign up at https://console.upstash.com/ and create a Redis database.
2. Open the database → **REST API** and copy:
   - `UPSTASH_REDIS_REST_URL`
   - `UPSTASH_REDIS_REST_TOKEN`

> Without these, the app still runs but falls back to an in-memory store, so
> sync only works within a single process (fine for local dev, not for Vercel).

## 2. Deploy to Vercel

Using the CLI from inside `nutriwear-web/`:

```
npm i -g vercel        # if you don't have it
vercel                 # first run links/creates the project
vercel --prod          # production deploy
```

Or import the GitHub repo at https://vercel.com/new and set the **Root
Directory** to `nutriwear-web`.

## 3. Set environment variables in Vercel

Project → Settings → Environment Variables (Production + Preview):

| Name | Value |
| --- | --- |
| `GROQ_API_KEY` | your Groq key |
| `UPSTASH_REDIS_REST_URL` | from Upstash |
| `UPSTASH_REDIS_REST_TOKEN` | from Upstash |

Redeploy after adding them.

## 4. Use it everywhere

- Open `https://<your-app>.vercel.app/wear` on your **phone** → allow camera +
  mic → voice commands ("let's eat", "I'm done") and the proactive slow-down
  coach work.
- Open `https://<your-app>.vercel.app/dashboard` on a **laptop** with the same
  pairing code → it syncs live.
- In the **iOS app**, set the Live tab's Server URL to your Vercel URL and enter
  the pairing code.

## Notes

- The SSE stream (`/api/stream`) polls the shared store once a second and emits
  a full `state` event on change — the same event the iOS app and dashboard
  already consume, so no client changes are needed.
- Channel state in Redis expires after 6 hours of inactivity.
