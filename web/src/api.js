// Relative paths: nginx proxies /api in-cluster, so no API URL in the bundle
// and one build runs in every environment.
const json = async (res) => {
  if (res.status === 204) return null;
  const body = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(body.error || (body.errors || []).join(', ') || res.statusText);
  return body;
};

// Paginated: returns { data, total, limit, offset }.
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
