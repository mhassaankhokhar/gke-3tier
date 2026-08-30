# api

Subscription tracker API. Express, Postgres via CloudNativePG, Redis for the
summary aggregation.

```
GET    /api/subscriptions[?status=active]
GET    /api/subscriptions/:id
POST   /api/subscriptions
PATCH  /api/subscriptions/:id
DELETE /api/subscriptions/:id
GET    /api/summary            totals, upcoming renewals, unused for 60+ days
GET    /healthz                liveness — process only
GET    /readyz                 readiness — checks Postgres
```

The schema is applied at startup from `schema.sql` and is idempotent, so
replicas racing to start cannot conflict.

Redis is a cache, not a dependency: every path through `cache.js` fails open, so
a Redis outage makes this slower rather than broken.
