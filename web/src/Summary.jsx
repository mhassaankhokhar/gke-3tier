// The reason the app exists: not the list, but what it costs and what could go.
export default function Summary({ data, money }) {
  if (!data) return null;
  const { monthly_total, yearly_total, active_count, unused, upcoming_renewals,
          potential_monthly_saving } = data;

  return (
    <section className="summary">
      <div className="stats">
        <Stat label="Monthly" value={money(monthly_total)} />
        <Stat label="Yearly" value={money(yearly_total)} />
        <Stat label="Active" value={active_count} />
        {/* Shown even at zero: an empty saving is a real answer, and hiding it
            makes the number look absent rather than settled. */}
        <Stat label="Could save / month" value={money(potential_monthly_saving)}
              highlight={potential_monthly_saving > 0} />
      </div>

      {unused.length > 0 && (
        <div className="panel warn">
          <h2>Not used in 60 days</h2>
          <p className="muted">Paid for, and apparently untouched.</p>
          <ul>
            {unused.map((s) => (
              <li key={s.id}>
                <strong>{s.name}</strong> — {money(s.cost, s.currency)}
                {' '}<span className="muted">
                  {s.last_used ? `last used ${s.last_used.slice(0, 10)}` : 'never recorded as used'}
                </span>
              </li>
            ))}
          </ul>
        </div>
      )}

      {upcoming_renewals.length > 0 && (
        <div className="panel">
          <h2>Renewing within 30 days</h2>
          <ul>
            {upcoming_renewals.map((s) => (
              <li key={s.id}>
                <strong>{s.name}</strong> — {money(s.cost, s.currency)}
                {' '}<span className="muted">on {s.next_renewal.slice(0, 10)}</span>
              </li>
            ))}
          </ul>
        </div>
      )}
    </section>
  );
}

function Stat({ label, value, highlight }) {
  return (
    <div className={`stat${highlight ? ' highlight' : ''}`}>
      <div className="stat-value">{value}</div>
      <div className="stat-label">{label}</div>
    </div>
  );
}
