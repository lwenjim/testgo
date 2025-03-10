#!/bin/bash
declare -A DebugServers=(
    # ["messagesv"]=54441
    # ["favoritesv"]=54452
    # ["openapi"]=54453

    # ["edgesv"]=19093
    # ["usersv"]=19091
    # ["paysv"]=19092
    # ["authsv"]=19090
)
declare -A ServiceServers=(
    ["mongo"]=27017
    ["mysql"]=3306
    ["redis"]=6379

    ["pushersv"]=64440
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
    ["favoritesv"]=64452
    ["openapi"]=64453
)
arr=(
    # "openapi"
    # "usersv"
    # "edgesv"
    # "paysv"
    # "authsv"
    # "pushersv"
    # "messagesv"
    # "squaresv"
    # "uploadsv"
    # "deliversv"
    # "usergrowthsv"
    # "riskcontrolsv"
    # "connectorsv"
    # "favoritesv"

    "pushersv"
    "messagesv"
    "squaresv"
    "edgesv"
    "usersv"
    "authsv"
    "uploadsv"
    "deliversv"
    "usergrowthsv"
    "riskcontrolsv"
    "paysv"
    "connectorsv"
    "favoritesv"
    "openapi"
)
debug=true
filename=~/servers/rpc.conf
if [[ ! $debug ]]; then
    echo >$filename
fi
for server in "${arr[@]}"; do
    if [ "$server" = 'mysql' ] || [ "$server" = "mongo" ] || [ "$server" = "redis" ]; then
        continue
    fi
    read -r -d '' template <<-'EOF'
server {
    server_name aaaaaa-svc;
    listen 9090 http2;
    access_log /tmp/aaaaaa-svc_nginx.log combined;

    location / {
        grpc_pass grpc://127.0.0.1:77777;
    }
}
EOF
    finded=false
    if [[ " ${!DebugServers[*]} " =~ $server ]]; then
        finded=true
    fi
    template="${template//aaaaaa/$server}"
    targetPort=${ServiceServers[$server]}
    if $finded; then
        targetPort=${DebugServers[$server]}
    fi
    template="${template//77777/$targetPort}"
    if [[ ! $debug ]]; then
        echo "$template" >>$filename
    else
        echo "$template"
    fi
done
