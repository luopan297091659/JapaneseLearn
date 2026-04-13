# cleanup_grammar.ps1 — 清理语法数据
# 删除 grammar_lessons, grammar_examples 等表的数据
# 注意：需要先执行 backup_grammar.ps1 进行备份！

param(
    [string]$ServerHost = "139.196.44.6",
    [string]$User       = "root",
    [string]$Passwd     = "Xiaoyun@123",
    [string]$DbUser     = "root",
    [string]$DbName     = "japanese_learn"
)

Write-Host "=== 清理语法数据 ===" -ForegroundColor Cyan
Write-Host "!! 警告：此操作将删除所有语法数据 !!" -ForegroundColor Red
Write-Host "!! 请确保已执行 backup_grammar.ps1 进行备份 !!" -ForegroundColor Red
Write-Host ""

# 双重确认
$confirm1 = Read-Host "确认已完成备份? (yes/no)"
if ($confirm1 -ne "yes") {
    Write-Host "已取消操作" -ForegroundColor Yellow
    exit 1
}

$confirm2 = Read-Host "确认删除所有语法数据? (yes/no)"
if ($confirm2 -ne "yes") {
    Write-Host "已取消操作" -ForegroundColor Yellow
    exit 1
}

# 检测plink
if (-not (Get-Command plink -EA SilentlyContinue)) {
    Write-Host "[!] 安装 PuTTY..." -ForegroundColor Yellow
    winget install PuTTY.PuTTY -e --silent 2>&1 | Out-Null
    $env:PATH = $env:PATH + ";C:\Program Files\PuTTY"
}

$HostKey = "SHA256:ySCdPD8LyDCmPPcUT7OjO6r+c0RUwBLMU/UWlOA9GHg"

function Remote-Run([string]$Cmd) {
    & plink -batch -hostkey $HostKey -pw $Passwd -P 22 "${User}@${ServerHost}" $Cmd
}

Write-Host "[1/3] 检查数据库连接..." -ForegroundColor Yellow
$checkCmd = "mysql -u$DbUser $DbName -e 'SELECT COUNT(*) as grammar_count FROM grammar_lessons;'"
$result = & plink -batch -hostkey $HostKey -pw $Passwd -P 22 "${User}@${ServerHost}" $checkCmd
Write-Host $result -ForegroundColor Gray

Write-Host "[2/3] 清理语法数据..." -ForegroundColor Yellow

$cleanupCmd = @"
mysql -u$DbUser $DbName << 'EOF'
START TRANSACTION;
DELETE FROM srs_cards WHERE card_type = 'grammar';
DELETE FROM grammar_examples;
DELETE FROM grammar_lessons;
COMMIT;
SELECT 'Grammar data cleaned successfully' as Status;
EOF
"@

$output = & plink -batch -hostkey $HostKey -pw $Passwd -P 22 "${User}@${ServerHost}" $cleanupCmd
Write-Host $output -ForegroundColor Gray

Write-Host "[3/3] 验证清理结果..." -ForegroundColor Yellow

$verifyCmd = @"
mysql -u$DbUser $DbName -e "SELECT COUNT(*) as '语法课程数' FROM grammar_lessons; SELECT COUNT(*) as '例句数' FROM grammar_examples;"
"@

$verify = & plink -batch -hostkey $HostKey -pw $Passwd -P 22 "${User}@${ServerHost}" $verifyCmd
Write-Host $verify -ForegroundColor Gray

Write-Host ""
Write-Host "[✓] 清理完成！" -ForegroundColor Green
Write-Host "现在可以导入新的语法数据了" -ForegroundColor Cyan
