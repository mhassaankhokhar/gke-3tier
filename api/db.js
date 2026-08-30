// One pool for the process.
//
// It was once created inside the request handler and ended at the end of it,
// so every request opened a TCP connection, completed a TLS handshake, ran one
// query and threw the connection away. That capped a replica at ~15 requests
// per second while using 0.18 of a core — the time went on connection setup,
// not on work. Fixing it moved the number to ~78.
const { Pool } = require('pg');
const fs = require('fs');
const path = require('path');

const pool = new Pool({
  user: process.env.DBUSER,
  database: process.env.DB,
  password: process.env.DBPASS,
  host: process.env.DBHOST,
  port: process.env.DBPORT,
  // CloudNativePG issues its own certificates and serves TLS 1.3. The CA is not
  // in the container's trust store, so verification is off — the alternative is
  // mounting the cluster CA, which is the right answer once this talks to a
  // database it does not fully control.
  ssl: process.env.DBSSL === 'true' ? { rejectUnauthorized: false } : false,
  // Bounded deliberately: Postgres allocates a backend process per connection,
  // so an unbounded pool times every replica is how an application knocks over
  // its own database during a scale-up.
  max: 10,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 5000,
});

// A pool emits errors for idle clients dropped by the server or the network.
// Unhandled, they become uncaught exceptions and take the process down — which
// under load reads as a crash loop rather than as a lost connection.
pool.on('error', (err) => console.error('postgres pool error:', err.message));

// Applied at startup, and safe to run on every replica: CREATE TABLE IF NOT
// EXISTS is idempotent, so several pods racing to start cannot conflict.
async function migrate() {
  const sql = fs.readFileSync(path.join(__dirname, 'schema.sql'), 'utf8');
  await pool.query(sql);
  console.log('schema ready');
}

module.exports = { pool, migrate };
