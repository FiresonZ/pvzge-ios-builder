<div align="center">
  <img width="22%" src="https://pvzge.com/pvz_logo-round.webp" alt="PvZ2 Gardendless">
  <h1>PvZ2 Gardendless — iOS 自动打包仓库</h1>
  <h3>📦 pvzge-ios-builder</h3>

[![Auto Release](https://img.shields.io/badge/Action-Auto%20Release-blueviolet?logo=github)](.github/workflows/auto-release.yml)
[![Latest Release](https://img.shields.io/github/v/release/FiresonZ/pvzge-ios-builder?label=Latest%20Release&color=informational)](https://github.com/FiresonZ/pvzge-ios-builder/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

📦 官方 Web 版 → 自动包装 → **无签名 iOS IPA**（正式版 + Lite 版），巨魔商店 / 自签即可装在 iPhone 上畅玩！

🍳 **项目名：`pvzge-ios-builder`** —— 纯脚本型壳仓库，只包含自动构建工具与工作流，**不保存任何游戏资源**。
</div>

---

## ⚡ 快速上手（两种玩法任选）

### 🤖 方式一：等自动发版（推荐，不需要任何操作）
本仓库 **北京时间每天早上 8:00** 会自动去官方仓库检查更新：

```
官方 docs/ 目录有新 commit？
  ├── 是 → 自动构建无签名 IPA → 创建一个新的 GitHub Release
  └── 否 → 跳过
```

👉 直接去 [Releases 页面](../../releases) 下载最新的 `.ipa` 文件就行。

---

### 🔧 方式二：手动点一下立刻打包
需要立刻打出特定历史版本 / Tag / Commit 的 IPA ？

1. 进入 [Actions → Build & Auto Release IPA](../../actions/workflows/auto-release.yml)
2. 点击右侧 **Run workflow** 按钮
3. 填写参数 → 点绿按钮运行
4. 10~20 分钟后在当前运行页面底部 **Artifacts** 里下载正式版 + Lite 版 IPA

---

## 📋 参数说明（Build & Auto Release 工作流通用）

| 参数 | 默认值 | 说明 |
|---|---|---|
| `source_repo` | `Gzh0821/pvzge_web` | 官方游戏源码仓库（格式 `owner/repo`）。fork 自己用或换项目时改这里即可 |
| `source_branch` | *(空)* | 要跟踪的分支 / Tag / Commit SHA。留空 = 官方默认分支 |
| `web_dir` | `docs` | 构建产物（含 `index.html` 的目录）在源仓库中的相对路径 |
| `app_name` | `PvZ2 Gardendless` | iPhone 桌面上显示的 App 名（中英文都可） |
| `app_bundle_id` | `com.pvzge.gardendless` | iOS Bundle Identifier；用证书自签时这个 ID 必须与你的证书 ID 一致 |
| `app_version` | *(空→自动提取)* | 自定义版本号（如 `0.13.0`），留空则自动从官方仓库 `index.html` 提取 |
| `force_build` | `false` | 勾选后即使检测到版本 / commit 没变也会强制重新打包并发 Release |

---

## 📥 下载后的 iPhone 安装指南

> 本仓库产出的所有 IPA 均为 **无签名 (unsigned)**，需要借助以下任一工具完成安装：

### 🟢 方式 1：TrollStore 巨魔商店（最推荐，iOS 15.0 ~ 16.6.1）
完全**无需签名、无需电脑、永不掉签**。
1. 确认自己的 iOS 版本在支持范围，然后按 [TrollStore 官方安装指南](https://github.com/opa334/TrollStore/blob/main/Install.md) 装好巨魔
2. 把下载好的 `.ipa` 发到手机：AirDrop（隔空投送）→ 用「TrollStore」打开，或保存到「文件 App」→ 在 TrollStore 内选 Import
3. 点击 Install 即可

### 🟡 方式 2：Sideloadly / AltStore（免费 Apple ID，通用所有 iOS 版本）
1. 电脑下载安装 [Sideloadly](https://sideloadly.io/)（Mac / Windows 都有）
2. iPhone 用数据线连电脑 → 打开 Sideloadly → 登录自己的 Apple ID（ID 不会外传，加密连接 Apple 官方）
3. IPA 文件拖进 Sideloadly → 点 **Start** → 等进度条完成
4. 手机上 **设置 → 通用 → VPN 与设备管理** → 信任刚装的开发者 App → 开玩
5. **有效期 7 天**，到期前再插上电脑点一下「Refresh」续签即可

### 🔵 方式 3：爱思助手 / 3uTools（Windows 用户最常用）
1. Windows 下载安装 [爱思助手](https://www.i4.cn/) 或 [3uTools](http://www.3u.com/)
2. 数据线连 iPhone → 助手识别到设备 → 「我的设备 → 应用 → 导入安装」选择 IPA
3. 如果弹出签名提示，选「使用个人 Apple ID 签名」→ 登录 → 一键安装

### 🟠 方式 4：企业签 / 开发者证书（$99/年，正规可分发）
1. 花 $99 开通 [Apple Developer Program](https://developer.apple.com/programs/)，或购买第三方企业签
2. 用 `codesign` / `fastlane` / iOS App Signer 等工具给 IPA 重签
3. 重签后可直接通过链接分发或上传 TestFlight

---

## 🏗️ 它是怎么工作的？（原理）

```
┌───────────────────────────────────────────────────────────────────────┐
│                Build & Auto Release 工作流（每天 08:00 北京时间）       │
│  ① curl 官方 docs/index.html → 正则解析 <title> 里的语义版本号（0.13.0） │
│  ② GitHub API 查询官方 docs/ 目录的最新 commit SHA → 短 sha(7位)        │
│  ③ tag = v<版本号>+<短sha>  → 和本仓库最新 Release tag 对比             │
└────────────────────────────┬──────────────────────────────────────────┘
                             │ 需要更新？
                ┌────────────┴────────────┐
                │ 是                      │ 否 → 结束
                ▼                         └─→ 输出日志「已是最新版本」
┌──────────────────────────────────────────────┐
│         macOS-14 Runner：构建 IPA            │
│  ① Node.js 20 + npm 装 Capacitor v6          │
│  ② sanitize-web 清理广告/统计/同意脚本       │
│  ③ npx cap init → npx cap add ios            │
│  ④ npx cap sync（把官方 docs/ 拷进 iOS 工程） │
│  ⑤ pod install（Capacitor 的 CocoaPods 依赖） │
│  ⑥ sed 清理所有 DEVELOPMENT_TEAM / SIGN_ID   │
│  ⑦ xcodebuild CODE_SIGNING_ALLOWED=NO 编译   │
│  ⑧ prepare-lite 压缩资源 → 再编译一次 Lite   │
│  ⑨ 产物 .app → Payload/ → zip → 正式版+Lite .ipa │
└────────────────────────────┬─────────────────┘
                             ▼
┌──────────────────────────────────────────────┐
│     Ubuntu Runner：创建 GitHub Release       │
│  ① sha256sum 校验和  +  du -h 体积           │
│  ② 生成带表格 + 安装教程的 Release Notes     │
│  ③ softprops/action-gh-release 创建 Release  │
│     并把正式版 + Lite 版 IPA 作为附件上传     │
└──────────────────────────────────────────────┘
```

---

## 🎯 工作流的产物

| 产物 | 生成方式 | 去向 |
|---|---|---|
| 🟢 **正式版 IPA** | 官方 `docs/` 完整打包 | **GitHub Releases**（永久保留）+ Actions Artifact（保留 90 天） |
| ⚡ **Lite 版 IPA** | PNG/MP3 有损压缩后再打包 | 同上，一并上传 Releases |

工作流同时支持**定时（`cron: 0 0 * * *`，北京 08:00）**与**手动 `workflow_dispatch`** 两种触发方式。

---

## ❓ 常见问题 FAQ

<details>
<summary><b>Q1：为什么不直接发布到 App Store？</b></summary>

1. **版权**：PvZ（植物大战僵尸）是 EA（电子艺界）的注册商标与著作权作品，原作同人改编写实风格的 App Store 审核通过率极低。
2. **需要 $99 开发者账号 + 完整签名链路**，对于纯兴趣分享来说成本过高。
3. **无签名 IPA + 巨魔 / 自签** 方案对技术玩家来说更灵活、可控、不受 Apple 审核政策影响。

如果你有正规证书与授权，可以把本仓库生成的 Xcode 工程直接拿去签名上架，所有资源和工程结构都是标准的。
</details>

<details>
<summary><b>Q2：打包失败 / 跑起来没声音 / 闪退怎么排查？</b></summary>

1. **打包失败**：先进入对应 Actions Run 的日志，失败步骤会有红色高亮，常见原因：
   - `pod install` 超时：重试一次即可，GitHub Actions 网络波动偶发
   - `xcodebuild` 签名错误：确认 `CODE_SIGNING_ALLOWED=NO` 生效（本工作流已强制设置）
2. **没声音**：iOS 的 WKWebView 禁止 JS 在用户首次触摸前播放音频。第一次进入游戏后先按一下屏幕任意位置让音频引擎 resume 即可。如果要彻底修复可以在 Capacitor 工程里加一个插件 patch。
3. **闪退**：通常是资源未完全下载。游戏首次启动会懒加载部分远程资源，确认 Wi-Fi / 4G 网络畅通。
</details>

<details>
<summary><b>Q3：我想把它改成自动发 Android APK，好改吗？</b></summary>

非常好改！Capacitor 本身就跨平台：
```bash
# 在 build job 里加两行即可
npx cap add android
./gradlew assembleDebug   # 输出 universal-debug.apk
```
GitHub Actions 有现成的 `ubuntu-latest + Android SDK` 镜像。有需要可以发 Issue 加这个功能。
</details>

<details>
<summary><b>Q4：这个仓库本身不需要保存任何游戏资源吗？</b></summary>

完全不需要！本仓库是**纯触发型壳仓库**：
- 没有任何一份游戏资源（零存储占用）
- 每次运行工作流都会从官方仓库 `git clone` 最新的 `docs/` 目录
- 官方一更新，第二天你就能在 Releases 收到新版 IPA
- 想 fork 到自己账号使用的话，只要 fork 本仓库、开启 Actions、设置 `Actions → General → Read and write permissions` 即可，不需要任何其他准备
</details>

---

## 📝 免责声明

本仓库仅为自动化构建脚本的集合，**不包含任何游戏源代码、美术资源或音频资源**。
所有游戏版权、商标、美术著作权归 **Electronic Arts Inc. (EA) / PopCap** 及其原作者所有。本脚本仅供学习、研究自动化构建流程使用。
请下载构建产物的用户**确保自身拥有游戏原版的合法使用授权**，任何违规分发或商用行为与本仓库维护者无关。

---

## 📜 协议声明（License）

本项目 `pvzge-ios-builder` 以 **MIT License** 开源，详见仓库根目录的 [LICENSE](LICENSE) 文件。

> **重要说明**：本 License **仅覆盖本仓库的自动化构建/打包脚本与工作流代码**，**不代表、不包含、不授予对任何游戏资源（代码、美术、音频等）的使用权**。游戏资源版权始终归其原作者所有，请另行遵守对方的授权与条款。

---

## 🛠️ 本仓库文件结构

```
.
├── .github/
│   └── workflows/
│       └── auto-release.yml       # Build & Auto Release：检测官方更新 → 构建IPA(正式+Lite) → 发布
├── capacitor-project/             # 本地的 Capacitor 工程模板（appId/appName/webDir 配置）
│   ├── capacitor.config.json
│   └── package.json
├── scripts/                       # 所有构建逻辑，供 workflow 调用，便于本地调试
│   ├── build-ipa.sh               # 初始化 Capacitor + 无签名编译 + 打包 unsigned IPA
│   ├── check-version.sh           # 检测官方版本/commit，决定是否发版
│   ├── create-release.sh          # 计算 SHA256 / 体积 + 生成 Release notes
│   ├── prepare-lite.sh            # 生成 Lite 版（PNG/MP3 有损压缩）
│   └── sanitize-web.sh            # 清理 index.html 中的广告/统计/隐私同意代码
├── .gitignore                     # 仅忽略 .vscode
├── LICENSE                        # MIT 开源许可证
└── README.md                      # 本文件
```

**🎉 Enjoy defending your endless garden on iPhone! 🌻🧟**
