#!/usr/local/bin/gawk -f

function FixedPath() {
    split(ENVIRON["PATH"], paths, ":");
    for (key in paths) {
        if (index(paths[key], " ")>0) {
            continue;
        }
        arr[paths[key]]=1;
        data=data":"paths[key];
    }
    gsub(/\s/, "", data);
    print substr(data, 2);
}