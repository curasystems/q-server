Q = require('quartermaster')
fs = require('fs')
qStore = require('q-fs-store')

_ = require('underscore')
async = require('async')
path = require('path')
mkdirp = require('mkdirp')
semver = require('semver')
moment = require('moment')

bs = require('bsdiff-bin')
temp = require('temp')

module.exports.InvalidAppError = class InvalidAppError extends Error
    constructor: (@message)->super(@message)

module.exports.InvalidIOError = class InvalidIOError extends Error
    constructor: (@message)->super(@message)

module.exports = (options)->
    if not options 
        throw Error("Options required")

    return new QServer(options)

class QServer

    constructor: (@options)->
        @store = new qStore(path:@options.path)

        q_options = {}
        q_options.verifyRequiresSignature = @options.verifyRequiresSignature
        q_options.keys = @options.users
        q_options.store = @store

        @q = new Q( q_options )
        @subscribers = []

    listen: (app, io)->
        if not app.get
            throw new InvalidAppError('must be able to register get route on app')
        
        if io and not io.on
            throw new InvalidIOError('second parameter is no socket emitter instance')
        
        @_configureRoutes(app)
        @_configureSockets(io) if io
        
    _configureSockets: (io)->
        io.on 'connection', (subscriber)=>
            @_subscribe(subscriber)

    _subscribe: (subscriber)->
        @subscribers.push(subscriber)
        
        @_confirmSubscriptionToSubscriber(subscriber)            
        @_sendPackageListToSubscriber(subscriber)
        
        subscriber.on 'data', (data)=>
            message = JSON.parse(data)
            if message.command == 'list-packages'
                @_sendPackageListToSubscriber(subscriber)

        subscriber.on 'close', =>
            @subscribers.splice( @subscribers.indexOf(subscriber), 1 )

    _publishNewPackageListToSubscribers: ()->
        @_sendPackageListToSubscriber(s) for s in @subscribers

    _confirmSubscriptionToSubscriber: (subscriber)->
        confirmation = 
            type: 'subscribed'

        subscriber.write(JSON.stringify(confirmation))

    _sendPackageListToSubscriber: (subscriber)->

        if @options.verbose 
            console.log "Sending package list to subscriber", subscriber

        @store.listAll (err,list)=>
            if err
                #res.send(500,err)
            else
                listEvent = 
                    type: 'package-list'
                    packages: list
                subscriber.write(JSON.stringify(listEvent))


    _configureRoutes: (app)->
        
        app.get '/packages/:name/:version/download', (req,res)=>
            @_downloadPackage(req,res)
        app.get '/packages/:name', (req,res)=>
            @_findPackageVersions(req,res)
        app.get '/packages', (req,res)=>
            @_getPackages(req,res)
        app.post '/packages', (req,res)=>
            @_postPackages(req,res)
        app.post '/packages/:name/:version/patch', (req,res)=>
            @_postPatch(req,res)

    _downloadPackage: (req,res)->
        if not req.params.name
            res.send(400, 'module name required')
        else if not semver.valid(req.params.version)
            res.send(400, 'version must be valid fully specified semver')
        else
            packageIdentifier = req.params.name+'@'+req.params.version
            @store.readPackage packageIdentifier, (err,packageStream)->
                if err
                    res.send(404)
                else
                    res.type('application/octet-stream')
                    res.setHeader('Content-Disposition', "filename=#{packageIdentifier}.pkg")
                    packageStream.pipe(res)


    _findPackageVersions: (req,res)->
        filter = req.query.version ? '>=0'
        
        @store.findMatching req.params.name, filter, (err,versions)->
            if err
                res.send(500,err)
            else if versions.length == 0
                res.send(404)
            else
                res.json(200,versions)

    _getPackages: (req,res)->
        console.log req.url
        if req.query.mode == 'raw'
            @store.listRaw (err,list)->
                if err
                    res.send(500,err)
                else
                    res.json(200,list)
        else
            @store.listAll (err,list)->
                if err
                    res.send(500,err)
                else
                    groupedByName = _.groupBy list, 'name'
                    res.json(200,groupedByName)

    _postPatch: (req,res)->        

        attachments = @_getAttachments(req)
        return res.send(400) if attachments.length != 1
        
        patchPath = attachments[0].path

        packageName = req.params.name
        packageVersion = req.params.version
        packageIdentifier = "#{packageName}@#{packageVersion}"

        @store.getPackageStoragePath packageIdentifier, (err,packagePath)=>
            return res.send(404) if err or not fs.existsSync(packagePath)
                
            patchedPath = temp.path(suffix: '.pkg')
            bs.patch packagePath, patchedPath, patchPath, (err)=>
                return res.send(500) if err
            
                fs.exists patchedPath, (exists)=>
                    return res.send(400) if not exists
                
                    @_importPackage patchedPath, (err)=>
                        return res.send(400) if err
                        return res.send(200)    

    _postPackages: (req,res)->
        
        attachments = @_getAttachments(req)
        return res.send(400) if attachments.length == 0

        packages = (a.path for a in attachments)

        if @options.verbose 
            console.log "package import requested", req

        @_importPackages(packages,req,res)

    _importPackages: (packages,req,res)->

        processingErrors = []
        validationResults = []

        for p in packages
            @_verifyPackage p, (err,result)=>
                processingErrors.push(err) if err
                validationResults.push(result)

                if validationResults.length == packages.length
                    @_afterAllPackagesVerified(req,res,packages,validationResults)
                    
    _afterAllPackagesVerified: (req, res, packages, validationResults)->
        
        allPackagesVerified = _.every validationResults, (r)->r?.verified
        return res.send(400) if not allPackagesVerified
            
        async.eachSeries packages, (p,cb)=>
                @_importPackage(p,cb)
            , (err)=>
                return res.send(500) if err
                res.send 202

                @_publishNewPackageListToSubscribers()

    _verifyPackage: (packagePath, callback)->
        @q.verifyPackage packagePath, callback

    _importPackage: (packagePath, callback)->

        @q.listPackageContent packagePath, (err,listing)=>
            return callback(err) if err

            packageInfo=
                uid:listing.uid
                name:listing.name
                version:listing.version
                description:listing.description
                signedBy:listing.signedBy
                signature:listing.signature
                imported: moment.utc().format()

            @store.writePackage packageInfo, (err,storageStream)=>
                fs.createReadStream(packagePath).pipe(storageStream)
                storageStream.on 'close', ->
                    if @options.verbose 
                        console.log "imported package", packageInfo

                    callback(null)

    _getStoragePathForPackage: (listing)->
        storageFolder = listing.uid.substr(0,2)
        name = listing.uid + '.pkg'
        storagePath = path.join(@options.store, storageFolder, name)

    _getAttachments: (req)->(attachment for own name,attachment of req.files)

