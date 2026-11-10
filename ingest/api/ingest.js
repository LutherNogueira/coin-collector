// POST /api/ingest: receives a batch of game events and stores it, untouched, as one JSON Lines file in
// Vercel Blob (the bronze layer's source). Anything that is not a well-formed batch is rejected.
//
// Environment (Vercel project settings):
//   BLOB_READ_WRITE_TOKEN  created by connecting a Blob store to the project
//   INGEST_ENABLED         set to "false" to switch collection off without redeploying
//   BLOB_ACCESS            "private" (default) or "public", it has to match the store that was created
import { put } from '@vercel/blob';
import { MAX_BODY_BYTES, validateBatch } from './_validate.js';
import { createLimiter } from './_ratelimit.js';

// 6 batches a minute is what one open game sends; 20 leaves room for a few tabs behind one address.
const limiter = createLimiter({ limit: 20, windowMs: 60_000 });

export default async function handler(req, res) {
  res.setHeader('Cache-Control', 'no-store');
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'method not allowed' });
  }
  if (process.env.INGEST_ENABLED === 'false') return res.status(503).json({ error: 'collection is off' });

  // Only the game served from this very host may send: the page's origin has to be this deployment.
  const origin = req.headers.origin;
  // This stops other websites from posting from a visitor's browser. It does not stop a script that sets the header
  // itself, which is why there is also the limit below and the validation that follows.
  if (origin && originHost(origin) !== req.headers.host) return res.status(403).json({ error: 'wrong origin' });

  const client = String(req.headers['x-forwarded-for'] ?? req.socket?.remoteAddress ?? 'unknown').split(',')[0].trim();
  if (!limiter.allow(client)) {
    res.setHeader('Retry-After', '60');
    return res.status(429).json({ error: 'too many batches' });
  }

  const declared = Number(req.headers['content-length'] ?? 0);
  if (declared > MAX_BODY_BYTES) return res.status(413).json({ error: 'body too large' });

  const body = typeof req.body === 'string' ? req.body : JSON.stringify(req.body ?? '');
  const result = validateBatch(body);
  if (!result.ok) return res.status(400).json({ error: result.error });

  const day = new Date().toISOString().slice(0, 10);
  try {
    await put(`events/${day}/${result.session}.jsonl`, result.lines.join('\n') + '\n', {
      access: process.env.BLOB_ACCESS === 'public' ? 'public' : 'private',
      addRandomSuffix: true,   // every batch is its own file; nothing is ever overwritten
      contentType: 'application/x-ndjson',
    });
  } catch (err) {
    console.error('blob put failed', err?.message);   // the cause goes to the log, not to the caller
    return res.status(502).json({ error: 'storage unavailable' });
  }
  return res.status(204).end();
}

function originHost(origin) {
  try {
    return new URL(origin).host;
  } catch {
    return null;   // a malformed Origin header is a wrong origin, not a server error
  }
}
