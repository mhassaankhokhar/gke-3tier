-- Applied by the api on startup. One table, so no migration tool yet.
CREATE TABLE IF NOT EXISTS subscriptions (
  id            SERIAL PRIMARY KEY,
  name          TEXT        NOT NULL,
  cost          NUMERIC(10,2) NOT NULL CHECK (cost >= 0),
  currency      TEXT        NOT NULL DEFAULT 'USD',
  -- Enforced in the database so it holds for every writer.
  billing_cycle TEXT        NOT NULL CHECK (billing_cycle IN ('monthly','yearly')),
  next_renewal  DATE        NOT NULL,
  category      TEXT,
  status        TEXT        NOT NULL DEFAULT 'active' CHECK (status IN ('active','cancelled')),
  -- Unused + paid = the subscription to cancel.
  last_used     DATE,
  notes         TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Status filter + renewal sort on nearly every request.
CREATE INDEX IF NOT EXISTS subscriptions_status_renewal_idx
  ON subscriptions (status, next_renewal);
