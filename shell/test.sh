#! /bin/bash
# shellcheck disable=SC2086
mapping="
        usersv
        mongo
        mysql
        redis
        pusher
        messagesv
        squaresv 
        edgesv
        authsv
        uploadsv
        deliversv
        usergrowthsv
        riskcontrolsv
        paysv"
service="$2"
my_function() {
    arr=()
    index=0
    while test $# -gt 0; do
        if [ "$service" = "$1" ]; then
            arr[index]=$1
            break
        fi
        shift
    done
    if [ ${#arr[@]} -eq 0 ]; then
        len=${#service}
        for ((i = 0; i < ${#service}; i++)); do
            current=$(echo "$service" | cut -c 1-"$len")
            for2() {
                while test $# -gt 0; do
                    item=$(echo "$1" | cut -c 1-"$len")
                    if [ "$current" = "$item" ]; then
                        arr[index]=$1
                        index=$((index + 1))
                    fi
                    shift
                done
            }
            for2 $mapping
            if [ ${#arr[@]} -gt 0 ]; then
                break
            fi
        done
    fi
    for i in "${arr[@]}"; do
        echo "$i"
    done
}
my_function $mapping
