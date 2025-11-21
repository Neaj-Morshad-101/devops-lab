#!/usr/bin/env bash
set -eu

# mssql-restart-uid-count.sh
# Count pod creations using Pod UID (minimal snapshots, no full yamls, no operator logs)
#
# Usage:
#   ./mssql-restart-uid-count.sh
# Environment overrides:
#   N, NAMESPACE, DB_NAME, POD_PREFIX, OPS_KIND, OPS_API_VERSION
#   OPS_TIMEOUT, WAIT_BETWEEN, SNAP_INTERVAL

N="${N:-100}"     # number of OpsRequests to run
NAMESPACE="${NAMESPACE:-demo}"
DB_NAME="${DB_NAME:-ms-cluster}" # Name of DB database CR
POD_PREFIX="${POD_PREFIX:-${DB_NAME}}"
OPS_KIND="${OPS_KIND:-MSSQLServerOpsRequest}"
OPS_API_VERSION="${OPS_API_VERSION:-ops.kubedb.com/v1alpha1}"
OPS_TIMEOUT="${OPS_TIMEOUT:-600}" # max wait for OpsRequest success
WAIT_BETWEEN="${WAIT_BETWEEN:-0}" # seconds to sleep after each OpsRequest
SNAP_INTERVAL="${SNAP_INTERVAL:-2}"  # seconds between continuous pod snapshots


OUTDIR="./mssql-restart-uid-output"
mkdir -p "$OUTDIR/snapshots"


command -v kubectl >/dev/null 2>&1 || { echo "kubectl required"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq required"; exit 1; }

echo "Config: N=$N NAMESPACE=$NAMESPACE DB_NAME=$DB_NAME POD_PREFIX=$POD_PREFIX"
echo "Minimal snapshots will be saved to: $OUTDIR/snapshots"



# take a minimal snapshot (CSV lines: name,uid)
take_snapshot() {
  local label="$1"   # e.g. iter-0 or ops-mssqlops-restart-5-<epoch>
  local out="$OUTDIR/snapshots/$label.csv"
  kubectl get pods -n "$NAMESPACE" -o json \
    | jq -r --arg prefix "$POD_PREFIX" '.items
        | map(select(.metadata.name | startswith($prefix)))
        | .[] | [.metadata.name, .metadata.uid] | @csv' \
    > "$out"
}


# poll and snapshot while an OpsRequest is running
poll_while_running() {
  local opsname="$1"
  local timeout="$2"
  local ns="$3"
  local start_time=$(date +%s)
  local end_time=$((start_time + timeout))

  while [ "$(date +%s)" -lt "$end_time" ]; do
    ts=$(date +%s)
    take_snapshot "ops-${opsname}-${ts}"
    # check ops status
    status_json=$(kubectl get -n "$ns" "$OPS_KIND" "$opsname" -o json 2>/dev/null || true)
    phase=$(echo "$status_json" | jq -r '.status.phase // empty')
    conds=$(echo "$status_json" | jq -r '.status.conditions // [] | map(select(.type=="Successful" and (.status=="True" or .status=="Succeeded"))) | length')
    if [ "$phase" = "Successful" ] || [ "$conds" -ne 0 ]; then
      # final snapshot after success to capture immediate recreation
      take_snapshot "ops-${opsname}-final-$(date +%s)"
      return 0
    fi
    sleep "$SNAP_INTERVAL"
  done

  # timeout: take one final snapshot
  take_snapshot "ops-${opsname}-timeout-$(date +%s)"
  return 1
}



# initial baseline
take_snapshot "iter-0-$(date +%s)"


# main loop: create opsrequests and poll
for i in $(seq 1 "$N"); do


  opsname="mssqlops-restart-$i"
  echo "[$i/$N] preparing $opsname"

  # --- Take snapshot BEFORE creating OpsRequest ---
  ts=$(date +%s)
  take_snapshot "ops-${opsname}-before-create-${ts}"

  echo "[$i/$N] creating $opsname"
  cat <<EOF | kubectl apply -n "$NAMESPACE" -f -
apiVersion: ${OPS_API_VERSION}
kind: ${OPS_KIND}
metadata:
  name: ${opsname}
  namespace: ${NAMESPACE}
spec:
  type: Restart
  databaseRef:
    name: ${DB_NAME}
EOF

  if ! poll_while_running "$opsname" "$OPS_TIMEOUT" "$NAMESPACE"; then
    echo "WARNING: $opsname timed out after ${OPS_TIMEOUT}s (snapshot taken). Continuing."
  fi

  sleep "$WAIT_BETWEEN"


done

echo "All OpsRequests applied. Aggregating UID counts..."




# aggregate unique UIDs per pod
AGG="$OUTDIR/pod-uid-aggregate.txt"
: > "$AGG"
# read every snapshot csv and record unique uid per pod in awk
awk -F, '
{
  gsub(/"/,"",$0);
  pod=$1; uid=$2;
  key = pod "||" uid;
  if (!(key in seen)) {
    seen[key]=1;
    pods[pod]++;
  }
}
END {
  for (p in pods) {
    print p "," pods[p];
  }
}
' "$OUTDIR/snapshots/"*.csv | sort > "$AGG"

# print results: pod -> total creations (UID count)
echo "Pod creations (unique UIDs per pod):"
column -t -s, "$AGG" | while IFS=, read -r pod cnt; do
  echo "$pod: $cnt"
done

# expected creations = 1 (initial) + N (one per OpsRequest)
echo
echo "Expected creations per pod (if one recreation per OpsRequest): $((1 + N))"
echo
echo "Results saved to: $OUTDIR (snapshots and $AGG)"
echo "Done."
