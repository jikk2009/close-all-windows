#Requires -Version 5.1
<#
.SYNOPSIS
    构建「关窗」安装包：编译启动器 + 组装目录 + 打包 zip。

.DESCRIPTION
    只依赖 Windows 自带的 .NET Framework 4.x（csc.exe），不需要装任何 SDK。
    产物：
        dist\关窗-安装包\        可直接双击安装的目录
        dist\关窗-安装包.zip     分发给别人的压缩包

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\build\build.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File .\build\build.ps1 -SkipCompile
#>
[CmdletBinding()]
param(
    [switch]$SkipCompile
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root  = Split-Path -Parent $PSScriptRoot
$dist  = Join-Path $root 'dist'
$pkg   = Join-Path $dist '关窗-安装包'
$zip   = Join-Path $dist '关窗-安装包.zip'
$exe   = Join-Path $dist '关窗.exe'
$icon  = Join-Path $root 'assets\closeall.ico'
$srcDir = Join-Path $root 'src'
$insDir = Join-Path $root 'installer'
$docDir = Join-Path $root 'docs'

Write-Host "仓库根目录: $root" -ForegroundColor Cyan

# ---------- 1. 编译启动器 ----------
if ($SkipCompile -and (Test-Path -LiteralPath $exe)) {
    Write-Host '跳过编译，沿用已有的 关窗.exe' -ForegroundColor DarkGray
}
else {
    $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    if (-not (Test-Path -LiteralPath $csc)) {
        $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
    }
    if (-not (Test-Path -LiteralPath $csc)) {
        throw '找不到 csc.exe，需要 .NET Framework 4.x（Windows 10/11 自带）'
    }

    New-Item -ItemType Directory -Path $dist -Force | Out-Null
    Write-Host '编译 src\Launcher.cs -> 关窗.exe' -ForegroundColor Cyan
    & $csc /nologo /target:winexe /optimize+ /platform:anycpu `
        "/win32icon:$icon" "/out:$exe" (Join-Path $srcDir 'Launcher.cs')
    if ($LASTEXITCODE -ne 0) { throw "编译失败（csc 退出码 $LASTEXITCODE）" }
    Write-Host ('  完成：{0:N0} 字节' -f (Get-Item -LiteralPath $exe).Length) -ForegroundColor Green
}

# ---------- 2. 组装安装包目录 ----------
if (Test-Path -LiteralPath $pkg) { Remove-Item -LiteralPath $pkg -Recurse -Force }
New-Item -ItemType Directory -Path $pkg -Force | Out-Null

$map = @(
    @{ From = $exe;                                  To = '关窗.exe' },
    @{ From = (Join-Path $srcDir 'CloseAllWindows.ps1');    To = 'CloseAllWindows.ps1' },
    @{ From = (Join-Path $srcDir 'CloseAllWindows.Ui.ps1'); To = 'CloseAllWindows.Ui.ps1' },
    @{ From = $icon;                                 To = 'closeall.ico' },
    @{ From = (Join-Path $insDir 'install.ps1');     To = 'install.ps1' },
    @{ From = (Join-Path $insDir 'uninstall.ps1');   To = 'uninstall.ps1' },
    @{ From = (Join-Path $insDir '安装.cmd');           To = '安装.cmd' },
    @{ From = (Join-Path $insDir '卸载.cmd');           To = '卸载.cmd' },
    @{ From = (Join-Path $docDir '使用说明.txt');        To = '使用说明.txt' }
)

foreach ($item in $map) {
    if (-not (Test-Path -LiteralPath $item.From)) { throw "缺少文件：$($item.From)" }
    Copy-Item -LiteralPath $item.From -Destination (Join-Path $pkg $item.To) -Force
}
Write-Host "已组装 $pkg" -ForegroundColor Cyan

# ---------- 3. 打包 ----------
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
# includeBaseDirectory = $true：解压后是一个「关窗-安装包」文件夹，不会把文件撒到当前目录
[System.IO.Compression.ZipFile]::CreateFromDirectory(
    $pkg, $zip, [System.IO.Compression.CompressionLevel]::Optimal, $true)
Write-Host ('已打包 {0}（{1:N0} 字节）' -f $zip, (Get-Item -LiteralPath $zip).Length) -ForegroundColor Green

Write-Host ''
Write-Host '构建完成。分发给别人时用：' -ForegroundColor Yellow
Write-Host "  $zip"
