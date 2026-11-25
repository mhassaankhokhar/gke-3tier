// Caches the summary aggregation. Every write path calls invalidate(), so
// totals are never stale after a change.
const { createClient } = require('redis');

const TTL_SECONDS = 60;
const PREFIX = 'sub:';

let client = null;
let available = false;

if (process.env.REDIS_URL) {
  client = createClient({ url: process.env.REDIS_URL });
  client.on('error', (err) => {
    // Logged once per state change, not per failure.
    if (available) console.error('redis error:', err.message);
    available = false;
  });
  client.on('ready', () => { available = true; });
  client.connect().catch((err) => console.error('redis connect failed:', err.message));
}

// Fails open: if Redis is down the app is slower, not broken.
async function get(key) {
  if (!available) return null;
  try {
    const raw = await client.get(PREFIX + key);
    return raw ? JSON.parse(raw) : null;
  } catch { return null; }
}

async function set(key, value) {
  if (!available) return;
  try {
    await client.set(PREFIX + key, JSON.stringify(value), { EX: TTL_SECONDS });
  } catch { /* cache write failures are not request failures */ }
}

async function invalidate() {
  if (!available) return;
  try {
    await client.del(PREFIX + 'summary');
  } catch { /* the TTL will clear it soon enough */ }
}

module.exports = { get, set, invalidate };
