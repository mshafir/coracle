# PROTOTYPE, throwaway. Coracle issue #10.
PKGS = gtk4 libadwaita-1 webkitgtk-6.0
CFLAGS ?= -O2 -Wall -Wno-unused-parameter

coracle-gtk4: main.c
	$(CC) $(CFLAGS) $$(pkg-config --cflags $(PKGS)) -o $@ main.c $$(pkg-config --libs $(PKGS))

run: coracle-gtk4
	./coracle-gtk4

.PHONY: run
