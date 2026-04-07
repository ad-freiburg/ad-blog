#!/usr/bin/env bash
set -euo pipefail

# Extended version of 2026-03-25_profiling-construct-export.sh.
# Reproduces the Problem Statement table and adds:
#   - A third column for the new CONSTRUCT implementation (0480d959).
#   - A 10M-row tier alongside the existing 10k / 100k / 1M tiers.
#
# Methodology (same as Problem Statement):
#   - One warmup run per (format, limit) to populate the OS page cache.
#   - Five timed runs, each with a fresh server instance (no QLever query cache).
#   - Timing from the QLever server log:
#       "Done processing query and sending result, total time was X ms"
#   - Median of the five runs is reported.

# Configuration
OLD_SERVER_BIN="/home/userNoPriv/code/qlever/qlever-code/build-af00534d-release/qlever-server"
NEW_SERVER_BIN="/home/userNoPriv/code/qlever/qlever-code/build-0480d959-Release/qlever-server"

SERVER_PORT=7001
INDEX_BASENAME="/home/userNoPriv/code/qlever/qlever-indices/dblp/dblp"
SERVER_ARGS="-i $INDEX_BASENAME -p $SERVER_PORT --default-query-timeout 3600s"

WARMUP_WAIT=10  # seconds to wait for the server to be ready
N_RUNS=5

LOG_DIR="./timing-logs"
mkdir -p "$LOG_DIR"

LIMITS=(10000 100000 1000000 10000000)

# ---------------------------------------------------------------------------
# Accept headers for each format
# ---------------------------------------------------------------------------
declare -A ACCEPT=(
  [TSV]="text/tab-separated-values"
  [CSV]="text/csv"
  [qleverJson]="application/qlever-results+json"
  [Turtle]="text/turtle"
)

# ---------------------------------------------------------------------------
# start_server BIN LOG_FILE  →  sets SERVER_PID
# ---------------------------------------------------------------------------
start_server() {
  local bin="$1"
  local log="$2"

  # Kill anything on the port and wait until the port is actually free.
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

  "$bin" $SERVER_ARGS >"$log" 2>&1 &
  SERVER_PID=$!
  sleep "$WARMUP_WAIT"
}

# ---------------------------------------------------------------------------
# stop_server
# ---------------------------------------------------------------------------
stop_server() {
  kill "$SERVER_PID" 2>/dev/null || true
  wait "$SERVER_PID" 2>/dev/null || true
  # Wait until the port is released before returning.
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
# send_query FORMAT QUERY
# ---------------------------------------------------------------------------
send_query() {
  local format="$1"
  local query="$2"
  curl -sf -X POST "http://localhost:$SERVER_PORT/query" \
    -H "Content-Type: application/sparql-query" \
    -H "Accept: ${ACCEPT[$format]}" \
    --data-binary "$query" \
    --max-time 3600 \
    >/dev/null
}

# ---------------------------------------------------------------------------
# extract_last_time LOG_FILE
#   Handles comma-formatted numbers like "22,864".
# ---------------------------------------------------------------------------
extract_last_time() {
  local log="$1"
  grep -oP 'total time was \K[0-9,]+(?= ms)' "$log" | tail -1 | tr -d ','
}

# ---------------------------------------------------------------------------
# median NUMBERS...
# ---------------------------------------------------------------------------
median() {
  local sorted
  sorted=($(printf '%s\n' "$@" | sort -n))
  local n="${#sorted[@]}"
  local mid=$(( n / 2 ))
  if (( n % 2 == 1 )); then
    echo "${sorted[$mid]}"
  else
    echo $(( (sorted[$mid - 1] + sorted[$mid]) / 2 ))
  fi
}

# ---------------------------------------------------------------------------
# measure BIN LABEL FORMAT QUERY  →  prints median ms
#   Runs N_RUNS timed queries, each with a fresh server. Assumes the index is
#   already in the OS page cache from a prior warmup run.
# ---------------------------------------------------------------------------
measure() {
  local bin="$1"
  local label="$2"
  local format="$3"
  local query="$4"

  local times=()
  for run in $(seq 1 "$N_RUNS"); do
    local log="$LOG_DIR/${label}_run${run}.log"
    start_server "$bin" "$log"
    send_query "$format" "$query"
    local t
    t=$(extract_last_time "$log")
    stop_server

    if [[ -z "$t" ]]; then
      echo "  ERROR: timing not found in $log" >&2
      tail -5 "$log" >&2
      exit 1
    fi
    times+=("$t")
    echo "    run $run: ${t} ms" >&2
  done

  median "${times[@]}"
}

# ---------------------------------------------------------------------------
# warmup FORMAT QUERY
#   One run with the old binary to load the index into the OS page cache.
#   The page cache persists across server restarts and is shared between
#   both binaries (they use the same index files).
# ---------------------------------------------------------------------------
warmup() {
  local bin="$1"
  local label="$2"
  local format="$3"
  local query="$4"
  local log="$LOG_DIR/warmup_${label}.log"

  echo "  warmup..." >&2
  start_server "$bin" "$log"
  send_query "$format" "$query"
  stop_server
}

# ---------------------------------------------------------------------------
# ratio OLD NEW  →  "X.XXx"
# ---------------------------------------------------------------------------
ratio() {
  awk "BEGIN { printf \"%.2fx\", $1 / $2 }"
}

# ===========================================================================
# Main
# ===========================================================================

echo "Old binary: $OLD_SERVER_BIN"
echo "New binary: $NEW_SERVER_BIN"
echo ""

# Accumulate table rows
declare -a R_FMT R_LIMIT R_SEL R_OLD R_NEW

row=0
for format in TSV CSV qleverJson Turtle; do
  for limit in "${LIMITS[@]}"; do
    select_query="SELECT ?s ?p ?o WHERE { ?s ?p ?o } LIMIT $limit"
    construct_query="CONSTRUCT { ?s ?p ?o } WHERE { ?s ?p ?o } LIMIT $limit"

    echo "=== $format | LIMIT $limit ==="

    # SELECT — only measured for formats that support it (not Turtle).
    if [[ "$format" == "Turtle" ]]; then
      sel_ms="n/a"
      echo "  SELECT: not supported for Turtle" >&2
    else
      echo "  SELECT (old binary):" >&2
      warmup "$OLD_SERVER_BIN" "${format}_${limit}_select" "$format" "$select_query"
      sel_ms=$(measure "$OLD_SERVER_BIN" "${format}_${limit}_select" "$format" "$select_query")
    fi

    # CONSTRUCT — old implementation.
    echo "  CONSTRUCT old:" >&2
    warmup "$OLD_SERVER_BIN" "${format}_${limit}_construct_old" "$format" "$construct_query"
    old_ms=$(measure "$OLD_SERVER_BIN" "${format}_${limit}_construct_old" "$format" "$construct_query")

    # CONSTRUCT — new implementation.
    echo "  CONSTRUCT new:" >&2
    warmup "$NEW_SERVER_BIN" "${format}_${limit}_construct_new" "$format" "$construct_query"
    new_ms=$(measure "$NEW_SERVER_BIN" "${format}_${limit}_construct_new" "$format" "$construct_query")

    R_FMT[$row]="$format"
    R_LIMIT[$row]="$limit"
    R_SEL[$row]="$sel_ms"
    R_OLD[$row]="$old_ms"
    R_NEW[$row]="$new_ms"
    (( row++ )) || true

    echo "" >&2
  done
done

# ---------------------------------------------------------------------------
# Print Markdown table
# ---------------------------------------------------------------------------

echo ""
echo "| Format     | Limit | SELECT (ms) | CONSTRUCT old (ms) | CONSTRUCT new (ms) | Old ratio | New ratio | Speedup |"
echo "|------------|-------|-------------|--------------------|--------------------|-----------|-----------|---------|"

for (( i = 0; i < row; i++ )); do
  fmt="${R_FMT[$i]}"
  lim="${R_LIMIT[$i]}"
  sel="${R_SEL[$i]}"
  old="${R_OLD[$i]}"
  new="${R_NEW[$i]}"

  case "$lim" in
    10000)    lim_str="10k"  ;;
    100000)   lim_str="100k" ;;
    1000000)  lim_str="1M"   ;;
    10000000) lim_str="10M"  ;;
    *)        lim_str="$lim" ;;
  esac

  if [[ "$sel" == "n/a" ]]; then
    old_ratio="n/a"
    new_ratio="n/a"
  else
    old_ratio=$(ratio "$old" "$sel")
    new_ratio=$(ratio "$new" "$sel")
  fi
  speedup=$(ratio "$old" "$new")

  printf "| %-10s | %-5s | %-11s | %-18s | %-18s | %-9s | %-9s | %-7s |\n" \
    "$fmt" "$lim_str" "$sel" "$old" "$new" "$old_ratio" "$new_ratio" "$speedup"
done
