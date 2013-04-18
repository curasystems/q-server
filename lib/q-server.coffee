module.exports.InvalidAppError = class InvalidAppError extends Error
    constructor: (@message)->super(@message)

module.exports = ()->
    return new QServer

class QServer
    listen: (app)->
        if not app.get
            throw new InvalidAppError('must be able to register get route on app')