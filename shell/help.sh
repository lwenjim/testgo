#!/usr/bin/env bash

source /Users/jim/.bashrc
shopt -s expand_aliases
service=messagesv
function cmd (){
    jspp-kubectl get pods
}
cmd|grep messagesv