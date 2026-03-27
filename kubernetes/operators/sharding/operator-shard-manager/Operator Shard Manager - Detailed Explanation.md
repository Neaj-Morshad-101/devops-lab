# Operator Shard Manager - Detailed Explanation

## Overview

The **operator-shard-manager** is a Kubernetes controller that enables horizontal scaling of operators by distributing (sharding) the resources they manage across multiple operator pods. It uses **consistent hashing with bounded load** to achieve uniform distribution while minimizing resource movement during scaling operations.

---

## How It Works: Step-by-Step

### 1. **Deploy the Shard Manager and Create a ShardConfiguration**

You deploy the operator-shard-manager as a controller in your cluster and create a `ShardConfiguration` custom resource that defines:
- **Controllers**: The operator deployments/statefulsets/daemonsets to shard (e.g., KubeDB provisioner)
- **Resources**: The Kubernetes resources to be sharded (e.g., all resources in `kubedb.com` API group)

**Example ShardConfiguration:**
```yaml
apiVersion: operator.k8s.appscode.com/v1alpha1
kind: ShardConfiguration
metadata:
  name: kubedb
spec:
  controllers:
  - apiGroup: apps
    kind: Deployment
    name: kubedb-provisioner
    namespace: kubedb
  resources:
  - apiGroup: kubedb.com
    # Optionally specify shardKey to use a custom field for hashing
    # useCooperativeShardMigration: true
```

---

### 2. **Discover Operator Pods and Assign Them Indices**

The controller continuously monitors the operator pods and assigns each pod a **shard index** (0, 1, 2, etc.).

#### How Pod Discovery Works:

In `ListPods()` function (lines 349-436 in shardconfiguration_controller.go):

**For Deployments:**
1. Gets the Deployment and its pod selector
2. Lists all pods matching the selector
3. Filters for pods that:
   - Are controlled by a ReplicaSet of this Deployment
   - Are not being deleted (DeletionTimestamp is nil)
4. Sorts pod names alphabetically
5. Returns the sorted list

**For StatefulSets:**
- Generates predictable pod names: `{name}-0`, `{name}-1`, etc.
- Replicas count determines how many shards exist

**For DaemonSets:**
- Lists all pods controlled by the DaemonSet
- Filters out terminating pods
- Sorts them alphabetically

#### Pod List Management During Scaling:

When pods change (in `getUpdatedPodLists()` - utils.go lines 26-94):

**Scale-Up/Update:**
- Preserves the position of existing pods in the shard list
- Adds new pods to available slots
- Example: `existing=[1, 3]` → `podLists=[2, 3, 0, 1]` → `output=[1, 3, 2, 0]`

**Scale-Down:**
- Maintains the order of surviving pods
- Example: `existing=[2, 3, 0, 1]` → `podLists=[1, 3]` → `output=[3, 1]`

This stability is crucial for minimizing resource reassignment!

---

### 3. **Label All Target Resources with Shard Indices Using Consistent Hashing**

The shard manager labels every resource with its assigned shard index.

#### The Consistent Hashing Process:

**A. Initialization (hashing.go):**
```go
func newConsistentConfig(shardCount int) *consistent.Consistent {
    // Create member for each shard (Member{ID: 0}, Member{ID: 1}, ...)
    members := make([]consistent.Member, 0, shardCount)
    for i := 0; i < shardCount; i++ {
        members = append(members, Member{ID: i})
    }
    
    // Configure consistent hash ring
    return consistent.New(members, consistent.Config{
        PartitionCount:    getBetterPartitionCount(shardCount, 1.0),
        ReplicationFactor: 1,
        Load:              1.0,
        Hasher:            hasher{},  // Uses xxhash for uniform distribution
    })
}
```

**B. Resource Labeling (UpdateShardLabel() - lines 210-273):**

For each resource:

1. **Extract the shard key:**
   - Default: `{namespace}/{name}` (e.g., `default/my-postgres`)
   - Custom: Use JSONPath if `shardKey` is specified (e.g., `.spec.databaseRef.name`)

2. **Hash the key to find the shard:**
   ```go
   key = []byte(fmt.Sprintf("%s/%s", namespace, name))
   member := consistentHashRing.LocateKey(key)  // Returns Member{ID: 2}
   ```

3. **Apply the label:**
   ```
   shard.operator.k8s.appscode.com/kubedb: "2"
   ```

**C. Cooperative Shard Migration (Optional):**

When `useCooperativeShardMigration: true`, the system uses a two-phase migration:

```go
if ifShardKeyLabelNeedsToBeChanged(labels, shardKey, member) {
    switch ri.UseCooperativeShardMigration {
    case true:
        // Don't immediately change the shard
        // Instead, set a "next" shard label
        labels[nextShardKey] = member.String()  // "next.operator.k8s.appscode.com/kubedb: 3"
    case false:
        // Immediately reassign
        labels[shardKey] = member.String()
    }
}
```

This allows operators to gracefully handle resources moving between shards.

---

### 4. **Each Operator Pod Reconciles Only Its Shard**

The operator implementation watches for resources and filters them based on the shard label.

**Two Implementation Strategies:**

#### Strategy 1: Label Selector (Memory Efficient)
```go
// In your operator's controller setup
labelSelector := labels.Set{
    fmt.Sprintf("shard.operator.k8s.appscode.com/%s", shardConfigName): myShardIndex,
}.AsSelector()

// Watch only resources in my shard
err := controller.Watch(
    source.Kind(cache, &myResource{},
        handler.EnqueueRequestsFromMapFunc(...),
        predicate.NewPredicateFuncs(func(obj client.Object) bool {
            return labelSelector.Matches(labels.Set(obj.GetLabels()))
        }),
    ),
)
```

**Important Caveat:** Missing from cache ≠ deleted! The resource might just be in a different shard.

#### Strategy 2: Watch All, Filter in Predicates (Better for Cross-References)
```go
// Watch all resources but skip reconciliation for non-assigned shards
predicate.NewPredicateFuncs(func(obj client.Object) bool {
    shardLabel := fmt.Sprintf("shard.operator.k8s.appscode.com/%s", shardConfigName)
    return obj.GetLabels()[shardLabel] == myShardIndex
})
```

This allows accessing referenced resources in other shards while only reconciling your own.

---

### 5. **Minimal Resource Movement During Scaling (Consistent Hashing)**

#### Why Consistent Hashing?

Traditional hashing: `shard = hash(key) % numShards`
- Problem: When `numShards` changes from 3 to 4, almost ALL resources get reassigned!

**Consistent Hashing with Bounded Load:**
- Uses a hash ring with virtual nodes (partitions)
- When scaling from 3 to 4 shards, only ~25% of resources move (ideally)
- Load balancing ensures no shard gets overloaded

#### Example Scaling Scenario:

**Before (3 shards):**
```
Resource A (hash=100) → Shard 0
Resource B (hash=200) → Shard 1
Resource C (hash=300) → Shard 2
Resource D (hash=400) → Shard 0
```

**After (4 shards with consistent hashing):**
```
Resource A (hash=100) → Shard 0  ✓ No change
Resource B (hash=200) → Shard 3  ✗ Moved
Resource C (hash=300) → Shard 2  ✓ No change
Resource D (hash=400) → Shard 0  ✓ No change
```

Only ~25% moved instead of ~75% with traditional hashing!

#### The Math Behind It (getBetterPartitionCount()):

The function selects a prime number slightly larger than `shardCount * load` to optimize distribution:
```go
func getBetterPartitionCount(members int, load float64) int {
    // Find prime number that gives best distribution
    // Uses list of precomputed primes (2, 3, 5, 7, ...)
    // Optimizes for minimal remainder when dividing partitions among shards
}
```

This ensures uniform distribution even with non-power-of-2 shard counts.

---

## Architecture Components

### Controller Reconciliation Flow

```
ShardConfiguration Created/Updated
         ↓
    Reconcile() triggered
         ↓
1. List pods for each controller → Assign indices [0,1,2,...]
         ↓
2. Update Status.Controllers with pod allocations
         ↓
3. Create consistent hash ring with shardCount members
         ↓
4. For each resource type in spec.resources:
   ├─ Discover GVK (GroupVersionKind)
   ├─ Register dynamic watcher for that resource type
   └─ List all instances and label them:
      └─ Extract key (namespace/name or custom JSONPath)
      └─ Hash key → Get shard index
      └─ Apply label: shard.{group}/{name}: "{index}"
         ↓
5. Resources now distributed across shards!
```

### Dynamic Resource Watching

The controller dynamically registers watchers for any resource type (lines 275-307):

```go
func (r *ShardConfigurationReconciler) RegisterResourceWatcher(gvk schema.GroupVersionKind) error {
    // Only register once per GroupKind
    if _, ok := r.resGKs[gvk.GroupKind()]; ok {
        return nil
    }
    
    // Create a watcher that triggers reconciliation when resources change
    var obj metav1.PartialObjectMetadata
    obj.SetGroupVersionKind(gvk)
    
    err := r.ctrl.Watch(
        source.Kind(r.cache, &obj, 
            handler.TypedEnqueueRequestsFromMapFunc(
                // When resource changes, re-reconcile all ShardConfigurations
                // that manage this resource type
            )
        )
    )
}
```

This means the shard manager automatically handles ANY Kubernetes resource type!

---

## Key Features Explained

### 1. **Finalizers for Safe Deletion**

The controller adds a finalizer to prevent deletion while controllers are using it:
```go
if cfg.DeletionTimestamp != nil {
    if shardCount <= 0 {
        // No controllers using it, safe to delete
        cfg.ObjectMeta = core_util.RemoveFinalizer(cfg.ObjectMeta, ...)
    } else {
        // Still in use, block deletion
        klog.Infof("Config %v is in use by %v. Can't delete it.", cfg.Name, cfg.Spec.Controllers)
    }
}
```

### 2. **Custom Shard Keys via JSONPath**

Instead of hashing `namespace/name`, you can use any field:
```yaml
resources:
- apiGroup: kubedb.com
  kind: PostgresBackup
  shardKey: ".spec.databaseRef.name"  # Group backups with their database
```

Evaluation happens in `EvaluateJSONPath()` (utils.go lines 104-158).

### 3. **Server-Preferred Resources Discovery**

The controller discovers all available resource types in an API group:
```go
resourceLists, err := r.d.ServerPreferredResources()
for _, resource := range cfg.Spec.Resources {
    if resource.Kind != "" {
        // Specific kind requested
    } else {
        // Discover all kinds in the API group
        for _, resourceList := range resourceLists {
            if gv.Group == resource.APIGroup {
                for _, apiResource := range resourceList.APIResources {
                    if isReadable(apiResource.Verbs) {
                        // Watch this resource type
                    }
                }
            }
        }
    }
}
```

---

## Status Tracking

The `Status.Controllers` field tracks pod assignments:
```yaml
status:
  controllers:
  - apiGroup: apps
    kind: Deployment
    name: kubedb-provisioner
    namespace: kubedb
    pods:
    - kubedb-provisioner-0
    - kubedb-provisioner-1
    - kubedb-provisioner-2
```

This allows operators to:
1. Know their own shard index (position in the pods list)
2. Know the total number of shards
3. Detect when resharding is happening

---

## Summary

The operator-shard-manager provides a **transparent sharding layer** for Kubernetes operators:

1. **Zero code changes** needed in managed resources
2. **Minimal operator changes** (just add label selectors/predicates)
3. **Elastic scaling** with minimal disruption
4. **Uniform distribution** via consistent hashing with bounded load
5. **Dynamic resource discovery** supports any Kubernetes resource
6. **Graceful migration** with cooperative mode

The key innovation is using **labels + consistent hashing** to create a stateless, declarative sharding system that works with any operator implementation!
