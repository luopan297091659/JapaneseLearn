# deploy_kokoro.ps1 — 部署 Kokoro TTS Python 微服务
param(
    [string]$ServerHost = "139.196.44.6",
    [string]$User       = "root",
    [string]$Passwd     = "Xiaoyun@123",
    [int]   $Port       = 22,
    [string]$RemotePath = "/home/japanese-learn/kokoro-tts"
)

$LocalBackend = Join-Path $PSScriptRoot "backend"
Write-Host "=== 部署 Kokoro TTS 微服务到 ${User}@${ServerHost} ===" -ForegroundColor Cyan

# 检测/安装 plink
if (-not (Get-Command plink -EA SilentlyContinue)) {
    Write-Host "[!] 安装 PuTTY..." -ForegroundColor Yellow
    winget install PuTTY.PuTTY -e --silent 2>&1 | Out-Null
    $env:PATH = $env:PATH + ";C:\Program Files\PuTTY"
}

$HostKey = "SHA256:ySCdPD8LyDCmPPcUT7OjO6r+c0RUwBLMU/UWlOA9GHg"

function Remote-Run([string]$Cmd) {
    & plink -batch -hostkey $HostKey -pw $Passwd -P $Port "${User}@${ServerHost}" $Cmd
    return $LASTEXITCODE
}

function Remote-Upload-File([string]$Local, [string]$RemoteFile) {
    & pscp -batch -hostkey $HostKey -pw $Passwd -P $Port $Local "${User}@${ServerHost}:${RemoteFile}"
}

# 步骤 1: 检查 Python 3.11
Write-Host "[1/5] 检查 Python 3.11 环境..." -ForegroundColor Yellow
Remote-Run "python3.11 --version && python3.11 -m pip --version"

# 步骤 2: 创建远程目录
Write-Host "[2/5] 创建远程目录..." -ForegroundColor Yellow
Remote-Run "mkdir -p $RemotePath"

# 步骤 3: 上传 Kokoro TTS 服务脚本
Write-Host "[3/5] 上传 Kokoro 服务脚本..." -ForegroundColor Yellow
Remote-Upload-File "$LocalBackend\config\kokoro_tts_settings.py" "$RemotePath/kokoro_tts_settings.py"
Remote-Upload-File "$LocalBackend\scripts\kokoro_tts_service_v2.py" "$RemotePath/kokoro_tts_service_v2.py"

# 步骤 4: 创建 requirements.txt 并安装依赖
Write-Host "[4/5] 安装 Python 3.11 依赖..." -ForegroundColor Yellow
Remote-Run "cd $RemotePath && cat > /tmp/req.txt << ENDOFREQ
fastapi==0.104.1
uvicorn==0.24.0
python-multipart==0.0.6
pydantic==2.5.0
numpy>=1.24.0
aiofiles>=23.2.0
gtts>=2.4.0
ENDOFREQ"

Remote-Run "cd $RemotePath && python3.11 -m pip install -r /tmp/req.txt --quiet 2>&1 || python3.11 -m pip install -r /tmp/req.txt"

# 步骤 5: 启动 Kokoro 服务（使用 pm2）
Write-Host "[5/5] 启动 Kokoro 服务..." -ForegroundColor Yellow
Remote-Run "which pm2 >/dev/null 2>&1 || npm install -g pm2 >/dev/null 2>&1"
Remote-Run "cd $RemotePath && pm2 kill 2>/dev/null; pm2 start 'python3.11 -m uvicorn kokoro_tts_service_v2:app --host 0.0.0.0 --port 8010' --name kokoro-tts"
Remote-Run "sleep 3"
Remote-Run "pm2 list"
Remote-Run "pm2 logs kokoro-tts --lines 30"

Write-Host ""
Write-Host "[✓] Kokoro 部署完成 (gTTS 轻量级方案)" -ForegroundColor Green
Write-Host "  Kokoro TTS API: http://${ServerHost}:8010/docs" -ForegroundColor Cyan
Write-Host "  后端 TTS 代理: http://${ServerHost}:8002/api/v1/tts/kokoro-speak" -ForegroundColor Cyan
Write-Host "  TTS 引擎: gTTS (优先) / Google TTS (备选)" -ForegroundColor Cyan
Write-Host ""
Write-Host "测试 Kokoro 服务:" -ForegroundColor Yellow
Write-Host '  curl -X POST "http://127.0.0.1:8010/api/v1/tts/kokoro"'
Write-Host '    -H "Content-Type: application/json"'
Write-Host '    -d "{\"text\":\"こんにちは\",\"voice\":\"a\",\"emotion\":\"neutral\",\"speed\":1.0}"'
