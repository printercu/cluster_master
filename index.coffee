fs  = require 'fs'
os  = require 'os'
CPUS_COUNT  = os.cpus().length

module.exports = class ClusterMaster
  @run: (options) ->
    new @(options).init().spawn()

  @runMaster: (options) ->
    return unless require('cluster').isMaster
    @run options

  log: (str, args...) ->
    date = new Date().toISOString()
    console.log "#{date}: #{str}", args...

  constructor: (@options = {}) ->
    @cluster = @options.cluster ? require 'cluster'
    @options.workers ?= CPUS_COUNT
    @options.reloadTimeout ?= 5000

  spawn: (options = {}) ->
    @log 'Cluster: start forking.'
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
        @log "Reload: all done"
        return callback?()
      unless worker = @cluster.workers[worker_id]
        @log "Reload: missing worker ##{worker_id}"
        return reload_next()
      @log "Reload: forking new worker."
      new_worker = @cluster.fork().on 'listening', =>
        @log "Reload: successful fork; disconnecting old worker ##{worker_id}."
        clearTimeout timer_fork_fail
        new_worker.reanimate = worker.reanimate
        reload_next()
        worker.reanimate = false
        worker.on 'disconnect', =>
          @log "Reload: old worker ##{worker_id} disconnected, killing."
          worker.kill()
        worker.disconnect()
      timer_fork_fail = setTimeout =>
        @log "Reload: fork failed, killing it."
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
      @log "Cluster: Worker #{deadWorker.process.pid} died. Reanimate: #{deadWorker.reanimate}."
      return unless deadWorker.reanimate
      worker = @cluster.fork()
      worker.reanimate = deadWorker.reanimate
      @log "Cluster: Worker #{deadWorker.process.pid} reanimated as #{worker.process.pid}."

    process.on 'exit', =>
      @log 'Cluster: exiting, closing workers...'
      @closeAll => @clearPid()

    process.on 'SIGINT', => process.exit()

    process.on 'SIGHUP', => @reloadAll()

    @
