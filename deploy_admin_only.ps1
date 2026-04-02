# deploy_admin_only.ps1 — 仅部署更新后的管理员界面
param(
    [string]$ServerHost = "139.196.44.6",
    [string]$User       = "root",
    [string]$Passwd     = "Xiaoyun@123",
    [int]   $Port       = 22,
    [string]$RemotePath = "/home/japanese-learn/backend"
)

$LocalBackend = Join-Path $PSScriptRoot "backend"
Write-Host "=== 部署更新的管理员界面到 ${User}@${ServerHost} ===" -ForegroundColor Cyan

# 检测/安装 plink
if (-not (Get-Command plink -EA SilentlyContinue)) {
    Write-Host "[!] 安装 PuTTY..." -ForegroundColor Yellow
    winget install PuTTY.PuTTY -e --silent 2>&1 | Out-Null
    $env:PATH = $env:PATH + ";C:\Program Files\PuTTY"
    if (-not (Get-Command plink -EA SilentlyContinue)) {
        Write-Host "[x] PuTTY 安装失败：https://www.putty.org/" -ForegroundColor Red; exit 1
    }
    Write-Host "[+] PuTTY 安装完成" -ForegroundColor Green
}

# 主机密钥指纹
$HostKey = "SHA256:ySCdPD8LyDCmPPcUT7OjO6r+c0RUwBLMU/UWlOA9GHg"

function Remote-Run([string]$Cmd) {
    & plink -batch -hostkey $HostKey -pw $Passwd -P $Port "${User}@${ServerHost}" $Cmd
}
function Remote-Upload-File([string]$Local, [string]$RemoteFile) {
    & pscp -batch -hostkey $HostKey -pw $Passwd -P $Port $Local "${User}@${ServerHost}:${RemoteFile}"
}

# 部署管理员界面
Write-Host "[1/2] 上传管理员界面..." -ForegroundColor Yellow
Remote-Upload-File "$LocalBackend\public\admin\index.html" "$RemotePath/public/admin/index.html"

# 重启服务
Write-Host "[2/2] 重启服务..." -ForegroundColor Yellow
Remote-Run "cd $RemotePath && pm2 restart japanese-learn"

Write-Host ""
Write-Host "[OK] Admin UI deployed successfully. Please refresh the browser." -ForegroundColor Green
Write-Host "  Admin: http://${ServerHost}:8002/admin/" -ForegroundColor Cyan
