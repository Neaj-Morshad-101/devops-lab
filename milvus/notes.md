Check this for milvus dependencies’ recommended charts: 
https://artifacthub.io/packages/helm/milvus-helm/milvus


Follow the official helm chart:
Standalone:
- use pvc for milvus standalone pod
- update etcd image to helm chart image: docker.io/milvusdb/etcd:3.5.5-r2

 ok image: milvusdb/milvus:v2.2.13
 image: quay.io/coreos/etcd:v3.5.5    #  helm chart image: docker.io/milvusdb/etcd:3.5.5-r2
 ok image: minio/minio:RELEASE.2023-03-20T20-16-18Z   # helm chart image: minio/minio:RELEASE.2023-03-20T20-16-18Z   https://hub.docker.com/r/minio/minio


cluster:
➤ kubectl get sts my-milvus-cluster-pulsar-bookie -oyaml | grep image
        image: apachepulsar/pulsar:2.8.2
➤ kubectl get sts my-milvus-cluster-pulsar-zookeeper -oyaml | grep image
        image: apachepulsar/pulsar:2.8.2

use secrets for authentication stuff: 
➤ kubectl view-secret my-milvus-minio -a
accesskey='minioadmin'
secretkey='minioadmin'

use configmap for minio:
configmap/my-milvus-minio    1      5m30s
➤ kubectl get cm my-milvus-minio -oyaml
apiVersion: v1
data:
  initialize: |-
    #!/bin/sh
    set -e ; # Have script exit in the event of a failed command.
    MC_CONFIG_DIR="/etc/minio/mc/"
    MC="/usr/bin/mc --insecure --config-dir ${MC_CONFIG_DIR}"

    # connectToMinio
    # Use a check-sleep-check loop to wait for Minio service to be available
    connectToMinio() {
      SCHEME=$1
      ATTEMPTS=0 ; LIMIT=29 ; # Allow 30 attempts
      set -e ; # fail if we can't read the keys.
      ACCESS=$(cat /config/accesskey) ; SECRET=$(cat /config/secretkey) ;
      set +e ; # The connections to minio are allowed to fail.
      echo "Connecting to Minio server: $SCHEME://$MINIO_ENDPOINT:$MINIO_PORT" ;
      MC_COMMAND="${MC} config host add myminio $SCHEME://$MINIO_ENDPOINT:$MINIO_PORT $ACCESS $SECRET" ;
      $MC_COMMAND ;
      STATUS=$? ;
      until [ $STATUS = 0 ]
      do
        ATTEMPTS=`expr $ATTEMPTS + 1` ;
        echo \"Failed attempts: $ATTEMPTS\" ;
        if [ $ATTEMPTS -gt $LIMIT ]; then
          exit 1 ;
        fi ;
        sleep 2 ; # 1 second intervals between attempts
        $MC_COMMAND ;
        STATUS=$? ;
      done ;
      set -e ; # reset `e` as active
      return 0
    }

    # checkBucketExists ($bucket)
    # Check if the bucket exists, by using the exit code of `mc ls`
    checkBucketExists() {
      BUCKET=$1
      CMD=$(${MC} ls myminio/$BUCKET > /dev/null 2>&1)
      return $?
    }

    # createBucket ($bucket, $policy, $purge)
    # Ensure bucket exists, purging if asked to
    createBucket() {
      BUCKET=$1
      POLICY=$2
      PURGE=$3
      VERSIONING=$4

      # Purge the bucket, if set & exists
      # Since PURGE is user input, check explicitly for `true`
      if [ $PURGE = true ]; then
        if checkBucketExists $BUCKET ; then
          echo "Purging bucket '$BUCKET'."
          set +e ; # don't exit if this fails
          ${MC} rm -r --force myminio/$BUCKET
          set -e ; # reset `e` as active
        else
          echo "Bucket '$BUCKET' does not exist, skipping purge."
        fi
      fi

      # Create the bucket if it does not exist
      if ! checkBucketExists $BUCKET ; then
        echo "Creating bucket '$BUCKET'"
        ${MC} mb myminio/$BUCKET
      else
        echo "Bucket '$BUCKET' already exists."
      fi


      # set versioning for bucket
      if [ ! -z $VERSIONING ] ; then
        if [ $VERSIONING = true ] ; then
            echo "Enabling versioning for '$BUCKET'"
            ${MC} version enable myminio/$BUCKET
        elif [ $VERSIONING = false ] ; then
            echo "Suspending versioning for '$BUCKET'"
            ${MC} version suspend myminio/$BUCKET
        fi
      else
          echo "Bucket '$BUCKET' versioning unchanged."
      fi

      # At this point, the bucket should exist, skip checking for existence
      # Set policy on the bucket
      echo "Setting policy of bucket '$BUCKET' to '$POLICY'."
      ${MC} policy set $POLICY myminio/$BUCKET
    }

    # Try connecting to Minio instance
    scheme=http
    connectToMinio $scheme
kind: ConfigMap
metadata:
  annotations:
    meta.helm.sh/release-name: my-milvus
    meta.helm.sh/release-namespace: default
  creationTimestamp: "2025-09-16T06:18:39Z"
  labels:
    app: minio
    app.kubernetes.io/managed-by: Helm
    chart: minio-8.0.17
    heritage: Helm
    release: my-milvus
  name: my-milvus-minio
  namespace: default
  resourceVersion: "5439"
  uid: b05ac587-31fe-487c-b285-370349502449








All milvus components of Distributed Milvus
8
NAME                                           READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/my-milvus-cluster-datacoord    1/1     1            1           12m
deployment.apps/my-milvus-cluster-datanode     1/1     1            1           12m
deployment.apps/my-milvus-cluster-indexcoord   1/1     1            1           12m
deployment.apps/my-milvus-cluster-indexnode    1/1     1            1           12m
deployment.apps/my-milvus-cluster-proxy        1/1     1            1           12m
deployment.apps/my-milvus-cluster-querycoord   1/1     1            1           12m
deployment.apps/my-milvus-cluster-querynode    2/2     2            2           12m
deployment.apps/my-milvus-cluster-rootcoord    1/1     1            1           12m

➤ kubectl get deploy -oyaml | grep image: 
          image: milvusdb/milvus:v2.2.13
          image: milvusdb/milvus-config-tool:v0.1.1
          image: milvusdb/milvus:v2.2.13
          image: milvusdb/milvus-config-tool:v0.1.1
          image: milvusdb/milvus:v2.2.13
          image: milvusdb/milvus-config-tool:v0.1.1
          image: milvusdb/milvus:v2.2.13
          image: milvusdb/milvus-config-tool:v0.1.1
          image: milvusdb/milvus:v2.2.13
          image: milvusdb/milvus-config-tool:v0.1.1
          image: milvusdb/milvus:v2.2.13
          image: milvusdb/milvus-config-tool:v0.1.1
          image: milvusdb/milvus:v2.2.13
          image: milvusdb/milvus-config-tool:v0.1.1
          image: milvusdb/milvus:v2.2.13
          image: milvusdb/milvus-config-tool:v0.1.1

For all type of milvus node's container, the image: milvusdb/milvus:v2.2.13.
For all init-containers the image: milvusdb/milvus-config-tool:v0.1.1


7
NAME                                                  READY   AGE
statefulset.apps/my-milvus-cluster-etcd     image: docker.io/milvusdb/etcd:3.5.5-r2
statefulset.apps/my-milvus-cluster-minio    image: minio/minio:RELEASE.2023-03-20T20-16-18Z
statefulset.apps/my-milvus-cluster-pulsar-bookie      3/3     12m
statefulset.apps/my-milvus-cluster-pulsar-broker      1/1     12m
statefulset.apps/my-milvus-cluster-pulsar-proxy       1/1     12m
statefulset.apps/my-milvus-cluster-pulsar-recovery    1/1     12m
statefulset.apps/my-milvus-cluster-pulsar-zookeeper   3/3     12m

➤ kubectl get sts -oyaml | grep image:
          image: docker.io/milvusdb/etcd:3.5.5-r2
          image: minio/minio:RELEASE.2023-03-20T20-16-18Z
          11
          image: apachepulsar/pulsar:2.8.2
          image: apachepulsar/pulsar:2.8.2
          image: apachepulsar/pulsar:2.8.2
          image: apachepulsar/pulsar:2.8.2
          image: apachepulsar/pulsar:2.8.2
          image: apachepulsar/pulsar:2.8.2
          image: apachepulsar/pulsar:2.8.2
          image: apachepulsar/pulsar:2.8.2
          image: apachepulsar/pulsar:2.8.2
          image: apachepulsar/pulsar:2.8.2
          image: apachepulsar/pulsar:2.8.2

For all type of pulsur node's container and all init-containers, the image: apachepulsar/pulsar:2.8.2









Every 2.0s: kubectl get all,pvc,secrets,cm

NAME                                                READY   STATUS      RESTARTS        AGE
pod/my-milvus-cluster-datacoord-f55888d4c-bn7nf     1/1     Running     0               12m
pod/my-milvus-cluster-datanode-79dd569f9-sqcrp      1/1     Running     1 (8m27s ago)   12m
pod/my-milvus-cluster-etcd-0                        1/1     Running     0               12m
pod/my-milvus-cluster-etcd-1                        1/1     Running     0               12m
pod/my-milvus-cluster-etcd-2                        1/1     Running     0               12m
pod/my-milvus-cluster-indexcoord-68846c5d79-ql9jx   1/1     Running     1 (8m27s ago)   12m
pod/my-milvus-cluster-indexnode-7c7b6ff94-bctlf     1/1     Running     0               12m
pod/my-milvus-cluster-minio-0                       1/1     Running     0               12m
pod/my-milvus-cluster-minio-1                       1/1     Running     0               12m
pod/my-milvus-cluster-minio-2                       1/1     Running     0               12m
pod/my-milvus-cluster-minio-3                       1/1     Running     0               12m
pod/my-milvus-cluster-proxy-5d5bd5f7f-t9bzh         1/1     Running     1 (8m27s ago)   12m
pod/my-milvus-cluster-pulsar-bookie-0               1/1     Running     0               12m
pod/my-milvus-cluster-pulsar-bookie-1               1/1     Running     0               12m
pod/my-milvus-cluster-pulsar-bookie-2               1/1     Running     0               12m
pod/my-milvus-cluster-pulsar-bookie-init-jj65f      0/1     Completed   0               12m
pod/my-milvus-cluster-pulsar-broker-0               1/1     Running     0               12m
pod/my-milvus-cluster-pulsar-proxy-0                1/1     Running     0               12m
pod/my-milvus-cluster-pulsar-pulsar-init-h6sxn      0/1     Completed   0               12m
pod/my-milvus-cluster-pulsar-recovery-0             1/1     Running     0               12m
pod/my-milvus-cluster-pulsar-zookeeper-0            1/1     Running     0               12m
pod/my-milvus-cluster-pulsar-zookeeper-1            1/1     Running     0               10m
pod/my-milvus-cluster-pulsar-zookeeper-2            1/1     Running     0               10m
pod/my-milvus-cluster-querycoord-b7fb4774d-48hff    1/1     Running     1 (8m27s ago)   12m
pod/my-milvus-cluster-querynode-59b78b79c7-7sq5l    1/1     Running     0               12m
pod/my-milvus-cluster-querynode-59b78b79c7-ctxjf    1/1     Running     0               12m
pod/my-milvus-cluster-rootcoord-7d89bc88c6-9jwt6    1/1     Running     1 (8m27s ago)   12m

NAME                                         TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)                               AGE
service/kubernetes                           ClusterIP   10.96.0.1       <none>        443/TCP                               169m
service/my-milvus-cluster                    ClusterIP   10.96.28.136    <none>        19530/TCP,9091/TCP                    12m
service/my-milvus-cluster-datacoord          ClusterIP   10.96.73.55     <none>        13333/TCP,9091/TCP                    12m
service/my-milvus-cluster-datanode           ClusterIP   None            <none>        9091/TCP                              12m
service/my-milvus-cluster-etcd               ClusterIP   10.96.215.169   <none>        2379/TCP,2380/TCP                     12m
service/my-milvus-cluster-etcd-headless      ClusterIP   None            <none>        2379/TCP,2380/TCP                     12m
service/my-milvus-cluster-indexcoord         ClusterIP   10.96.218.88    <none>        31000/TCP,9091/TCP                    12m
service/my-milvus-cluster-indexnode          ClusterIP   None            <none>        9091/TCP                              12m
service/my-milvus-cluster-minio              ClusterIP   10.96.19.76     <none>        9000/TCP                              12m
service/my-milvus-cluster-minio-svc          ClusterIP   None            <none>        9000/TCP                              12m
service/my-milvus-cluster-pulsar-bookie      ClusterIP   None            <none>        3181/TCP,8000/TCP                     12m
service/my-milvus-cluster-pulsar-broker      ClusterIP   None            <none>        8080/TCP,6650/TCP                     12m
service/my-milvus-cluster-pulsar-proxy       ClusterIP   10.96.92.27     <none>        80/TCP,6650/TCP                       12m
service/my-milvus-cluster-pulsar-recovery    ClusterIP   None            <none>        8000/TCP                              12m
service/my-milvus-cluster-pulsar-zookeeper   ClusterIP   None            <none>        8000/TCP,2888/TCP,3888/TCP,2181/TCP   12m
service/my-milvus-cluster-querycoord         ClusterIP   10.96.27.70     <none>        19531/TCP,9091/TCP                    12m
service/my-milvus-cluster-querynode          ClusterIP   None            <none>        9091/TCP                              12m
service/my-milvus-cluster-rootcoord          ClusterIP   10.96.96.117    <none>        53100/TCP,9091/TCP                    12m

NAME                                           READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/my-milvus-cluster-datacoord    1/1     1            1           12m
deployment.apps/my-milvus-cluster-datanode     1/1     1            1           12m
deployment.apps/my-milvus-cluster-indexcoord   1/1     1            1           12m
deployment.apps/my-milvus-cluster-indexnode    1/1     1            1           12m
deployment.apps/my-milvus-cluster-proxy        1/1     1            1           12m
deployment.apps/my-milvus-cluster-querycoord   1/1     1            1           12m
deployment.apps/my-milvus-cluster-querynode    2/2     2            2           12m
deployment.apps/my-milvus-cluster-rootcoord    1/1     1            1           12m

NAME                                                      DESIRED   CURRENT   READY   AGE
replicaset.apps/my-milvus-cluster-datacoord-f55888d4c     1         1         1       12m
replicaset.apps/my-milvus-cluster-datanode-79dd569f9      1         1         1       12m
replicaset.apps/my-milvus-cluster-indexcoord-68846c5d79   1         1         1       12m
replicaset.apps/my-milvus-cluster-indexnode-7c7b6ff94     1         1         1       12m
replicaset.apps/my-milvus-cluster-proxy-5d5bd5f7f         1         1         1       12m
replicaset.apps/my-milvus-cluster-querycoord-b7fb4774d    1         1         1       12m
replicaset.apps/my-milvus-cluster-querynode-59b78b79c7    2         2         2       12m
replicaset.apps/my-milvus-cluster-rootcoord-7d89bc88c6    1         1         1       12m

NAME                                                  READY   AGE
statefulset.apps/my-milvus-cluster-etcd               3/3     12m
statefulset.apps/my-milvus-cluster-minio              4/4     12m
statefulset.apps/my-milvus-cluster-pulsar-bookie      3/3     12m
statefulset.apps/my-milvus-cluster-pulsar-broker      1/1     12m
statefulset.apps/my-milvus-cluster-pulsar-proxy       1/1     12m
statefulset.apps/my-milvus-cluster-pulsar-recovery    1/1     12m
statefulset.apps/my-milvus-cluster-pulsar-zookeeper   3/3     12m

NAME                                             STATUS     COMPLETIONS   DURATION   AGE
job.batch/my-milvus-cluster-pulsar-bookie-init   Complete   1/1           3m12s      12m
job.batch/my-milvus-cluster-pulsar-pulsar-init   Complete   1/1           3m19s      12m

NAME                                                                                                 STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
persistentvolumeclaim/data-my-milvus-cluster-etcd-0                                                  Bound    pvc-83b2687d-40e4-4ccb-97db-196ce3a7f286   20Gi       RWO            standard       <unset>                 12m
persistentvolumeclaim/data-my-milvus-cluster-etcd-1                                                  Bound    pvc-df7da4ee-2c8f-427a-a3af-26c1adf2e440   20Gi       RWO            standard       <unset>                 12m
persistentvolumeclaim/data-my-milvus-cluster-etcd-2                                                  Bound    pvc-9aa6a4b1-b0e5-43c9-b71e-3351fc7481f6   20Gi       RWO            standard       <unset>                 12m
persistentvolumeclaim/export-my-milvus-cluster-minio-0                                               Bound    pvc-17de769d-1055-4e0d-b850-fa5716898b0b   50Gi       RWO            standard       <unset>                 12m
persistentvolumeclaim/export-my-milvus-cluster-minio-1                                               Bound    pvc-928074f1-62bf-457c-b82a-05e5ec17b9e6   50Gi       RWO            standard       <unset>                 12m
persistentvolumeclaim/export-my-milvus-cluster-minio-2                                               Bound    pvc-fee32e1b-2523-4bfb-9cf0-f5e7a9a94c25   50Gi       RWO            standard       <unset>                 12m
persistentvolumeclaim/export-my-milvus-cluster-minio-3                                               Bound    pvc-971aecc0-45b1-4a0d-a023-c56e2ee85198   50Gi       RWO            standard       <unset>                 12m
persistentvolumeclaim/my-milvus-cluster-pulsar-bookie-journal-my-milvus-cluster-pulsar-bookie-0      Bound    pvc-bc31f323-bec3-4f61-b460-633cb9c087c9   100Gi      RWO            standard       <unset>                 12m
persistentvolumeclaim/my-milvus-cluster-pulsar-bookie-journal-my-milvus-cluster-pulsar-bookie-1      Bound    pvc-71cd8f44-eb25-4b02-944a-bbf1d85db73e   100Gi      RWO            standard       <unset>                 12m
persistentvolumeclaim/my-milvus-cluster-pulsar-bookie-journal-my-milvus-cluster-pulsar-bookie-2      Bound    pvc-535b25a8-3757-4f16-91ce-aaa09b7bc35d   100Gi      RWO            standard       <unset>                 12m
persistentvolumeclaim/my-milvus-cluster-pulsar-bookie-ledgers-my-milvus-cluster-pulsar-bookie-0      Bound    pvc-e2af143e-aa47-4e19-b659-77b36495eef1   200Gi      RWO            standard       <unset>                 12m
persistentvolumeclaim/my-milvus-cluster-pulsar-bookie-ledgers-my-milvus-cluster-pulsar-bookie-1      Bound    pvc-7a909947-2ab1-47c0-a294-d1c49f1cf65c   200Gi      RWO            standard       <unset>                 12m
persistentvolumeclaim/my-milvus-cluster-pulsar-bookie-ledgers-my-milvus-cluster-pulsar-bookie-2      Bound    pvc-b7bccbba-d5bc-4e54-9e14-d2fd901d72b0   200Gi      RWO            standard       <unset>                 12m
persistentvolumeclaim/my-milvus-cluster-pulsar-zookeeper-data-my-milvus-cluster-pulsar-zookeeper-0   Bound    pvc-3583371b-7ec6-43e6-b996-532142573ef1   20Gi       RWO            standard       <unset>                 12m
persistentvolumeclaim/my-milvus-cluster-pulsar-zookeeper-data-my-milvus-cluster-pulsar-zookeeper-1   Bound    pvc-a015c4fe-c25e-4fc3-b8f4-45f111d206b8   20Gi       RWO            standard       <unset>                 10m
persistentvolumeclaim/my-milvus-cluster-pulsar-zookeeper-data-my-milvus-cluster-pulsar-zookeeper-2   Bound    pvc-42a09cf2-2b15-4a3e-877f-c1a032552bfd   20Gi       RWO            standard       <unset>                 10m

NAME                                             TYPE                 DATA   AGE
secret/my-milvus-cluster-minio                   Opaque               2      12m
secret/sh.helm.release.v1.my-milvus-cluster.v1   helm.sh/release.v1   1      12m

NAME                                           DATA   AGE
configmap/kube-root-ca.crt                     1      169m
configmap/my-milvus-cluster                    2      12m
configmap/my-milvus-cluster-minio              1      12m
configmap/my-milvus-cluster-pulsar-bookie      18     12m
configmap/my-milvus-cluster-pulsar-broker      22     12m
configmap/my-milvus-cluster-pulsar-proxy       9      12m
configmap/my-milvus-cluster-pulsar-recovery    7      12m
configmap/my-milvus-cluster-pulsar-zookeeper   5      12m



### High-Level Overview: What You Are Looking At

This output shows a **complete, healthy, and production-grade Milvus cluster** running on Kubernetes. You are not just seeing Milvus; you are seeing Milvus *and* all of its critical dependencies, managed by various Kubernetes resources.

The components can be split into two main categories:
1.  **Milvus Core Components:** The microservices that make up Milvus itself (the "brains" and "muscle").
2.  **External Dependencies:** The infrastructure Milvus relies on for storage and messaging (the "foundation").

Let's go through each Kubernetes object type.

---

### 1. Pods (The Actual Running Software)

**Analogy:** Think of Pods as the individual "workers" or "virtual servers" running a single piece of your application.

Your pods are neatly divided into the two categories mentioned above:

#### A) Milvus Core Components (The "Brains" and "Muscle")
*   `pod/my-milvus-cluster-proxy-...`: This is the **front door**. All your requests (from the Python SDK, etc.) go here first. It's the API gateway that routes requests to the correct internal components.
*   `pod/my-milvus-cluster-rootcoord-...`: The **master controller** (Root Coordinator). It handles Data Definition Language (DDL) commands like creating/dropping collections and schemas.
*   `pod/my-milvus-cluster-querycoord-...`: The **query manager** (Query Coordinator). It manages the state of the query nodes and assigns search/query tasks to them.
*   `pod/my-milvus-cluster-datacoord-...`: The **data manager** (Data Coordinator). It manages the state of the data nodes and handles data insertion, flushing, and compaction.
*   `pod/my-milvus-cluster-indexcoord-...`: The **index manager** (Index Coordinator). It manages the state of the index nodes and handles building the vector indexes.
*   `pod/my-milvus-cluster-querynode-...` (x2): These are the **search workers**. They load data into memory and execute the actual vector similarity searches. You have two of them for scalability and availability.
*   `pod/my-milvus-cluster-datanode-...`: This is the **data persistence worker**. It subscribes to the log stream (from Pulsar) and writes inserted data into persistent object storage (MinIO).
*   `pod/my-milvus-cluster-indexnode-...`: This is the **index building worker**. It is responsible for creating the complex index files for your vector data.

#### B) External Dependencies (The "Foundation")
*   `pod/my-milvus-cluster-etcd-...` (x3): **Etcd** is a distributed key-value store. Milvus uses it as its **metadata engine**. It stores all the crucial information *about* your data: collection schemas, segment locations, index types, etc. It's like the librarian's card catalog. You have 3 pods for high availability.
*   `pod/my-milvus-cluster-minio-...` (x4): **MinIO** is an S3-compatible **object storage system**. This is where Milvus stores the "heavy" data: the raw vector files, index files, etc. It's like the library's main warehouse shelves. You have 4 pods for a distributed, resilient storage layer.
*   `pod/my-milvus-cluster-pulsar-...`: **Pulsar** is a distributed messaging system. Milvus uses it as its **log broker**. All data operations (inserts, deletes) are written as messages to Pulsar first. This decouples the components and ensures data is never lost. The various `bookie`, `broker`, `zookeeper`, and `proxy` pods are all parts of a complete Pulsar cluster.

#### C) Jobs (One-off Tasks)
*   `pod/...-init-...`: These pods with a `STATUS` of `Completed` are **initialization jobs**. They run once when the cluster is first created to set up configurations for dependencies like Pulsar. Seeing them as `Completed` is perfect.

---

### 2. Services (The Internal Network)

**Analogy:** Services provide a stable network address (like a static IP address or a DNS name) for a group of pods. They allow pods to find and communicate with each other, even if the pods themselves are deleted and recreated.

*   `service/my-milvus-cluster`: This is the **main entry point** for your entire cluster. It points to the `proxy` pod. When your Python client connects, it connects to this service's address.
*   **All the other services** (`...-datacoord`, `...-etcd`, etc.) are for **internal communication**. For example, the `proxy` needs to talk to the `querycoord`, so it uses the `service/my-milvus-cluster-querycoord` address.
*   **`TYPE: ClusterIP`**: This means the service is only accessible from *inside* the Kubernetes cluster. This is why you need `kubectl port-forward` to connect from your local machine.

---

### 3. Deployments & StatefulSets (The Pod Managers)

These resources manage the lifecycle of your pods, ensuring they are running, healthy, and scalable.

*   **`deployment.apps/...`**: A Deployment is used for **stateless** applications. If a pod managed by a Deployment dies, it is simply replaced by a new, identical one. The Milvus core components (`proxy`, `querynode`, `datanode`, etc.) are stateless because their important data is stored externally in Etcd and MinIO.
*   **`statefulset.apps/...`**: A StatefulSet is used for **stateful** applications that need a stable identity and persistent storage. Your dependencies (`etcd`, `minio`, `pulsar`) are stateful. For example, `etcd-0` is not interchangeable with `etcd-1`; they each have their own unique data. A StatefulSet ensures that if `etcd-0` restarts, it comes back with the same name and connects to the same storage volume.

---

### 4. Persistent Volume Claims (PVCs) (The Hard Drives)

**Analogy:** A PVC is a "request for storage" (like a hard drive) from the Kubernetes cluster.

*   This section shows all the storage that has been provisioned for your stateful applications.
*   `STATUS: Bound`: This is great news. It means your cluster was able to provide the storage that was requested.
*   Notice the naming convention: `data-my-milvus-cluster-etcd-0` is the PVC for the `etcd-0` pod. This is how StatefulSets link pods to their specific storage.
*   This is where your actual data lives. **Even if you delete all the pods, your data will remain safe in these volumes.**

---

### 5. Secrets & ConfigMaps (The Configuration)

*   **`configmap/...`**: A ConfigMap stores non-sensitive configuration data as key-value pairs. Milvus and its dependencies use these to know how to start up and how to talk to each other.
*   **`secret/...`**: A Secret is similar to a ConfigMap but is used for sensitive data like passwords or API keys. The `secret/my-milvus-cluster-minio` likely contains the access keys for your MinIO object storage.

In summary, you have successfully deployed a complex, distributed system with resilient storage, a robust messaging backbone, and a full suite of scalable microservices to power your vector database. Everything looks healthy and correctly configured.

