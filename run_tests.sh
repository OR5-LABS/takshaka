#!/usr/bin/env bash
# run_tests.sh — run every test entry listed in tests/expected.txt and compare
# its exit code and PASS/FAIL verdict-line counts with the recorded baseline.
# Counting verdict lines as well as exit codes catches silent failures and
# silently dropped tests.
#
# An entry is "script" or "script:argument", e.g. "build.sh:priv" runs
# "bash build.sh priv". Lines ending in "# KNOWN: ..." are documented known
# failures (the recorded result is still compared exactly).
#
#   ./run_tests.sh             check against tests/expected.txt (CI mode)
#   ./run_tests.sh --baseline  re-record tests/expected.txt from this run
set -u
cd "$(dirname "$0")"
mkdir -p build/test-logs
mode="${1:-check}"

# entries recorded by --baseline, in run order
ENTRIES="build.sh:sim build.sh:cosim build.sh:rvfi build.sh:zcb build.sh:trig build.sh:debug
build.sh:priv build.sh:axi build.sh:fpga run_isa.sh"

count() {  # $1 = log -> "pass fail"
  local p f
  p=$(grep -aE '\bPASS(ED)?\b' "$1" | wc -l)
  f=$(grep -aE '\bFAIL(ED|URE|URES)?\b' "$1" | wc -l)
  echo "$p $f"
}

run_entry() {  # $1 = entry, $2 = log; returns the entry's exit code
  local script="${1%%:*}" arg=""
  [[ "$1" == *:* ]] && arg="${1#*:}"
  timeout 3600 bash "$script" $arg > "$2" 2>&1
}

logname() { echo "build/test-logs/$(echo "$1" | tr ':/' '__').log"; }

if [ "$mode" = "--baseline" ]; then
  : > tests/expected.txt.new
  for e in $ENTRIES; do
    log=$(logname "$e")
    run_entry "$e" "$log"; rc=$?
    read -r p f < <(count "$log")
    known=$(grep -E "^$e " tests/expected.txt 2>/dev/null | sed -n 's/.*# KNOWN: //p')
    printf '%s %s %s %s%s\n' "$e" "$rc" "$p" "$f" "${known:+ # KNOWN: $known}" | tee -a tests/expected.txt.new
  done
  mv tests/expected.txt.new tests/expected.txt
  exit 0
fi

status=0
while read -r e erc ep ef rest; do
  case "$e" in ''|\#*) continue ;; esac
  log=$(logname "$e")
  run_entry "$e" "$log"; rc=$?
  read -r p f < <(count "$log")
  known=$(echo "$rest" | sed -n 's/.*# KNOWN: //p')
  if [ "$rc" = "$erc" ] && [ "$p" = "$ep" ] && [ "$f" = "$ef" ]; then
    if [ -n "$known" ]; then echo "KNOWN   $e  ($known)"; else echo "PASS    $e"; fi
  else
    echo "FAIL    $e  exit=$rc (expected $erc)  PASS lines=$p (expected $ep)  FAIL lines=$f (expected $ef)  log: $log"
    status=1
  fi
done < tests/expected.txt
exit $status
