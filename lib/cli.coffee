fs = require('fs')
path = require('path')
webserver = require('./webserver')

home = "#{process.cwd()}"

main = ()->

  Q_OPTIONS =
      path: "#{home}/store"
      users: loadUsersSync()
      verbose: true



  SOCKJS_OPTIONS = 
      log: (severity,message)->console.log(message) if severity is 'error'


  options = 
        key: fs.readFileSync( home + '/key.pem')
        cert: fs.readFileSync( home + '/cert.pem')
        q: Q_OPTIONS
        sockjs: SOCKJS_OPTIONS
        
  w = webserver.create(options)
  w.server.listen(8963);

  console.log "Listening on #{w.server.address().address}:#{w.server.address().port}"


loadUsersSync = ()->
  userKeys = {}
  keysPath = path.join(home,'keys')
  for file in fs.readdirSync(keysPath)
      keyFilePath = path.join(keysPath,file)
      userName = path.basename(file)
      userKeys[userName] = fs.readFileSync(keyFilePath, encoding:'utf8')   

  return userKeys


main()