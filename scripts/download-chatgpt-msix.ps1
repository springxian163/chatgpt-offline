<#
.SYNOPSIS
    从 OpenAI 官方源下载 ChatGPT 桌面版 MSIX 安装包及离线授权文件。

.DESCRIPTION
    支持断点续传（优先使用系统自带的 curl.exe，其次 BITS）。
    下载完成后自动校验文件大小与数字签名。

.PARAMETER Arch
    目标架构：auto（默认，跟随当前系统）、x64、arm64。

.PARAMETER OutDir
    输出目录，默认为仓库的 pkg\ 目录。

.PARAMETER Force
    已存在同名文件时重新下载（而不是续传/跳过）。

.PARAMETER NoPause
    结束时不等待按键。

.EXAMPLE
    .\download-chatgpt-msix.ps1
    .\download-chatgpt-msix.ps1 -Arch arm64 -Force
#>
[CmdletBinding()]
param(
    [ValidateSet('auto', 'x64', 'arm64')]
    [string] $Arch = 'auto',
    [string] $OutDir,
    [switch] $Force,
    [switch] $NoPause
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$logFile  = Start-AppLog -Name 'download'
$exitCode = 0

function Get-RemoteSize {
    param([string]$Url)
    try {
        $req = [System.Net.HttpWebRequest]::Create($Url)
        $req.Method  = 'HEAD'
        $req.Timeout = 30000
        $resp = $req.GetResponse()
        $len  = $resp.ContentLength
        $resp.Close()
        return [int64]$len
    } catch { return [int64]-1 }
}

function Invoke-Download {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$Destination,
        [switch]$Resume
    )

    $curl = Join-Path $env:SystemRoot 'System32\curl.exe'
    if (Test-Path -LiteralPath $curl) {
        Write-Info '下载引擎: curl.exe（支持断点续传）'
        $args = @('-L', '--fail', '--retry', '3', '--retry-delay', '2',
                  '--connect-timeout', '30', '--progress-bar', '-o', $Destination)
        if ($Resume) { $args += @('-C', '-') }
        $args += $Url
        & $curl @args
        if ($LASTEXITCODE -ne 0) { throw "curl 下载失败，退出码 $LASTEXITCODE。" }
        return
    }

    if (Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue) {
        Write-Info '下载引擎: BITS'
        Start-BitsTransfer -Source $Url -Destination $Destination -Description 'ChatGPT MSIX' -ErrorAction Stop
        return
    }

    Write-Info '下载引擎: Invoke-WebRequest（无进度显示，请耐心等待）'
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing -ErrorAction Stop
}

try {
    Write-Banner 'ChatGPT 桌面版 · 下载安装包'

    # 1. 目标架构
    if ($Arch -eq 'auto') {
        $Arch = Get-SystemArch
        if ($Arch -eq 'x86') { throw 'ChatGPT 桌面版不支持 32 位系统。' }
        Write-Info "自动识别架构: $Arch"
    } else {
        Write-Info "指定架构: $Arch"
    }

    $url = if ($Arch -eq 'arm64') { $UrlMsixArm64 } else { $UrlMsixX64 }

    # 2. 输出目录
    if (-not $OutDir) { $OutDir = $PkgDir }
    if (-not (Test-Path -LiteralPath $OutDir)) {
        New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
    }
    $OutDir = (Resolve-Path -LiteralPath $OutDir).Path
    $dest   = Join-Path $OutDir "ChatGPT-$Arch.msix"

    Write-Info "下载地址: $url"
    Write-Info "保存位置: $dest"
    Write-Host ''

    # 3. 查询远端大小
    Write-Step '查询官方安装包信息'
    $remoteSize = Get-RemoteSize -Url $url
    if ($remoteSize -gt 0) {
        Write-Info "官方文件大小: $(Format-Size $remoteSize)"
    } else {
        Write-Warn2 '无法获取文件大小（不影响下载），请检查网络是否可以访问 oaistatic.com。'
    }

    # 4. 已有文件的处理
    $resume = $false
    $skip   = $false
    if (Test-Path -LiteralPath $dest) {
        $local = (Get-Item -LiteralPath $dest).Length
        Write-Info "本地已有文件: $(Format-Size $local)"

        if ($Force) {
            Write-Warn2 '已指定 -Force，删除旧文件重新下载。'
            Remove-Item -LiteralPath $dest -Force
        } elseif ($remoteSize -gt 0 -and $local -eq $remoteSize) {
            Write-Ok '本地文件已完整，跳过下载。'
            $skip = $true
        } elseif ($remoteSize -gt 0 -and $local -lt $remoteSize) {
            Write-Warn2 '本地文件不完整，将从断点处继续下载。'
            $resume = $true
        } else {
            Write-Warn2 '本地文件异常，删除后重新下载。'
            Remove-Item -LiteralPath $dest -Force
        }
    }
    Write-Host ''

    # 5. 下载主体
    if (-not $skip) {
        Write-Step "下载安装包（约 $(if ($remoteSize -gt 0) { Format-Size $remoteSize } else { '800 MB' })）"
        Write-Info '文件较大，请保持网络通畅；中断后重新运行本脚本可继续下载。'
        Write-Host ''

        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        Invoke-Download -Url $url -Destination $dest -Resume:$resume
        $sw.Stop()

        Write-Host ''
        $got = (Get-Item -LiteralPath $dest).Length
        $sec = [math]::Max($sw.Elapsed.TotalSeconds, 1)
        Write-Ok "下载完成: $(Format-Size $got)，用时 $([math]::Round($sw.Elapsed.TotalMinutes,1)) 分钟（平均 $(Format-Size ($got/$sec))/s）"

        if ($remoteSize -gt 0 -and $got -ne $remoteSize) {
            throw "文件大小不符：期望 $(Format-Size $remoteSize)，实际 $(Format-Size $got)。请重新运行本脚本续传。"
        }
    }
    Write-Host ''

    # 6. 授权文件
    Write-Step '下载离线授权文件'
    $licDest = Join-Path $OutDir 'ChatGPT-License.xml'
    try {
        Invoke-WebRequest -Uri $UrlLicense -OutFile $licDest -UseBasicParsing -ErrorAction Stop
        Write-Ok "已保存 ChatGPT-License.xml（$(Format-Size (Get-Item -LiteralPath $licDest).Length)）"
    } catch {
        Write-Warn2 "授权文件下载失败：$($_.Exception.Message)"
        Write-Info '不影响安装，安装脚本会自动改用 -SkipLicense 方式。'
    }
    Write-Host ''

    # 7. 校验
    Write-Step '校验安装包'
    $info = Get-MsixInfo -Path $dest
    Write-Info "包标识: $($info.Name) $($info.Version) [$($info.Architecture)]"
    Write-Info "显示名: $($info.DisplayName)"

    $sig = Test-MsixSignature -Path $dest
    if ($sig.Valid) {
        Write-Info "签名主体: $($sig.Subject)"
        Write-Ok '数字签名有效'
    } else {
        Write-Err2 "签名校验未通过：$($sig.Status)"
        throw '安装包签名异常，请删除文件后重新下载。'
    }

    $sha = (Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash
    Write-Info "SHA256: $sha"

    Write-Host ''
    Write-Host '───────────────────────────────────────────────' -ForegroundColor DarkGray
    Write-Host ' 安装包已就绪。' -ForegroundColor White
    Write-Host ' 接下来双击运行「安装ChatGPT桌面版.bat」即可完成安装。' -ForegroundColor Gray
    Write-Host '───────────────────────────────────────────────' -ForegroundColor DarkGray

} catch {
    Write-Host ''
    Show-FriendlyError -ErrorRecord $_
    Write-Host ''
    Write-Info "完整日志: $logFile"
    $exitCode = 1
} finally {
    Write-Host ''
    Stop-AppLog
    if (-not $NoPause) {
        Write-Host '按任意键关闭窗口…' -ForegroundColor DarkGray
        try { $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') } catch { Read-Host | Out-Null }
    }
    exit $exitCode
}
