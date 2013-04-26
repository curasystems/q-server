q = require('../lib/q-server')

fs = require('fs')
supertest = require('supertest')
express = require('express')
wrench = require('wrench')

{expect} = require('./testing')

describe 'Q Server', ->

    s = null
    TEST_OPTIONS=
        path: "#{__dirname}/store"
        verifyRequiresSignature: true
        users:
            'user_a': fs.readFileSync("#{__dirname}/keys/user_a.pub", encoding:'utf8')

    beforeEach ()->
        wrench.rmdirSyncRecursive TEST_OPTIONS.path if fs.existsSync TEST_OPTIONS.path
        s = q(TEST_OPTIONS)
        
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

        it 'can get an empty list of packages as json', (done)->
            request.get('/packages')
                .expect('Content-Type', /json/)
                .expect(200)
                .end (err,res)->
                    res.body.should.be.empty
                    done(err)

        describe 'uploading packages', ->

            it 'accepts new packages by uploading them', (done)->
                request.post('/packages')
                    .attach('0.1.0.pkg', "#{__dirname}/packages/valid-0.1.0.zip")
                    .expect(202,done)

            it 'posts without packages are not accepted', (done)->
                request.post('/packages')
                    .expect(400,done)

            it 'invalid packages are not accepted', (done)->
                request.post('/packages')
                    .attach('0.1.0.pkg', "#{__dirname}/packages/manipulated.zip")
                    .expect(400,done)
   
            it 'invalid package signatures are not accepted', (done)->
                request.post('/packages')
                    .attach('0.1.0.pkg', "#{__dirname}/packages/manipulatedSignature.zip")
                    .expect(400,done)

        describe 'uploading packages as diffs', ->

            it 'by posting a bsdiff', (done)->
                request.post('/packages')
                    .attach('0.1.0.pkg', "#{__dirname}/packages/valid-0.1.0.zip")
                    .expect(202)
                    .end (err,req)->
                        done(err) if err

                        request.post('/packages/my-package/0.1.0/patch')
                            .attach('test.patch', "#{__dirname}/packages/diff-0.1.0-0.2.0.patch")
                            .expect(200,done)

            it 'returns 404 if source package does not exist ', (done)->
                request.post('/packages/my-package/0.1.0/patch')
                    .attach('valid-0.1.0-0.2.0.patch', "#{__dirname}/packages/diff-0.1.0-0.2.0.patch")
                    .expect(404,done)

        describe 'once packages are uploaded', ->

            beforeEach (done)->

                request.post('/packages')
                    .attach('first.pkg', "#{__dirname}/packages/valid-0.1.0.zip")
                    .attach('second.pkg', "#{__dirname}/packages/valid-0.2.0.zip")
                    .expect(202,done)

            it 'can get list of packages as json', (done)->
                request.get('/packages')
                    .expect('Content-Type', /json/)
                    .expect(200)
                    .end (err,res)->
                        res.body['my-package'][0].should.deep.equal( name:'my-package',version:'0.1.0')
                        res.body['my-package'][1].should.deep.equal( name:'my-package',version:'0.2.0')
                        done(err)

            it 'is possible to list all package uids again', (done)->
                request.get('/packages?mode=raw')
                    .expect('Content-Type', /json/)
                    .expect(200)
                    .end (err,res)->
                        expect(err).to.be.null
                        res.body.should.contain('898a0ad816c517f8c888fa00c1a84dce73fed656') 
                        done()

            it 'is possible to list all versions of a specific package', (done)->
                request.get('/packages/my-package')
                    .expect('Content-Type', /json/)
                    .expect(200)
                    .end (err,res)->
                        expect(err).to.be.null
                        res.body.should.contain('0.1.0')
                        res.body.should.contain('0.2.0')
                        done(err)

            it 'is possible to list all versions of a specific package', (done)->
                request.get('/packages/unknown-package')
                    .expect(404,done)

            it 'is possible to look-up the latest version matching a range for a specific package', (done)->
                request.get('/packages/my-package?version=~0.1')
                    .expect(200)
                    .end (err,res)->
                        res.body.should.contain '0.1.0'
                        done(err)

            it 'can return package info for any version', (done)->
                request.get('/packages/my-package/0.2.0')
                    .expect(200)
                    .end (err,res)->
                        res.body.uid.should.equal 'a74eda650a0d01c47211367f8af0885120ce1a3d'
                        res.body.name.should.equal 'my-package'
                        res.body.version.should.equal '0.2.0'
                        done(err)

            it 'can return package info for the highest version', (done)->
                request.get('/packages/my-package/latest')
                    .expect(200)
                    .end (err,res)->
                        res.body.uid.should.equal 'a74eda650a0d01c47211367f8af0885120ce1a3d'
                        res.body.name.should.equal 'my-package'
                        res.body.version.should.equal '0.2.0'
                        done(err)


            it 'returns 404 when no matching for a range is found', (done)->
                request.get('/packages/my-package?version=>0.2.0')
                    .expect(404,done)

            it 'is possible download a package by name and exact version', (done)->
                request.get('/packages/my-package/0.1.0/download')
                    .expect('Content-Type', 'application/octet-stream')
                    .expect(200)
                    .end (err,res)->
                        done(err)

            it 'is '