#!/usr/local/bin/gawk -f
function UniquePATH() {
    split(ENVIRON["PATH"], paths, ":")

    for (key in paths) {
        if (index(paths[key], " ") > 0) { continue }

        arr[paths[key]] = 1
        data = data ":" paths[key]
    }

    gsub(/^\s+/, "", data)
    gsub(/\s+$/, "", data)
    print substr(data, 2)
}

function DateToTime(val) {
    if (\
        match(\
            val, /([0-9]+)\/([0-9]+)\/([0-9]+) ([0-9]+):([0-9]+):([0-9]+)/, res\
        ) > 0\
    ) {
        gsub("/", " ", val)
        gsub(":", " ", val)
        return mktime(val)
    }

    return "match error"
}

function TimeToDate(num) {
    if (match(num, /^[0-9]+$/) > 0) { print strftime("%Y/%m/%d %H:%M:%S", val) }
}

function UrlDecode(str) {
    decoded = ""
    i = 1

    while (i <= length(str)) {
        c = substr(str, i, 1)

        if (c == "%" && i + 2 <= length(str)) {
            hex = substr(str, i + 1, 2)
            val = strtonum("0x" hex)
            decoded = decoded sprintf("%c", val)
            i += 3
        }
        else if (c == "+") {
            decoded = decoded " "
            i++
        }
        else {
            decoded = decoded c

            i++
        }
    }

    return decoded
}

function UrlEncode(str) {
    encoded = ""
    safe_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~"
    len = length(str)

    for (i = 0; i < 256; ++i) { ord[sprintf("%c", i)] = i }

    for (i = 1; i <= len; i++) {
        c = substr(str, i, 1)

        if (index(safe_chars, c) > 0) { encoded = encoded c }
        else if (c == " ") { encoded = encoded "%20" }
        else {
            ord_val = ord[c]

            if (ord_val < 0 x80) {
                encoded = encoded "%" sprintf("%02X", ord_val)
            }
            else if (ord_val < 0 x800) {
                a = rshift(ord_val, 6)
                encoded = encoded "%" sprintf("%02X", or(0 xC0, a))
                b = and(ord_val, 0 x3F)
                encoded = encoded "%" sprintf("%02X", or(0 x80, b))
            }
            else if (ord_val < 0 x10000) {
                encoded = encoded "%"\
                    sprintf("%02X", or(0 xE0, rshift(ord_val, 12)))
                encoded = encoded "%"\
                    sprintf("%02X", or(0 x80, and(rshift(ord_val, 6), 0 x3F)))
                encoded = encoded "%"\
                    sprintf("%02X", or(0 x80, and(ord_val, 0 x3F)))
            }
        }
    }

    return encoded
}

function Trim(val) {
    gsub(/(^\s|\s$)/, "", val);
    return val
}