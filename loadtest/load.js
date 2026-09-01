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
    // 2000, not 400. An arrival-rate executor is only an open model while it
    // has VUs to spare; run out and it silently becomes a closed one, where the
    // system under test decides the load instead of the test deciding it. Three
    // runs logged "Insufficient VUs, reached 400 active VUs" and all three
    // reported ~116 req/s against a 320/s target — the generator's number, not
    // the application's.
    //
    // The size comes from Little's Law rather than a guess: at the measured
    // peak, L = 324 requests were in flight toward api at once (read directly
    // from envoy_cluster_upstream_rq_active, not derived). A VU is busy for the
    // whole of one request, so the pool has to exceed the concurrency the target
    // rate implies, with room for the generator's own overhead.
    preAllocatedVUs: 200, maxVUs: 2000,
    // 2 minutes per stage, not 40 seconds.
    //
    // Prometheus scrapes envoy every 10s (17-monitoring.yaml), so a rate window
    // needs ~40s to hold enough samples to be stable. At 40s stages that window
    // spanned three of them and every per-stage number came out smeared — the
    // curve's shape was readable and its values were not. A 2-minute stage lets
    // the window sit entirely inside one load level.
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
      // avg first, and not as decoration: Little's Law (L = lambda x W) needs the
      // mean, and p50 is not it. This run had a p50 of 68ms against a mean an
      // order of magnitude higher, because the tail carries the weight — using
      // the median would understate concurrency by that same factor.
      line('mean latency', `${d.avg.toFixed(0)} ms`),
      line('p50 latency', `${d['p(50)'].toFixed(0)} ms`),
      line('p95 latency', `${d['p(95)'].toFixed(0)} ms`),
      line('p99 latency', `${d['p(99)'].toFixed(0)} ms`),
      line('max latency', `${d.max.toFixed(0)} ms`),
      line('writes', m.writes ? m.writes.values.count : 0),
      line('summary cache hits', m.summary_cache_hits
        ? `${(m.summary_cache_hits.values.rate * 100).toFixed(1)}%` : 'n/a'),
      '',
      // Little's Law, computed here so the run states its own concurrency
      // instead of leaving it to be reconstructed afterwards. If `concurrency`
      // approaches `VUs max` the generator was the limit and the throughput
      // figure describes k6, not the application.
      line('concurrency L=lambda*W', (m.http_reqs.values.rate * (d.avg / 1000)).toFixed(0)),
      line('VUs max', m.vus_max ? m.vus_max.values.max : 'n/a'),
      '',
    ].join('\n'),
  };
}
