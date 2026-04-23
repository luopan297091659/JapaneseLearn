# deploy.ps1 — 自动部署 言旅 Kotabi 后端（Rocky Linux）
# 使用 PuTTY plink/pscp，自动信任主机密钥、自动输入密码
# 用法: .\deploy.ps1 -Env test   # 部署到测试环境
#       .\deploy.ps1 -Env prod   # 部署到生产环境（默认）
# app 编译:
#       flutter build apk --release # 部署到测试环境
#       flutter build apk --release --dart-define=ENV=prod # 部署到生产环境（默认）
param(
    [ValidateSet('test','prod')]
    [string]$Env        = "prod",
    [string]$User       = "root",
    [string]$Passwd     = "Xiaoyun@123",
    [int]   $Port       = 22,
    [string]$RemotePath = "/home/japanese-learn/backend"
)

# ── 环境配置 ──
$EnvConfig = @{
    test = @{
        ServerHost     = "139.196.44.6"
        HostKey        = "SHA256:ySCdPD8LyDCmPPcUT7OjO6r+c0RUwBLMU/UWlOA9GHg"
        ApiUrl         = "https://139.196.44.6:8002/api/v1"
        AdminUrl       = "https://139.196.44.6:8002/admin/"
        AllowedOrigins = "https://139.196.44.6:8002,http://localhost:8002"
        UseNginx       = $false
    }
    prod = @{
        ServerHost     = "47.76.27.234"
        HostKey        = "SHA256:QH97HV9yERJhO4cuy/DdMVwX0WVAKrQXl7bbvT0Eqls"
        ApiUrl         = "https://www.kotabi.top/api/v1"
        AdminUrl       = "https://www.kotabi.top/admin/"
        AllowedOrigins = "https://www.kotabi.top,https://kotabi.top"
        UseNginx       = $true
    }
}

$Config     = $EnvConfig[$Env]
$ServerHost = $Config.ServerHost
$HostKey    = $Config.HostKey

$LocalBackend = Join-Path $PSScriptRoot "backend"
Write-Host "=== 部署 言旅 Kotabi [$Env] 到 ${User}@${ServerHost} ===" -ForegroundColor Cyan

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
$ConfigFiles = @(
    'ai_settings.json',
    'feature_tiers.json',
    'feature_toggles.json',
    'membership.json',
    'kokoro_tts_settings.py'
)

foreach ($ConfigFile in $ConfigFiles) {
    $RemoteConfig = "$RemotePath/config/$ConfigFile"
    Remote-Run "if [ -f $RemoteConfig ]; then cp $RemoteConfig $RemoteConfig.backup && echo '已备份$ConfigFile'; else echo '$ConfigFile不存在'; fi"
}

# 上传新的配置文件（如果本地存在，否则保留远程备份）
foreach ($ConfigFile in $ConfigFiles) {
    # $LocalConfig = "$LocalBackend\config\$ConfigFile"
    $RemoteConfig = "$RemotePath/config/$ConfigFile"
    Remote-Run "if [ -f $RemoteConfig.backup ]; then cp $RemoteConfig.backup $RemoteConfig && echo '从备份恢复$ConfigFile'; fi"
    Write-Host "  ⚠ 本地不存在 $ConfigFile，保留远程版本" -ForegroundColor Yellow
    # if (Test-Path $LocalConfig) {
        # Remote-Upload-File $LocalConfig "$RemoteConfig"
        # Write-Host "  ✓ 上传 $ConfigFile" -ForegroundColor Gray
        # Remote-Run "if [ -f $RemoteConfig.backup ]; then cp $RemoteConfig.backup $RemoteConfig && echo '从备份恢复$ConfigFile'; fi"
        # Write-Host "  ⚠ 本地不存在 $ConfigFile，保留远程版本" -ForegroundColor Yellow
    # } else {
    #     # 本地不存在，检查远程是否有备份，有则恢复
    #     Remote-Run "if [ -f $RemoteConfig.backup ]; then cp $RemoteConfig.backup $RemoteConfig && echo '从备份恢复$ConfigFile'; fi"
    #     Write-Host "  ⚠ 本地不存在 $ConfigFile，保留远程版本" -ForegroundColor Yellow
    # }
}


Write-Host "  配置文件保留完成" -ForegroundColor Green

# 步骤 2.5: 修复 pscp 导致的日文文件名编码（EUC-JP → UTF-8）
Write-Host "[2.5/5] 修复SVG文件名编码..." -ForegroundColor Yellow
Remote-Run "which convmv >/dev/null 2>&1 || dnf install -y convmv >/dev/null 2>&1"
Remote-Run "cd $RemotePath/public/app/svg/kana/hiragana && convmv -f euc-jp -t utf-8 --notest *.svg 2>/dev/null; cd $RemotePath/public/app/svg/kana/katakana && convmv -f euc-jp -t utf-8 --notest *.svg 2>/dev/null; echo done"

# 步骤 2.7: 生产环境修补远程 .env（ALLOWED_ORIGINS / 禁用 SSL）
if ($Config.UseNginx) {
    Write-Host "[2.7] 修补远程 .env [prod]..." -ForegroundColor Yellow
    $Origins = $Config.AllowedOrigins
    Remote-Run "sed -i 's|^ALLOWED_ORIGINS=.*|ALLOWED_ORIGINS=$Origins|' $RemotePath/.env"
    Remote-Run "sed -i 's|^SSL_CERT_PATH=.*|#SSL_CERT_PATH=|; s|^SSL_KEY_PATH=.*|#SSL_KEY_PATH=|' $RemotePath/.env"
    # 移除 certs 目录，防止 app.js 检测到证书文件后启用 HTTPS
    Remote-Run "rm -rf $RemotePath/certs 2>/dev/null; echo 'certs removed'"
    Write-Host "  生产模式：SSL 由 Nginx 处理，Node 运行 HTTP" -ForegroundColor Gray
}

# 步骤 3: npm install
Write-Host "[3/6] 安装依赖..." -ForegroundColor Yellow
Remote-Run "cd $RemotePath; npm install --production 2>&1 | tail -n 5"

# # 步骤 4: 生产环境部署 Nginx（仅首次或配置更新时）
# if ($Config.UseNginx) {
#     Write-Host "[4/6] 配置 Nginx 反向代理..." -ForegroundColor Yellow
#     $LocalNginxConf = Join-Path $PSScriptRoot "nginx\kotabi.conf"
#     if (Test-Path $LocalNginxConf) {
#         Remote-Run "which nginx >/dev/null 2>&1 || (dnf install -y nginx && systemctl enable nginx)"
#         Remote-Upload-File $LocalNginxConf "/etc/nginx/conf.d/kotabi.conf"
#         Remote-Run "nginx -t 2>&1 && (systemctl reload nginx 2>/dev/null || systemctl start nginx) && echo 'Nginx OK' || echo 'Nginx config error!'"
#     } else {
#         Write-Host "  ⚠ 未找到 nginx/kotabi.conf，跳过 Nginx 配置" -ForegroundColor Yellow
#     }
# } else {
#     Write-Host "[4/6] 跳过 Nginx（测试环境）" -ForegroundColor Gray
# }

# 步骤 5: pm2 启动/重启
Write-Host "[5/6] 启动服务..." -ForegroundColor Yellow
# 先尝试 restart，失败则 delete + start
Remote-Run "cd $RemotePath && pm2 restart japanese-learn 2>/dev/null || pm2 start src/app.js --name japanese-learn"
Remote-Run "pm2 save --force"
Remote-Run "pm2 list"

Write-Host ""
Write-Host "[6/6] 部署完成 [$Env]" -ForegroundColor Green
Write-Host "  API:  $($Config.ApiUrl)" -ForegroundColor Cyan
Write-Host "  后台: $($Config.AdminUrl)" -ForegroundColor Cyan
