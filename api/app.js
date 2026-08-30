var express = require('express');
var app = express();
var uuid = require('node-uuid');

var { Pool } = require('pg');
const conString = {
    user: process.env.DBUSER,
    database: process.env.DB,
    password: process.env.DBPASS,
    host: process.env.DBHOST,
    port: process.env.DBPORT,
    ssl: process.env.DBSSL === 'true' ? { rejectUnauthorized: false } : false
};

// One pool for the process, created once.
//
// It used to be created inside the handler and ended at the end of it, which
// meant every request opened a TCP connection, completed a TLS handshake, ran
// one query, and threw the connection away. A pool that is created per request
// is not a pool.
//
// The cost was measurable rather than theoretical: a single api replica stopped
// keeping up at ~15 requests/second while using 0.18 of a core — it was not
// short of CPU, it was spending the time on connection setup. `SELECT now()`
// does not take 77ms; a TLS handshake does.
const pool = new Pool({
  ...conString,
  // Bounded deliberately. Postgres allocates a backend process per connection,
  // so an unbounded pool multiplied by every replica is how a database gets
  // knocked over by its own application during a scale-up.
  max: 10,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 5000,
});

// A pool emits errors for idle clients dropped by the server or the network.
// Unhandled, they are thrown as uncaught exceptions and take the process down —
// which under load looks like a crash loop rather than a lost connection.
pool.on('error', (err) => {
  console.error('postgres pool error:', err.message);
});

// Routes
app.get('/api/status', function(req, res) {
  pool.query('SELECT now() as time', (err, result) => {
    if (err) {
      console.error('query failed:', err.message);
      return res.status(500).send({ error: 'database query failed' });
    }
    // request_uuid was always expected — web's template renders it and
    // node-uuid was imported for it — but nothing ever set it, so the page has
    // been showing an empty box since the beginning.
    res.status(200).send(result.rows.map((row) => ({
      ...row,
      request_uuid: uuid.v4(),
    })));
  });
});

// Liveness: is this process alive? Nothing else.
//
// The probes used to point at /api/status, which reaches Postgres — so a slow
// database made Kubernetes kill healthy api pods, and the pods that remained
// took the load and were killed in turn. Web and api pods restarted 9 and 11
// times during a load test for this reason.
app.get('/healthz', function(req, res) {
  res.status(200).send({ status: 'ok' });
});

// Readiness: should this pod receive traffic? Here the database does matter —
// an api that cannot reach Postgres has nothing to serve — but failing this
// only removes the pod from the Service, it does not kill it.
app.get('/readyz', function(req, res) {
  pool.query('SELECT 1', (err) => {
    if (err) return res.status(503).send({ status: 'database unreachable' });
    res.status(200).send({ status: 'ok' });
  });
});

// catch 404 and forward to error handler
app.use(function(req, res, next) {
  var err = new Error('Not Found');
  err.status = 404;
  next(err);
});

// error handlers

// development error handler
// will print stacktrace
if (app.get('env') === 'development') {
  app.use(function(err, req, res, next) {
    res.status(err.status || 500);
    res.json({
      message: err.message,
      error: err
    });
  });
}

// production error handler
// no stacktraces leaked to user
app.use(function(err, req, res, next) {
  res.status(err.status || 500);
  res.json({
    message: err.message,
    error: {}
  });
});


module.exports = app;
