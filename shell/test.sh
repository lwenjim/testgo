#!/bin/bash
# shellcheck disable=SC2206 disable=SC2068 disable=SC2086 disable=SC1091 disable=SC2317 disable=SC1090 disable=SC2090 disable=SC2089 disable=SC2059

IFS=$'\n'
a=$(env)
b=($a)
template="%-40s %-10s\n"
printf ${template} "环境变量" "变量值"
for variable in ${b[@]}; do
    IFS="="
    item=($variable)
    if [ "${item[0]}" = "PATH" ] || [ "${item[1]}" = "" ]; then
        continue
    fi
    printf ${template} "${item[0]}" "${item[1]}"
done

# a="a=b"
# IFS="="
# item=($a)
# for variable in ${item[@]}; do
#     echo $variable
# done
