# deploy.ps1 — 自动部署 Japanese Learn 后端（Rocky Linux）
# 使用 PuTTY plink/pscp，自动信任主机密钥、自动输入密码
param(
    [string]$ServerHost = "139.196.44.6",
    [string]$User       = "root",
    [string]$Passwd     = "Xiaoyun@123",
    [int]   $Port       = 22,
    [string]$RemotePath = "/home/japanese-learn/backend"
)

$LocalBackend = Join-Path $PSScriptRoot "backend"
Write-Host "=== 部署 Japanese Learn 到 ${User}@${ServerHost} ===" -ForegroundColor Cyan

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

# 主机密钥指纹（从首次连接中获取，避免每次询问）
$HostKey = "SHA256:ySCdPD8LyDCmPPcUT7OjO6r+c0RUwBLMU/UWlOA9GHg"

function Remote-Run([string]$Cmd) {
    & plink -batch -hostkey $HostKey -pw $Passwd -P $Port "${User}@${ServerHost}" $Cmd
    return $LASTEXITCODE
}
function Remote-Upload-Dir([string]$Local, [string]$RemoteDir) {
    & pscp -batch -hostkey $HostKey -pw $Passwd -P $Port -r $Local "${User}@${ServerHost}:${RemoteDir}"
}
function Remote-Upload-File([string]$Local, [string]$RemoteFile) {
    & pscp -batch -hostkey $HostKey -pw $Passwd -P $Port $Local "${User}@${ServerHost}:${RemoteFile}"
}

# 步骤 1: 创建远程目录
Write-Host "[1/4] 创建远程目录..." -ForegroundColor Yellow
Remote-Run "mkdir -p $RemotePath"

# 步骤 2: 上传代码
Write-Host "[2/4] 上传文件..." -ForegroundColor Yellow
Remote-Upload-Dir  "$LocalBackend\src"          "$RemotePath/"
Remote-Upload-Dir  "$LocalBackend\public"       "$RemotePath/"
Remote-Upload-File "$LocalBackend\package.json" "$RemotePath/package.json"
Remote-Upload-File "$LocalBackend\.env"         "$RemotePath/.env"

# 步骤 3: npm install
Write-Host "[3/4] 安装依赖..." -ForegroundColor Yellow
Remote-Run "cd $RemotePath; npm install --production 2>&1 | tail -n 5"

# 步骤 4: pm2 启动/重启
Write-Host "[4/4] 启动服务..." -ForegroundColor Yellow
$pm2Script = "if pm2 describe japanese-learn > /dev/null 2>&1; then pm2 restart japanese-learn; else pm2 start src/app.js --name japanese-learn; fi; pm2 save --force; pm2 list"
$code = Remote-Run "bash -c 'cd $RemotePath; $pm2Script'"

if ($code -eq 0) {
    Write-Host ""
    Write-Host "=== 部署成功! ===" -ForegroundColor Green
    Write-Host "  API:  http://${ServerHost}:8002/api/v1" -ForegroundColor Cyan
    Write-Host "  后台: http://${ServerHost}:8002/admin/" -ForegroundColor Cyan
} else {
    Write-Host "[x] 部署失败，查看日志: pm2 logs japanese-learn --lines 50" -ForegroundColor Red
    exit 1
}
