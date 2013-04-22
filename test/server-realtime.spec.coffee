qServer = require('../lib/q-server')

fs = require('fs')
supertest = require('supertest')
wrench = require('wrench')
socketClient  = require('sockjs-client')

{expect} = require('./testing')

describe 'Q Server Realtime', ->

    socket = null
    
    listener = null
    request = null

    Q_OPTIONS =
        path: "#{__dirname}/store"

    beforeEach ()->
        wrench.rmdirSyncRecursive Q_OPTIONS.path if fs.existsSync Q_OPTIONS.path

    describe 'on startup', ->

        it 'opens a sockjs server to connect to', (done)->
            socket = connect()
            socket.on 'connection', ()->
                done()
        
    describe 'when a client subscribed to packages channel', ->

        beforeEach (done)->
            socket = connect()
            socket.on 'connection', ()->
                packageSubscription = 
                    command: 'subscribe'
                    channel: 'packages'

                socket.write JSON.stringify(packageSubscription)
                done()
    
        it 'sends a confirmation', (done)->
            waitForMessages 1, (message)->
                expect(message.type).to.equal('subscribed')
                done()

        it 'send the list of currently known packages', (done)->
            waitForMessages 2, (messages)->
                expect(messages[1].type).to.equal('package-list')
                messages[1].packages.should.be.empty
                done()

        # cannot implement until i actual have a second version of a package
        it 'it gets a list whenever a new package is added', (done)->
            waitForMessages 3, (messages)->
                packagesA = messages[1].packages
                packagesB = messages[2].packages
                
                packagesA.should.be.empty
                packagesB.should.have.length(1)

                done()
    
            uploadPackage()

    describe 'when the server already has packages installed', ->

        beforeEach (done)->
            uploadPackage ()->
                socket = connect() 
                done()

        it 'includes any previously installed packages', (done)->

            waitForMessages 2, (messages)->
                packages = messages[1].packages
                packages.should.have.length(1)
                packages.should.deep.equal [ {name:'my-package',version:'0.1.0'} ]
                done()

        it 'is possible to ask for a fresh list at any time', (done)->
            waitForMessages 3, (messages)->
                packagesA = messages[1].packages
                packagesB = messages[2].packages
                packagesA.should.deep.equal packagesB
                done()

            listPackages = command: 'list-packages'
            socket.write JSON.stringify(listPackages)

    uploadPackage = (cb) ->
        request.post('/packages')
            .attach('b74ed98ef279f61233bad0d4b34c1488f8525f27.pkg', "#{__dirname}/packages/valid.zip")
            .expect(202)
            .end ()->cb() if cb

    waitForMessages = (expectedNumberOfMessages,cb)->
        messages = []
        socket.on 'data', (data)->
            #console.log data
            return if messages is null

            #console.log data
            message = JSON.parse(data)
            
            messages.push(message)
                
            if expectedNumberOfMessages == 1
                messages = null
                cb(message)
            else
                if(expectedNumberOfMessages == messages.length)
                    messagesReceived = messages
                    messages = null
                    cb(messagesReceived)

    connect = (cb)->
        
        connections = []
        server = createWebServer()
        listener = server.listen()

        return socketClient.create("https://127.0.0.1:#{server.address().port}/live/packages")

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

        # Setup a request object to talk to server via http requests        
        request = supertest(app)

        return server
