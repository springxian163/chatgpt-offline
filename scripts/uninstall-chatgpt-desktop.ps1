<#
.SYNOPSIS
    彻底卸载 ChatGPT 桌面版（MSIX），并清理常见残留。

.DESCRIPTION
    依次执行：结束进程 → 移除所有用户的应用包 → 取消整机预置 →
    删除残留的沙箱服务 → 清理执行别名。用户数据默认保留。

.PARAMETER Force
    不再逐项确认，直接执行。

.PARAMETER RemoveUserData
    同时删除应用数据目录（登录状态、缓存、设置会全部丢失）。

.PARAMETER RemoveCliConfig
    同时删除 Codex CLI 配置目录 %USERPROFILE%\.codex。

.PARAMETER CleanFirewall
    同时删除该应用注册的防火墙规则。

.PARAMETER NoPause
    结束时不等待按键。

.EXAMPLE
    .\uninstall-chatgpt-desktop.ps1
    .\uninstall-chatgpt-desktop.ps1 -Force -RemoveUserData -CleanFirewall
#>
[CmdletBinding()]
param(
    [switch] $Force,
    [switch] $RemoveUserData,
    [switch] $RemoveCliConfig,
    [switch] $CleanFirewall,
    [switch] $NoPause
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$logFile  = Start-AppLog -Name 'uninstall'
$exitCode = 0
$removed  = @()
$failed   = @()

try {
    Write-Banner 'ChatGPT 桌面版 · 卸载与清理'

    $isAdmin = Test-IsAdmin
    if (-not $isAdmin) {
        Write-Warn2 '当前没有管理员权限：只能卸载当前用户的安装，整机预置与系统服务无法清理。'
        Write-Host ''
    }

    # ---------------------------------------------------------
    # 1. 盘点
    # ---------------------------------------------------------
    Write-Step '检查安装状态'

    $pkgs = @(Get-AppxPackage -Name $AppPackageName -AllUsers:$isAdmin -ErrorAction SilentlyContinue)
    $prov = @()
    if ($isAdmin) {
        try {
            $prov = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
                      Where-Object { $_.DisplayName -eq $AppPackageName })
        } catch { }
    }
    $svc = Get-Service -Name $AppServiceName -ErrorAction SilentlyContinue

    if ($pkgs.Count -eq 0 -and $prov.Count -eq 0 -and -not $svc) {
        Write-Ok '系统中没有检测到 ChatGPT 桌面版，无需卸载。'
        Write-Info '如仅想清理残留数据，可加 -RemoveUserData 或 -RemoveCliConfig 参数重新运行。'
        if (-not ($RemoveUserData -or $RemoveCliConfig -or $CleanFirewall)) { return }
    } else {
        foreach ($p in $pkgs) { Write-Info "应用包    : $($p.PackageFullName)" }
        if ($prov.Count -gt 0) { Write-Info "整机预置  : $($prov.Count) 项" }
        if ($svc)              { Write-Info "系统服务  : $($svc.Name) [$($svc.Status)]" }
    }
    Write-Host ''

    # ---------------------------------------------------------
    # 2. 确认
    # ---------------------------------------------------------
    if (-not $Force) {
        Write-Host '即将执行的操作：' -ForegroundColor White
        Write-Host '  · 卸载 ChatGPT 桌面版应用包' -ForegroundColor Gray
        Write-Host '  · 清理整机预置与残留的沙箱服务' -ForegroundColor Gray
        Write-Host ("  · 应用数据（登录状态/缓存）: " + $(if ($RemoveUserData) { '一并删除' } else { '保留' })) -ForegroundColor Gray
        Write-Host ("  · Codex CLI 配置 (~/.codex): "  + $(if ($RemoveCliConfig) { '一并删除' } else { '保留' })) -ForegroundColor Gray
        Write-Host ("  · 防火墙规则: "                 + $(if ($CleanFirewall)  { '一并删除' } else { '保留' })) -ForegroundColor Gray
        Write-Host ''
        $ans = Read-Host '确认继续？输入 Y 开始卸载，其他键取消'
        if ($ans -notmatch '^[Yy]') { Write-Warn2 '已取消，未做任何改动。'; return }
        Write-Host ''
    }

    # ---------------------------------------------------------
    # 3. 结束进程
    # ---------------------------------------------------------
    Write-Step '结束正在运行的进程'
    $names = @('ChatGPT', 'Codex', 'codex', 'chrome_proxy', 'codex-command-runner',
               'codex-windows-sandbox-service', 'extension-host')
    $killed = 0
    foreach ($n in $names) {
        Get-Process -Name $n -ErrorAction SilentlyContinue | ForEach-Object {
            try { Stop-Process -Id $_.Id -Force -ErrorAction Stop; $killed++ } catch { }
        }
    }
    if ($killed -gt 0) {
        Write-Ok "已结束 $killed 个进程"
        Start-Sleep -Seconds 2
    } else {
        Write-Info '没有正在运行的相关进程'
    }
    Write-Host ''

    # ---------------------------------------------------------
    # 4. 卸载应用包
    # ---------------------------------------------------------
    if ($pkgs.Count -gt 0) {
        Write-Step '卸载应用包'
        foreach ($p in $pkgs) {
            try {
                if ($isAdmin) {
                    Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction Stop
                } else {
                    Remove-AppxPackage -Package $p.PackageFullName -ErrorAction Stop
                }
                Write-Ok "已卸载 $($p.PackageFullName)"
                $removed += '应用包'
            } catch {
                Write-Err2 "卸载失败: $($p.PackageFullName)"
                Write-Info $_.Exception.Message
                $failed += '应用包'
            }
        }
        Write-Host ''
    }

    # ---------------------------------------------------------
    # 5. 取消整机预置
    # ---------------------------------------------------------
    if ($prov.Count -gt 0) {
        Write-Step '取消整机预置'
        foreach ($p in $prov) {
            try {
                # -AllUsers 在较老的 Windows 版本上不存在，失败后退回不带该参数的调用
                try {
                    Remove-AppxProvisionedPackage -Online -PackageName $p.PackageName -AllUsers -ErrorAction Stop | Out-Null
                } catch [System.Management.Automation.ParameterBindingException] {
                    Remove-AppxProvisionedPackage -Online -PackageName $p.PackageName -ErrorAction Stop | Out-Null
                }
                Write-Ok "已移除预置 $($p.PackageName)"
                $removed += '整机预置'
            } catch {
                Write-Warn2 "移除预置失败: $($_.Exception.Message)"
                $failed += '整机预置'
            }
        }
        Write-Host ''
    }

    # ---------------------------------------------------------
    # 6. 清理残留服务（卸载后偶尔会留下"幽灵服务"）
    # ---------------------------------------------------------
    if ($isAdmin) {
        Write-Step '检查残留系统服务'
        $svc = Get-Service -Name $AppServiceName -ErrorAction SilentlyContinue
        if ($svc) {
            try {
                if ($svc.Status -ne 'Stopped') {
                    Stop-Service -Name $AppServiceName -Force -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 1
                }
                $out = & sc.exe delete $AppServiceName 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Ok "已删除残留服务 $AppServiceName"
                    $removed += '沙箱服务'
                } else {
                    Write-Warn2 "删除服务返回码 $LASTEXITCODE : $out"
                    Write-Info '该服务通常会在重启后自动消失。'
                }
            } catch {
                Write-Warn2 "处理服务时出错: $($_.Exception.Message)"
            }
        } else {
            Write-Info '没有残留服务'
        }
        Write-Host ''
    }

    # ---------------------------------------------------------
    # 7. 清理执行别名
    # ---------------------------------------------------------
    Write-Step '清理命令行执行别名'
    $aliasDir = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps'
    $aliases  = @('codex-chrome-native-host.exe', 'codex-core-command-runner.exe')
    $aliasHit = 0
    foreach ($a in $aliases) {
        $ap = Join-Path $aliasDir $a
        if (Test-Path -LiteralPath $ap) {
            try { Remove-Item -LiteralPath $ap -Force -ErrorAction Stop; $aliasHit++ } catch { }
        }
    }
    if ($aliasHit -gt 0) { Write-Ok "已清理 $aliasHit 个执行别名" } else { Write-Info '没有残留别名' }
    Write-Host ''

    # ---------------------------------------------------------
    # 8. 可选：应用数据
    # ---------------------------------------------------------
    if ($RemoveUserData) {
        Write-Step '删除应用数据'
        $dataDirs = @(
            (Join-Path $env:LOCALAPPDATA "Packages\$AppFamilyName"),
            (Join-Path $env:LOCALAPPDATA 'OpenAI')
        )
        foreach ($d in $dataDirs) {
            if (Test-Path -LiteralPath $d) {
                try {
                    Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction Stop
                    Write-Ok "已删除 $d"
                    $removed += '应用数据'
                } catch {
                    Write-Warn2 "删除失败 $d"
                    Write-Info $_.Exception.Message
                    $failed += '应用数据'
                }
            }
        }
        Write-Host ''
    }

    # ---------------------------------------------------------
    # 9. 可选：CLI 配置
    # ---------------------------------------------------------
    if ($RemoveCliConfig) {
        Write-Step '删除 Codex CLI 配置'
        $cli = Join-Path $env:USERPROFILE '.codex'
        if (Test-Path -LiteralPath $cli) {
            try {
                Remove-Item -LiteralPath $cli -Recurse -Force -ErrorAction Stop
                Write-Ok "已删除 $cli"
                $removed += 'CLI 配置'
            } catch {
                Write-Warn2 "删除失败：$($_.Exception.Message)"
                $failed += 'CLI 配置'
            }
        } else {
            Write-Info '没有 CLI 配置目录'
        }
        Write-Host ''
    }

    # ---------------------------------------------------------
    # 10. 可选：防火墙规则
    # ---------------------------------------------------------
    if ($CleanFirewall) {
        Write-Step '清理防火墙规则'
        if (-not $isAdmin) {
            Write-Warn2 '需要管理员权限，已跳过。'
        } else {
            try {
                $rules = @(Get-NetFirewallRule -ErrorAction SilentlyContinue |
                           Where-Object { $_.DisplayName -match 'ChatGPT|Codex|OpenAI' })
                if ($rules.Count -gt 0) {
                    $rules | Remove-NetFirewallRule -ErrorAction SilentlyContinue
                    Write-Ok "已删除 $($rules.Count) 条防火墙规则"
                    $removed += '防火墙规则'
                } else {
                    Write-Info '没有匹配的防火墙规则'
                }
            } catch {
                Write-Warn2 "清理防火墙规则失败：$($_.Exception.Message)"
            }
        }
        Write-Host ''
    }

    # ---------------------------------------------------------
    # 11. 汇总
    # ---------------------------------------------------------
    Write-Step '复查卸载结果'
    $left = @(Get-AppxPackage -Name $AppPackageName -ErrorAction SilentlyContinue)
    if ($left.Count -eq 0) {
        Write-Ok 'ChatGPT 桌面版已从本机移除'
    } else {
        Write-Warn2 "仍有 $($left.Count) 个包未移除，可能被其他已登录用户占用，重启后再运行一次本脚本。"
        $exitCode = 1
    }

    Write-Host ''
    Write-Host '───────────────────────────────────────────────' -ForegroundColor DarkGray
    if ($removed.Count -gt 0) {
        Write-Host (' 已清理: ' + (($removed | Select-Object -Unique) -join '、')) -ForegroundColor Gray
    }
    if ($failed.Count -gt 0) {
        Write-Host (' 未完成: ' + (($failed  | Select-Object -Unique) -join '、')) -ForegroundColor Yellow
    }
    if (-not $RemoveUserData) {
        Write-Host ' 提示: 登录状态与本地数据已保留，重装后可直接继续使用。' -ForegroundColor DarkGray
        Write-Host '       如需彻底清空，请加 -RemoveUserData 参数重新运行。' -ForegroundColor DarkGray
    }
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
