// Load profiles for the subscription tracker.
//
// Two scenarios, because they answer different questions:
//   capacity  how many requests per second this can serve before latency breaks
//   traffic   how it behaves under a plausible number of real users
//
//   SCENARIO=capacity k6 run loadtest/load.js
//
// Run in-cluster (loadtest/k6-job.yaml). From a laptop in Pakistan against
// us-central1, three round trips of ~250ms dominate everything: the same page
// measured 803ms externally and 3ms from a pod.
//
// The request mix is weighted the way this app is actually used: mostly
// reading, occasionally writing. A pure-GET test would miss the write path
// entirely and make the cache look better than it is, since /api/summary is
// cached for 60s and every write invalidates it.
import http from 'k6/http';
import { check } from 'k6';
import { Rate, Counter } from 'k6/metrics';

const BASE = __ENV.BASE_URL || 'http://web.app.svc.cluster.local';
const SCENARIO = __ENV.SCENARIO || 'capacity';

const errors = new Rate('app_errors');
const cacheHits = new Rate('summary_cache_hits');
const writes = new Counter('writes');

const scenarios = {
  // Open model: iterations start at a fixed rate whether or not earlier ones
  // finished. A closed model with think time can only ever produce the rate you
  // dialled in, so it can never find the ceiling — under an arrival rate the
  // queue builds when the system falls behind, and latency shows it.
  capacity: {
    executor: 'ramping-arrival-rate',
    startRate: 20, timeUnit: '1s',
    preAllocatedVUs: 50, maxVUs: 400,
    stages: [
      { target: 40,  duration: '40s' },
      { target: 80,  duration: '40s' },
      { target: 140, duration: '40s' },
      { target: 220, duration: '40s' },
      { target: 320, duration: '40s' },
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
  // 70 / 20 / 10. Weighted rather than round-robin so the mix holds at any
  // rate — a rotation would tie the write rate to the number of VUs.
  const roll = Math.random();

  if (roll < 0.70) {
    // The expensive read, and the cached one. Tracking the hit rate matters:
    // if writes invalidate it faster than the TTL refills it, the cache stops
    // being a cache and every request pays for three aggregate queries.
    const res = http.get(`${BASE}/api/summary`, { tags: { name: 'summary' } });
    const ok = check(res, {
      'summary 200': (r) => r.status === 200,
      'summary has totals': (r) => r.json('monthly_total') !== undefined,
    });
    errors.add(!ok);
    cacheHits.add(res.headers['X-Cache'] === 'HIT');

  } else if (roll < 0.90) {
    // A page, not the table. The endpoint is paginated now; asking for
    // everything was what made this response grow as the test wrote rows, so
    // the test was steadily changing what it measured.
    const res = http.get(`${BASE}/api/subscriptions?status=active&limit=50`, { tags: { name: 'list' } });
    errors.add(!check(res, {
      'list 200': (r) => r.status === 200,
      'list is a page': (r) => Array.isArray(r.json('data')),
    }));

  } else {
    // A write, which also invalidates the summary cache — so the read path
    // above is measured against a cache under real churn rather than one that
    // is never disturbed.
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
      line('p50 latency', `${d['p(50)'].toFixed(0)} ms`),
      line('p95 latency', `${d['p(95)'].toFixed(0)} ms`),
      line('p99 latency', `${d['p(99)'].toFixed(0)} ms`),
      line('max latency', `${d.max.toFixed(0)} ms`),
      line('writes', m.writes ? m.writes.values.count : 0),
      line('summary cache hits', m.summary_cache_hits
        ? `${(m.summary_cache_hits.values.rate * 100).toFixed(1)}%` : 'n/a'),
      '',
    ].join('\n'),
  };
}
