// Load profiles for the subscription tracker.
//   capacity  max requests/s before latency breaks (SCENARIO=capacity)
//   traffic   behaviour under a plausible number of users
// Run in-cluster (loadtest/k6-job.yaml); from outside, network latency dominates.
// Read-heavy mix with writes, so the summary cache is measured under invalidation.
import http from 'k6/http';
import { check } from 'k6';
import { Rate, Counter } from 'k6/metrics';

const BASE = __ENV.BASE_URL || 'http://web.app.svc.cluster.local';
const SCENARIO = __ENV.SCENARIO || 'capacity';

const errors = new Rate('app_errors');
const cacheHits = new Rate('summary_cache_hits');
const writes = new Counter('writes');

const scenarios = {
  // Open model (arrival rate), so a falling-behind system shows up as latency.
  capacity: {
    executor: 'ramping-arrival-rate',
    startRate: 20, timeUnit: '1s',
    // Sized from Little's Law against the measured peak concurrency (~324 in
    // flight). Too few VUs silently turns this into a closed model and the result
    // measures k6, not the app.
    preAllocatedVUs: 200, maxVUs: 2000,
    // 2-minute stages so the Prometheus rate window (10s scrapes) fits inside one level.
    stages: [
      { target: 40,  duration: '2m' },
      { target: 80,  duration: '2m' },
      { target: 140, duration: '2m' },
      { target: 220, duration: '2m' },
      { target: 320, duration: '2m' },
    ],
  },
  traffic: {
    executor: 'ramping-vus',
    startVUs: 0,
    stages: [
      { target: 30, duration: '1m' },
      { target: 80, duration: '2m' },
      { target: 80, duration: '2m' },
      { target: 0,  duration: '1m' },
    ],
  },
};

export const options = {
  scenarios: { [SCENARIO]: scenarios[SCENARIO] },
  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<1000'],
    app_errors: ['rate<0.01'],
  },
  summaryTrendStats: ['avg', 'p(50)', 'p(95)', 'p(99)', 'max'],
};

const CYCLES = ['monthly', 'yearly'];

export default function () {
  // 70/20/10, random so the mix holds at any rate.
  const roll = Math.random();

  if (roll < 0.70) {
    // Cached read; writes invalidate it, so watch the hit rate.
    const res = http.get(`${BASE}/api/summary`, { tags: { name: 'summary' } });
    const ok = check(res, {
      'summary 200': (r) => r.status === 200,
      'summary has totals': (r) => r.json('monthly_total') !== undefined,
    });
    errors.add(!ok);
    cacheHits.add(res.headers['X-Cache'] === 'HIT');

  } else if (roll < 0.90) {
    // One page, not the whole table.
    const res = http.get(`${BASE}/api/subscriptions?status=active&limit=50`, { tags: { name: 'list' } });
    errors.add(!check(res, {
      'list 200': (r) => r.status === 200,
      'list is a page': (r) => Array.isArray(r.json('data')),
    }));

  } else {
    // Writes also invalidate the summary cache.
    const res = http.post(`${BASE}/api/subscriptions`, JSON.stringify({
      name: `loadtest-${__VU}-${__ITER}`,
      cost: Math.round(Math.random() * 5000) / 100,
      billing_cycle: CYCLES[Math.floor(Math.random() * CYCLES.length)],
      next_renewal: '2026-12-01',
      category: 'loadtest',
    }), { headers: { 'Content-Type': 'application/json' }, tags: { name: 'create' } });
    const ok = check(res, { 'create 201': (r) => r.status === 201 });
    errors.add(!ok);
    if (ok) writes.add(1);
  }
}

export function handleSummary(data) {
  const m = data.metrics;
  const line = (k, v) => `  ${k.padEnd(22)} ${v}`;
  const d = m.http_req_duration.values;
  return {
    stdout: [
      '',
      `subscription tracker — ${SCENARIO}`,
      line('requests', m.http_reqs.values.count),
      line('req/s', m.http_reqs.values.rate.toFixed(1)),
      line('failed', `${(m.http_req_failed.values.rate * 100).toFixed(2)}%`),
      // Mean, not p50: Little's Law (L = λW) needs the mean.
      line('mean latency', `${d.avg.toFixed(0)} ms`),
      line('p50 latency', `${d['p(50)'].toFixed(0)} ms`),
      line('p95 latency', `${d['p(95)'].toFixed(0)} ms`),
      line('p99 latency', `${d['p(99)'].toFixed(0)} ms`),
      line('max latency', `${d.max.toFixed(0)} ms`),
      line('writes', m.writes ? m.writes.values.count : 0),
      line('summary cache hits', m.summary_cache_hits
        ? `${(m.summary_cache_hits.values.rate * 100).toFixed(1)}%` : 'n/a'),
      '',
      // If this approaches VUs max, the generator was the limit, not the app.
      line('concurrency L=lambda*W', (m.http_reqs.values.rate * (d.avg / 1000)).toFixed(0)),
      line('VUs max', m.vus_max ? m.vus_max.values.max : 'n/a'),
      '',
    ].join('\n'),
  };
}
