# ChatGPT 桌面版离线安装工具

一套 Windows 小脚本，帮你在**不打开微软商店**的前提下，下载、安装、卸载 ChatGPT 桌面版（MSIX）。

全部操作双击 `.bat` 即可完成，不需要懂命令行。

> 适用场景：内网/离线机器、商店被禁用或登录不上、批量装机、安装卡住需要干净重来。

---

## 适用环境

| 项目 | 要求 |
| --- | --- |
| 操作系统 | Windows 10 Build 19041（2004 版）及以上 / Windows 11 |
| CPU 架构 | x64 或 arm64（不支持 32 位） |
| 磁盘空间 | 约 3 GB（安装包 786 MB，展开后约 1.9 GB） |
| 权限 | 建议管理员（可整机预置）；普通用户也能只装给自己 |

> 已实测通过：Windows 11 Build 26200 + Windows PowerShell 5.1，x64，全新安装耗时约 45 秒。

---

## 快速开始

### 情况一：已经有 MSIX 安装包

1. 把安装包改名为 `ChatGPT-x64.msix`（arm64 机器则为 `ChatGPT-arm64.msix`），放进 `pkg\` 目录。
2. 双击 **`安装ChatGPT桌面版.bat`**，在 UAC 弹窗点「是」。
3. 等待 1–5 分钟，看到绿色的「安装成功」即可。按 Win 键搜索 `ChatGPT` 启动。

### 情况二：还没有安装包

1. 双击 **`下载ChatGPT安装包.bat`**，从 OpenAI 官方源下载（支持断点续传，断了重跑即可）。
2. 再双击 **`安装ChatGPT桌面版.bat`**。

### 卸载

双击 **`卸载ChatGPT桌面版.bat`**。默认保留登录状态和本地数据，重装后可直接继续用。

### 验证及登录

桌面版chatgpt需要验证外国手机号，没有外国手机号在
接码平台
https://hero-sms.com/cn
账号
SPRING-XIAN@163.COM
.0B

---

## 目录结构

```
chatgpt-offline/
├─ 安装ChatGPT桌面版.bat        ← 安装入口（自动请求管理员权限）
├─ 卸载ChatGPT桌面版.bat        ← 卸载入口（自动请求管理员权限）
├─ 下载ChatGPT安装包.bat        ← 下载入口（无需管理员）
├─ scripts/
│  ├─ common.ps1                 公共函数：环境检测、包解析、错误码翻译
│  ├─ install-chatgpt-desktop.ps1
│  ├─ uninstall-chatgpt-desktop.ps1
│  └─ download-chatgpt-msix.ps1
├─ pkg/                          安装包与离线授权文件存放处
│  ├─ ChatGPT-x64.msix           （体积大，已在 .gitignore 中排除）
│  └─ ChatGPT-License.xml        离线授权文件，用于整机预置
└─ log/                          每次运行的完整日志，排查问题时看这里
```

---

## 安装脚本做了什么

1. **环境自检** — 系统版本、CPU 架构、管理员权限、磁盘余量，任一不满足就明确告诉你缺什么。
2. **校验安装包** — 直接读取 MSIX 内部的 `AppxManifest.xml`，确认包标识、版本、架构与本机匹配；体积异常（下载不全）会被拦下。
3. **校验数字签名** — 必须是微软商店签发的有效签名才继续，防止装到被篡改的包。
4. **处理旧版本** — 同版本跳过、低版本升级、高版本降级前先征求确认。
5. **开启旁加载** — 若系统策略禁止安装本地应用包，自动放行。
6. **安装** — 先给当前用户装好（立刻可用），再整机预置（新建的用户账户登录后也能直接用）。
7. **复查** — 确认包已注册、沙箱服务状态正常，并打印安装位置。

## 卸载脚本做了什么

除了常规卸载，还会清理标准卸载常留下的尾巴：

- 结束仍在后台跑的 `ChatGPT.exe` / `codex.exe` 等进程（否则卸载会报"应用正在使用中"）
- 移除**所有用户**的应用包，并取消整机预置
- 删除残留的系统服务 `CodexSandboxService.OpenAI.Codex`（俗称"幽灵服务"）
- 清理 `WindowsApps` 下失效的命令行别名

---

## 参数用法（进阶）

`.bat` 后面跟的参数会原样传给 PowerShell 脚本，也可以直接调用 `.ps1`。

### 安装

| 参数 | 作用 |
| --- | --- |
| `-PackagePath <路径>` | 指定安装包位置，不从 `pkg\` 找 |
| `-Force` | 跳过确认，强制覆盖安装 |
| `-SkipProvision` | 只装给当前用户，不做整机预置 |
| `-NoPause` | 结束后不等待按键（适合脚本化/批量装机） |

```powershell
# 静默装机
powershell -ExecutionPolicy Bypass -File scripts\install-chatgpt-desktop.ps1 -Force -NoPause
```

### 卸载

| 参数 | 作用 |
| --- | --- |
| `-Force` | 跳过确认 |
| `-RemoveUserData` | 连同登录状态、缓存、设置一并删除（`%LOCALAPPDATA%\Packages\OpenAI.Codex_*` 与 `%LOCALAPPDATA%\OpenAI`） |
| `-RemoveCliConfig` | 删除 `%USERPROFILE%\.codex` |
| `-CleanFirewall` | 删除应用注册的防火墙规则 |
| `-NoPause` | 结束后不等待按键 |

```powershell
# 彻底清除，一点不留
powershell -ExecutionPolicy Bypass -File scripts\uninstall-chatgpt-desktop.ps1 -Force -RemoveUserData -RemoveCliConfig -CleanFirewall
```

### 下载

| 参数 | 作用 |
| --- | --- |
| `-Arch auto\|x64\|arm64` | 目标架构，默认跟随当前系统 |
| `-OutDir <目录>` | 输出目录，默认 `pkg\` |
| `-Force` | 删除已有文件重新下载（默认是续传） |

---

## 安装包来源与校验

安装包全部来自 OpenAI 官方 CDN，脚本不做任何二次打包或修改：

- x64：`https://persistent.oaistatic.com/codex-app-prod/ChatGPT-x64.msix`
- arm64：`https://persistent.oaistatic.com/codex-app-prod/ChatGPT-arm64.msix`
- 离线授权：`https://persistent.oaistatic.com/codex-app-prod/ChatGPT-License.xml`

当前随仓库验证过的版本：

| 项目 | 值 |
| --- | --- |
| 包标识 | `OpenAI.Codex` |
| 包全名 | `OpenAI.Codex_2p2nqsd0c76g0` |
| 显示名 | ChatGPT |
| 版本 | 26.915.4065.0 |
| 大小 | 824,570,408 字节（786.4 MB） |
| SHA256 | `fb4745f5378c8a4122f74643a3c7c1000da5f4b184f0d9dc9faf275c79ac73a4` |
| 签名主体 | `CN=50BDFD77-8903-4850-9FFE-6E8522F64D5B`（OpenAI 商店发布者标识） |
| 证书链 | Microsoft Marketplace CA G 027 → Microsoft MarketPlace PCA 2011 → Microsoft Root Certificate Authority 2011 |

自行核对：

```powershell
Get-FileHash .\pkg\ChatGPT-x64.msix -Algorithm SHA256
Get-AuthenticodeSignature .\pkg\ChatGPT-x64.msix | Format-List Status, SignerCertificate
```

> 版本会随官方更新而变化。SHA256 对不上不代表文件有问题——先看 `Get-AuthenticodeSignature` 的 `Status` 是不是 `Valid`，那才是判断来源可信的依据。

---

## 常见问题

**装完了，开始菜单里搜不到？**
按 Win 键直接输 `chatgpt`。若仍搜不到，注销一次再登录；整机预置的包需要重新登录才对已有账户生效。

**提示"应用正在使用中"（0x80073D02）**
ChatGPT 没完全退出。右下角托盘图标右键退出，或在任务管理器里结束 `ChatGPT.exe`，再重试。

**提示"无法安装此应用包"（0x80073CFD）**
系统禁止了旁加载。用管理员身份运行安装脚本，脚本会自动放行；也可手动到「设置 → 系统 → 开发者选项」打开"旁加载应用"。

**提示证书不受信任（0x800B0109）**
安装包在传输中损坏了。删掉 `pkg\` 里的 msix，重新运行下载脚本。

**下载到一半断了**
直接重新运行 `下载ChatGPT安装包.bat`，会从断点继续，不用从头来。

**安装完成时提示"沙箱服务 [Stopped]"，是不是装坏了？**
正常。`CodexSandboxService.OpenAI.Codex` 由应用按需拉起，不是常驻运行，安装刚结束时处于停止状态是预期行为。

**卸载后服务还在**
运行卸载脚本时确保是管理员身份，脚本会主动删除 `CodexSandboxService.OpenAI.Codex`。仍在的话重启一次即可。

**其他问题**
翻 `log\` 目录下对应时间的日志，里面有完整的执行记录和原始报错。

---

## 说明

- 本工具只负责**下载和部署**官方安装包，不修改、不破解、不绕过任何授权。使用 ChatGPT 仍需登录你自己的 OpenAI 账号。
- 与 OpenAI 无任何隶属关系，非官方项目。
- 实现思路参考自 [claude-code-desktop-offline](https://github.com/xqnode/claude-code-desktop-offline)。

## 许可

[CC BY-NC 4.0](LICENSE) — 可自由使用、修改、分享，但不得用于商业用途。
