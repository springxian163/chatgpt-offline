# pkg —— 安装包目录

把官方 MSIX 安装包放在这里，文件名需符合以下之一：

- `ChatGPT-x64.msix`（Intel/AMD 64 位机器）
- `ChatGPT-arm64.msix`（骁龙等 ARM 机器）

也可以直接运行根目录的 `下载ChatGPT安装包.bat` 自动下载到这里。

`ChatGPT-License.xml` 是官方离线授权文件，用于整机预置（`Add-AppxProvisionedPackage`）。
缺失时安装脚本会自动改用 `-SkipLicense` 方式，不影响安装。

安装包已在 `.gitignore` 中排除，不会被提交到仓库。
