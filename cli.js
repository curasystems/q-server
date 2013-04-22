// Support coffee script and source maps for stack traces
require('coffee-script');
require('source-map-support').install();

var fs = require('fs')

var express = require('express');
var app = express();

app.use(express.bodyParser())
app.use(express.methodOverride())


var options = {
      key: fs.readFileSync(__dirname + '/test/key.pem'),
      cert: fs.readFileSync(__dirname + '/test/cert.pem')
      }


//  SPDY
var spdy = require('spdy')
var server = spdy.createServer(options, app)

// STANDARD HTTPS
//var server = require('https').createServer(options, app)

// STANDARD HTTP
//var server = require('http').createServer(app)

// CONFIGURE WITH SOCKJS
var sockjs  = require('sockjs').createServer()
sockjs.installHandlers( server , {prefix:'/live/packages'} )

// START Q SERVER
var q = require('./lib/q-server')
var qServer = q({path: __dirname+'/packages'})

qServer.listen(app, sockjs);

//var io = require('socket.io').listen(server);
//io.set('log level', 10);
//io.set('transports', ['websocket']);
//
server.listen(8963);

