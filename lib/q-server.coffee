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

        if @options.verbose
            console.log "allowed publishing users:"
            for own user of @options.users
                console.log ' > ', user

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
        
        app.get '/packages/:name/latest/download', (req,res)=>
            @_downloadPackage(req,res)
        app.get '/packages/:name/:version/download', (req,res)=>
            @_downloadPackage(req,res)
        app.get '/packages/:name/:version', (req,res)=>
            @_getPackage(req,res)
        app.get '/packages/:name', (req,res)=>
            @_findPackageVersions(req,res)
        app.get '/packages', (req,res)=>
            @_getPackages(req,res)
        app.post '/packages/:name/:version/patch', (req,res)=>
            @_postPatch(req,res)
        app.post '/packages', (req,res)=>
            @_postPackages(req,res)

    _downloadPackage: (req,res)->
        if not req.params.name
            res.send(400, 'module name required')
        else
            packageIdentifier = req.params.name    
            patchFrom = req.query?.patchFrom

            if req.params.version
              packageIdentifier += '@'+req.params.version
              @_initiateDownload(packageIdentifier,patchFrom, res)
            else
              @store.listVersions packageIdentifier, (err,versions)=>
                version = @store.highestVersionOf(versions)
                packageIdentifier += '@'+version
                @_initiateDownload(packageIdentifier,patchFrom,res)
        

    _initiateDownload: (packageIdentifier, patchFrom, res)->

      @store.getPackageStoragePath packageIdentifier, (err, packagePath)=>
          if err or not fs.existsSync(packagePath)
              return res.send(404)

          if patchFrom
              @_returnPatch(packageIdentifier,packagePath,patchFrom,res)
          else
              @_returnPackage(packageIdentifier,packagePath,res)
    
    _returnPatch: (identifier, packagePath, patchFromUid, res)->
        @store.getPackageStoragePath patchFromUid, (err, patchFromPackagePath)=>
            if err or not fs.existsSync(patchFromPackagePath)
                return @_returnPackage(identifier, packagePath, res) 

            patchPath = temp.path(suffix:'.patch')

            bs.diff patchFromPackagePath, packagePath, patchPath, (err)=>
                return @_returnPackage(identifier, packagePath, res) if err

                #res.type('application/octet-stream')
                res.setHeader('Content-Disposition', "filename=#{identifier}.#{patchFromUid}.patch")                
                res.sendfile(patchPath)
                #packageStream = fs.createReadStream(patchPath)
                #packageStream.pipe(res)

    _returnPackage: (identifier, packagePath, res)->

        #res.type('application/octet-stream')
        res.setHeader('Content-Disposition', "filename=#{identifier}.pkg")
        res.sendfile(packagePath)
        
        #packageStream = fs.createReadStream(packagePath)
        #packageStream.pipe(res)

    _findPackageVersions: (req,res)->

        filter = req.query.version ? '>=0'
        
        @store.findMatching req.params.name, filter, (err,versions)->

            if err
                return res.send(500,err)
            else if not versions or versions.length == 0
                return res.send(404)

            res.json(200,versions)

    _getPackage: (req, res)->
        packageName = req.params.name
        version = req.params.version

        if version == 'latest'
            @store.listVersions packageName, (err,versions)=>
                version = @store.highestVersionOf(versions)
                @_getPackageInfo packageName, version, req, res
        else
            if not semver.valid(version)
                res.send(400)
            else
                @_getPackageInfo packageName, version, req, res

    _getPackageInfo: (name, version, req, res)=>
        @store.getInfo name, version, (err,info)=>
            if err
                return res.send(500)
            if not info 
                return res.send(404)

            return res.json(info)

    _getPackages: (req,res)->
       
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
            console.log "package import requested..."

        @_importPackages(packages,req,res)

    _importPackages: (packages,req,res)->

        processingErrors = []
        verificationResults = []

        for p in packages
            @_verifyPackage p, (err,result)=>
                processingErrors.push(err) if err
                verificationResults.push(result)

                if verificationResults.length == packages.length
                    @_afterAllPackagesVerified(req,res,packages,verificationResults)
                    
    _afterAllPackagesVerified: (req, res, packages, verificationResults)->
        
        for r in verificationResults
            for f in r.files when not f.verified
                console.log "invalid ",f
            for err in r.errors 
                console.log "error ", err

        allPackagesVerified = _.every verificationResults, (r)->r.verified
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
                storageStream.on 'close', =>
                    if @options.verbose 
                        console.log "imported package", packageInfo

                    callback(null)

    _getStoragePathForPackage: (listing)->
        storageFolder = listing.uid.substr(0,2)
        name = listing.uid + '.pkg'
        storagePath = path.join(@options.store, storageFolder, name)

    _getAttachments: (req)->(attachment for own name,attachment of req.files)

