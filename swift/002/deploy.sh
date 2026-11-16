#!/bin/zsh
# deploy.sh — 编译一次，并行安装到所有已连接的真机
#
# 用法：
#   ./deploy.sh               # Release 编译 → 装到所有在线设备 → 自动启动
#   ./deploy.sh -d            # Debug 编译（保留调试符号，便于连 Xcode 排查）
#   ./deploy.sh iPhone13 iPad # 只装指定设备（名字或 UDID 片段，模糊匹配）
#   ./deploy.sh -l            # 只看当前有哪些设备在线
#
# 前提：设备已经用数据线或 Xcode「无线调试」配对过一次，处于 connected 状态。

set -euo pipefail
cd "$(dirname "$0")"

SCHEME="002"
PROJECT="002.xcodeproj"
BUNDLE_ID="songshuai.-02"
DERIVED="build"
CONFIG="Release"
LAUNCH=1
FILTERS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--debug)  CONFIG="Debug"; shift ;;
    -l|--list)   LAUNCH=2; shift ;;
    -n|--no-launch) LAUNCH=0; shift ;;
    *) FILTERS+=("$1"); shift ;;
  esac
done

# ---------- 1. 找设备 ----------
DEVJSON=$(mktemp -t devicectl)
xcrun devicectl list devices --json-output "$DEVJSON" >/dev/null 2>&1 || true

# identifier \t name \t tunnelState
DEVICES=$(python3 - "$DEVJSON" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
for x in d.get("result", {}).get("devices", []):
    name = x.get("deviceProperties", {}).get("name") or ""
    tunnel = x.get("connectionProperties", {}).get("tunnelState") or ""
    udid = x.get("hardwareProperties", {}).get("udid") or ""
    print(f"{x.get('identifier','')}\t{name}\t{tunnel}\t{udid}")
PY
)

if [[ -z "$DEVICES" ]]; then
  echo "✗ 没有找到任何已配对的设备（先在 Xcode 里连一次设备）"
  exit 1
fi

if [[ ${#FILTERS[@]} -gt 0 ]]; then
  SELECTED=$(echo "$DEVICES" | awk -F'\t' -v pat="$(printf '%s|' "${FILTERS[@]}")" '
    BEGIN { n = split(pat, a, "|"); for (i=1;i<=n;i++) if (a[i]!="") k[i]=a[i]; c=n }
    { for (i in k) if (index(tolower($2), tolower(k[i])) || index(tolower($1), tolower(k[i])) || index(tolower($4), tolower(k[i]))) { print; break } }')
else
  # connected = 隧道已建立；disconnected / available (paired) = 已配对，尝试按需建立隧道
  SELECTED=$(echo "$DEVICES" | awk -F'\t' '$3 != "unavailable" && $3 != ""')
fi

if [[ -z "$SELECTED" ]]; then
  echo "✗ 没有匹配到在线设备。当前状态："
  echo "$DEVICES" | awk -F'\t' '{ printf "  %-22s %-12s %s\n", $2, $3, $1 }'
  exit 1
fi

echo "▶︎ 目标设备："
echo "$SELECTED" | awk -F'\t' '{ printf "  • %s (%s)\n", $2, $3 }'

SKIPPED=$(echo "$DEVICES" | awk -F'\t' '$3 == "unavailable"')
if [[ -n "$SKIPPED" ]]; then
  echo "  ⚠︎ 以下设备未参与（离线，或 iOS 16 及更早——devicectl 不支持，需用 Xcode 装）："
  echo "$SKIPPED" | awk -F'\t' '{ name = ($2 == "" ? $1 : $2); printf "     - %s\n", name }'
fi
[[ $LAUNCH -eq 2 ]] && exit 0

# ---------- 2. 编译一次 ----------
echo "\n▶︎ 编译 $CONFIG（generic iOS device）…"
APP="$DERIVED/Build/Products/$CONFIG-iphoneos/002.app"
EXECUTABLE="$APP/$(basename "$APP" .app)"
# 先删掉旧产物：否则编译中断留下的残缺 .app 会被当成本次结果去安装，
# 真机报 "The item at 002.app is not a valid bundle"（就是缺可执行文件）
rm -rf "$APP"

# 关键：清掉污染编译的环境变量。~/.bashrc 里为 macOS C 开发设了
# SDKROOT/CPATH/LIBRARY_PATH 指向 MacOSX.sdk，交互式终端会继承；它们会让 clang
# 在编译 iOS 时强行包含 macOS 头文件，报 "could not build module 'DarwinFoundation'"，
# 而且错误信息会误导成 MacOSX.sdk 的问题。必须在 xcodebuild 前 unset，
# 让 Xcode 自己用 -sdk iPhoneOS 决定头文件路径。
unset SDKROOT CPATH CPLUS_INCLUDE_PATH C_INCLUDE_PATH LIBRARY_PATH

# 共享 module 缓存里可能残留用污染环境构建过的 module，一并清掉更保险。
rm -rf "$DERIVED/ModuleCache.noindex"

BUILDLOG=$(mktemp -t xcodebuild)
set +e
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" \
  -destination 'generic/platform=iOS' -derivedDataPath "$DERIVED" \
  -allowProvisioningUpdates build > "$BUILDLOG" 2>&1
STATUS=$?
set -e

grep -E "error:|warning: .*signing|\*\* BUILD" "$BUILDLOG" | tail -20 || true

if [[ $STATUS -ne 0 ]] || ! grep -q "\*\* BUILD SUCCEEDED" "$BUILDLOG"; then
  echo "✗ 编译失败（xcodebuild 退出码 $STATUS），完整日志：$BUILDLOG"
  grep -E "error:" "$BUILDLOG" | head -10 || true
  exit 1
fi

if [[ ! -d "$APP" || ! -x "$EXECUTABLE" ]]; then
  echo "✗ 产物不完整：$APP（缺少可执行文件 $EXECUTABLE）"
  exit 1
fi
echo "✓ 产物：$APP"

# ---------- 3. 并行安装 ----------
echo "\n▶︎ 安装中…"
PIDS=(); NAMES=(); LOGS=()
while IFS=$'\t' read -r id name state udid; do
  log=$(mktemp -t deploy)
  (
    xcrun devicectl device install app --device "$id" "$APP" > "$log" 2>&1
    if [[ $LAUNCH -eq 1 ]]; then
      xcrun devicectl device process launch --device "$id" --terminate-existing "$BUNDLE_ID" >> "$log" 2>&1 || true
    fi
  ) &
  PIDS+=($!); NAMES+=("$name"); LOGS+=("$log")
done <<< "$SELECTED"

FAIL=0
for i in {1..${#PIDS[@]}}; do
  if wait ${PIDS[$i]} && ! grep -qi "error" "${LOGS[$i]}"; then
    echo "  ✅ ${NAMES[$i]}"
  else
    echo "  ❌ ${NAMES[$i]}"
    sed -n '1,6p' "${LOGS[$i]}" | sed 's/^/     /'
    FAIL=1
  fi
done

if [[ $FAIL -eq 0 ]]; then
  echo "\n🎉 全部安装完成（$CONFIG）"
else
  echo "\n⚠️ 有设备安装失败，见上面的日志；常见原因：设备锁屏、签名里没包含该设备 UDID"
  exit 1
fi
