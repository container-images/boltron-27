#! /bin/sh

tmb=5m
tme=20m

if [ "x$1" != "x" ]; then
    tmb="$1"
fi

if [ "x$2" != "x" ]; then
    tme="$2"
fi

tm="$tmb"
while true; do

    if ./up-base-check.sh; then
        ./up-base.sh && \
        sudo make build && \
        sudo make push-james && \
        ./ping-ci.sh && \
        sudo make tests && \
        ./report.sh email
        tm="$tme"
    fi

    echo "Sleep for $tm: $(date --iso=minutes | tr T ' ')"
    sleep $tm
done
