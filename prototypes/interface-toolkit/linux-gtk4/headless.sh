#!/bin/sh
# PROTOTYPE. Runs INSIDE the container (see docker-smoke.sh): builds, starts the prototype on a headless
# software-rendered X server, takes a screenshot and prints memory. Proves it compiles, starts and loads
# pages. Says nothing about feel: no GPU, no compositor, no Wayland.
set -e
cd /work/linux-gtk4
make -B
export DISPLAY=:99 GDK_BACKEND=x11 LIBGL_ALWAYS_SOFTWARE=1 NO_AT_BRIDGE=1
export WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1   # bubblewrap cannot nest inside an unprivileged container
Xvfb :99 -screen 0 1280x820x24 >/dev/null 2>&1 &
sleep 1
dbus-run-session -- ./coracle-gtk4 > /tmp/app.log 2>&1 &
sleep "${WAIT:-30}"
[ -n "$SHOT" ] && import -window root "/work/screenshots/$SHOT" && echo "screenshot: $SHOT"
echo "--- memory (kB): Rss and Pss from /proc/<pid>/smaps_rollup"
total_rss=0; total_pss=0
for pid in $(pgrep -f 'coracle-gtk4|WebKitWebProcess|WebKitNetworkProcess|WebKitGPUProcess'); do
  [ -r /proc/$pid/smaps_rollup ] || continue
  rss=$(awk '/^Rss:/{print $2}' /proc/$pid/smaps_rollup); pss=$(awk '/^Pss:/{print $2}' /proc/$pid/smaps_rollup)
  [ -n "$rss" ] || continue
  echo "$pid rss=$rss pss=$pss $(cat /proc/$pid/comm)"
  total_rss=$((total_rss + rss)); total_pss=$((total_pss + pss))
done
echo "TOTAL rss_MB=$((total_rss / 1024)) pss_MB=$((total_pss / 1024))"
echo "--- app output"
cat /tmp/app.log
