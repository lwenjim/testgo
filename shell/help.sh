#!/usr/bin/env bash

shopt -s expand_aliases
source /Users/jim/.bashrc

function auto-match-cmd() {
    if [ "$1" = "" ]; then
        return 1
    fi
    local paramService="$1"
    local patternLen="${#paramService}"
    servers="
        update-git-hook
        jspp-k8s-port-forward
        iipfasdfsd
        iipafsasdf
        help"
    servers=$(echo $servers | tr -d "\n")

    newServers=(0)
    for server in $servers; do
        if [ ${#server} -ge $patternLen ]; then
            newServers[${#newServers[*]}]=$server
        fi
    done

    local resultServices=()
    for server in ${newServers[@]}; do
        if [ $paramService = $server ]; then
            resultServices[${#resultServices[*]}]=$server
            break
        fi
    done

    if [ ${#resultServices[@]} -eq 0 ]; then
        for ((strPos = ${#paramService}; strPos >= 1; strPos--)); do
            local partService=$(echo "$paramService" | cut -c 1-$strPos)
            for server in ${newServers[@]}; do
                local forService=$(echo "$server" | cut -c 1-$strPos)
                if [ $partService = $forService ]; then
                    resultServices[${#resultServices[*]}]=$server
                fi
            done
            if [ ${#resultServices[@]} -gt 0 ]; then
                break
            fi
        done
    fi

    if [ ${#resultServices[@]} -gt 0 ]; then
        if [ ${#resultServices[@]} -eq 1 ]; then
            echo simple_command=${resultServices[0]}
            echo "匹配成功 ---> $simple_command"
        else
            for i in "${resultServices[@]}"; do
                echo "$i"
            done
        fi
    fi
}

auto-match-cmd iip
