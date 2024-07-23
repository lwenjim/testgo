#! /usr/bin/env bash
cd /Users/jim/Workdata/goland/src/jspp||exit 1
for i in edgesv pushersv smssv messagesv usersv paysv authsv deliversv adminsv momentsv ;do
    cd $i || exit 1
    go work init
    go work use . ../favoritesv
    go work sync
    cd ..
done