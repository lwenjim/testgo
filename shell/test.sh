#!/bin/sh

    mapping="
        mongo
        mysql
        redis
        pusher
        messagesv
        squaresv 
        edgesv
        usersv
        authsv
        uploadsv
        deliversv
        usergrowthsv
        riskcontrolsv
        paysv"    
        service="$2"
    {
        # shellcheck disable=SC2317
        my_function() {
            while test $# -gt 0; do
                if [ "$service" = "$1" ];then
                    in=true
                fi
                shift
            done
            if [ "$in" -eq "" ];then
                # shellcheck disable=SC2034
                len=${#service}
                arr=()
                index=0
                # 遍历每列
                while $len -gt 0;do
                    current=$(echo "$service"|cut -c 1-"$len")
                    # 遍历每行
                    while test $# -gt 0; do
                        item=$(echo "$1"|cut -c 1-"$len")
                        if [ "$current" = "$item" ];then
                            arr[index]=$1
                            index=$index+1
                        fi
                        shift
                    done                  

                done
            fi
        }
        # shellcheck disable=SC2086
        # shellcheck disable=SC2317
        my_function $mapping
    }
