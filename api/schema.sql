-- Applied by the api on startup.
--
-- A migration tool would be the right answer for a system that outlives one
-- schema; this is one table, and CREATE TABLE IF NOT EXISTS is honest about
-- that. When a second migration is needed, that is the moment to add one —
-- not before.
CREATE TABLE IF NOT EXISTS subscriptions (
  id            SERIAL PRIMARY KEY,
  name          TEXT        NOT NULL,
  cost          NUMERIC(10,2) NOT NULL CHECK (cost >= 0),
  currency      TEXT        NOT NULL DEFAULT 'USD',
  -- Only two cycles, enforced in the database rather than only in the API.
  -- A constraint here holds for anything that writes to the table, including a
  -- future service and a person with psql.
  billing_cycle TEXT        NOT NULL CHECK (billing_cycle IN ('monthly','yearly')),
  next_renewal  DATE        NOT NULL,
  category      TEXT,
  status        TEXT        NOT NULL DEFAULT 'active' CHECK (status IN ('active','cancelled')),
  -- The column the whole point of the app hangs on: a subscription that costs
  -- money and has not been used is the one to cancel.
  last_used     DATE,
  notes         TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- The list is filtered by status on nearly every request, and sorted by
-- renewal date. Without this the table is scanned each time — invisible at ten
-- rows, and the first thing to hurt under the load test.
CREATE INDEX IF NOT EXISTS subscriptions_status_renewal_idx
  ON subscriptions (status, next_renewal);
