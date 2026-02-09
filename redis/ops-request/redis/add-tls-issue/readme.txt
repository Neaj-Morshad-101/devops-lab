rotate nonTL redis pod with new TLS configured failed
witch
```
spec:
  podTemplate:
    spec:
      runtimeClassName: runsc
```      


rotate nonTL redis pod with new TLS configured failed
lastTransitionTime: "2026-01-14T10:19:31Z"
message: 'The Redis: demo/rd-sample is not accepting client requests. error: failed
 to connect to database: read: connection reset by peer'
observedGeneration: 2
reason: DatabaseNotAcceptingConnectionRequest



steps that I set up for node and enable runtimeclass:

install gvisor package on OS workernode (ex: apt-get install -y runsc )

edit config containerd docker runtime:

...
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runsc]
  runtime_type = "io.containerd.runsc.v1"
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runsc.options]
  TypeUrl = "io.containerd.runsc.v1.options"
  ConfigPath = "/etc/containerd/runsc.toml"
  SystemdCgroup = true
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runsc-kvm]
  runtime_type = "io.containerd.runsc.v1"
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runsc-kvm.options]
  TypeUrl = "io.containerd.runsc.v1.options"
  ConfigPath = "/etc/containerd/runsc-kvm.toml"
  SystemdCgroup = true
....


runsc.toml 
log_level = "info"
[runsc_config]
  systemd-cgroup = "true"
  network = "host"
  net-raw = "true"

Create runtimeClass runsc type:
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: runsc
handler: runsc 