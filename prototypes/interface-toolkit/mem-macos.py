#!/usr/bin/env python3
"""PROTOTYPE measurement helper. Usage: mem-macos.py <pid>

Sums memory for an app process plus its WKWebView helpers (WebContent, Networking, GPU).
Those helpers are XPC services whose parent is launchd, so they are matched as: a
com.apple.WebKit.* process that started no earlier than the app and that macOS holds the
same process responsible for (private libSystem call
responsibility_get_pid_responsible_for_pid; for an app started from a terminal that is the
terminal, so do not run two prototypes from the same terminal at once while measuring).
Prints resident size (ps rss) and physical footprint (the `footprint` tool, the figure
Activity Monitor shows as Memory) per process and in total.
"""
import ctypes, re, subprocess, sys

root = int(sys.argv[1])
libc = ctypes.CDLL(None)
fn = libc.responsibility_get_pid_responsible_for_pid
fn.argtypes, fn.restype = [ctypes.c_int], ctypes.c_int
rows = subprocess.run(["ps", "-axo", "pid=,etime=,rss=,comm="], capture_output=True, text=True).stdout.splitlines()
def secs(t):  # [[dd-]hh:]mm:ss
    d, _, rest = t.rpartition("-")
    n = 0
    for part in rest.split(":"):
        n = n * 60 + int(part)
    return n + int(d or 0) * 86400
age = {int(r.split()[0]): secs(r.split()[1]) for r in rows}
total_rss = total_fp = 0
for row in rows:
    pid, _, rss, comm = row.split(None, 3)
    pid, rss = int(pid), int(rss)
    helper = "com.apple.WebKit." in comm and fn(pid) in (root, fn(root)) and age[pid] <= age[root] + 1
    if pid != root and not helper:
        continue
    out = subprocess.run(["footprint", str(pid)], capture_output=True, text=True).stdout
    m = re.search(r"Footprint:\s*([\d.]+)\s*(KB|MB|GB)", out)
    fp = float(m.group(1)) * {"KB": 1 / 1024, "MB": 1, "GB": 1024}[m.group(2)] if m else float("nan")
    total_rss += rss
    total_fp += fp
    print(f"{pid:>7} rss {rss / 1024:8.1f} MB  footprint {fp:8.1f} MB  {comm.rsplit('/', 1)[-1]}")
print(f"TOTAL   rss {total_rss / 1024:8.1f} MB  footprint {total_fp:8.1f} MB")
