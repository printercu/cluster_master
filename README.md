# ClusterMaster

Basic cluster management in one line:

```coffee
return if require('cluster_master').runMaster()
# worker's code here
```

By default it'll spawn `os.cpus().length` workers and respawn every dead worker.

Out of box you'll get safe zero downtime reload:

- send `SIGHUP` to process
- cluster will try to spawn new worker
- if new worker is ok then cluster will gracefully close one running worker & 'll reload all old workers
- if new forker failed it won't destroy old workers

For more stuff see source.

## Use forever
Oops! Seems like forever still does not have proper support for specifying kill signal.

However you can specify pid file for ClusterMaster and send hups yourself:

```
return if require('cluster_master').runMaster(pidfile: 'pids/cluster.pid')
```

May be later:
Once cluster is started with [forever](https://github.com/nodejitsu/forever)

```sh
forever start -c coffee server.coffee
```

it can be reloaded with

```sh
forever stop --killSignal SIGHUP -c coffee server.coffee
```

## License
MIT
