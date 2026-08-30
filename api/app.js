// Subscription tracker — the API.
//
// CRUD over one table, plus the summary the app exists for: what this costs per
// month, what renews soon, and what has not been used in a while. The last one
// is the point — a subscription that costs money and goes unused is the one to
// cancel.
const express = require('express');
const { pool, migrate } = require('./db');
const cache = require('./cache');

const app = express();
app.use(express.json());

// ── health ────────────────────────────────────────────────────────────────
//
// Liveness asks only whether this process is alive, and touches nothing else.
// Both probes once pointed at a handler that queried Postgres, so a slow
// database made Kubernetes kill healthy api pods, and the survivors inherited
// the load and were killed in turn — 11 restarts in one load test.
app.get('/healthz', (req, res) => res.json({ status: 'ok' }));

// Readiness does check the dependency: an api that cannot reach Postgres has
// nothing to serve. Failing this removes the pod from the Service; it does not
// kill it.
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
app.get('/api/subscriptions', async (req, res, next) => {
  try {
    const { status } = req.query;
    // Parameterised, not interpolated. The value comes from a query string, and
    // string-building a WHERE clause from user input is how SQL injection
    // happens — no less so because this one looks like a harmless enum.
    const { rows } = status
      ? await pool.query(
          'SELECT * FROM subscriptions WHERE status = $1 ORDER BY next_renewal',
          [status])
      : await pool.query('SELECT * FROM subscriptions ORDER BY next_renewal');
    res.json(rows);
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
    // Column names come from the allow-list above, never from the request, so
    // only the values are ever parameterised — a field name cannot be injected
    // because an unknown one is dropped before it reaches here.
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
//
// The expensive read, and the one every page load wants — so it is the one
// that is cached. Redis is here for this rather than for sessions: a React
// client and a JSON API have no server-side session to keep.
app.get('/api/summary', async (req, res, next) => {
  try {
    const cached = await cache.get('summary');
    if (cached) return res.set('X-Cache', 'HIT').json(cached);

    const [totals, upcoming, unused] = await Promise.all([
      // Yearly costs are divided to a monthly figure so the two are comparable;
      // comparing a yearly subscription's sticker price against a monthly one
      // is how these apps end up lying about the total.
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
      // The trimming list: paid for, and untouched for two months.
      pool.query(`
        SELECT id, name, cost, currency, last_used FROM subscriptions
        WHERE status = 'active'
          AND (last_used IS NULL OR last_used < CURRENT_DATE - INTERVAL '60 days')
        ORDER BY cost DESC`),
    ]);

    const payload = {
      monthly_total: Number(totals.rows[0].monthly),
      yearly_total: Number(totals.rows[0].yearly),
      active_count: Number(totals.rows[0].count),
      upcoming_renewals: upcoming.rows,
      unused: unused.rows,
      // What cancelling everything on the unused list would save each month.
      potential_monthly_saving: unused.rows.reduce((n, r) => n + Number(r.cost), 0),
    };

    await cache.set('summary', payload);
    res.set('X-Cache', 'MISS').json(payload);
  } catch (err) { next(err); }
});

// ── errors ────────────────────────────────────────────────────────────────
app.use((req, res) => res.status(404).json({ error: 'not found' }));

app.use((err, req, res, next) => {
  // Logged in full, returned in outline. A database error can carry the query
  // and the schema, and neither belongs in an HTTP response.
  console.error('request failed:', err.message);
  res.status(500).json({ error: 'internal error' });
});

module.exports = { app, migrate };
