#! /bin/sh

while true; do

    if ./up-base-check.sh; then
        ./up-base.sh && \
        sudo make build push-james tests && \
        ./report.sh email
    fi

    echo "Sleep for 20m: $(date --iso=minutes | tr T ' ')"
    sleep 20m
done
