# Recommender Sharding Implementation - Detailed Guide

## What Was Changed

### The Problem
The **recommender** component runs a periodic loop (`RunOnce` every 1 minute) that lists **all** autoscaler objects cluster-wide via `ListVPAs()` and `ListCheckpoints()`. Without shard filtering, every operator pod processes every autoscaler object — defeating the purpose of sharding.

### The Solution
Thread a shard-based **label selector** (`client.MatchingLabels`) from the operator entrypoint down to every `kbClient.List()` call in the recommender's data pipeline. This filters autoscaler objects **server-side** (at the API server) so each pod only fetches objects assigned to its shard.

---

## Data Flow (How Shard Filtering Reaches the List Calls)

```
operator.go (shardConfig string = "kubedb-autoscaler")
    │
    ├── WaitForShardIdUpdate()  ← waits until shard manager labels this pod
    │
    └── recommender.New(..., shardConfig)
            │
            ├── resolveMyShardIndex(kc, shardConfig)
            │       ├── HOSTNAME env → "kubedb-kubedb-autoscaler-1"
            │       ├── FindHeadOfLineage(kc) → StatefulSet owner
            │       ├── GetPodListsFromShardConfig(kc, head, "kubedb-autoscaler")
            │       │     → ["...-0", "...-1", "...-2"]
            │       └── Returns "1" (index of this pod)
            │
            ├── shardLabelKey = "shard.operator.k8s.appscode.com/kubedb-autoscaler"
            ├── shardListOpts = [MatchingLabels{"shard.operator.k8s.appscode.com/kubedb-autoscaler": "1"}]
            │
            └── routines.NewRecommender(..., shardListOpts...)
                    │
                    └── input.NewClusterStateFeeder(..., shardListOpts...)
                            │
                            ├── clusterStateFeeder.shardListOpts = shardListOpts
                            │
                            ├── LoadVPAs()
                            │     └── ic.ListVPAs(kc, shardListOpts...)
                            │           ├── ListVPAsForMSSQLServer(kc, opts...)
                            │           │     └── kbClient.List(ctx, &list, opts...)  ← FILTERED!
                            │           ├── ListVPAsForPostgres(kc, opts...)
                            │           │     └── kbClient.List(ctx, &list, opts...)  ← FILTERED!
                            │           └── ... (all 23 DB types)
                            │
                            ├── InitFromCheckpoints() / GarbageCollectCheckpoints()
                            │     └── ic.ListCheckpoints(kc, ns, shardListOpts...)
                            │           ├── listCheckpointsForMSSQLServer(kc, ns, opts...)
                            │           │     └── kbClient.List(ctx, &list, append([InNamespace(ns)], opts...)...)
                            │           └── ... (all 22 DB types)
                            │
                            └── LoadPods() / LoadRealTimeMetrics()
                                  └── (unchanged — pods are matched via VPA selectors,
                                       so only pods for our shard's VPAs are processed)
```

---

## Files Modified (28 files total)

### 1. `pkg/cmds/server/operator.go` (entrypoint)
- **Enabled** `WaitForShardIdUpdate()` for the recommender (was commented out)
- **Passes** `s.shardConfig` to `recommender.New()`

### 2. `pkg/recommender/controller.go` (recommender factory)
- `New()` now accepts `shardConfig string` parameter
- Added `resolveMyShardIndex()` — resolves this pod's shard index from ShardConfiguration
- Computes `shardListOpts` = `client.MatchingLabels{"shard.operator.k8s.appscode.com/<config>": "<index>"}`
- Passes `shardListOpts` to `routines.NewRecommender()`

### 3. `pkg/recommender/routines/recommender.go` (recommender loop)
- `RecommenderFactory` gains `ShardListOpts []client.ListOption`
- `NewRecommender()` accepts `shardListOpts ...client.ListOption`, passes to `input.NewClusterStateFeeder()`

### 4. `pkg/recommender/input/cluster_feeder.go` (VPA/checkpoint loading)
- `ClusterStateFeederFactory` gains `ShardListOpts []client.ListOption`
- `clusterStateFeeder` gains `shardListOpts []client.ListOption`
- `NewClusterStateFeeder()` accepts `shardListOpts ...client.ListOption`
- `LoadVPAs()` → `ic.ListVPAs(kc, feeder.shardListOpts...)`
- `InitFromCheckpoints()` → `ic.ListCheckpoints(kc, ns, feeder.shardListOpts...)`
- `GarbageCollectCheckpoints()` → `ic.ListCheckpoints(kc, ns, feeder.shardListOpts...)`

### 5. `pkg/internal/client/api.go` (aggregator functions)
- `ListVPAs(kc, opts ...client.ListOption)` — passes opts to all `ListVPAsFor*()` calls
- `ListCheckpoints(kc, ns, opts ...client.ListOption)` — passes opts to all `listCheckpointsFor*()` calls

### 6. All 23 per-DB files (e.g., `mssqlserver.go`, `postgres.go`, etc.)
- `ListVPAsFor*(kc, opts ...client.ListOption)` → `kbClient.List(ctx, &list, opts...)`
- `listCheckpointsFor*(kc, ns, opts ...client.ListOption)` → `kbClient.List(ctx, &list, append([]client.ListOption{client.InNamespace(ns)}, opts...)...)`

---

## How It Works End-to-End

### Without Sharding (`shardConfig = ""`)
- `shardListOpts` is `nil`
- All `List()` calls use no label selector → **all objects returned** (backward compatible)

### With Sharding (`shardConfig = "kubedb-autoscaler"`)

1. **operator-shard-manager** labels every autoscaler CR:
   ```
   shard.operator.k8s.appscode.com/kubedb-autoscaler: "1"
   ```

2. **At startup**: `WaitForShardIdUpdate()` blocks until the shard manager has registered this pod

3. **`resolveMyShardIndex()`**: Reads `HOSTNAME` (e.g., `kubedb-kubedb-autoscaler-1`), finds it at index 1 in the ShardConfiguration status → returns `"1"`

4. **Label selector** is built: `shard.operator.k8s.appscode.com/kubedb-autoscaler=1`

5. **Every `RunOnce()` cycle**: 
   - `LoadVPAs()` lists only autoscalers with label `=1`
   - `LoadPods()` only processes pods matching those VPAs
   - `LoadRealTimeMetrics()` only collects metrics for those pods
   - `UpdateVPAs()` only computes recommendations for those VPAs
   - `MaintainCheckpoints()` only stores/GCs checkpoints for those VPAs

### Result with 3 pods:
| Pod | Shard Index | Processes |
|-----|------------|-----------|
| `kubedb-kubedb-autoscaler-0` | 0 | ~33% of autoscalers |
| `kubedb-kubedb-autoscaler-1` | 1 | ~33% of autoscalers |
| `kubedb-kubedb-autoscaler-2` | 2 | ~33% of autoscalers |

---

## Key Design Decisions

1. **Server-side filtering** via `client.MatchingLabels` — more efficient than post-filtering, API server does the work
2. **`...client.ListOption` variadic** — backward compatible, no extra arg when sharding is disabled
3. **Shard index resolved once at startup** — not on every `RunOnce()` cycle, avoiding repeated API calls
4. **Same `shardConfig` shared** between controller (predicates) and recommender (list opts) — both filter the same way
