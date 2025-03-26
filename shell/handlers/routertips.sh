#! /usr/bin/env bash

function routertips() {
    curl -H 'Content-Type:multipart/form-data; boundary=----WebKitFormBoundaryrGKCBY7qhFd3TrwA' -d ${SHELL_FOLDER/../bin/parseurl } localhost:10087/tips_heartbeat
}
