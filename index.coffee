fs  = require 'fs'
os  = require 'os'
CPUS_COUNT  = os.cpus().length

module.exports = class ClusterMaster
  @run: (options) ->
    new @(options).init().spawn()

  @runMaster: (options) ->
    return unless require('cluster').isMaster
    @run options

  constructor: (@options = {}) ->
    @cluster = @options.cluster ? require 'cluster'
    @options.workers ?= CPUS_COUNT
    @options.reloadTimeout ?= 5000

  spawn: (options = {}) ->
    console.log 'Cluster: start forking.'
    while @workersCount < @options.workers
      worker = @cluster.fork()
      worker.reanimate = options.reanimate ? true
    @

  Object.defineProperty @::, 'workersCount', get: ->
    Object.getOwnPropertyNames(@cluster.workers).length

  sliceWorkers: ->
    workers = {}
    workers[id] = worker for id, worker of @cluster.workers
    workers

  closeAll: (callback) ->
    workers = @sliceWorkers()
    for id, worker of workers
      do (worker) =>
        worker.reanimate = false
        worker.on 'disconnect', =>
          worker.kill()
          callback?() unless @workersCount
        worker.disconnect()
    @

  killAll: ->
    for id, worker of @cluster.workers
      worker.reanimate = false
      worker.kill()
    @

  reloadAll: (callback) ->
    worker_ids = []
    worker_ids.push id for id of @cluster.workers
    do reload_next = =>
      worker_id = worker_ids.shift()
      unless worker_id?
        console.log "Reload: all done"
        return callback?()
      unless worker = @cluster.workers[worker_id]
        console.log "Reload: missing worker ##{worker_id}"
        return reload_next()
      console.log "Reload: forking new worker."
      new_worker = @cluster.fork().on 'listening', ->
        console.log "Reload: successful fork; disconnecting old worker ##{worker_id}."
        clearTimeout timer_fork_fail
        new_worker.reanimate = worker.reanimate
        reload_next()
        worker.reanimate = false
        worker.on 'disconnect', =>
          console.log "Reload: old worker ##{worker_id} disconnected, killing."
          worker.kill()
        worker.disconnect()
      timer_fork_fail = setTimeout ->
        console.log "Reload: fork failed, killing it."
        new_worker.kill?()
        callback? new Error 'Fork failed'
      , @options.reloadTimeout
    @

  writePid: ->
    return @ unless @options.pidfile?
    fs.writeFileSync @options.pidfile, "#{process.pid}\n"
    @

  clearPid: ->
    return @ unless @options.pidfile?
    fs.unlinkSync @options.pidfile
    @

  init: ->
    @writePid()

    @cluster.on 'exit', (deadWorker, code, signal) =>
      console.log "Cluster: Worker #{deadWorker.process.pid} died. Reanimate: #{deadWorker.reanimate}."
      return unless deadWorker.reanimate
      worker = @cluster.fork()
      worker.reanimate = deadWorker.reanimate
      console.log "Cluster: Worker #{deadWorker.process.pid} reanimated as #{worker.process.pid}."

    process.on 'close', =>
      console.log 'Cluster: exiting, closing workers...'
      @closeAll => @clearPid()

    process.on 'SIGHUP', =>
      @reloadAll()

    @
