#! /bin/sh -e

if [ ! -f latest-Fedora-Modular-27.COMPOSE_ID ]; then
    echo No known latest mod.
    exit 1
fi

if [ ! -f prev-Fedora-Modular-27.COMPOSE_ID ]; then
    echo No known prev mod.
    exit 1
fi

tests="test-$(cat latest-Fedora-Modular-27.COMPOSE_ID)"
otests="test-$(cat prev-Fedora-Modular-27.COMPOSE_ID)"

diff -u $otests/mods $tests/mods
