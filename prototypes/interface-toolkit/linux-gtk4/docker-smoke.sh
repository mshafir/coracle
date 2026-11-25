#!/bin/sh
# PROTOTYPE. Build the image once, then build and smoke-test the GTK 4 prototype headlessly.
# Usage: ./docker-smoke.sh            (env: PROTO_LIVE_TABS, PROTO_ACTIONS, WAIT, SHOT are passed through)
set -e
cd "$(dirname "$0")"
docker build -q -t coracle-gtk4-proto . >/dev/null
docker run --rm -v "$PWD/..":/work -e PROTO_LIVE_TABS -e PROTO_ACTIONS -e PROTO_ACTIONS_DELAY -e WAIT -e SHOT -e GSK_RENDERER \
  coracle-gtk4-proto sh /work/linux-gtk4/headless.sh
