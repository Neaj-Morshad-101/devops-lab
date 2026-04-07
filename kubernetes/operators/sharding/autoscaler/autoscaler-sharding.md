# Sharding KubeDB Autoscaler Resources - Complete Guide

This guide provides **step-by-step instructions** for sharding KubeDB autoscaler resources (`MSSQLServerAutoscaler`, `PostgresAutoscaler`, etc.) across multiple operator pods.

---

## Table of Contents

1. [Overview](#overview)
2. [What Needs to Be Changed?](#what-needs-to-be-changed)
3. [Quick Start (TL;DR)](#quick-start-tldr)
4. [Step-by-Step Guide](#step-by-step-guide)
5. [Operator Code Integration](#operator-code-integration)
6. [Configuration Options](#configuration-options)
7. [Scaling Operations](#scaling-operations)
8. [Monitoring and Troubleshooting](#monitoring-and-troubleshooting)
9. [Best Practices](#best-practices)
10. [Supported Autoscaler Types](#supported-autoscaler-types)
11. [Summary](#summary)

---

## Overview

KubeDB autoscaler resources (e.g., `MSSQLServerAutoscaler`, `PostgresAutoscaler`, `MongoDBAutoscaler`) can be sharded across multiple operator pods to distribute the reconciliation workload. The operator-shard-manager automatically labels each autoscaler CR with a shard index, and operator pods filter resources based on their assigned shard.

### Prerequisites

1. **operator-shard-manager** deployed in your cluster
2. **KubeDB autoscaler operator** (or ops-manager) running with multiple replicas
3. Autoscaler CRDs installed (`autoscaling.kubedb.com` API group)

---

## What Needs to Be Changed?

### ✅ **NO CHANGES NEEDED** in:
1. **Autoscaler CRs themselves** - They remain unchanged
2. **CRD definitions** - No modifications required
3. **operator-shard-manager** - Already supports autoscaler resources

### 🔧 **CHANGES REQUIRED** in:
1. **ShardConfiguration CR** - Add autoscaler resources
2. **Operator StatefulSet** - Add POD_NAME environment variable (if not present)
3. **Operator code** - Add shard filtering logic (one-time change)

---

## Quick Start (TL;DR)

### 1. Create ShardConfiguration (5 minutes)

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
    # Omitting 'kind' shards ALL autoscaler types

---

apiVersion: operator.k8s.appscode.com/v1alpha1
kind: ShardConfiguration
metadata:
  name: kubedb-autoscaler
spec:
  controllers:
  - apiGroup: apps
    kind: StatefulSet
    name: kubedb-autoscaler
    namespace: kubedb
  resources:
  - apiGroup: autoscaling.kubedb.com
    # Omitting 'kind' shards ALL autoscaler types
```

Apply it:
```bash
kubectl apply -f shardconfiguration.yaml
```

### 2. Scale Operator (1 minute)

```bash
kubectl scale StatefulSet kubedb-kubedb-autoscaler -n kubedb --replicas=3
```

### 3. Add POD_NAME to StatefulSet (2 minutes)

```yaml
env:
- name: POD_NAME
  valueFrom:
    fieldRef:
      fieldPath: metadata.name
- name: SHARD_CONFIG_NAME
  value: "kubedb-autoscaler"
```

### 4. Add Shard Filtering to Operator Code (30 minutes)

**Step 4a:** Copy `hack/examples/shard-helper.go` to your operator repo as `pkg/shard/helper.go`

**Step 4b:** Update controller setup:

```go
// Get shard index
myShardIndex, err := shard.GetMyShardIndex(ctx, mgr.GetClient(), shardConfigName)

// Add predicate to controller
ctrl.NewControllerManagedBy(mgr).
    For(&autoscalingv1alpha1.MSSQLServerAutoscaler{}).
    WithEventFilter(shard.NewShardPredicate(shardConfigName, myShardIndex)).
    Complete(reconciler)
```

**Step 4c:** Verify in reconciler:

```go
func (r *Reconciler) Reconcile(ctx context.Context, req reconcile.Request) (reconcile.Result, error) {
    var autoscaler autoscalingv1alpha1.MSSQLServerAutoscaler
    if err := r.Get(ctx, req.NamespacedName, &autoscaler); err != nil {
        if apierrors.IsNotFound(err) {
            return reconcile.Result{}, nil  // Might be in different shard
        }
        return reconcile.Result{}, err
    }
    
    // Double-check shard assignment
    if !shard.IsMyResource(&autoscaler, r.ShardConfigName, r.MyShardIndex) {
        return reconcile.Result{}, nil
    }
    
    // ... your reconciliation logic ...
}
```

### Verification Commands

```bash
# Check ShardConfiguration status
kubectl get shardconfiguration kubedb-autoscaler -o yaml

# Verify autoscalers are labeled
kubectl get mssqlserverautoscaler -A --show-labels

# Check distribution across shards
for i in 0 1 2; do
  echo "Shard $i:"
  kubectl get autoscaling.kubedb.com -A \
    -l "shard.operator.k8s.appscode.com/kubedb-autoscaler=$i" --no-headers | wc -l
done

# Check operator logs
kubectl logs -n kubedb kubedb-kubedb-autoscaler-0 | grep shard
```

---

## Step-by-Step Guide

### Step 1: Create ShardConfiguration for Autoscalers

Create a `ShardConfiguration` that specifies:
- Which **operator StatefulSet** to shard (e.g., `kubedb-kubedb-autoscaler`)
- Which **autoscaler resources** to distribute

#### Example Configuration

```yaml
apiVersion: operator.k8s.appscode.com/v1alpha1
kind: ShardConfiguration
metadata:
  name: kubedb-autoscaler
spec:
  # The operator StatefulSet that manages autoscalers
  controllers:
  - apiGroup: apps
    kind: StatefulSet
    name: kubedb-kubedb-autoscaler  # Your autoscaler operator name
    namespace: kubedb
  
  # The autoscaler resources to shard
  resources:
  - apiGroup: autoscaling.kubedb.com
    # Leaving 'kind' empty shards ALL autoscaler types automatically
    # This includes: MSSQLServerAutoscaler, PostgresAutoscaler, 
    # MongoDBAutoscaler, MySQLAutoscaler, etc.
```

### Step 2: Scale the Autoscaler Operator

Scale your autoscaler operator to multiple replicas:

```bash
# Scale to 3 replicas (creates 3 shards)
kubectl scale StatefulSet kubedb-kubedb-autoscaler -n kubedb --replicas=3
```

Wait for all pods to be running:
```bash
kubectl get pods -n kubedb -l app=kubedb-kubedb-autoscaler
```

Expected output:
```
NAME                               READY   STATUS    RESTARTS   AGE
kubedb-kubedb-autoscaler-0                1/1     Running   0          1m
kubedb-kubedb-autoscaler-1                1/1     Running   0          1m
kubedb-kubedb-autoscaler-2                1/1     Running   0          1m
```

### Step 3: Apply the ShardConfiguration

```bash
kubectl apply -f autoscaler-shardconfiguration.yaml
```

Verify it's working:
```bash
kubectl get shardconfiguration kubedb-autoscaler -o yaml
```

Expected status:
```yaml
status:
  phase: Current
  controllers:
  - apiGroup: apps
    kind: StatefulSet
    name: kubedb-kubedb-autoscaler
    namespace: kubedb
    pods:
    - kubedb-kubedb-autoscaler-0
    - kubedb-kubedb-autoscaler-1
    - kubedb-kubedb-autoscaler-2
```

### Step 4: Verify Autoscaler Resources Are Labeled

The shard manager automatically labels all autoscaler resources:

```bash
# Check MSSQLServerAutoscalers
kubectl get mssqlserverautoscaler -A --show-labels

# Check PostgresAutoscalers
kubectl get postgresautoscaler -A --show-labels

# Check all autoscalers in a namespace
kubectl get autoscaling.kubedb.com -n demo --show-labels
```

Expected labels:
```
NAME                    LABELS
mssql-autoscaler-1      shard.operator.k8s.appscode.com/kubedb-autoscaler=0
mssql-autoscaler-2      shard.operator.k8s.appscode.com/kubedb-autoscaler=1
pg-autoscaler-1         shard.operator.k8s.appscode.com/kubedb-autoscaler=2
pg-autoscaler-2         shard.operator.k8s.appscode.com/kubedb-autoscaler=0
```

---

## Operator Code Integration

Your autoscaler operator needs to filter resources by shard label. Here's how:

### A. Add POD_NAME Environment Variable to StatefulSet

Edit your operator StatefulSet:

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: kubedb-kubedb-autoscaler
  namespace: kubedb
spec:
  replicas: 3
  template:
    spec:
      containers:
      - name: autoscaler
        image: your-autoscaler-image:latest
        env:
        # ADD THIS ENVIRONMENT VARIABLE
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        # ADD THIS IF NOT PRESENT
        - name: SHARD_CONFIG_NAME
          value: "kubedb-autoscaler"
```

### B. Create Shard Helper Package

Create a new file `pkg/shard/helper.go`:

```go
package shard

import (
	"context"
	"fmt"
	"os"
	"strconv"

	shardapi "kubeops.dev/operator-shard-manager/api/v1alpha1"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/predicate"
)

// GetMyShardIndex returns the shard index for the current pod
func GetMyShardIndex(ctx context.Context, kc client.Client, shardConfigName string) (string, error) {
	var cfg shardapi.ShardConfiguration
	err := kc.Get(ctx, client.ObjectKey{Name: shardConfigName}, &cfg)
	if err != nil {
		return "", err
	}

	podName := os.Getenv("POD_NAME")
	if podName == "" {
		return "", fmt.Errorf("POD_NAME environment variable not set")
	}

	for _, ctrl := range cfg.Status.Controllers {
		for idx, pod := range ctrl.Pods {
			if pod == podName {
				return strconv.Itoa(idx), nil
			}
		}
	}

	return "", fmt.Errorf("pod %s not found in shard configuration %s", podName, shardConfigName)
}

// NewShardPredicate creates a predicate that filters resources by shard label
func NewShardPredicate(shardConfigName, myShardIndex string) predicate.Predicate {
	shardLabel := fmt.Sprintf("shard.operator.k8s.appscode.com/%s", shardConfigName)

	return predicate.NewPredicateFuncs(func(obj client.Object) bool {
		labels := obj.GetLabels()
		if labels == nil {
			// Resources without labels are not yet sharded, skip them
			return false
		}
		return labels[shardLabel] == myShardIndex
	})
}

// IsMyResource checks if a resource belongs to my shard
func IsMyResource(obj client.Object, shardConfigName, myShardIndex string) bool {
	shardLabel := fmt.Sprintf("shard.operator.k8s.appscode.com/%s", shardConfigName)
	labels := obj.GetLabels()
	if labels == nil {
		return false
	}
	return labels[shardLabel] == myShardIndex
}
```

### C. Update Controller Setup to Use Shard Filtering

Modify your autoscaler controller setup (typically in `pkg/controller/setup.go` or `main.go`):

```go
package main

import (
	"context"
	"os"
	
	autoscalingv1alpha1 "kubedb.dev/apimachinery/apis/autoscaling/v1alpha1"
	"your-module/pkg/controller"
	"your-module/pkg/shard"
	
	ctrl "sigs.k8s.io/controller-runtime"
)

func main() {
	// ... existing manager setup ...
	
	mgr, err := ctrl.NewManager(ctrl.GetConfigOrDie(), ctrl.Options{
		// ... existing options ...
	})
	if err != nil {
		panic(err)
	}
	
	// Get shard configuration name from environment
	shardConfigName := os.Getenv("SHARD_CONFIG_NAME")
	if shardConfigName == "" {
		// If not sharding, use empty string
		shardConfigName = ""
	}
	
	// Get my shard index
	var myShardIndex string
	if shardConfigName != "" {
		myShardIndex, err = shard.GetMyShardIndex(context.Background(), mgr.GetClient(), shardConfigName)
		if err != nil {
			log.Error(err, "Failed to get shard index, running without sharding")
			shardConfigName = "" // Disable sharding
		} else {
			log.Info("Running with shard configuration", "config", shardConfigName, "shard", myShardIndex)
		}
	}
	
	// Setup controllers with shard filtering
	if err := setupAutoscalerControllers(mgr, shardConfigName, myShardIndex); err != nil {
		panic(err)
	}
	
	// ... start manager ...
}

func setupAutoscalerControllers(mgr ctrl.Manager, shardConfigName, myShardIndex string) error {
	// Create shard predicate
	var shardPred predicate.Predicate
	if shardConfigName != "" {
		shardPred = shard.NewShardPredicate(shardConfigName, myShardIndex)
	} else {
		// No sharding, accept all resources
		shardPred = predicate.NewPredicateFuncs(func(obj client.Object) bool {
			return true
		})
	}
	
	// Setup MSSQLServerAutoscaler controller
	if err := ctrl.NewControllerManagedBy(mgr).
		For(&autoscalingv1alpha1.MSSQLServerAutoscaler{}).
		WithEventFilter(shardPred).  // ADD THIS LINE
		Complete(&controller.MSSQLServerAutoscalerReconciler{
			Client:          mgr.GetClient(),
			ShardConfigName: shardConfigName,
			MyShardIndex:    myShardIndex,
		}); err != nil {
		return err
	}
	
	// Setup PostgresAutoscaler controller
	if err := ctrl.NewControllerManagedBy(mgr).
		For(&autoscalingv1alpha1.PostgresAutoscaler{}).
		WithEventFilter(shardPred).  // ADD THIS LINE
		Complete(&controller.PostgresAutoscalerReconciler{
			Client:          mgr.GetClient(),
			ShardConfigName: shardConfigName,
			MyShardIndex:    myShardIndex,
		}); err != nil {
		return err
	}
	
	// Repeat for all autoscaler types...
	
	return nil
}
```

### D. Update Reconciler to Verify Shard Assignment

In your reconciler (e.g., `pkg/controller/mssqlserver_autoscaler_controller.go`):

```go
package controller

import (
	"context"
	
	autoscalingv1alpha1 "kubedb.dev/apimachinery/apis/autoscaling/v1alpha1"
	"your-module/pkg/shard"
	
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/reconcile"
)

type MSSQLServerAutoscalerReconciler struct {
	client.Client
	ShardConfigName string
	MyShardIndex    string
}

func (r *MSSQLServerAutoscalerReconciler) Reconcile(ctx context.Context, req reconcile.Request) (reconcile.Result, error) {
	// Fetch the autoscaler
	var autoscaler autoscalingv1alpha1.MSSQLServerAutoscaler
	err := r.Get(ctx, req.NamespacedName, &autoscaler)
	if err != nil {
		if apierrors.IsNotFound(err) {
			// IMPORTANT: Don't assume deletion!
			// The resource might be in a different shard
			return reconcile.Result{}, nil
		}
		return reconcile.Result{}, err
	}
	
	// Verify it belongs to our shard (double-check)
	if r.ShardConfigName != "" {
		if !shard.IsMyResource(&autoscaler, r.ShardConfigName, r.MyShardIndex) {
			// Resource moved to different shard or not yet labeled
			return reconcile.Result{}, nil
		}
	}
	
	// Proceed with normal reconciliation
	// ... your existing reconciliation logic ...
	
	return reconcile.Result{}, nil
}
```

---

## Configuration Options

### Option 1: Shard All Autoscaler Resources (Recommended)

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
    # No kind specified = shard ALL kinds in this API group
```

**Benefits:**
- Simple configuration
- Automatically handles all autoscaler types
- Works with future autoscaler CRs without configuration changes

### Option 2: Shard Specific Autoscaler Kinds

```yaml
resources:
- apiGroup: autoscaling.kubedb.com
  kind: MSSQLServerAutoscaler
- apiGroup: autoscaling.kubedb.com
  kind: PostgresAutoscaler
- apiGroup: autoscaling.kubedb.com
  kind: MongoDBAutoscaler
- apiGroup: autoscaling.kubedb.com
  kind: MySQLAutoscaler
```

**Use Case:** You only run specific database types and want explicit control.

### Option 3: Use Custom Shard Key (Advanced)

Group autoscalers with their target databases on the same shard:

```yaml
resources:
- apiGroup: autoscaling.kubedb.com
  kind: PostgresAutoscaler
  shardKey: ".spec.databaseRef.name"
  useCooperativeShardMigration: true
- apiGroup: autoscaling.kubedb.com
  kind: MSSQLServerAutoscaler
  shardKey: ".spec.databaseRef.name"
  useCooperativeShardMigration: true
```

**How it works:**
- Instead of hashing `{namespace}/{name}` of the autoscaler, it hashes `{namespace}/{databaseRef.name}`
- If database `demo/my-postgres` is on shard 2, its autoscaler will also be on shard 2

**Benefits:**
- Reduces cross-shard references
- Autoscaler and database managed by the same operator pod
- More efficient cache usage


---

## Scaling Operations

### Scaling Up (3 → 5 replicas)

```bash
kubectl scale StatefulSet kubedb-kubedb-autoscaler -n kubedb --replicas=5
```

**What happens:**
1. New pods start: `kubedb-kubedb-autoscaler-3`, `kubedb-kubedb-autoscaler-4`
2. Shard manager detects new pods and updates `Status.Controllers`
3. **~20% of autoscalers** are relabeled (from shards 0-2 to shards 3-4)
4. Each pod now manages ~20% of the total autoscalers

**Consistent hashing ensures minimal resource movement!**

### Scaling Down (5 → 3 replicas)

```bash
kubectl scale StatefulSet kubedb-kubedb-autoscaler -n kubedb --replicas=3
```

**What happens:**
1. Pods `kubedb-kubedb-autoscaler-3` and `kubedb-kubedb-autoscaler-4` terminate
2. Their autoscalers are relabeled and distributed to shards 0-2
3. Existing autoscalers on shards 0-2 mostly stay put

### Cooperative Shard Migration

When `useCooperativeShardMigration: true`, resources get a "next shard" label during resharding:

```yaml
labels:
  shard.operator.k8s.appscode.com/kubedb-autoscaler: "1"        # Current shard
  next.operator.k8s.appscode.com/kubedb-autoscaler: "3"         # Moving to shard 3
```

**Operator behavior:**
1. Pod on shard 1 continues managing the autoscaler
2. Pod on shard 3 sees the "next" label and prepares to take over
3. After graceful handoff, the main label changes to "3"

This prevents reconciliation gaps during resharding.

---

## Monitoring and Troubleshooting

### Check Shard Distribution

```bash
# Count autoscalers per shard
for i in 0 1 2; do
  echo "Shard $i:"
  kubectl get postgresautoscaler -A -l "shard.operator.k8s.appscode.com/kubedb-autoscaler=$i" | wc -l
done
```

### Verify Operator Pod is Watching Correct Shard

Check operator logs for shard index:

```bash
kubectl logs -n kubedb kubedb-kubedb-autoscaler-0 | grep -i shard
```

### Check Operator Logs

```bash
# Check that each pod knows its shard index
kubectl logs -n kubedb kubedb-kubedb-autoscaler-0 | grep -i shard
kubectl logs -n kubedb kubedb-kubedb-autoscaler-1 | grep -i shard
kubectl logs -n kubedb kubedb-kubedb-autoscaler-2 | grep -i shard
```

Expected output:
```
Running with shard configuration config=kubedb-autoscaler shard=0
Running with shard configuration config=kubedb-autoscaler shard=1
Running with shard configuration config=kubedb-autoscaler shard=2
```

### Force Relabeling

If labels are missing or incorrect:

```bash
# Delete and recreate the ShardConfiguration
kubectl delete shardconfiguration kubedb-autoscaler
kubectl apply -f hack/samples/autoscaler-shardconfiguration.yaml
```

The shard manager will relabel all autoscalers.

---

## Best Practices

1. **Use the same shard count for related resources:**
   - If databases are on 3 shards, use 3 shards for autoscalers
   - Consider using custom `shardKey` to co-locate them

2. **Enable cooperative migration for production:**
   ```yaml
   useCooperativeShardMigration: true
   ```

3. **Monitor shard balance:**
   - Ensure autoscalers are evenly distributed
   - Check for hot spots in specific shards

4. **Plan scaling operations:**
   - Scale during low-traffic periods
   - Expect brief reconciliation delays during resharding

5. **Set POD_NAME environment variable in operator StatefulSet:**
   ```yaml
   env:
   - name: POD_NAME
     valueFrom:
       fieldRef:
         fieldPath: metadata.name
   ```

6. **Handle missing resources correctly:**
   ⚠️ **Important:** A missing autoscaler from cache does NOT mean it was deleted! It might be in a different shard.

---

## Supported Autoscaler Types

All KubeDB autoscaler CRs in `autoscaling.kubedb.com` are supported:

| Autoscaler Kind | Supported |
|-----------------|-----------|
| DruidAutoscaler | ✅ |
| ElasticsearchAutoscaler | ✅ |
| FerretDBAutoscaler | ✅ |
| KafkaAutoscaler | ✅ |
| MariaDBAutoscaler | ✅ |
| MemcachedAutoscaler | ✅ |
| MongoDBAutoscaler | ✅ |
| **MSSQLServerAutoscaler** | ✅ |
| MySQLAutoscaler | ✅ |
| PerconaXtraDBAutoscaler | ✅ |
| PgBouncerAutoscaler | ✅ |
| PgpoolAutoscaler | ✅ |
| **PostgresAutoscaler** | ✅ |
| ProxySQLAutoscaler | ✅ |
| RabbitMQAutoscaler | ✅ |
| RedisAutoscaler | ✅ |
| RedisSentinelAutoscaler | ✅ |
| SinglestoreAutoscaler | ✅ |
| SolrAutoscaler | ✅ |
| ZooKeeperAutoscaler | ✅ |

**All work with the same ShardConfiguration!**

---

## Summary

### What You Need to Change

| Component | Change Required | Effort |
|-----------|----------------|--------|
| Autoscaler CRs | ❌ None | N/A |
| CRDs | ❌ None | N/A |
| operator-shard-manager | ❌ None | N/A |
| ShardConfiguration CR | ✅ Create new | 5 min |
| Operator StatefulSet | ✅ Add POD_NAME env var | 2 min |
| Operator Code | ✅ Add shard filtering | 30 min |

### What Happens Automatically

✅ operator-shard-manager discovers all autoscaler CRs  
✅ Labels them: `shard.operator.k8s.appscode.com/kubedb-autoscaler: "0"`  
✅ Distributes evenly using consistent hashing  
✅ Watches for new autoscalers and labels them immediately  
✅ Handles scaling with minimal resource movement  

### Benefits

✅ **Horizontal scaling** - Scale autoscaler operator to handle more resources  
✅ **Better performance** - Each pod manages fewer autoscalers  
✅ **Fault isolation** - Issues in one shard don't affect others  
✅ **Minimal disruption** - Consistent hashing ensures smooth scaling  
✅ **Zero downtime** - Resources continue being managed during resharding  

The operator-shard-manager does the heavy lifting of resource distribution and labeling!

---

## Files Reference

| File | Description |
|------|-------------|
| `hack/samples/autoscaler-shardconfiguration.yaml` | Ready-to-use ShardConfiguration example |
| `hack/samples/autoscaler-examples.yaml` | Sample autoscaler CRs |
| `hack/examples/shard-helper.go` | Helper code for operator integration |
