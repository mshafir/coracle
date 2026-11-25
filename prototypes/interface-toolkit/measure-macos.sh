#!/bin/bash
# PROTOTYPE measurement script. Usage: ./measure-macos.sh macos-appkit|macos-swiftui
# Prints launch time (5 runs), memory with 1 and with 10 live tabs, and main-thread pacing for the
# scripted steps. Run one prototype at a time, with nothing else of ours open. See README for what each
# number does and does not mean.
set -e
cd "$(dirname "$0")"
DIR=$1
(cd "$DIR" && swift build -c release 2>&1 | tail -1)
BIN=$(cd "$DIR" && swift build -c release --show-bin-path)/$(grep -o 'name: "[A-Za-z]*"' "$DIR/Package.swift" | head -1 | cut -d'"' -f2)
SHOTS="$PWD/screenshots"

echo "== launch to first frame, ms (process start to first committed layout/display pass)"
for i in 1 2 3 4 5; do PROTO_ACTIONS=quit PROTO_ACTIONS_DELAY=2 "$BIN" 2>/dev/null | grep FIRST_FRAME; done

for n in 1 10; do
  echo "== memory with $n live tab(s), 45 s after launch"
  PROTO_LIVE_TABS=$n "$BIN" >/dev/null 2>&1 &
  pid=$!
  sleep 45
  ./mem-macos.py $pid
  kill $pid; wait $pid 2>/dev/null || true
  sleep 2
done

echo "== scripted steps and main-thread pacing"
PROTO_ACTIONS="snap=$SHOTS/$DIR.png,folder,folder,space1,space0,stress,scroll,snap=$SHOTS/$DIR-stress.png,heavy,resize,collapse,collapse,quit" \
  "$BIN" 2>/dev/null | grep -E "STRESS|PACING|SCROLL|SNAPSHOT"
