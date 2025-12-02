GitOps Overview for PostgreSQL
This guide will give you an overview of how KubeDB gitops operator works with PostgreSQL databases using the gitops.kubedb.com/v1alpha1 API. It will help you understand the GitOps workflow for managing PostgreSQL databases in Kubernetes.

Before You Begin
You should be familiar with the following KubeDB concepts:
Postgres
PostgresOpsRequest
GitOps Postgres
Workflow GitOps with PostgreSQL
The following diagram shows how the KubeDB GitOps Operator used to sync with your database. Open the image in a new tab to see the enlarged version.

￼
Fig: GitOps process of Postgres
Define GitOps Postgres: Create Custom Resource (CR) of kind Postgres using the gitops.kubedb.com/v1alpha1 API.
Store in Git: Push the CR to a Git repository.
Automated Deployment: Use a GitOps tool (like ArgoCD or FluxCD) to monitor the Git repository and synchronize the state of the Kubernetes cluster with the desired state defined in Git.
Create Database: The GitOps operator creates a corresponding KubeDB Postgres CR in the Kubernetes cluster to deploy the database.
Handle Updates: When you update the PostgresGitOps CR, the operator generates an Ops Request to safely apply the update(e.g. VerticalScaling, HorizontalScaling, VolumeExapnsion, Reconfigure, RotateAuth, ReconfigureTLS, VersionUpdate, ans Restart.
This flow makes managing PostgreSQL databases efficient, reliable, and fully integrated with GitOps practices.

In the next doc, we are going to show a step by step guide on running postgres using GitOps.


GitOps Postgres using KubeDB GitOps Operator
This guide will show you how to use KubeDB GitOps operator to create postgres database and manage updates using GitOps workflow.

Before You Begin
At first, you need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster. If you do not already have a cluster, you can create one by using kind.
Install KubeDB operator in your cluster following the steps here. Pass --set kubedb-crd-manager.installGitOpsCRDs=true in the kubedb installation process to enable GitOps operator.
You need to install GitOps tools like ArgoCD or FluxCD and configure with your Git Repository to monitor the Git repository and synchronize the state of the Kubernetes cluster with the desired state defined in Git.
$ kubectl create ns monitoring
namespace/monitoring created

$ kubectl create ns demo
namespace/demo created
Note: YAML files used in this tutorial are stored in docs/examples/postgres folder in GitHub repository kubedb/docs.

We are going to use ArgoCD in this tutorial. You can install ArgoCD in your cluster by following the steps here. Also, you need to install argocd CLI in your local machine. You can install argocd CLI by following the steps here.

Creating Apps via CLI
For Public Repository
argocd app create kubedb --repo <repo-url> --path kubedb --dest-server https://kubernetes.default.svc --dest-namespace <namespace>
For Private Repository
Using HTTPS
argocd app create kubedb --repo <repo-url> --path kubedb --dest-server https://kubernetes.default.svc --dest-namespace <namespace> --username <username> --password <github-token>
Using SSH
argocd app create kubedb --repo <repo-url> --path kubedb --dest-server https://kubernetes.default.svc --dest-namespace <namespace> --ssh-private-key-path ~/.ssh/id_rsa
Create Postgres Database using GitOps
Create a Postgres GitOps CR
apiVersion: gitops.kubedb.com/v1alpha1
kind: Postgres
metadata:
name: ha-postgres
namespace: demo
spec:
replicas: 3
version: "16.6"
storageType: Durable
podTemplate:
spec:
containers:
- name: postgres
resources:
limits:
memory: 1Gi
requests:
cpu: 500m
memory: 1Gi
storage:
storageClassName: "standard"
accessModes:
- ReadWriteOnce
resources:
requests:
storage: 1Gi
deletionPolicy: WipeOut
Create a directory like below,

$ tree .
├── kubedb
└── postgres.yaml
1 directories, 1 files
Now commit the changes and push to your Git repository. Your repository is synced with ArgoCD and the Postgres CR is created in your cluster.

Our gitops operator will create an actual Postgres database CR in the cluster. List the resources created by gitops operator in the demo namespace.

$ kubectl get postgreses.gitops.kubedb.com,postgreses.kubedb.com -n demo
NAME                                     AGE
postgres.gitops.kubedb.com/ha-postgres   2m11s

NAME                              VERSION   STATUS   AGE
postgres.kubedb.com/ha-postgres   16.6      Ready    2m11s
List the resources created by kubedb operator created for kubedb.com/v1 Postgres.

$ kubectl get petset,pod,secret,service,appbinding -n demo -l 'app.kubernetes.io/instance=ha-postgres'
NAME                                       AGE
petset.apps.k8s.appscode.com/ha-postgres   3m26s

NAME                READY   STATUS    RESTARTS   AGE
pod/ha-postgres-0   2/2     Running   0          3m26s
pod/ha-postgres-1   2/2     Running   0          3m8s
pod/ha-postgres-2   2/2     Running   0          2m50s

NAME                      TYPE                       DATA   AGE
secret/ha-postgres-auth   kubernetes.io/basic-auth   2      3m29s

NAME                          TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)                      AGE
service/ha-postgres           ClusterIP   10.43.169.122   <none>        5432/TCP,2379/TCP            3m29s
service/ha-postgres-pods      ClusterIP   None            <none>        5432/TCP,2380/TCP,2379/TCP   3m29s
service/ha-postgres-standby   ClusterIP   10.43.106.75    <none>        5432/TCP                     3m29s

NAME                                             TYPE                  VERSION   AGE
appbinding.appcatalog.appscode.com/ha-postgres   kubedb.com/postgres   16.6      3m26s
Update Postgres Database using GitOps
Scale Postgres Database Resources
Update the postgres.yaml with the following,

apiVersion: gitops.kubedb.com/v1alpha1
kind: Postgres
metadata:
name: ha-postgres
namespace: demo
spec:
replicas: 3
version: "16.6"
storageType: Durable
podTemplate:
spec:
containers:
- name: postgres
resources:
limits:
memory: 2Gi
requests:
cpu: 700m
memory: 2Gi
storage:
storageClassName: "standard"
accessModes:
- ReadWriteOnce
resources:
requests:
storage: 1Gi
deletionPolicy: WipeOut
Resource Requests and Limits are updated to 700m CPU and 2Gi Memory. Commit the changes and push to your Git repository. Your repository is synced with ArgoCD and the Postgres CR is updated in your cluster.

Now, gitops operator will detect the resource changes and create a PostgresOpsRequest to update the Postgres database. List the resources created by gitops operator in the demo namespace.

$ kubectl get postgreses.gitops.kubedb.com,postgreses.kubedb.com,postgresopsrequest -n demo
NAME                                     AGE
postgres.gitops.kubedb.com/ha-postgres   13m

NAME                              VERSION   STATUS   AGE
postgres.kubedb.com/ha-postgres   16.6      Ready    13m

NAME                                                                   TYPE              STATUS        AGE
postgresopsrequest.ops.kubedb.com/ha-postgres-verticalscaling-i0kr1l   VerticalScaling   Progressing   2s
After Ops Request becomes Successful, We can validate the changes by checking the one of the pod,

$ kubectl get pod -n demo ha-postgres-0 -o json | jq '.spec.containers[0].resources'
{
"limits": {
"memory": "2Gi"
},
"requests": {
"cpu": "700m",
"memory": "2Gi"
}
}


```yaml
apiVersion: gitops.kubedb.com/v1alpha1
kind: Postgres
metadata:
  name: grafana-db
  namespace: demo
spec:
  arbiter:
    resources:
      limits:
        memory: 256Mi
      requests:
        cpu: 200m
        memory: 256Mi
        storage: 10Gi
  deletionPolicy: Delete
  replicas: 2
  standbyMode: Hot
  storage:
    accessModes:
    - ReadWriteOnce
    resources:
      requests:
        storage: 5Gi
  storageType: Durable
  version: "17.5"
```


```yaml
apiVersion: ops.kubedb.com/v1alpha1
kind: PostgresOpsRequest
metadata:
  creationTimestamp: "2025-11-28T12:38:56Z"
  generation: 1
  name: grafana-db-verticalscaling-hvonp6
  namespace: demo
  resourceVersion: "1215348"
  uid: 24bae44a-c0e3-448a-8b7d-3ef9f73834b5
spec:
  apply: IfReady
  databaseRef:
    name: grafana-db
  type: VerticalScaling
  verticalScaling:
    arbiter:
      resources:
        limits:
          memory: 256Mi
        requests:
          cpu: 200m
          memory: 256Mi
          storage: 10Gi
status:
  phase: Pending
```