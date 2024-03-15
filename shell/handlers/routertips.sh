#! /usr/bin/env bash
# shellcheck disable=SC2206,2068,2086,1091,2317,1090,2090,2089,2059,2046

function routertips() {
    curl -H 'Content-Type:multipart/form-data; boundary=----WebKitFormBoundaryrGKCBY7qhFd3TrwA' -d ${SHELL_FOLDER/../bin/parseurl } localhost:10087/tips_heartbeat
}