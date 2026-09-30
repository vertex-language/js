#!/bin/sh
# run.sh runs the conformance cases in tests/cases against vjs and compares
# each one's stdout with tests/expected/<case>.out, produced by Node.
#
#     tests/run.sh               build vjs, run every case, print a summary
#     tests/run.sh 04 regexp     run only cases whose name contains a filter
#     tests/run.sh -v 068        also show a diff for each failure
#     tests/run.sh --update      regenerate tests/expected from Node (the oracle)
#
# Every case gets TIMEOUT seconds (default 10) before it counts as a hang.
set -u
cd "$(dirname "$0")"
TIMEOUT=${TIMEOUT:-10}
verbose=0
update=0
filters=""
for a in "$@"; do
  case "$a" in
    -v) verbose=1 ;;
    --update) update=1 ;;
    *) filters="$filters $a" ;;
  esac
done

selected() {
  [ -z "$filters" ] && return 0
  for flt in $filters; do case "$1" in *"$flt"*) return 0 ;; esac; done
  return 1
}

# runfor SECONDS CMD... runs CMD with a wall-clock limit (macOS has no timeout(1)).
runfor() { perl -e 'alarm shift; exec @ARGV or exit 127' "$@"; }

if [ $update = 1 ]; then
  n=0
  for f in cases/*.js; do
    name=$(basename "$f" .js)
    selected "$name" || continue
    node oracle.mjs "$f" > "expected/$name.out" || { echo "oracle rejected $name"; exit 1; }
    n=$((n + 1))
  done
  echo "wrote $n expected outputs"
  exit 0
fi

mkdir -p .build
echo "building vjs..."
(cd .. && vsc build -o tests/.build/vjs ./cmd/vjs) || { echo "vjs failed to build"; exit 1; }

pass=0; fail=0; failed=""
for f in cases/*.js; do
  name=$(basename "$f" .js)
  selected "$name" || continue
  runfor "$TIMEOUT" .build/vjs "$f" > ".build/$name.out" 2>&1
  status=$?
  if [ $status -eq 0 ] && cmp -s ".build/$name.out" "expected/$name.out"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1)); failed="$failed $name"
    if [ $status -eq 142 ]; then why="timeout"; elif [ $status -gt 128 ]; then why="crash ($status)"; elif [ $status -ne 0 ]; then why="exit $status"; else why="output differs"; fi
    echo "FAIL  $name  [$why]"
    if [ $verbose = 1 ]; then
      diff -u "expected/$name.out" ".build/$name.out" | sed -n '3,40p'
      echo
    fi
  fi
done
echo
echo "$pass passed, $fail failed, $((pass + fail)) total"
[ $fail -eq 0 ]
