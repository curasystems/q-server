qServer = require('../lib/q-server')

fs = require('fs')
supertest = require('supertest')
wrench = require('wrench')
socketClient  = require('sockjs-client')

{expect} = require('./testing')

describe.only 'Q Server Realtime', ->

    socket = null
    
    listener = null
    connections = null

    Q_OPTIONS =
        path: "#{__dirname}/store"

    beforeEach ()->
        wrench.rmdirSyncRecursive Q_OPTIONS.path if fs.existsSync Q_OPTIONS.path
        socket = connect()

    afterEach ()->
        disconnect(socket)

    it.only 'opens a socket.io server to connect to', (done)->

        socket.on 'connection', ()->
            done()
        
    it 'allow to subscribe to the list of packages', (done)->
        socket.on 'connection', ()->
            packageSubscription = 
                command: 'subscribe'
                channel: 'packages'

            socket.write JSON.stringify(packageSubscription)

        socket.on 'data', (message)->
            console.log message
            done()

        socket.on 'error', (error)->
            console.log "ERR", error

    connect = (cb)->
        
        connections = []
        server = createWebServer()
        listener = server.listen()

        return socketClient.create("https://127.0.0.1:#{server.address().port}/live/packages")

    disconnect = (socket)->
        socket.close()
        shutdownWebServer()

    createWebServer = ()->
        
        # since we are using a self-signed certificate
        # make sure we dont fail connecting to it
        require('https').globalAgent.options.rejectUnauthorized = false;
                

        options = 
          key: fs.readFileSync(__dirname + '/key.pem')
          cert: fs.readFileSync(__dirname + '/cert.pem')
          # SPDY-specific options
          #windowSize: 1024 # Server's window size
          #debug: yes

        # *** CREATE HTTP/S/SPDY SERVER

        #  SPDY
        server = require('spdy').createServer(options, app)

        # STANDARD HTTPS
        #server = require('https').createServer(options, app)

        # STANDARD HTTP
        #server = require('http').createServer(app)

        # *** SETUP LIVE CONNECTIONS
        
        # CONFIGURE WITH SOCK-JS (dont log to console.log)
        SOCKJS_OPTIONS = 
            log: (severity,message)->console.log(message) if severity is 'error'

        sockjs  = require('sockjs').createServer(SOCKJS_OPTIONS)
        sockjs.installHandlers( server , {prefix:'/live/packages'} )

        # *** CREATE/CONFIGURE EXPRESS SERVER
        
        express = require('express')

        app = express()
        app.use(express.bodyParser())
        app.use(express.methodOverride())


        # *** CONFIGURE THE Q Server with express and sockets
        s = new qServer(Q_OPTIONS)
        s.listen(app,sockjs)

        #
        # Keep a list of all active connections for graceful 
        # shutdown after test
        #    
        connections = []
        server.on 'connection', (c)->
            connections.push(c)
            c.on 'close', ()->
                connections.splice(connections.indexOf(c), 1)

    

        return server

    shutdownWebServer = ()->
        for connection in connections
            connection.destroy()