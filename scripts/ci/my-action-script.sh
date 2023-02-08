#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

case "$CRTOOLS_SCRIPT_ACTION" in
    pre-dump)
        cat /proc/$CRTOOLS_INIT_PID/cmdline | tr '\000' ' ' && echo
        ls -l /proc/$CRTOOLS_INIT_PID/map_files
        for f in /proc/$CRTOOLS_INIT_PID/map_files/*
        do
            echo ===
            stat $f
            echo ---
            stat -L $f || true
            echo ---
            stat $(readlink $f) || true
            echo ===
        done
        ;;
    *)
        ;;
esac
