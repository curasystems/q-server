Q = require('quartermaster')
QServer = require('../lib/q-server')

fs = require('fs')
wrench = require('wrench')

webserver = require('../lib/webserver')

describe.only 'Q client against Server', ->

  q = null
  s = null
  w = null
  TEST_OPTIONS=
    path: "#{__dirname}/client-test-store"
    verifyRequiresSignature: false
    verbose: true    
  
  before (done)->
    
    webOptions = 
      key: fs.readFileSync(__dirname + '/key.pem')
      cert: fs.readFileSync(__dirname + '/cert.pem')
      q: TEST_OPTIONS

    w = webserver.create(webOptions)
    w.server.listen 8965, ->
      console.log "Listening on #{w.server.address().address}:#{w.server.address().port}"
      done()

    q = new Q()

  # after (done)->
  #   @timeout 30000

  #   setTimeout ()->
  #     w.server.close()
  #     done()
  #   ,20000
  
  describe 'access packages', ->
        
    it 'should be able to \'list\' all available versions of a package', (done) ->

      q.listPackageVersions 'my-package', 'https://localhost:8965', {rejectUnauthorized:false}, (err,versions)->
        return done(err) if err

        versions.should.have.length(2)
        done()

    it 'should be able to \'list\' only matching versions of a package', (done) ->

      q.listPackageVersions 'my-package@0.1.x', 'https://localhost:8965', {rejectUnauthorized:false}, (err,versions)->
        return done(err) if err

        versions.should.have.length(1)
        done()

    it 'should be able to retrieve information on a specific package version', (done)->
    
      q.getPackageInfo 'my-package@0.1.0', 'https://localhost:8965', {rejectUnauthorized:false}, (err,info)->
        return done(err) if err

        info.name.should.equal('my-package')
        info.version.should.equal('0.1.0')
        done()

    it 'should be able to retrieve information on a the latest package version', (done)->
    
      q.getPackageInfo 'my-package', 'https://localhost:8965', {rejectUnauthorized:false}, (err,info)->
        return done(err) if err

        info.name.should.equal('my-package')
        info.version.should.equal('0.2.0')
        done()