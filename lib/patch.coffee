path = require('path')
child_process = require('child_process')

module.exports = (originalFile, targetFile, patchFile, cb)->
    bspatchPath = path.join( "#{__dirname}", '..', 'bin', process.platform, 'bspatch' )

    if process.platform is 'win32'
        bspatchPath += '.exe'

    options = timeout: 60 * 1000
    args = [originalFile,targetFile,patchFile]
    
    child_process.execFile bspatchPath, args, options, cb