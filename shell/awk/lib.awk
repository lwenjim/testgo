#!/usr/local/bin/gawk -f

function UniquePATH() {
    split(ENVIRON["PATH"], paths, ":");
    for (key in paths) {
        if (index(paths[key], " ")>0) {
            continue;
        }
        arr[paths[key]]=1;
        data=data":"paths[key];
    }
    gsub(/^\s+/, "", data);
    gsub(/\s+$/, "", data);
    print substr(data, 2);
}

function DateToTime(val) {
   if (match(val, /([0-9]+)\/([0-9]+)\/([0-9]+) ([0-9]+):([0-9]+):([0-9]+)/, res) > 0 ) {
        gsub("/", " ", val);
        gsub(":", " ", val);
        return mktime(val);
   }
    return "match error";
}

function TimeToDate(num) {
    if (match(num, /^[0-9]+$/)>0) {
        print strftime("%Y/%m/%d %H:%M:%S", val);
    }
}