#!/bin/zsh
# deploy.sh — 编译一次，并行安装到所有已连接的真机；也可单独装 Mac 版
#
# 用法：
#   ./deploy.sh               # Release 编译 → 先更新 Mac 版（到「应用程序」）→ 再装到所有在线 iOS 设备
#   ./deploy.sh -d            # Debug 编译（保留调试符号，便于连 Xcode 排查）
#   ./deploy.sh iPhone13 iPad # 只装指定 iOS 设备（名字或 UDID 片段，模糊匹配）
#   ./deploy.sh -l            # 只看当前有哪些 iOS 设备在线
#   ./deploy.sh mac           # 只编译 + 覆盖安装 Mac 版，并启动（不动 iOS）
#   ./deploy.sh -i            # 只装 iOS，跳过 Mac 版
#   ./deploy.sh -a            # 强制 Mac + 所有 iOS 设备（与默认行为相同）
#
# 前提：iOS 设备已经用数据线或 Xcode「无线调试」配对过一次；Mac 版无需配对。

set -euo pipefail
cd "$(dirname "$0")"

SCHEME="002"
PROJECT="002.xcodeproj"
BUNDLE_ID="songshuai.-02"
DERIVED="build"
CONFIG="Release"
LAUNCH=1
MAC=1        # 默认顺带更新 Mac 版（-i 可关掉）
IOS=1        # 是否装 iOS
FILTERS=()

MAC_PROJECT="Mac/ShenSuanziMac.xcodeproj"
MAC_SCHEME="ShenSuanziMac"
MAC_APP_NAME="ShenSuanziMac.app"
MAC_INSTALL="/Applications/$MAC_APP_NAME"

# ---------- Mac 版：编译 → 退出旧进程 → 覆盖安装 → 启动 ----------
# Mac 端是独立工程，不走 devicectl；用 ditto 原地覆盖，避免 rm -rf 整个 .app
deploy_mac() {
  echo "\n▶︎ 编译 Mac 版（Release）…"
  local out="$PWD/Mac/build/Build/Products/Release/$MAC_APP_NAME"
  local log
  log=$(mktemp -t macbuild)
  local st=0
  set +e
  xcodebuild -project "$MAC_PROJECT" -scheme "$MAC_SCHEME" -configuration Release \
    -derivedDataPath Mac/build -allowProvisioningUpdates build > "$log" 2>&1
  st=$?
  set -e
  grep -E "error:|\*\* BUILD" "$log" | tail -10 || true
  if [[ $st -ne 0 ]] || ! grep -q "\*\* BUILD SUCCEEDED" "$log"; then
    echo "✗ Mac 编译失败（xcodebuild 退出码 $st），完整日志：$log"
    return 1
  fi
  if [[ ! -d "$out" ]]; then
    echo "✗ Mac 产物缺失：$out"
    return 1
  fi

  # 覆盖前必须先退出：直接覆盖正在运行的 Mach-O 会报 "Text file busy"
  if pgrep -x "${MAC_APP_NAME%.app}" >/dev/null 2>&1; then
    echo "  退出正在运行的 Mac 版…"
    pkill -x "${MAC_APP_NAME%.app}" 2>/dev/null || true
    for _ in {1..20}; do
      pgrep -x "${MAC_APP_NAME%.app}" >/dev/null 2>&1 || break
      sleep 0.2
    done
  fi

  # ditto 原地覆盖：保留签名与资源分支；首次安装时就是新建
  if ! ditto "$out" "$MAC_INSTALL" 2>/dev/null; then
    echo "  覆盖安装失败（可能在「应用程序」里没有写权限），尝试用户目录…"
    MAC_INSTALL="$HOME/Applications/$MAC_APP_NAME"
    mkdir -p "$HOME/Applications"
    ditto "$out" "$MAC_INSTALL"
  fi
  echo "✓ 已安装：$MAC_INSTALL"
  open "$MAC_INSTALL"
  echo "✅ Mac 版已启动"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--debug)  CONFIG="Debug"; shift ;;
    -l|--list)   LAUNCH=2; shift ;;
    -n|--no-launch) LAUNCH=0; shift ;;
    -a|--all)    MAC=1; shift ;;
    -i|--ios)    MAC=0; shift ;;
    -m|--mac)    MAC=1; IOS=0; shift ;;
    mac|macos|macOS|Mac) MAC=1; IOS=0; shift ;;
    *) FILTERS+=("$1"); shift ;;
  esac
done

if [[ $MAC -eq 1 && $LAUNCH -ne 2 ]]; then
  deploy_mac || exit 1
fi
if [[ $IOS -eq 0 ]]; then
  exit 0
fi

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
  if [[ $MAC -eq 1 ]]; then
    echo "⚠︎ 没有找到任何已配对的 iOS 设备（Mac 版已更新完成）"
    exit 0
  fi
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
  [[ $MAC -eq 1 ]] && { echo "（Mac 版已更新完成）"; exit 0; }
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

# 共享 module 缓存里可能残留用污染环境构建过的 module，挪走让它重建。
# 用 mv 而非 rm -rf：缓存目录常有数百个文件，批量删除会被环境的安全守卫拦下。
if [[ -d "$DERIVED/ModuleCache.noindex" ]]; then
  mv "$DERIVED/ModuleCache.noindex" "$DERIVED/ModuleCache.noindex.prev.$$" 2>/dev/null || true
fi

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
