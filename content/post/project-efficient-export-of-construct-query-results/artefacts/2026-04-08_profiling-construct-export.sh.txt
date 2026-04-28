#!/usr/bin/env bash
set -euo pipefail

# Profiles the new CONSTRUCT export pipeline using perf + flamegraph.
# Produces two flamegraphs:
#   - construct_warm: query run after one warmup (OS page cache populated)
#   - construct_cold: query run after vmtouch -e eviction (cold OS page cache)


# Configuration
SERVER_BIN="/home/userNoPriv/code/qlever/qlever-code/build-0480d959-Profiling/qlever-server"
SERVER_PORT=7001
INDEX_DIR="/home/userNoPriv/code/qlever/qlever-indices/dblp"
INDEX_BASENAME="$INDEX_DIR/dblp"
SERVER_ARGS="-i $INDEX_BASENAME -p $SERVER_PORT --default-query-timeout 3600s"
OUTPUT_DIR="./profiles"
LOG_DIR="./logs"
WARMUP_WAIT=10 # seconds to wait for server to start

mkdir -p "$OUTPUT_DIR"
mkdir -p "$LOG_DIR"

CONSTRUCT_QUERY="CONSTRUCT { ?s ?p ?o } WHERE { ?s ?p ?o } LIMIT 10000000"

# ---------------------------------------------------------------------------
# start_server LOG_FILE  →  sets SERVER_PID
# ---------------------------------------------------------------------------
start_server() {
  local log="$1"

  if lsof -ti:"$SERVER_PORT" >/dev/null 2>&1; then
    lsof -ti:"$SERVER_PORT" | xargs kill -9
  fi
  local waited=0
  while lsof -ti:"$SERVER_PORT" >/dev/null 2>&1; do
    sleep 0.2
    (( waited++ ))
    if (( waited > 50 )); then
      echo "ERROR: port $SERVER_PORT still in use after 10 s" >&2; exit 1
    fi
  done

  "$SERVER_BIN" $SERVER_ARGS >"$log" 2>&1 &
  SERVER_PID=$!
  echo "Server started (PID $SERVER_PID), waiting $WARMUP_WAIT seconds..."
  sleep "$WARMUP_WAIT"
}

# ---------------------------------------------------------------------------
# stop_server
# ---------------------------------------------------------------------------
stop_server() {
  kill "$SERVER_PID" 2>/dev/null || true
  wait "$SERVER_PID" 2>/dev/null || true
  local waited=0
  while lsof -ti:"$SERVER_PORT" >/dev/null 2>&1; do
    sleep 0.2
    (( waited++ ))
    if (( waited > 50 )); then
      echo "ERROR: port $SERVER_PORT not released after 10 s" >&2; exit 1
    fi
  done
}

# ---------------------------------------------------------------------------
# evict_cache LABEL
# ---------------------------------------------------------------------------
evict_cache() {
  local label="$1"
  echo "Evicting index and vocabulary files from OS page cache..."
  echo "Pages resident before eviction:"
  vmtouch "$INDEX_DIR" | tee "$LOG_DIR/${label}_vmtouch_before.txt"
  vmtouch -e "$INDEX_DIR"
  echo "Pages resident after eviction:"
  vmtouch "$INDEX_DIR" | tee "$LOG_DIR/${label}_vmtouch_after.txt"
}

# ---------------------------------------------------------------------------
# run_profile LABEL WARM
#   LABEL: used for output file names
#   WARM:  "warm" populates the page cache first; "cold" evicts it first
# ---------------------------------------------------------------------------
run_profile() {
  local label="$1"
  local warm="$2"

  echo "=== Profiling: $label ==="

  if [ "$warm" = "warm" ]; then
    start_server "$LOG_DIR/${label}_warmup_server.log"
    echo "Warming cache..."
    curl -f -G "http://localhost:$SERVER_PORT/" \
      --data-urlencode "query=$CONSTRUCT_QUERY" \
      --data-urlencode "action=sparql_query" \
      >/dev/null
    stop_server
  else
    evict_cache "$label"
  fi

  # Start a fresh server for the profiled run
  start_server "$LOG_DIR/${label}_server.log"

  # Record with perf
  local perf_out="$OUTPUT_DIR/${label}.perf.data"
  perf record --call-graph fp --freq=997 -p "$SERVER_PID" -o "$perf_out" &
  PERF_PID=$!
  sleep 1 # give perf time to attach to all threads

  echo "Recording... sending query."
  curl -sf -X POST "http://localhost:$SERVER_PORT/query" \
    -H "Content-Type: application/sparql-query" \
    -H "Accept: text/tab-separated-values" \
    --data-binary "$CONSTRUCT_QUERY" \
    --max-time 3600 \
    >/dev/null

  kill -SIGINT "$PERF_PID"
  wait "$PERF_PID" 2>/dev/null || true

  # Generate flamegraph
  echo "Generating flamegraph..."
  perf script -i "$perf_out" \
    | stackcollapse-perf.pl \
    | flamegraph.pl \
    >"$OUTPUT_DIR/${label}.svg"

  echo "Flamegraph written to $OUTPUT_DIR/${label}.svg"

  stop_server
  echo ""
}

run_profile "construct_warm" "warm"
run_profile "construct_cold" "cold"

echo "All profiles complete. Results in $OUTPUT_DIR/"
