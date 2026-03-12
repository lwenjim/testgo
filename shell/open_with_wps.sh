#!/bin/bash

# /Users/jim/Workdata/testgo/shell/open_with_wps.sh \1
# 接收 iTerm2 传递的文件路径参数
FILE_PATH="$1"

# 判断文件后缀，指定对应打开程序
case "$FILE_PATH" in
*.json | *.txt | *.log)
    # 打开 JSON 文件用 VS Code
    /Applications/Visual\ Studio\ Code.app/Contents/Resources/app/bin/code --goto "$FILE_PATH"
    ;;
*.csv)
    # 保留之前的 CSV 用 WPS 打开（如果需要）
    open -a wpsoffice.app "$FILE_PATH"
    ;;
*)
    # 其他文件用系统默认程序打开
    open "$FILE_PATH"
    ;;
esac
