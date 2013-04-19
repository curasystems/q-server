// Support coffee script and source maps for stack traces
require('coffee-script');
require('source-map-support').install();

var express = require('express');
var app = express();
app.use(express.bodyParser())
app.use(express.methodOverride())

var q = require('./lib/q-server')
var s = q({path: __dirname+'/packages'})
s.listen(app);
app.listen(8080);

