import { useEffect, useState, useCallback } from 'react';
import * as api from './api';
import SubscriptionForm from './SubscriptionForm.jsx';
import Summary from './Summary.jsx';

const money = (n, currency = 'USD') =>
  new Intl.NumberFormat(undefined, { style: 'currency', currency }).format(Number(n));

export default function App() {
  const [subs, setSubs] = useState([]);
  const [total, setTotal] = useState(0);
  const [offset, setOffset] = useState(0);
  const [summary, setSummary] = useState(null);
  const [error, setError] = useState(null);
  const [loading, setLoading] = useState(true);
  const [editing, setEditing] = useState(null);

  // Both are refetched together after every write. The summary is aggregated
  // server-side and cached, so re-deriving it in the browser would drift from
  // what the API reports the moment the two disagree.
  const PAGE = 50;

  const load = useCallback(async () => {
    try {
      const [s, sum] = await Promise.all([
        api.listSubscriptions({ limit: PAGE, offset }),
        api.getSummary(),
      ]);
      setSubs(s.data);
      setTotal(s.total);
      setSummary(sum);
      setError(null);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  }, [offset]);

  useEffect(() => { load(); }, [load]);

  const save = async (data) => {
    if (editing) await api.updateSubscription(editing.id, data);
    else await api.createSubscription(data);
    setEditing(null);
    await load();
  };

  const remove = async (id) => {
    await api.deleteSubscription(id);
    await load();
  };

  // Cancelling rather than deleting, because the two mean different things:
  // a cancelled subscription is history worth keeping, and deleting it loses
  // the record of what was once being paid for.
  const cancel = async (sub) => {
    await api.updateSubscription(sub.id, { status: 'cancelled' });
    await load();
  };

  return (
    <div className="app">
      <header>
        <h1>Subscriptions</h1>
        <p className="sub">What you pay for, and what you could stop paying for.</p>
      </header>

      {error && <div className="error">{error}</div>}
      {loading ? <p className="muted">Loading…</p> : (
        <>
          <Summary data={summary} money={money} />

          <section className="panel">
            <h2>{editing ? `Edit ${editing.name}` : 'Add a subscription'}</h2>
            <SubscriptionForm
              key={editing ? editing.id : 'new'}
              initial={editing}
              onSave={save}
              onCancel={editing ? () => setEditing(null) : null}
            />
          </section>

          <section className="panel">
            <h2>All subscriptions <span className="muted">
              ({total}{total > PAGE && ` — showing ${offset + 1}–${Math.min(offset + PAGE, total)}`})
            </span></h2>
            {subs.length === 0 ? (
              <p className="muted">Nothing tracked yet.</p>
            ) : (
              <table>
                <thead>
                  <tr>
                    <th>Name</th><th>Cost</th><th>Cycle</th>
                    <th>Renews</th><th>Last used</th><th>Status</th><th />
                  </tr>
                </thead>
                <tbody>
                  {subs.map((s) => (
                    <tr key={s.id} className={s.status === 'cancelled' ? 'cancelled' : ''}>
                      <td>{s.name}{s.category && <span className="tag">{s.category}</span>}</td>
                      <td>{money(s.cost, s.currency)}</td>
                      <td>{s.billing_cycle}</td>
                      <td>{s.next_renewal?.slice(0, 10)}</td>
                      <td>{s.last_used ? s.last_used.slice(0, 10) : <span className="muted">never</span>}</td>
                      <td>{s.status}</td>
                      <td className="actions">
                        <button onClick={() => setEditing(s)}>Edit</button>
                        {s.status === 'active' && <button onClick={() => cancel(s)}>Cancel</button>}
                        <button className="danger" onClick={() => remove(s.id)}>Delete</button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
            {total > PAGE && (
              <div className="actions">
                <button disabled={offset === 0} onClick={() => setOffset(Math.max(offset - PAGE, 0))}>
                  Previous
                </button>
                <button disabled={offset + PAGE >= total} onClick={() => setOffset(offset + PAGE)}>
                  Next
                </button>
              </div>
            )}
          </section>
        </>
      )}
    </div>
  );
}
