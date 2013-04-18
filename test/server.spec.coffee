q = require('../lib/q-server')

request = require('supertest')
express = require('express')

{expect} = require('./testing')

describe 'starting it', ->

    s = null

    beforeEach ()->
        s = q()

    it 'can be built', ->
        expect(s).to.not.be.undefined
        expect(s).to.not.be.null

    it 'can hook up to an express application', ->
        app = express()
        s.listen(app)

    it 'can only hook up when the application allows to register routes', ->
        app = {}
        expect( ()->s.listen(app) ).to.throw( q.InvalidAppError, /invalid/ )


