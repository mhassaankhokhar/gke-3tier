// Every call goes to a relative path.
//
// nginx proxies /api to the api Service inside the cluster, so the browser
// never learns an API address and there is no CORS to configure. It also means
// the same build runs in any environment — an API URL baked in at build time
// would make the image environment-specific, which defeats promoting one
// artifact through environments.
const json = async (res) => {
  if (res.status === 204) return null;
  const body = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(body.error || (body.errors || []).join(', ') || res.statusText);
  return body;
};

// Returns { data, total, limit, offset }. The endpoint is paginated because an
// unbounded list grew with the table — 363KB at 1,275 rows — so the caller has
// to carry the offset rather than assume it received everything.
export const listSubscriptions = ({ status, limit = 50, offset = 0 } = {}) => {
  const q = new URLSearchParams({ limit, offset });
  if (status) q.set('status', status);
  return fetch(`/api/subscriptions?${q}`).then(json);
};

export const getSummary = () => fetch('/api/summary').then(json);

export const createSubscription = (data) =>
  fetch('/api/subscriptions', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data),
  }).then(json);

export const updateSubscription = (id, data) =>
  fetch(`/api/subscriptions/${id}`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data),
  }).then(json);

export const deleteSubscription = (id) =>
  fetch(`/api/subscriptions/${id}`, { method: 'DELETE' }).then(json);
