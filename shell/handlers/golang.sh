#! /usr/bin/env bash
# shellcheck disable=SC2206,2068,2086,1091,2317,1090,2090,2089,2059,2046,2162,2236

function icurl() {
    param="
    t:,content-type:,
    "
    contentType=
    url=
    param=$(echo "$param" | tr -d '\n')
    args=$(getopt -o ht: -l "$param" -n "$0" -- "$@" __)
    eval set -- "${args}"
    echo $args
    while true; do
        case "$1" in
        -t | --content-type)        
            shift
            contentType=$1
            shift
            ;;
        -p | --pipe)
            shift
            shift
            ;;
        --)
            shift
            url=$2
            ;;
        __ | *)
            shift         
            break
            ;;
        esac
    done

    case "${contentType}" in
        "application/json")
            data=$($SHELL_FOLDER/../bin/json-convert "application/json")
            curl \
            -H 'Content-Type: application/json' \
            -H "Content-Length: ${#data}" \
            -d "${data}" \
            $url
        ;;
        "application/x-www-form-urlencoded")
            data=$($SHELL_FOLDER/../bin/json-convert "application/x-www-form-urlencoded")
            curl \
            -H 'Content-Type: application/x-www-form-urlencoded' \
            -H "Content-Length: ${#data}" \
            -d "${data}" \
            $url
        ;;
        "multipart/form-data")
            data=$($SHELL_FOLDER/../bin/json-convert 'multipart/form-data' 'WebAppBoundary')
            curl \
            -H 'Content-Type: multipart/form-data; boundary=WebAppBoundary' \
            -H "Content-Length: ${#data}" \
            -d "${data}" \
            $url
        ;;
        *)
            echo "default (none of above)"
        ;;
    esac
}