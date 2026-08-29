var express = require('express');
var os = require('os');
var router = express.Router();
var request = require('request');


var api_url = process.env.API_HOST + '/api/status';

/* GET home page. */
router.get('/', function(req, res, next) {
    // The point of the session store, made visible: this counter is held in
    // Redis, so it keeps climbing as requests land on different replicas and
    // survives any one of them being preempted. The hostname below is the pod
    // that served the request — watch it change while the count does not reset.
    req.session.views = (req.session.views || 0) + 1;

    request({
            method: 'GET',
            url: api_url,
            json: true
        },
        function(error, response, body) {
            if (error || response.statusCode !== 200) {
                return res.status(500).send('error running request to ' + api_url);
            } else {
                res.render('index', {
                    title: '3tier App',
                    request_uuid: body[0].request_uuid,
                    time: body[0].time,
                    views: req.session.views,
                    served_by: os.hostname()
                });
            }
        }
    );
});

module.exports = router;