fs = require('fs')
webserver = require('./webserver')

home = "#{process.cwd()}"

Q_OPTIONS =
    path: "#{home}/store"

SOCKJS_OPTIONS = 
    log: (severity,message)->console.log(message) if severity is 'error'

options = 
      key: fs.readFileSync( home + '/key.pem')
      cert: fs.readFileSync( home + '/cert.pem')
      q: Q_OPTIONS
      sockjs: SOCKJS_OPTIONS

w = webserver.create(options)
w.server.listen(8963);

console.log "Listining on #{w.server.address().address}:#{w.server.address().port}"
