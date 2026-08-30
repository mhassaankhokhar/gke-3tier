import { useState } from 'react';

const blank = {
  name: '', cost: '', currency: 'USD', billing_cycle: 'monthly',
  next_renewal: '', category: '', last_used: '', notes: '',
};

export default function SubscriptionForm({ initial, onSave, onCancel }) {
  const [form, setForm] = useState(() => {
    if (!initial) return blank;
    // Date inputs need YYYY-MM-DD; the API returns full timestamps.
    return {
      ...blank, ...initial,
      next_renewal: initial.next_renewal?.slice(0, 10) || '',
      last_used: initial.last_used?.slice(0, 10) || '',
    };
  });
  const [error, setError] = useState(null);
  const [saving, setSaving] = useState(false);

  const set = (k) => (e) => setForm({ ...form, [k]: e.target.value });

  const submit = async (e) => {
    e.preventDefault();
    setSaving(true);
    setError(null);
    try {
      await onSave({
        ...form,
        cost: Number(form.cost),
        // Empty strings are not empty dates. Sent as '' the API's date parse
        // fails and the request is rejected for a field the user left blank on
        // purpose.
        last_used: form.last_used || null,
        category: form.category || null,
        notes: form.notes || null,
      });
      if (!initial) setForm(blank);
    } catch (err) {
      setError(err.message);
    } finally {
      setSaving(false);
    }
  };

  return (
    <form onSubmit={submit}>
      {error && <div className="error">{error}</div>}
      <div className="grid">
        <label>Name<input required value={form.name} onChange={set('name')} placeholder="Netflix" /></label>
        <label>Cost<input required type="number" step="0.01" min="0" value={form.cost} onChange={set('cost')} placeholder="15.99" /></label>
        <label>Currency<input value={form.currency} onChange={set('currency')} maxLength={3} /></label>
        <label>Cycle
          <select value={form.billing_cycle} onChange={set('billing_cycle')}>
            <option value="monthly">monthly</option>
            <option value="yearly">yearly</option>
          </select>
        </label>
        <label>Next renewal<input required type="date" value={form.next_renewal} onChange={set('next_renewal')} /></label>
        <label>Category<input value={form.category} onChange={set('category')} placeholder="streaming" /></label>
        <label>Last used<input type="date" value={form.last_used} onChange={set('last_used')} /></label>
        <label>Notes<input value={form.notes} onChange={set('notes')} /></label>
      </div>
      <div className="actions">
        <button type="submit" disabled={saving}>{saving ? 'Saving…' : initial ? 'Save changes' : 'Add'}</button>
        {onCancel && <button type="button" onClick={onCancel}>Cancel</button>}
      </div>
    </form>
  );
}
