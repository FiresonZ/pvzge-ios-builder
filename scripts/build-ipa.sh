#!/usr/bin/env bash
# ============================================================
# build-ipa.sh - 初始化 Capacitor、无签名编译并打包 unsigned IPA
#
# 前提：本脚本运行前，workflow 已将官方源码 checkout 到
#       $GITHUB_WORKSPACE/_game_src，且脚本所在仓库位于 $GITHUB_WORKSPACE。
#
# 输入（通过环境变量）：
#   APP_NAME / APP_BUNDLE_ID / WEB_DIR / VERSION / COMMIT_SHORT
#   XCODE_SCHEME / CAPACITOR_CORE_VERSION
#   RUNNER_TEMP / GITHUB_WORKSPACE（GitHub Actions 自动提供）
#
# 输出：
#   $GITHUB_ENV   : APP_PATH
#   $GITHUB_OUTPUT: ipa_name、ipa_output_dir、size
# ============================================================
set -euo pipefail

APP_NAME="${APP_NAME:?APP_NAME 未设置}"
APP_BUNDLE_ID="${APP_BUNDLE_ID:?APP_BUNDLE_ID 未设置}"
WEB_DIR="${WEB_DIR:?WEB_DIR 未设置}"
VERSION="${VERSION:?VERSION 未设置}"
COMMIT_SHORT="${COMMIT_SHORT:-}"
SUFFIX="${SUFFIX:-}"          # 空=正式版；lite = Lite 版
VTOK="${SUFFIX:-full}"        # 区分正式/Lite 的各类中间/产物目录，避免并行构建互相覆盖
CAP_VERSION="${CAPACITOR_CORE_VERSION:-6}"
SCHEME="${XCODE_SCHEME:-App}"
GITHUB_WORKSPACE="${GITHUB_WORKSPACE:?}"
RUNNER_TEMP="${RUNNER_TEMP:?}"

SRC="$GITHUB_WORKSPACE/_game_src"
# WEB_DIR 可能传绝对路径（如 prepare-lite 生成的临时目录），否则相对 SRC
WEB_DIR_ABS="${WEB_DIR}"
[ -d "$WEB_DIR_ABS" ] || WEB_DIR_ABS="$SRC/$WEB_DIR"
[ -d "$WEB_DIR_ABS" ] || { echo "::error:: Web 目录不存在: $WEB_DIR_ABS"; exit 1; }

# ============================================================
# 方案B：注入 JS 错误捕获器 + 构建溯源（真机排错用）
#   - 溯源 SOURCE_INFO 始终注入，便于确认 IPA 对应当前官方 commit
#   - 错误捕获器仅在 DEBUG_CAPTURE=1 时注入：捕获 window 错误 /
#     console / 未处理 rejection / 首帧前的 getUserMedia、alert、confirm、prompt，
#     写到 localStorage + 屏幕调试面板（需连接 idevicesyslog 采集 console）
# ============================================================
SOURCE_REPO="${SOURCE_REPO:-Gzh0821/pvzge_web}"
SOURCE_BRANCH="${SOURCE_BRANCH:-master}"
COMMIT_SHA="${COMMIT_SHA:-}"
CAPTURE="${DEBUG_CAPTURE:-0}"
SERVER_URL="${SERVER_URL:-}"     # 非空 = 远程加载（App 从该 https 地址拉网页，而非本地源）
CUSTOM_SCHEME="${CUSTOM_SCHEME:-}" # 非空且未填 SERVER_URL = 本地自定义 scheme（如 gardendless-game），
                                   # 覆盖 Capacitor 默认的 capacitor://，本地加载游戏资源
LOCAL_SERVER="${LOCAL_SERVER:-1}"  # =1 且未填 SERVER_URL = 内嵌本地 http 服务器（GCDWebServer）离线加载，修复灰屏
LOCAL_PORT="${LOCAL_SERVER_PORT:-8080}"  # 本地 http 服务器端口，需与 server.url 及 Swift 端一致
BUILD_TIME="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

INDEX_F="$WEB_DIR_ABS/index.html"
if [ -f "$INDEX_F" ]; then
  if [ "$CAPTURE" = "1" ]; then
    cat > "$WEB_DIR_ABS/__pvzge_capture.js" <<'CAPJS'
(function () {
  var E = window.__PVZGE_ERR = [];
  var nativeError = function () {};
  try { nativeError = console.error.bind(console); } catch (e) {}
  function push(t, m, s, d) {
    try { E.push({ t: t, ts: Date.now(), m: String(m == null ? '' : m), s: String(s == null ? '' : s), d: d }); } catch (e) {}
    try { localStorage.setItem('pvzge_errs', JSON.stringify(E.slice(-200))); } catch (e) {}
    // 走原生 console.error，配合原生开启的 console→syslog 后可被 idevicesyslog 捕获
    try { nativeError('[PVZGE] ' + t + ' | ' + (s == null ? '' : s) + ' | ' + (m == null ? '' : m)); } catch (e) {}
  }
  window.addEventListener('error', function (ev) {
    push('window.onerror', ev.message, (ev.filename || '') + ':' + ev.lineno + ':' + ev.colno);
  }, true);
  window.addEventListener('unhandledrejection', function (ev) {
    var r = ev.reason; var m = (r && r.message) ? (r.name + ': ' + r.message) : String(r);
    push('unhandledrejection', m, 'promise');
  });
  ['log', 'info', 'warn', 'error', 'debug'].forEach(function (lv) {
    var orig = console[lv];
    console[lv] = function () {
      push('console.' + lv, Array.prototype.join.call(arguments, ' '), '');
      try { orig.apply(console, arguments); } catch (e) {}
    };
  });
  // 拦截首帧前的相机 / 麦克风权限申请，记录调用点（getUserMedia）
  try {
    if (navigator.mediaDevices && navigator.mediaDevices.getUserMedia) {
      var gum = navigator.mediaDevices.getUserMedia;
      navigator.mediaDevices.getUserMedia = function () {
        var c = arguments[0];
        push('getUserMedia', 'CALLED constraints=' + (c ? JSON.stringify(c) : '(none)'),
          (new Error().stack || '').split('\n').slice(1, 4).join(' | '));
        return gum.apply(this, arguments);
      };
    }
  } catch (e) {}
  // 拦截首帧前的 alert / confirm / prompt，观察是否被调用
  ['alert', 'confirm', 'prompt'].forEach(function (m) {
    var o = window[m];
    if (typeof o === 'function') {
      window[m] = function () {
        push('dialog.' + m, String(arguments[0] == null ? '' : arguments[0]), '');
        return o.apply(window, arguments);
      };
    }
  });
  if (window.__PVZGE_SOURCE) push('source', JSON.stringify(window.__PVZGE_SOURCE), '');
  // 屏幕调试面板：无调试工具时也能看到已捕获的错误
  setTimeout(function () {
    if (!E.length) return;
    try {
      var d = document.createElement('div');
      d.id = 'pvzge-debug';
      d.style.cssText = 'position:fixed;left:0;top:0;right:0;z-index:999999;background:rgba(0,0,0,.92);color:#4fc3ff;font:9px/1.35 monospace;white-space:pre-wrap;padding:6px 8px;max-height:55%;overflow:auto;pointer-events:auto;';
      d.textContent = '[PVZGE_DEBUG] ' + E.map(function (e) {
        return e.t + '@' + e.ts + ' ' + (e.s ? e.s + ' ' : '') + e.m;
      }).join('\n---\n');
      (document.body || document.documentElement).appendChild(d);
    } catch (err) {}
  }, 1500);
})();
CAPJS
  fi

  SOURCE_JSON=$(printf '{"repo":%s,"branch":%s,"commit":%s,"version":%s,"builtAt":%s}' \
    "$(printf '%s' "${SOURCE_REPO}" | python3 -c "import sys,json;print(json.dumps(sys.stdin.read()))")" \
    "$(printf '%s' "${SOURCE_BRANCH}" | python3 -c "import sys,json;print(json.dumps(sys.stdin.read()))")" \
    "$(printf '%s' "${COMMIT_SHA}" | python3 -c "import sys,json;print(json.dumps(sys.stdin.read()))")" \
    "$(printf '%s' "${VERSION}" | python3 -c "import sys,json;print(json.dumps(sys.stdin.read()))")" \
    "$(printf '%s' "${BUILD_TIME}" | python3 -c "import sys,json;print(json.dumps(sys.stdin.read()))")")

  python3 - "$INDEX_F" "$SOURCE_JSON" "$CAPTURE" <<'PY'
import sys
idx, src_json, capture = sys.argv[1], sys.argv[2], sys.argv[3]
html = open(idx, encoding="utf-8", errors="replace").read()
marker = "window.__PVZGE_SOURCE"
inject = "<script>" + marker + "=" + src_json + ";</script>"
if capture == "1":
    inject += '\n  <script src="__pvzge_capture.js"></script>'
if marker in html:
    pass  # 已注入过，保持幂等，避免重复追加
elif "</head>" in html:
    html = html.replace("</head>", inject + "\n" + "</head>", 1)
    open(idx, "w", encoding="utf-8").write(html)
else:
    open(idx, "w", encoding="utf-8").write(inject + "\n" + html)
PY

  printf '%s\n' "repo=$SOURCE_REPO" "branch=$SOURCE_BRANCH" "commit=$COMMIT_SHA" \
    "version=$VERSION" "builtAt=$BUILD_TIME" > "$WEB_DIR_ABS/PVZGE_SOURCE.txt"
  if [ "$CAPTURE" = "1" ]; then
    echo "✅ 已注入错误捕获器 + 构建溯源到 $INDEX_F (DEBUG_CAPTURE=$CAPTURE)"
  else
    echo "ℹ️  已注入构建溯源到 $INDEX_F (DEBUG_CAPTURE=0，未启用捕获)"
  fi
else
  echo "::warning:: 无法注入（index.html 不存在）: $INDEX_F"
fi

# 每个变体用独立工程目录，避免多次构建相互覆盖
proj="${PROJ_DIR:-$RUNNER_TEMP/capacitor-project}"
mkdir -p "$proj"
cd "$proj"

# ---------- 1) 初始化 package.json ----------
cat > package.json <<'PKGJSON'
{
  "name": "pvzge-ios-wrapper",
  "version": "1.0.0",
  "private": true,
  "description": "Capacitor wrapper for PvZ2 Gardendless iOS"
}
PKGJSON

# ---------- 2) 安装 Capacitor 依赖 ----------
npm install --silent --no-audit --no-fund \
  "@capacitor/core@^$CAP_VERSION" \
  "@capacitor/cli@^$CAP_VERSION" \
  "@capacitor/ios@^$CAP_VERSION"

# 远程加载模式（SERVER_URL 非空）：运行时从 server.url 拉网页，本地 webDir 资源
# 无需打进包。把 webDir 切到一个仅含占位页的临时目录，cap sync 后包里不携带游戏
# 资源 → 得到几 MB 的瘦包。留空则维持本地电容加载（全量资源打入包内）。
if [ -n "$SERVER_URL" ]; then
  EMPTY_WEB_DIR="${RUNNER_TEMP}/empty_web_${VTOK}"
  mkdir -p "${EMPTY_WEB_DIR}"
  printf '<!doctype html><html><head><meta charset="utf-8"><title>%s</title></head><body>remote-load: %s</body></html>' \
    "${APP_NAME}" "${SERVER_URL}" > "${EMPTY_WEB_DIR}/index.html"
  echo "remote-slim: webDir switch to placeholder dir -> ${EMPTY_WEB_DIR}"
  WEB_DIR_ABS="${EMPTY_WEB_DIR}"
fi

# ---------- 3) cap init（Capacitor 6 不支持 --app-version）----------
npx cap init "$APP_NAME" "$APP_BUNDLE_ID" --web-dir="$WEB_DIR_ABS"

# ---------- 4) 写入 appId/appName/appVersion/appVersionCode ----------
#    server 段四选一（优先级：SERVER_URL > CUSTOM_SCHEME > LOCAL_SERVER > 默认）：
#      - SERVER_URL    非空 → 远程加载（server.url = https://...）
#      - CUSTOM_SCHEME 非空 → 本地自定义 scheme（server.appleScheme）
#      - LOCAL_SERVER=1      → 内嵌本地 http 服务器（server.url = http://127.0.0.1:PORT）
#      - 否则                 → 移除 server 段，走 Capacitor 默认 capacitor://
python3 - <<PYEOF
import json, os
p = "capacitor.config.json"
c = json.load(open(p))
c["appId"] = c.get("appId") or os.environ["APP_BUNDLE_ID"]
c["appName"] = c.get("appName") or os.environ["APP_NAME"]
c["appVersion"] = os.environ["VERSION"]
c["appVersionCode"] = 1
server_url = os.environ.get("SERVER_URL", "").strip()
custom_scheme = os.environ.get("CUSTOM_SCHEME", "").strip()
local_server = os.environ.get("LOCAL_SERVER", "1").strip().lower() in ("1", "true")
local_port = os.environ.get("LOCAL_PORT", "8080").strip()
if server_url:
    c["server"] = {"url": server_url}
    print("✅ server.url =", server_url)
elif custom_scheme:
    c["server"] = {"appleScheme": custom_scheme}
    print("✅ server.appleScheme =", custom_scheme)
elif local_server:
    c["server"] = {"url": f"http://127.0.0.1:{local_port}"}
    print("✅ local http server -> server.url =", c["server"]["url"])
else:
    c.pop("server", None)  # 清掉旧配置，走默认 capacitor://
with open(p, "w") as f:
    f.write(json.dumps(c, indent=2) + "\n")
PYEOF

# ---------- 5) 添加 iOS 平台并同步 ----------
npx cap add ios
npx cap sync ios

# --- 5.5) 调试构建：开启 WKWebView JS console → 系统日志（供 idevicesyslog 抓 [PVZGE]）---
if [ "$CAPTURE" = "1" ]; then
  APPD="$proj/ios/App/App/AppDelegate.swift"
  if [ -f "$APPD" ]; then
    python3 - "$APPD" <<'PY' && echo "✅ 已开启 WKWebView console→syslog（AppDelegate.swift）" \
      || echo "::warning:: 注入 console→syslog 开关失败（不影响构建）"
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
if "LogsPageMessagesToSystemConsoleEnabled" in s:
    sys.exit(0)  # 已注入过，幂等
i = s.find("didFinishLaunchingWithOptions")
j = s.find("return", i) if i >= 0 else -1
if j < 0:
    print("::warning:: 未能在 AppDelegate.swift 定位注入点")
    sys.exit(0)
ls = s.rfind("\n", 0, j) + 1
le = s.find("\n", j)
le = le if le >= 0 else len(s)
line = s[ls:le]
ind = line[: len(line) - len(line.lstrip())]
inject = ind + 'UserDefaults.standard.set(true, forKey: "WebKitLogsPageMessagesToSystemConsoleEnabled")\n' \
       + ind + 'UserDefaults.standard.set(true, forKey: "WebKit2.LogsPageMessagesToSystemConsoleEnabled")\n'
s = s[:ls] + inject + s[ls:]
open(p, "w", encoding="utf-8").write(s)
PY
  else
    echo "::warning:: 未找到 AppDelegate.swift：$APPD"
  fi
fi

# --- 5.6) 本地 http 服务器（默认开）：内嵌 GCDWebServer Serve 打包进 public 的网页，
#          WebView 加载 http://127.0.0.1:$LOCAL_PORT，等价于"打包版 python http.server"，
#          修复 capacitor:// 本地源导致的灰屏（可离线）。
#          当填写 SERVER_URL(远程) 或 CUSTOM_SCHEME 时自动跳过本注入。
if [ "$LOCAL_SERVER" = "1" ] || [ "$LOCAL_SERVER" = "true" ]; then 
  if [ -z "$SERVER_URL" ] && [ -z "$CUSTOM_SCHEME" ]; then
  PODFILE="$proj/ios/App/Podfile"
  APPD="$proj/ios/App/App/AppDelegate.swift"
  PLIST="$proj/ios/App/App/Info.plist"
  {
    python3 - "$PODFILE" "$APPD" "$PLIST" "$LOCAL_PORT" <<'PY'
import sys
podfile, appd, plist, port = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

# ---- 1) Podfile：向 App target 添加 GCDWebServer ----
with open(podfile, encoding="utf-8") as f:
    s = f.read()
if "GCDWebServer" not in s:
    needle = "  capacitor_pods\n"
    if needle not in s:
        needle = "target 'App' do\n"
    inject_pod = "  pod 'GCDWebServer'\n"
    s = s.replace(needle, needle + inject_pod, 1)
    with open(podfile, "w", encoding="utf-8") as f:
        f.write(s)

# ---- 2) AppDelegate.swift：启动本地 http 服务器 ----
with open(appd, encoding="utf-8") as f:
    s = f.read()
method_marker = "kLocalServerPort"
if method_marker not in s:
    # 2a) import GCDWebServer
    if "import GCDWebServer" not in s:
        idx = s.find("import Capacitor")
        if idx >= 0:
            eol = s.find("\n", idx)
            s = s[:eol] + "\nimport GCDWebServer" + s[eol:]
    # 2b) 常量 + webServer 属性（放在 class 开头、第一个 { 之后）
    cls = s.find("class AppDelegate")
    ob = s.find("{", cls)
    nl = s.find("\n", ob)
    if nl >= 0:
        head = "\n    private let kLocalServerPort: UInt = " + port + "\n" \
             + "    private var webServer: GCDWebServer?\n"
        s = s[:nl] + head + s[nl:]
    # 2c) 在 didFinishLaunchingWithOptions 里、return true 前启动服务器
    i = s.find("didFinishLaunchingWithOptions")
    j = s.find("return true", i) if i >= 0 else -1
    if j >= 0:
        ls = s.rfind("\n", 0, j) + 1
        line = s[ls:s.find("\n", j)]
        ind = line[: len(line) - len(line.lstrip())]
        call = ind + "self.webServer = startLocalWebServer()\n"
        s = s[:ls] + call + s[ls:]
    # 2d) 追加服务器方法（插到类最后一个右花括号前）
    method = '''
    @discardableResult
    func startLocalWebServer() -> GCDWebServer? {
        guard let webPath = Bundle.main.path(forResource: "public", ofType: nil) else { return nil }
        let server = GCDWebServer()
        // .wasm 需要正确 MIME，否则 Cocos wasm 加载失败
        server.addHandler(forMethod: "GET", pathRegex: ".*\\\\.wasm(/[^/]*)?$",
                          request: GCDWebServerRequest.self) { [webPath] request in
            var rel = request.path
            if rel.hasPrefix("/") { rel.removeFirst() }
            rel = rel.removingPercentEncoding ?? rel
            let file = URL(fileURLWithPath: webPath).appendingPathComponent(rel).path
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: file)) else {
                return GCDWebServerResponse(statusCode: 404)
            }
            return GCDWebServerDataResponse(data: data, contentType: "application/wasm")
        }
        server.addGETHandler(forBasePath: "/", directoryPath: webPath,
                             indexFilename: "index.html", cacheAge: 120, allowRangeRequests: true)
        do {
            try server.start(withPort: self.kLocalServerPort, bonjourName: nil)
        } catch {
            print("[PVZGE] local http server start failed: \\(error)")
            return nil
        }
        return server
    }
'''
    ri = s.rfind("}")
    s = s[:ri] + method + "\n" + s[ri:]
    with open(appd, "w", encoding="utf-8") as f:
        f.write(s)

# ---- 3) Info.plist：允许本地明文 HTTP（NSAllowsLocalNetworking）----
with open(plist, encoding="utf-8", errors="replace") as f:
    s = f.read()
if "NSAllowsLocalNetworking" not in s:
    if "<key>NSAppTransportSecurity</key>" in s:
        i = s.find("<key>NSAppTransportSecurity</key>")
        d = s.find("<dict>", i)
        if d >= 0:
            d += len("<dict>")
            inj = "\n<key>NSAllowsLocalNetworking</key><true/>\n"
            s = s[:d] + inj + s[d:]
    else:
        anchor = "</dict>\n</plist>"
        inj = "<key>NSAppTransportSecurity</key>\n<dict>\n<key>NSAllowsLocalNetworking</key><true/>\n</dict>\n"
        s = s.replace(anchor, inj + anchor, 1) if anchor in s else s
    with open(plist, "w", encoding="utf-8") as f:
        f.write(s)
PY
  } && echo "✅ 已注入本地 http 服务器（GCDWebServer, port=$LOCAL_PORT）" \
    || echo "::warning:: 本地 http 服务器注入失败（不影响构建）"
  fi
fi

# ---------- 6) 定位 iOS 工程根目录（含 Podfile / App.xcworkspace）----------
#    注意用 -prune 排除 .xcodeproj 内部自带的 project.xcworkspace，
#    避免把工作目录定位到工程容器（App.xcodeproj）而非工程根（App）。
cd ios
WS=$(find . -maxdepth 5 \( -name "*.xcodeproj" -prune \) -o \( -name "*.xcworkspace" -print \) | sort | head -1)
[ -n "$WS" ] || { echo "::error:: 未找到 .xcworkspace（cap add ios 是否成功？）"; exit 1; }
WS_DIR=$(cd "$(dirname "$WS")" && pwd)
WS_NAME=$(basename "$WS")
cd "$WS_DIR"
[ -f Podfile ] || { echo "::error:: $WS_DIR 下未找到 Podfile"; exit 1; }

# ---------- 7) CocoaPods ----------
pod install --repo-update || pod install

# ---------- 8) 强制无签名 ----------
PBXPROJ=$(find . -maxdepth 2 -name "project.pbxproj" | head -1)
[ -n "$PBXPROJ" ] || { echo "::error:: 未找到 project.pbxproj"; exit 1; }
/usr/bin/sed -i '' 's/DEVELOPMENT_TEAM = [^;]*;//g' "$PBXPROJ"
/usr/bin/sed -i '' 's/CODE_SIGN_IDENTITY = [^;]*;//g' "$PBXPROJ"
/usr/bin/sed -i '' 's/"CODE_SIGN_IDENTITY\[sdk=iphoneos\*\]" = [^;]*;//g' "$PBXPROJ"
/usr/bin/sed -i '' 's/CODE_SIGN_STYLE = [^;]*;//g' "$PBXPROJ"
/usr/bin/sed -i '' 's/PROVISIONING_PROFILE_SPECIFIER = [^;]*;//g' "$PBXPROJ"

# ---------- 9) 编译（Release / iphoneos，无签名）----------
DERIVED_DATA="$RUNNER_TEMP/derived_data_${VTOK}"
BUILD_DIR="$RUNNER_TEMP/build_output_${VTOK}"
mkdir -p "$DERIVED_DATA" "$BUILD_DIR"
set -o pipefail
xcodebuild \
  -workspace "$WS_NAME" \
  -scheme "$SCHEME" \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath "$DERIVED_DATA" \
  -resultBundlePath "$BUILD_DIR/xcresult" \
  CODE_SIGNING_ALLOWED="NO" \
  CODE_SIGNING_REQUIRED="NO" \
  CODE_SIGN_IDENTITY="" \
  "CODE_SIGN_IDENTITY[sdk=iphoneos*]"="" \
  DEVELOPMENT_TEAM="" \
  PROVISIONING_PROFILE_SPECIFIER="" \
  CODE_SIGN_STYLE="Manual" \
  ENABLE_BITCODE="NO" \
  ONLY_ACTIVE_ARCH="NO" \
  SUPPORTS_MACCATALYST="NO" \
  build | xcbeautify

APP_PATH=$(find "$DERIVED_DATA/Build/Products/Release-iphoneos" -maxdepth 1 -name "*.app" -type d | head -1)
[ -n "$APP_PATH" ] || { echo "::error:: 编译后未找到 .app"; exit 1; }

# ---------- 9) 打包 unsigned IPA ----------
SAFE_NAME=$(printf '%s' "$APP_NAME" | sed 's/[^A-Za-z0-9._-]/_/g')
BASE="${SAFE_NAME}-${VERSION}"
[ -n "$COMMIT_SHORT" ] && BASE="${BASE}-${COMMIT_SHORT}"
if [ -n "$SUFFIX" ]; then
  IPA_NAME="${BASE}-${SUFFIX}-unsigned.ipa"
else
  IPA_NAME="${BASE}-unsigned.ipa"
fi
STAGE="$RUNNER_TEMP/ipa_stage_${VTOK}"
OUT="$RUNNER_TEMP/ipa_output_${VTOK}"
mkdir -p "$STAGE/Payload" "$OUT"
cp -R "$APP_PATH" "$STAGE/Payload/"

cd "$STAGE"
zip -qrX "$OUT/$IPA_NAME" Payload

echo "APP_PATH=$APP_PATH"       >> "$GITHUB_ENV"
echo "ipa_name=$IPA_NAME"       >> "$GITHUB_OUTPUT"
echo "ipa_output_dir=$OUT"      >> "$GITHUB_OUTPUT"
echo "✅ IPA: $OUT/$IPA_NAME ($(du -h "$OUT/$IPA_NAME" | cut -f1))"