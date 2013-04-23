fs = require('fs')
path = require('path')
webserver = require('./webserver')

home = "#{process.cwd()}"

Q_OPTIONS =
    path: "#{home}/store"

SOCKJS_OPTIONS = 
    log: (severity,message)->console.log(message) if severity is 'error'

loadUsersSync = ()->
  userKeys = {}
  keysPath = home + '/keys'
  for file in fs.readdirSync home + '/keys'
      keyFilePath = path.join(keysPath,file)
      userName = path.basename(file)
      userKeys[userName] = fs.readFileSync(keyFilePath)              
  return userKeys

options = 
      key: fs.readFileSync( home + '/key.pem')
      cert: fs.readFileSync( home + '/cert.pem')
      q: Q_OPTIONS
      sockjs: SOCKJS_OPTIONS
      users: loadUsersSync()

w = webserver.create(options)
w.server.listen(8963);

console.log "Listening on #{w.server.address().address}:#{w.server.address().port}"


