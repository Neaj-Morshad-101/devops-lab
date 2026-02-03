# MSSQLServerAutoscaler Shard-Based Filtering - How It Works

## Summary of Changes Made

### 1. `pkg/cmds/server/operator.go`

**Added `shardConfig` to `controllerInfo`:**
```go
type controllerInfo struct {
    kbClient       client.Client
    ctx            context.Context
    updateInterval time.Duration
    promConfig     storage.PrometheusConfig
    recorder       record.EventRecorder
    auditor        *auditlib.EventPublisher
    shardConfig    string  // NEW: Added for shard-based filtering
}
```

**Pass `shardConfig` when creating `controllerInfo`:**
```go
cf := controllerInfo{
    // ... other fields ...
    shardConfig:    s.shardConfig,  // NEW: Passed from OperatorOptions
}
```

**Updated `addMSSQLServerManager` to pass `Config` with `ShardConfig`:**
```go
func (c controllerInfo) addMSSQLServerManager(mgr manager.Manager) *mssqlserver.Reconciler {
    ms := &mssqlserver.Reconciler{
        Client: c.kbClient,
        Config: &amc.Config{
            ShardConfig: c.shardConfig,  // NEW: Pass shard config
        },
        // ... other fields ...
    }
    // ...
}
```

### 2. `pkg/controller/mssqlserver/controller.go`

**Already has the correct implementation:**
```go
type Reconciler struct {
    client.Client
    *amc.Config  // Embeds Config which has ShardConfig
    // ...
}

func (r *Reconciler) SetupWithManager(mgr ctrl.Manager) error {
    // Create predicator with shard config
    p := utils.NewPredicator(r.Client, schema.GroupVersionKind{
        Group:   dbapi.SchemeGroupVersion.Group,
        Version: dbapi.SchemeGroupVersion.Version,
        Kind:    dbapi.ResourceKindMSSQLServer,
    }, r.ShardConfig, nil)  // r.ShardConfig comes from embedded *amc.Config

    return ctrl.NewControllerManagedBy(mgr).
        // Apply shard predicate to For()
        For(&autoscaling.MSSQLServerAutoscaler{}, 
            builder.ForOption(builder.WithPredicates(p.GetPredicateFuncsForDatabase()))).
        // Apply shard predicate to Owns()
        Owns(&opsapi.MSSQLServerOpsRequest{}, 
            builder.OwnsOption(builder.WithPredicates(p.GetPredicateFuncsForOwnerObjects()))).
        Complete(r)
}
```

---

## How Shard Filtering Works - Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    SHARD-BASED FILTERING FLOW                               │
└─────────────────────────────────────────────────────────────────────────────┘

1. STARTUP
   ┌────────────────────────────────────────────────────────────────────────┐
   │  Operator Pod Starts (e.g., kubedb-kubedb-autoscaler-1)               │
   │                                                                        │
   │  • HOSTNAME env = "kubedb-kubedb-autoscaler-1"                        │
   │  • shardConfig = "kubedb-autoscaler" (from --shard-config flag)       │
   └────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
2. CONTROLLER SETUP
   ┌────────────────────────────────────────────────────────────────────────┐
   │  addMSSQLServerManager() creates Reconciler with:                      │
   │                                                                        │
   │  ms := &mssqlserver.Reconciler{                                        │
   │      Config: &amc.Config{                                              │
   │          ShardConfig: "kubedb-autoscaler",                             │
   │      },                                                                │
   │  }                                                                     │
   └────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
3. PREDICATOR CREATION
   ┌────────────────────────────────────────────────────────────────────────┐
   │  SetupWithManager() creates predicator:                                │
   │                                                                        │
   │  p := utils.NewPredicator(client, gvk, "kubedb-autoscaler", nil)      │
   │                                                                        │
   │  This predicator will filter events based on shard labels!            │
   └────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
4. EVENT FILTERING (GetPredicateFuncsForDatabase)
   ┌────────────────────────────────────────────────────────────────────────┐
   │  When MSSQLServerAutoscaler event occurs (Create/Update/Delete):       │
   │                                                                        │
   │  CreateFunc/UpdateFunc/DeleteFunc:                                     │
   │    └── ShouldEnqueueObjectForShard(client, shardConfig, labels)        │
   │          │                                                             │
   │          ├── If shardConfig == "" → return true (no filtering)         │
   │          │                                                             │
   │          └── If shardConfig != "" → Check shard label                  │
   │                │                                                       │
   │                ├── ExtractShardKeyFromLabels()                         │
   │                │   Label: "shard.operator.k8s.appscode.com/kubedb-autoscaler"
   │                │   Value: "1" (shard index)                            │
   │                │                                                       │
   │                └── ShouldReconcileByShard()                            │
   │                    └── isShardIdAndHostnameMatched()                   │
   │                        • Get HOSTNAME env (e.g., "kubedb-autoscaler-1")│
   │                        • Extract pod index from hostname → 1           │
   │                        • Compare: shardId == podIndex?                 │
   │                          - "1" == "1" → TRUE (reconcile)               │
   │                          - "0" == "1" → FALSE (skip)                   │
   └────────────────────────────────────────────────────────────────────────┘

```

---

## Detailed Filtering Logic

### `ShouldEnqueueObjectForShard` (from vendor)

```go
func ShouldEnqueueObjectForShard(kbClient client.Client, shardConfig string, labels map[string]string) bool {
    // No shard config = process all resources
    if shardConfig == "" {
        return true
    }
    
    // Get shard ID from resource labels
    // Label key: "shard.operator.k8s.appscode.com/{shardConfigName}"
    // Example: "shard.operator.k8s.appscode.com/kubedb-autoscaler" = "1"
    shardId := ExtractShardKeyFromLabels(labels, shardConfig)
    if shardId == "" {
        return false  // Resource not labeled yet, skip
    }
    
    // Check if this pod should handle this shard
    requeue, _ := ShouldReconcileByShard(kbClient, shardConfig, shardId)
    return requeue
}
```

### `isShardIdAndHostnameMatched` (from vendor)

```go
func isShardIdAndHostnameMatched(shardId string, pods []string) bool {
    hostName := os.Getenv("HOSTNAME")  // e.g., "kubedb-kubedb-autoscaler-1"
    
    for i, pod := range pods {
        // pods = ["kubedb-kubedb-autoscaler-0", "kubedb-kubedb-autoscaler-1", "kubedb-kubedb-autoscaler-2"]
        // If HOSTNAME matches pod at index i, and shardId == i, return true
        if pod == hostName && strconv.Itoa(i) == shardId {
            return true
        }
    }
    return false
}
```

---

## Example Scenario

### Setup
- 3 operator pods: `kubedb-kubedb-autoscaler-0`, `kubedb-kubedb-autoscaler-1`, `kubedb-kubedb-autoscaler-2`
- ShardConfiguration: `kubedb-autoscaler`

### Resource Distribution

| MSSQLServerAutoscaler | Shard Label Value | Processed By |
|-----------------------|-------------------|--------------|
| `mssql-scaler-a` | `shard.../kubedb-autoscaler=0` | Pod-0 |
| `mssql-scaler-b` | `shard.../kubedb-autoscaler=1` | Pod-1 |
| `mssql-scaler-c` | `shard.../kubedb-autoscaler=2` | Pod-2 |
| `mssql-scaler-d` | `shard.../kubedb-autoscaler=0` | Pod-0 |

### What Happens When `mssql-scaler-b` is Updated

1. **All 3 pods** receive the update event from informer
2. **Pod-0** (`HOSTNAME=kubedb-kubedb-autoscaler-0`):
   - Checks label: shard ID = "1"
   - Compares: pod index (0) ≠ shard ID (1)
   - **Result: SKIP** (predicate returns `false`)
   
3. **Pod-1** (`HOSTNAME=kubedb-kubedb-autoscaler-1`):
   - Checks label: shard ID = "1"
   - Compares: pod index (1) == shard ID (1)
   - **Result: RECONCILE** (predicate returns `true`)
   
4. **Pod-2** (`HOSTNAME=kubedb-kubedb-autoscaler-2`):
   - Checks label: shard ID = "1"
   - Compares: pod index (2) ≠ shard ID (1)
   - **Result: SKIP** (predicate returns `false`)

---

## Configuration Required

### 1. Default ShardConfig (already set)

In `NewOperatorOptions()`:
```go
shardConfig: "kubedb-autoscaler",  // Default value
```

### 2. ShardConfiguration CR (deploy this)

```yaml
apiVersion: operator.k8s.appscode.com/v1alpha1
kind: ShardConfiguration
metadata:
  name: kubedb-autoscaler
spec:
  controllers:
  - apiGroup: apps
    kind: StatefulSet
    name: kubedb-kubedb-autoscaler
    namespace: kubedb
  resources:
  - apiGroup: autoscaling.kubedb.com
    # All autoscaler types
```

### 3. Scale Operator

```bash
kubectl scale StatefulSet kubedb-kubedb-autoscaler -n kubedb --replicas=3
```

---

## Verification

```bash
# Check autoscaler labels
kubectl get mssqlserverautoscaler -A --show-labels

# Expected output:
# NAME              LABELS
# mssql-scaler-1    shard.operator.k8s.appscode.com/kubedb-autoscaler=0
# mssql-scaler-2    shard.operator.k8s.appscode.com/kubedb-autoscaler=1

# Check which pod handles which shard
kubectl logs kubedb-kubedb-autoscaler-0 -n kubedb | grep -i "reconcil"
kubectl logs kubedb-kubedb-autoscaler-1 -n kubedb | grep -i "reconcil"
```
