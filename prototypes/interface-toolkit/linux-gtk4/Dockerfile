# PROTOTYPE. Build-and-smoke-test container only: proves the GTK 4 prototype compiles
# and starts under a headless X server. Feel cannot be judged here.
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential pkg-config libgtk-4-dev libadwaita-1-dev libwebkitgtk-6.0-dev \
    glib-networking gsettings-desktop-schemas adwaita-icon-theme fonts-dejavu-core \
    ca-certificates dbus dbus-x11 xvfb xauth x11-utils xdotool imagemagick procps \
    libgl1-mesa-dri libegl1 libgles2 bubblewrap xdg-dbus-proxy \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /src
