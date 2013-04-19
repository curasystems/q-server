q = require('../lib/q-server')

fs = require('fs')
supertest = require('supertest')
express = require('express')
wrench = require('wrench')

{expect} = require('./testing')

describe 'starting it', ->

    s = null
    TEST_OPTIONS=
        path: "#{__dirname}/store"

    beforeEach ()->
        s = q(TEST_OPTIONS)
        wrench.rmdirSyncRecursive TEST_OPTIONS.path if fs.existsSync TEST_OPTIONS.path

    it 'can be built', ->
        expect(s).to.not.be.undefined
        expect(s).to.not.be.null

    it 'can only hook up when the application allows to register routes', ->
        app = {}
        expect( ()->s.listen(app) ).to.throw( q.InvalidAppError, /route/ )

    describe 'with express', ->

        app = null
        request = null

        beforeEach ->
            app = express()
            app.use(express.bodyParser())
            app.use(express.methodOverride())

            s.listen(app)

            request = supertest(app)


        describe 'uploading packages', ->

            it 'accepts new packages by uploading them', (done)->
                request.post('/packages')
                    .attach('b74ed98ef279f61233bad0d4b34c1488f8525f27.pkg', "#{__dirname}/packages/valid.zip")
                    .expect(202,done)

            it 'posts without packages are not accepted', (done)->
                request.post('/packages')
                    .expect(400,done)

            it 'invalid packages are not accepted', (done)->
                request.post('/packages')
                    .attach('b74ed98ef279f61233bad0d4b34c1488f8525f27.pkg', "#{__dirname}/packages/manipulated.zip")
                    .expect(400,done)

        describe 'once packages are uploaded', ->

            beforeEach (done)->
                request.post('/packages')
                    .attach('b74ed98ef279f61233bad0d4b34c1488f8525f27.pkg', "#{__dirname}/packages/valid.zip")
                    .end(done)

            it 'can get list of packages as json', (done)->
                request.get('/packages')
                    .expect('Content-Type', /json/)
                    .expect(200)
                    .end (err,res)->
                        res.body['my-package'][0].should.deep.equal( name:'my-package',version:'0.1.0')
                        done()

            it 'is possible to list all package uids again', (done)->
                request.get('/packages?mode=raw')
                    .expect('Content-Type', /json/)
                    .expect(200)
                    .end (err,res)->
                        expect(err).to.be.null
                        res.body.should.contain('b74ed98ef279f61233bad0d4b34c1488f8525f27') 
                        done()

            it 'is possible to list all versions of a specific package', (done)->
                request.get('/packages/my-package')
                    .expect('Content-Type', /json/)
                    .expect(200)
                    .end (err,res)->
                        expect(err).to.be.null
                        res.body.should.contain('0.1.0')
                        done()

            it 'is possible to list all versions of a specific package', (done)->
                request.get('/packages/unknown-package')
                    .expect(404,done)