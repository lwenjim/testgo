#!/bin/bash
# shellcheck disable=SC2206 disable=SC2068 disable=SC2086

if abc >/dev/null 2>&1; then
    echo ok
else
    echo "a$?a"
fi
