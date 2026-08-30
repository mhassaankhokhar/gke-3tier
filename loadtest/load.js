// Load profiles for gke-3tier.
//
// Two scenarios, because they answer different questions and the first version
// of this file conflated them:
//
//   capacity  how many requests per second the system can actually serve
//   traffic   how it behaves under a plausible number of real users
//
// Run one at a time:
//   k6 run -e SCENARIO=capacity loadtest/load.js
//   k6 run -e SCENARIO=traffic  loadtest/load.js
//
// Run it from INSIDE the cluster (see loadtest/k6-job.yaml). From a laptop in
// Pakistan against us-central1, three round trips of ~250ms dominate every
// measurement: a page that takes 3ms in-cluster measured 803ms externally, and
// the number you would be reading is your own internet connection.
//
// Known ceilings, because knowing them separates a result from a misreading:
// both HPAs stop at 6 replicas and the spot pool's autoscaler stops at 3 nodes.
// Saturation there is the configuration working.
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';

const BASE_URL = __ENV.BASE_URL || 'http://web.app.svc.cluster.local';
const SCENARIO = __ENV.SCENARIO || 'traffic';

const appErrors = new Rate('app_errors');
const sessionViews = new Trend('session_views');

const scenarios = {
  // Open model: iterations start at a fixed rate whether or not the previous
  // ones finished. That is the difference that matters — a closed model with
  // think time can only ever produce the rate you dialled in, so it measures
  // behaviour at that rate and can never find the ceiling. Under an arrival
  // rate the queue builds when the system falls behind, and latency shows it.
  capacity: {
    executor: 'ramping-arrival-rate',
    startRate: 10,
    timeUnit: '1s',
    preAllocatedVUs: 50,
    // Allowed to grow, because iterations pile up once the system stops
    // keeping pace; without headroom k6 reports dropped iterations instead of
    // the latency that is the actual finding.
    maxVUs: 500,
    stages: [
      { target: 50, duration: '1m' },
      { target: 150, duration: '2m' },
      { target: 300, duration: '2m' },
      { target: 500, duration: '2m' },
      { target: 0, duration: '1m' },
    ],
  },

  // Closed model with think time: a fixed population of users, each pausing
  // between requests. This is the realistic shape, and the one to watch the
  // HPA against — but it measures behaviour, not capacity.
  traffic: {
    executor: 'ramping-vus',
    startVUs: 0,
    stages: [
      { target: 20, duration: '1m' },
      { target: 50, duration: '2m' },
      { target: 50, duration: '3m' },
      { target: 100, duration: '1m' },
      { target: 100, duration: '2m' },
      { target: 0, duration: '1m' },
    ],
  },
};

export const options = {
  scenarios: { [SCENARIO]: scenarios[SCENARIO] },

  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<1500'],
    app_errors: ['rate<0.01'],
  },

  // true, not false. k6 resets each VU's cookie jar at the start of every
  // iteration by default, so without this each request arrives with no cookie
  // and creates a fresh session — the counter never rises above 1 and Redis
  // fills with one-request sessions. The first run of this test had it set to
  // `false` with a comment claiming the opposite.
  noCookiesReset: true,
};

export default function () {
  const res = http.get(`${BASE_URL}/`, { tags: { name: 'home' } });

  const ok = check(res, {
    'status is 200': (r) => r.status === 200,
    'rendered the page': (r) => r.body && r.body.includes('3tier App'),
    // The session store is otherwise invisible: the page still renders if Redis
    // is unreachable, so a green run without this check says nothing about it.
    'session is served': (r) => r.body && r.body.includes('Session views:'),
  });

  appErrors.add(!ok);

  if (ok) {
    const m = res.body.match(/Session views: (\d+)/);
    if (m) sessionViews.add(parseInt(m[1], 10));
  }

  // Think time in the closed model only. Under an arrival rate the executor
  // controls pacing, and sleeping here would just hold VUs open for no reason.
  if (SCENARIO === 'traffic') sleep(1);
}

export function handleSummary(data) {
  const m = data.metrics;
  const line = (k, v) => `  ${k.padEnd(22)} ${v}`;
  const sv = m.session_views ? m.session_views.values : null;
  return {
    stdout: [
      '',
      `gke-3tier load test — ${SCENARIO}`,
      line('requests', m.http_reqs.values.count),
      line('req/s', m.http_reqs.values.rate.toFixed(1)),
      line('failed', `${(m.http_req_failed.values.rate * 100).toFixed(2)}%`),
      line('p95 latency', `${m.http_req_duration.values['p(95)'].toFixed(0)} ms`),
      line('p99 latency', `${(m.http_req_duration.values['p(99)'] || 0).toFixed(0)} ms`),
      line('max latency', `${m.http_req_duration.values.max.toFixed(0)} ms`),
      // Rising max proves cookies survive iterations, i.e. the session store is
      // being reused rather than recreated on every request.
      line('session views max', sv ? sv.max : 'n/a'),
      '',
    ].join('\n'),
  };
}
