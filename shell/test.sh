#!/usr/bin/env bash
# shellcheck disable=SC2206 disable=SC2068 disable=SC2086 disable=SC1091 disable=SC2317 disable=SC1090 disable=SC2090 disable=SC2089 disable=SC2059

declare -A arr=(
  [a]=123
)

echo ${arr["a"]}
