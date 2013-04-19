Q = require('q')
qStore = require('q-fs-store')

async = require('async')
path = require('path')
_ = require('underscore')
mkdirp = require('mkdirp')

module.exports.InvalidAppError = class InvalidAppError extends Error
    constructor: (@message)->super(@message)

module.exports = (options)->
    if not options 
        throw Error("Options required")

    return new QServer(options)

class QServer

    constructor: (@options)->
        @store = new qStore(path:@options.path)
        @q = new Q(store:@store)

    listen: (app)->
        if not app.get
            throw new InvalidAppError('must be able to register get route on app')
        @_configureRoutes(app)

    _configureRoutes: (app)->

        app.get '/packages', (req,res)=>@_getPackages(req,res)
        app.get '/packages/raw', (req,res)=>@_getRawPackages(req,res)
        app.post '/packages', (req,res)=>@_postPackages(req,res)

    _getPackages: (req,res)->

        @store.listAll (err,list)->
            if err
                res.end(500,err)
            else
                groupedByName = _.groupBy list, 'name'
                res.json(200,groupedByName)
       

    _getRawPackages: (req,res)->
        @store.listRaw (err,list)->
            if err
                res.end(500,err)
            else
                res.json(200,list)

    _postPackages: (req,res)->
        
        attachments = @_getAttachments(req)
        return res.send(400) if attachments.length == 0

        processingErrors = []
        validationResults = []

        for a in attachments
            @_verifyPackage a, (err,result)=>
                processingErrors.push(err) if err
                validationResults.push(result)

                if validationResults.length == attachments.length
                    @_afterAllPackagesVerified(req,res,attachments,validationResults)
                    
    _afterAllPackagesVerified: (req, res, attachments, validationResults)->
        
        allPackagesValid = _.every validationResults, (r)->r?.valid
        return res.send(400) if not allPackagesValid
            
        async.eachSeries attachments, (a,cb)=>
                @_importPackage(a,cb)
            , (err)->
                return res.send(500) if err
                res.send 202

    _verifyPackage: (uploadedPackage, callback)->
        @q.verifyPackage uploadedPackage.path, callback

    _importPackage: (uploadedPackage, callback)->

        @q.listPackageContent uploadedPackage.path, (err,listing)=>
            return callback(err) if err

            packageInfo=
                uid:listing.uid
                name:listing.name
                version:listing.version
                description:listing.description

            @store.writePackage packageInfo, (err,storageStream)=>
                fs.createReadStream(uploadedPackage.path).pipe(storageStream)
                
                storageStream.on 'close', ->
                    callback(null)

    _getStoragePathForPackage: (listing)->
        storageFolder = listing.uid.substr(0,2)
        name = listing.uid + '.pkg'
        storagePath = path.join(@options.store, storageFolder, name)

    _getAttachments: (req)->(attachment for own name,attachment of req.files)

