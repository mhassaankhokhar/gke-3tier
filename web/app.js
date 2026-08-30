var express = require('express');
var path = require('path');
var favicon = require('serve-favicon');
var logger = require('morgan');
var cookieParser = require('cookie-parser');
var bodyParser = require('body-parser');
var session = require('express-session');
var { RedisStore } = require('connect-redis');
var { createClient } = require('redis');

var routes = require('./routes/index');

var app = express();

// view engine setup
app.set('views', path.join(__dirname, 'views'));
app.set('view engine', 'jade');

// uncomment after placing your favicon in /public
//app.use(favicon(path.join(__dirname, 'public', 'favicon.ico')));
app.use(logger('dev'));
app.use(bodyParser.json());
app.use(bodyParser.urlencoded({ extended: false }));
app.use(cookieParser());
app.use(express.static(path.join(__dirname, 'public')));

// Sessions live in Redis, not in this process.
//
// The web tier runs several replicas on preemptible nodes, so in-memory
// sessions would be wrong twice over: consecutive requests from one browser
// land on different replicas, and a reclaimed node takes its replica's
// sessions with it. Both look like users being randomly logged out.
//
// The client reconnects on its own; a Redis restart therefore costs the
// sessions it held, not the web tier's health.
var redisClient = createClient({ url: process.env.REDIS_URL });
redisClient.on('error', function (err) {
    console.error('redis:', err.message);
});
redisClient.connect().catch(function (err) {
    console.error('redis connect failed:', err.message);
});

// TLS is terminated in front of this process, never by it, so without this
// Express sees plain http on every request. With cookie.secure that means the
// session cookie is silently never set — sessions that appear to work in a
// local test and do nothing at all once deployed.
app.set('trust proxy', 1);

app.use(session({
    store: new RedisStore({ client: redisClient, prefix: 'web:sess:' }),
    secret: process.env.SESSION_SECRET,
    // Cookie is rewritten only when the session changes; the store's TTL is
    // refreshed separately, so an idle-but-active browser is not logged out.
    resave: false,
    // Do not persist a session for a visitor who has not caused one. Without
    // this, every crawler request writes a key to Redis.
    saveUninitialized: false,
    cookie: {
        httpOnly: true,
        // 'auto', not true: express-session then marks the cookie Secure when
        // the connection actually is, which it determines from
        // X-Forwarded-Proto because of the trust proxy setting above. A hard
        // `true` also means the cookie is never set when running this locally
        // over http, so the session silently does nothing.
        secure: 'auto',
        sameSite: 'lax',
        maxAge: 1000 * 60 * 60,
    },
}));

// Liveness: is this process alive? Nothing else.
//
// The probes used to point at `/`, which renders the page — calling the api,
// which queries Postgres. Under load that took 2-5 seconds while the probe's
// default timeout is 1, so Kubernetes killed pods that were healthy and merely
// busy. The remaining pods took their share of the load and were killed in
// turn: web restarted 9 and 11 times during a load test before anyone looked
// at why.
//
// Declared before the router so it stays cheap and cannot be affected by
// session handling or anything downstream.
app.get('/healthz', function (req, res) {
    res.status(200).json({ status: 'ok' });
});

// Readiness: should this pod receive traffic? The session store matters here —
// without Redis every request would create a new session — but failing this
// only removes the pod from the Service rather than killing it.
app.get('/readyz', function (req, res) {
    if (redisClient.isReady) return res.status(200).json({ status: 'ok' });
    res.status(503).json({ status: 'redis unavailable' });
});

app.use('/', routes);

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
        res.render('error', {
            message: err.message,
            error: err
        });
    });
}

// production error handler
// no stacktraces leaked to user
app.use(function(err, req, res, next) {
    res.status(err.status || 500);
    res.render('error', {
        message: err.message,
        error: {}
    });
});


module.exports = app;