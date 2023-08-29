#! /bin/bash
# shellcheck disable=2086,2068

serviceServers="
        mongo 27017
        mysql 3306
        redis 6379
        pusher 64440
        messagesv 64441
        squaresv 64442
        edgesv 64443
        usersv 64444

        authsv 64445
        uploadsv 64446
        deliversv 64447
        usergrowthsv 64448
        riskcontrolsv 64449
        paysv 64450
        connectorsv 64451
        "
declare -A serviceServers=(
    ["mongo"]=27017
    ["mysql"]=3306
    ["redis"]=6379
    ["pusher"]=64440
    ["messagesv"]=64441
    ["squaresv"]=64442
    ["edgesv"]=64443
    ["usersv"]=64444

    ["authsv"]=64445
    ["uploadsv"]=64446
    ["deliversv"]=64447
    ["usergrowthsv"]=64448
    ["riskcontrolsv"]=64449
    ["paysv"]=64450
    ["connectorsv"]=64451
)
for variable in ${!serviceServers[@]}; do
    echo "$variable"
done