# import_grammar.ps1 — 导入新的语法数据
# 将 grammar_import.sql 文件上传到服务器并执行

param(
    [string]$ServerHost    = "139.196.44.6",
    [string]$User          = "root",
    [string]$Passwd        = "Xiaoyun@123",
    [string]$DbUser        = "root",
    [string]$DbName        = "japanese_learn",
    [string]$SqlFilePath   = "",
    [string]$RemotePath    = "/home/japanese-learn/backups"
)

Write-Host "=== 导入语法数据 ===" -ForegroundColor Cyan

# 如果未指定SQL文件，使用默认路径
if (-not $SqlFilePath) {
    $SqlFilePath = Join-Path $PSScriptRoot "temp_grammar_import.sql"
}

if (-not (Test-Path $SqlFilePath)) {
    Write-Host "[x] 找不到SQL文件: $SqlFilePath" -ForegroundColor Red
    Write-Host "请提供有效的SQL文件路径" -ForegroundColor Red
    exit 1
}

Write-Host "SQL文件: $SqlFilePath" -ForegroundColor Gray
$fileSize = (Get-Item $SqlFilePath).Length / 1KB
Write-Host "文件大小: $('{0:F2}' -f $fileSize) KB" -ForegroundColor Gray

# 检测plink/pscp
if (-not (Get-Command plink -EA SilentlyContinue) -or -not (Get-Command pscp -EA SilentlyContinue)) {
    Write-Host "[!] 安装 PuTTY..." -ForegroundColor Yellow
    winget install PuTTY.PuTTY -e --silent 2>&1 | Out-Null
    $env:PATH = $env:PATH + ";C:\Program Files\PuTTY"
}

$HostKey = "SHA256:ySCdPD8LyDCmPPcUT7OjO6r+c0RUwBLMU/UWlOA9GHg"

function Remote-Run([string]$Cmd) {
    & plink -batch -hostkey $HostKey -pw $Passwd -P 22 "${User}@${ServerHost}" $Cmd
}

function Remote-Upload-File([string]$Local, [string]$RemoteFile) {
    & pscp -batch -hostkey $HostKey -pw $Passwd -P 22 $Local "${User}@${ServerHost}:${RemoteFile}"
}

# 步骤1: 创建备份目录
Write-Host "[1/4] 准备远程目录..." -ForegroundColor Yellow
Remote-Run "mkdir -p $RemotePath"

# 步骤2: 上传SQL文件
Write-Host "[2/4] 上传SQL文件..." -ForegroundColor Yellow
$remoteFile = "$RemotePath/grammar_import_$(Get-Date -Format 'yyyyMMdd_HHmmss').sql"
Remote-Upload-File $SqlFilePath $remoteFile
Write-Host "  远程文件: $remoteFile" -ForegroundColor Gray

# 步骤3: 执行导入
Write-Host "[3/4] 执行数据导入..." -ForegroundColor Yellow

$importCmd = @"
mysql -u$DbUser $DbName < $remoteFile 2>&1
"@

$output = & plink -batch -hostkey $HostKey -pw $Passwd -P 22 "${User}@${ServerHost}" $importCmd
Write-Host $output -ForegroundColor Gray

# 步骤4: 验证导入结果
Write-Host "[4/4] 验证导入结果..." -ForegroundColor Yellow

$verifyCmd = @"
echo "=== 语法课程统计 ==="
mysql -u$DbUser $DbName -e "SELECT COUNT(*) as '总课程数' FROM grammar_lessons;"
echo ""
echo "=== 按JLPT级别统计 ==="
mysql -u$DbUser $DbName -e "SELECT jlpt_level, COUNT(*) as count FROM grammar_lessons GROUP BY jlpt_level ORDER BY jlpt_level LIMIT 10;"
echo ""
echo "=== 例句统计 ==="
mysql -u$DbUser $DbName -e "SELECT COUNT(*) as '总例句数' FROM grammar_examples;"
echo ""
echo "=== 有音频的例句 ==="
mysql -u$DbUser $DbName -e "SELECT COUNT(*) as '有音频的例句' FROM grammar_examples WHERE audio_url IS NOT NULL AND audio_url != '';"
"@

$stats = & plink -batch -hostkey $HostKey -pw $Passwd -P 22 "${User}@${ServerHost}" $verifyCmd
Write-Host $stats -ForegroundColor Gray

Write-Host ""
Write-Host "[✓] 导入完成！" -ForegroundColor Green
Write-Host "现在可以测试语法功能了:" -ForegroundColor Cyan
Write-Host "  - 应用中: 查看语法 → 选择语法条目" -ForegroundColor Gray
Write-Host "  - API: GET http://$ServerHost/api/grammar" -ForegroundColor Gray
Write-Host "  - 测验: GET http://$ServerHost/api/quiz?quiz_type=grammar&level=N1" -ForegroundColor Gray
