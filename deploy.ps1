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
Write-Host "[1/5] 创建远程目录..." -ForegroundColor Yellow
Remote-Run "mkdir -p $RemotePath/config"

# 步骤 2: 上传代码
Write-Host "[2/5] 上传文件..." -ForegroundColor Yellow
Remote-Upload-Dir  "$LocalBackend\src"          "$RemotePath/"
Remote-Upload-Dir  "$LocalBackend\public"       "$RemotePath/"
Remote-Upload-Dir  "$LocalBackend\scripts"      "$RemotePath/"
Remote-Upload-File "$LocalBackend\package.json" "$RemotePath/package.json"
Remote-Upload-File "$LocalBackend\.env"         "$RemotePath/.env"

# 步骤 2.3: 备份和恢复配置文件（保留用户自定义配置）
Write-Host "[2.3/5] 备份和恢复用户配置..." -ForegroundColor Yellow
# 检查远程是否有现有配置，如果有则备份
Remote-Run "if [ -f $RemotePath/config/ai_settings.json ]; then cp $RemotePath/config/ai_settings.json $RemotePath/config/ai_settings.json.backup; echo '已备份ai_settings'; fi"
Remote-Run "if [ -f $RemotePath/config/feature_tiers.json ]; then cp $RemotePath/config/feature_tiers.json $RemotePath/config/feature_tiers.json.backup; echo '已备份feature_tiers'; fi"

# 上传新的配置文件（必须存在于本地）
if (Test-Path "$LocalBackend\config\ai_settings.json") {
    Remote-Upload-File "$LocalBackend\config\ai_settings.json" "$RemotePath/config/ai_settings.json"
    Write-Host "  - 已上传 ai_settings.json" -ForegroundColor Gray
} else {
    Write-Host "  - 警告: 本地不存在 ai_settings.json" -ForegroundColor Yellow
}

if (Test-Path "$LocalBackend\config\feature_tiers.json") {
    Remote-Upload-File "$LocalBackend\config\feature_tiers.json" "$RemotePath/config/feature_tiers.json"
    Write-Host "  - 已上传 feature_tiers.json" -ForegroundColor Gray
} else {
    Write-Host "  - 警告: 本地不存在 feature_tiers.json" -ForegroundColor Yellow
}

# 恢复关键配置（如果备份存在且新上传的配置不完整）
Remote-Run "cd $RemotePath/config && [ -f ai_settings.json.backup ] && ! grep -q 'api_key' ai_settings.json 2>/dev/null && cp ai_settings.json.backup ai_settings.json && echo '已恢复ai_settings' || echo '已使用新ai_settings'"

# 步骤 2.5: 修复 pscp 导致的日文文件名编码（EUC-JP → UTF-8）
Write-Host "[2.5/5] 修复SVG文件名编码..." -ForegroundColor Yellow
Remote-Run "which convmv >/dev/null 2>&1 || dnf install -y convmv >/dev/null 2>&1"
Remote-Run "cd $RemotePath/public/app/svg/kana/hiragana && convmv -f euc-jp -t utf-8 --notest *.svg 2>/dev/null; cd $RemotePath/public/app/svg/kana/katakana && convmv -f euc-jp -t utf-8 --notest *.svg 2>/dev/null; echo done"

# 步骤 3: npm install
Write-Host "[3/5] 安装依赖..." -ForegroundColor Yellow
Remote-Run "cd $RemotePath; npm install --production 2>&1 | tail -n 5"

# 步骤 4: pm2 启动/重启
Write-Host "[4/5] 启动服务..." -ForegroundColor Yellow
# 先尝试 restart，失败则 delete + start
Remote-Run "cd $RemotePath && pm2 restart japanese-learn 2>/dev/null || pm2 start src/app.js --name japanese-learn"
Remote-Run "pm2 save --force"
Remote-Run "pm2 list"

Write-Host ""
Write-Host "[5/5] 部署完成" -ForegroundColor Green
Write-Host "  API:  http://${ServerHost}:8002/api/v1" -ForegroundColor Cyan
Write-Host "  后台: http://${ServerHost}:8002/admin/" -ForegroundColor Cyan
