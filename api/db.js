// One pool per process; a connection per request caps throughput.
const { Pool } = require('pg');
const fs = require('fs');
const path = require('path');

const pool = new Pool({
  user: process.env.DBUSER,
  database: process.env.DB,
  password: process.env.DBPASS,
  host: process.env.DBHOST,
  port: process.env.DBPORT,
  // CloudNativePG uses its own CA, which isn't in the image's trust store, so
  // verification is off. Mount the cluster CA to enable it.
  ssl: process.env.DBSSL === 'true' ? { rejectUnauthorized: false } : false,
  // 25 per pod × 6 pods = 150 connections; Postgres max_connections is 200
  // (postgres/cluster.yaml). Raise both together.
  max: 25,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 5000,
});

// Unhandled pool errors crash the process.
pool.on('error', (err) => console.error('postgres pool error:', err.message));

// Runs on every replica at startup; idempotent (IF NOT EXISTS).
async function migrate() {
  const sql = fs.readFileSync(path.join(__dirname, 'schema.sql'), 'utf8');
  await pool.query(sql);
  console.log('schema ready');
}

module.exports = { pool, migrate };
