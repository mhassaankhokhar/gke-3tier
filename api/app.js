// Subscription tracker API: CRUD over one table, plus a summary of monthly
// cost, upcoming renewals and unused subscriptions.
const express = require('express');
const { pool, migrate } = require('./db');
const cache = require('./cache');

const app = express();
app.use(express.json());

// ── health ────────────────────────────────────────────────────────────────
// Liveness checks only this process; it must not depend on Postgres, or a slow
// database gets healthy pods killed.
app.get('/healthz', (req, res) => res.json({ status: 'ok' }));

// Readiness checks Postgres: failing removes the pod from the Service, it doesn't kill it.
app.get('/readyz', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ status: 'ok' });
  } catch (err) {
    res.status(503).json({ status: 'database unreachable' });
  }
});

// ── validation ────────────────────────────────────────────────────────────
const CYCLES = ['monthly', 'yearly'];
const STATUSES = ['active', 'cancelled'];

function validate(body, { partial = false } = {}) {
  const errors = [];
  const has = (k) => body[k] !== undefined;
  const required = (k) => (partial ? has(k) : true);

  if (required('name') && (!has('name') || !String(body.name).trim())) {
    errors.push('name is required');
  }
  if (required('cost')) {
    const c = Number(body.cost);
    if (!Number.isFinite(c) || c < 0) errors.push('cost must be a number >= 0');
  }
  if (required('billing_cycle') && !CYCLES.includes(body.billing_cycle)) {
    errors.push(`billing_cycle must be one of ${CYCLES.join(', ')}`);
  }
  if (required('next_renewal') && Number.isNaN(Date.parse(body.next_renewal))) {
    errors.push('next_renewal must be a date');
  }
  if (has('status') && !STATUSES.includes(body.status)) {
    errors.push(`status must be one of ${STATUSES.join(', ')}`);
  }
  if (has('last_used') && body.last_used !== null && Number.isNaN(Date.parse(body.last_used))) {
    errors.push('last_used must be a date or null');
  }
  return errors;
}

// ── list ──────────────────────────────────────────────────────────────────
// Paginated so response size doesn't grow with the table.
const MAX_LIMIT = 100;
const DEFAULT_LIMIT = 50;

app.get('/api/subscriptions', async (req, res, next) => {
  try {
    const { status } = req.query;

    // Clamped to MAX_LIMIT so ?limit= can't request the whole table.
    const limit = Math.min(
      Math.max(parseInt(req.query.limit, 10) || DEFAULT_LIMIT, 1), MAX_LIMIT);
    const offset = Math.max(parseInt(req.query.offset, 10) || 0, 0);

    // Separate count query: tells the client there's a next page and keeps the
    // row query a plain index scan.
    const where = status ? 'WHERE status = $1' : '';
    const params = status ? [status] : [];

    const [rows, total] = await Promise.all([
      pool.query(
        `SELECT * FROM subscriptions ${where}
         ORDER BY next_renewal, id
         LIMIT $${params.length + 1} OFFSET $${params.length + 2}`,
        [...params, limit, offset]),
      pool.query(`SELECT COUNT(*)::int AS n FROM subscriptions ${where}`, params),
    ]);

    // id breaks ties on next_renewal so pages are stable.
    res.json({
      data: rows.rows,
      total: total.rows[0].n,
      limit,
      offset,
    });
  } catch (err) { next(err); }
});

app.get('/api/subscriptions/:id', async (req, res, next) => {
  try {
    const { rows } = await pool.query('SELECT * FROM subscriptions WHERE id = $1', [req.params.id]);
    if (!rows.length) return res.status(404).json({ error: 'not found' });
    res.json(rows[0]);
  } catch (err) { next(err); }
});

// ── create ────────────────────────────────────────────────────────────────
app.post('/api/subscriptions', async (req, res, next) => {
  const errors = validate(req.body);
  if (errors.length) return res.status(400).json({ errors });
  try {
    const b = req.body;
    const { rows } = await pool.query(
      `INSERT INTO subscriptions (name, cost, currency, billing_cycle, next_renewal, category, status, last_used, notes)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING *`,
      [b.name, b.cost, b.currency || 'USD', b.billing_cycle, b.next_renewal,
       b.category || null, b.status || 'active', b.last_used || null, b.notes || null]);
    await cache.invalidate();
    res.status(201).json(rows[0]);
  } catch (err) { next(err); }
});

// ── update ────────────────────────────────────────────────────────────────
app.patch('/api/subscriptions/:id', async (req, res, next) => {
  const errors = validate(req.body, { partial: true });
  if (errors.length) return res.status(400).json({ errors });

  const allowed = ['name', 'cost', 'currency', 'billing_cycle', 'next_renewal',
                   'category', 'status', 'last_used', 'notes'];
  const fields = allowed.filter((k) => req.body[k] !== undefined);
  if (!fields.length) return res.status(400).json({ error: 'no updatable fields supplied' });

  try {
    // Column names come from the allow-list, never the request; only values are parameterised.
    const set = fields.map((k, i) => `${k} = $${i + 1}`).join(', ');
    const values = fields.map((k) => req.body[k]);
    const { rows } = await pool.query(
      `UPDATE subscriptions SET ${set}, updated_at = now()
       WHERE id = $${fields.length + 1} RETURNING *`,
      [...values, req.params.id]);
    if (!rows.length) return res.status(404).json({ error: 'not found' });
    await cache.invalidate();
    res.json(rows[0]);
  } catch (err) { next(err); }
});

// ── delete ────────────────────────────────────────────────────────────────
app.delete('/api/subscriptions/:id', async (req, res, next) => {
  try {
    const { rowCount } = await pool.query('DELETE FROM subscriptions WHERE id = $1', [req.params.id]);
    if (!rowCount) return res.status(404).json({ error: 'not found' });
    await cache.invalidate();
    res.status(204).end();
  } catch (err) { next(err); }
});

// ── summary ───────────────────────────────────────────────────────────────
// The expensive read every page load wants, so it is cached in Redis.
app.get('/api/summary', async (req, res, next) => {
  try {
    const cached = await cache.get('summary');
    if (cached) return res.set('X-Cache', 'HIT').json(cached);

    const [totals, upcoming, unused, unusedTotal] = await Promise.all([
      // Yearly costs normalised to monthly so totals are comparable.
      pool.query(`
        SELECT
          COALESCE(SUM(CASE WHEN billing_cycle = 'monthly' THEN cost ELSE cost/12 END), 0) AS monthly,
          COALESCE(SUM(CASE WHEN billing_cycle = 'yearly'  THEN cost ELSE cost*12 END), 0) AS yearly,
          COUNT(*) AS count
        FROM subscriptions WHERE status = 'active'`),
      pool.query(`
        SELECT id, name, cost, currency, next_renewal FROM subscriptions
        WHERE status = 'active' AND next_renewal <= CURRENT_DATE + INTERVAL '30 days'
        ORDER BY next_renewal LIMIT 10`),
      // Unused: paid for and untouched for two months. List capped at 20; the
      // saving total below still counts all of them.
      pool.query(`
        SELECT id, name, cost, currency, last_used FROM subscriptions
        WHERE status = 'active'
          AND (last_used IS NULL OR last_used < CURRENT_DATE - INTERVAL '60 days')
        ORDER BY cost DESC LIMIT 20`),
      pool.query(`
        SELECT COALESCE(SUM(cost), 0) AS total, COUNT(*)::int AS n FROM subscriptions
        WHERE status = 'active'
          AND (last_used IS NULL OR last_used < CURRENT_DATE - INTERVAL '60 days')`),
    ]);

    const payload = {
      monthly_total: Number(totals.rows[0].monthly),
      yearly_total: Number(totals.rows[0].yearly),
      active_count: Number(totals.rows[0].count),
      upcoming_renewals: upcoming.rows,
      unused: unused.rows,
      unused_count: unusedTotal.rows[0].n,
      // Summed over all unused subscriptions, not just the 20 returned.
      potential_monthly_saving: Number(unusedTotal.rows[0].total),
    };

    await cache.set('summary', payload);
    res.set('X-Cache', 'MISS').json(payload);
  } catch (err) { next(err); }
});

// ── errors ────────────────────────────────────────────────────────────────
app.use((req, res) => res.status(404).json({ error: 'not found' }));

app.use((err, req, res, next) => {
  // Full error in the log only: it can contain the query and schema.
  console.error('request failed:', err.message);
  res.status(500).json({ error: 'internal error' });
});

module.exports = { app, migrate };
