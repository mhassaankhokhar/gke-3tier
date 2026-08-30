// Redis, used for what it is actually good at here.
//
// It arrived in this project as a session store for a server-rendered web tier.
// A React client talking to a JSON API has no server-side session, so that
// reason is gone — and rather than keep a component with no purpose, it now
// caches the summary aggregation, which is three queries every page load wants.
//
// Every write path calls invalidate(). A cache that is only ever written to and
// never cleared shows stale totals a few seconds after someone adds a
// subscription, which is exactly when they are looking at the number.
const { createClient } = require('redis');

const TTL_SECONDS = 60;
const PREFIX = 'sub:';

let client = null;
let available = false;

if (process.env.REDIS_URL) {
  client = createClient({ url: process.env.REDIS_URL });
  client.on('error', (err) => {
    // Logged once per state change rather than per failure: a Redis outage
    // otherwise fills the log at request rate and hides everything else.
    if (available) console.error('redis error:', err.message);
    available = false;
  });
  client.on('ready', () => { available = true; });
  client.connect().catch((err) => console.error('redis connect failed:', err.message));
}

// Every function below fails open. Redis is a cache: if it is down the app
// should be slower, not broken. Treating a cache as a hard dependency turns an
// optimisation into a second thing that can take the service offline.
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
