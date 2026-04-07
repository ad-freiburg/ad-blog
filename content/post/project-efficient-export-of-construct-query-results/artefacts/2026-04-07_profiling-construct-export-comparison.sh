#!/usr/bin/env bash
set -euo pipefail

# Methodology:
#   - One warmup run per (format, limit) to load the index into the OS page cache.
#   - Then 5 timed runs, each with a fresh server instance (no QLever query cache).
#   - Timing is taken from the QLever server log:
#       "Done processing query and sending result, total time was XXX ms"
#   - Median of the 5 runs is reported.
#   - Results are printed as a Markdown table: old (ms) | new (ms) | speedup.
#
# Usage: $0 [OLD_SERVER_BIN [NEW_SERVER_BIN]]
# Defaults to pre-built binaries for af00534d (master) and 0480d959 (refactor).

BASE="/home/userNoPriv/code/qlever/qlever-code"
DEFAULT_OLD="$BASE/build-af00534d-release/qlever-server"
DEFAULT_NEW="$BASE/build-0480d959-Release/qlever-server"

OLD_SERVER_BIN="${1:-$DEFAULT_OLD}"
NEW_SERVER_BIN="${2:-$DEFAULT_NEW}"

SERVER_PORT=7001
INDEX_BASENAME="/home/userNoPriv/code/qlever/qlever-indices/dblp/dblp"
SERVER_ARGS="-i $INDEX_BASENAME -p $SERVER_PORT --default-query-timeout 3600s"

WARMUP_WAIT=10  # seconds to wait for the server to be ready
N_RUNS=5

LOG_DIR="./comparison-logs"
mkdir -p "$LOG_DIR"

# Format -> Accept header value
declare -A ACCEPT_HEADER=(
  [TSV]="text/tab-separated-values"
  [CSV]="text/csv"
  [qleverJson]="application/qlever-results+json"
  [Turtle]="text/turtle"
)

# Limits to test
LIMITS=(10000 10000000)

echo "Old binary: $OLD_SERVER_BIN"
echo "New binary: $NEW_SERVER_BIN"
echo ""

# ---------------------------------------------------------------------------
# start_server BIN LOG_FILE
#   Starts a fresh server, waits for it to be ready. Sets SERVER_PID.
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
# send_query FORMAT LIMIT
#   Sends a CONSTRUCT query in the given format/limit to the running server.
#   Discards the response body.
# ---------------------------------------------------------------------------
send_query() {
  local format="$1"
  local limit="$2"
  local accept="${ACCEPT_HEADER[$format]}"
  local query="CONSTRUCT { ?s ?p ?o } WHERE { ?s ?p ?o } LIMIT $limit"

  curl -sf -X POST "http://localhost:$SERVER_PORT/query" \
    -H "Content-Type: application/sparql-query" \
    -H "Accept: $accept" \
    --data-binary "$query" \
    --max-time 3600 \
    >/dev/null
}

# ---------------------------------------------------------------------------
# extract_last_time LOG_FILE
#   Greps for QLever's timing log line and prints the last ms value found.
#   Handles comma-formatted numbers like "22,864".
# ---------------------------------------------------------------------------
extract_last_time() {
  local log="$1"
  grep -oP 'total time was \K[0-9,]+(?= ms)' "$log" | tail -1 | tr -d ','
}

# ---------------------------------------------------------------------------
# median NUMBERS...
#   Prints the median of the given integers.
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
# measure_median BIN LABEL FORMAT LIMIT
#   Runs N_RUNS timed queries (each with a fresh server) and returns the
#   median time. The first call to this function for a given (format, limit)
#   pair should be the warmup (using run_warmup instead).
# ---------------------------------------------------------------------------
measure_median() {
  local bin="$1"
  local label="$2"
  local format="$3"
  local limit="$4"

  local times=()
  for run in $(seq 1 "$N_RUNS"); do
    local log="$LOG_DIR/${label}_${format}_${limit}_run${run}.log"
    start_server "$bin" "$log"
    send_query "$format" "$limit"
    local t
    t=$(extract_last_time "$log")
    stop_server
    if [[ -z "$t" ]]; then
      echo "  run $run: ERROR – timing not found in $log" >&2
      echo "  last lines of log:" >&2
      tail -5 "$log" >&2
      exit 1
    fi
    times+=("$t")
    echo "  run $run: ${t} ms" >&2
  done

  median "${times[@]}"
}

# ---------------------------------------------------------------------------
# run_warmup BIN FORMAT LIMIT
#   Runs a single warmup query to load the index into the OS page cache.
#   The server is stopped afterwards; the page cache survives the restart.
# ---------------------------------------------------------------------------
run_warmup() {
  local bin="$1"
  local format="$2"
  local limit="$3"
  local log="$LOG_DIR/warmup_${format}_${limit}.log"

  echo "  warmup (${format}, LIMIT ${limit})..." >&2
  start_server "$bin" "$log"
  send_query "$format" "$limit"
  stop_server
}

# ===========================================================================
# Main measurement loop
# ===========================================================================

# Collect results into parallel arrays for table printing
declare -a ROW_FORMAT ROW_LIMIT ROW_OLD ROW_NEW

row=0
for format in TSV CSV qleverJson Turtle; do
  for limit in "${LIMITS[@]}"; do
    echo "=== Format: $format | LIMIT: $limit ==="

    # Warmup with the OLD binary (loads the index into OS page cache; the
    # page cache is shared across binaries since the index files are the same).
    run_warmup "$OLD_SERVER_BIN" "$format" "$limit"

    echo "  measuring OLD..." >&2
    old_ms=$(measure_median "$OLD_SERVER_BIN" "old" "$format" "$limit")

    echo "  measuring NEW..." >&2
    new_ms=$(measure_median "$NEW_SERVER_BIN" "new" "$format" "$limit")

    ROW_FORMAT[$row]="$format"
    ROW_LIMIT[$row]="$limit"
    ROW_OLD[$row]="$old_ms"
    ROW_NEW[$row]="$new_ms"
    (( row++ )) || true

    echo "  -> old=${old_ms} ms  new=${new_ms} ms" >&2
    echo ""
  done
done

# ===========================================================================
# Print Markdown table
# ===========================================================================

echo ""
echo "| Format     | Limit | Old (ms) | New (ms) | Speedup |"
echo "|------------|-------|----------|----------|---------|"

for (( i = 0; i < row; i++ )); do
  fmt="${ROW_FORMAT[$i]}"
  lim="${ROW_LIMIT[$i]}"
  old="${ROW_OLD[$i]}"
  new="${ROW_NEW[$i]}"

  # Format limit as 10k or 10M
  if (( lim == 10000 )); then
    lim_str="10k"
  else
    lim_str="10M"
  fi

  # Speedup ratio (old/new, higher = new is faster), printed to 2 decimal places
  speedup=$(awk "BEGIN { printf \"%.2fx\", $old / $new }")

  printf "| %-10s | %-5s | %-8s | %-8s | %-7s |\n" \
    "$fmt" "$lim_str" "$old" "$new" "$speedup"
done
