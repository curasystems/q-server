
module.exports.create = (options)->

      # SPDY-specific options
      #windowSize: 1024 # Server's window size
      #debug: yes

    # *** CREATE/CONFIGURE EXPRESS SERVER
    express = require('express')

    app = express()
    app.use(express.bodyParser())
    app.use(express.methodOverride())

    # *** CREATE HTTP/S/SPDY SERVER and configure with express

    #  SPDY
    server = require('spdy').createServer(options, app)

    # STANDARD HTTPS
    #server = require('https').createServer(options, app)

    # STANDARD HTTP
    #server = require('http').createServer(app)

    # *** SETUP LIVE CONNECTIONS
    
    # CONFIGURE WITH SOCK-JS (dont log to console.log)
    sockjs  = require('sockjs').createServer(options.sockjs)
    sockjs.installHandlers( server , {prefix:'/live/packages'} )

    # *** CONFIGURE THE Q Server with express and sockets
    qServer = require('./q-server')
    s = new qServer(options.q)
    s.listen(app,sockjs)

    return server:server,app:app