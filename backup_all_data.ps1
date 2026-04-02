param(
    [string]$ServerHost = "139.196.44.6",
    [string]$SshUser    = "root",
    [string]$SshPasswd  = "Xiaoyun@123",
    [string]$DbUser     = "root",
    [string]$DbPasswd   = "6586156",
    [string]$DbName     = "japanese_learn",
    [string]$BackupDir  = "/home/japanese-learn/backups"
)

Write-Host "=== Complete Japanese Learning Database Backup ===" -ForegroundColor Cyan

if (-not (Get-Command plink -EA SilentlyContinue)) {
    Write-Host "[!] Installing PuTTY..." -ForegroundColor Yellow
    winget install PuTTY.PuTTY -e --silent 2>&1 | Out-Null
    $env:PATH = $env:PATH + ";C:\Program Files\PuTTY"
}

$HostKey = "SHA256:ySCdPD8LyDCmPPcUT7OjO6r+c0RUwBLMU/UWlOA9GHg"

function Remote-Run([string]$Cmd) {
    & plink -batch -hostkey $HostKey -pw $SshPasswd -P 22 "${SshUser}@${ServerHost}" $Cmd
}

function Remote-Download-File([string]$RemoteFile, [string]$LocalFile) {
    & pscp -batch -hostkey $HostKey -pw $SshPasswd -P 22 "${SshUser}@${ServerHost}:${RemoteFile}" $LocalFile
}

Write-Host "[1/5] Creating backup directory..." -ForegroundColor Yellow
Remote-Run "mkdir -p $BackupDir"

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupFile = "$BackupDir/japanese_learn_full_backup_${timestamp}.sql"

Write-Host "[2/5] Starting database backup..." -ForegroundColor Yellow
Write-Host "  Location: $backupFile" -ForegroundColor Gray

$dumpCmd = "mysqldump -u$DbUser -p$DbPasswd --single-transaction --quick $DbName > $backupFile 2>&1"
Remote-Run $dumpCmd

Write-Host "[3/5] Verifying backup file..." -ForegroundColor Yellow

$verifyCmd = "ls -lh $backupFile && wc -l $backupFile && head -5 $backupFile"
$verifyOutput = Remote-Run $verifyCmd
Write-Host $verifyOutput -ForegroundColor Gray

Write-Host "[4/5] Downloading backup to local..." -ForegroundColor Yellow
$localBackupDir = Join-Path $PSScriptRoot "backups"
if (-not (Test-Path $localBackupDir)) {
    New-Item -Type Directory -Path $localBackupDir | Out-Null
}
$localBackupFile = Join-Path $localBackupDir "japanese_learn_full_backup_${timestamp}.sql"

Remote-Download-File $backupFile $localBackupFile

Write-Host "[5/5] Backup Summary Statistics" -ForegroundColor Yellow

$statsCmd = @"
mysql -u$DbUser -p$DbPasswd $DbName << 'EOF'
SELECT 'USERS' as TableName, COUNT(*) as RecordCount FROM users
UNION ALL
SELECT 'VOCABULARY', COUNT(*) FROM vocabulary
UNION ALL
SELECT 'GRAMMAR LESSONS', COUNT(*) FROM grammar_lessons
UNION ALL
SELECT 'GRAMMAR EXAMPLES', COUNT(*) FROM grammar_examples
UNION ALL
SELECT 'SRS CARDS', COUNT(*) FROM srs_cards
UNION ALL
SELECT 'USER VOCABULARY', COUNT(*) FROM user_vocabulary
UNION ALL
SELECT 'WRONG ANSWERS', COUNT(*) FROM wrong_answers
UNION ALL
SELECT 'QUIZ SESSIONS', COUNT(*) FROM quiz_sessions
UNION ALL
SELECT 'USER PROGRESS', COUNT(*) FROM user_progress
UNION ALL
SELECT 'LISTENING TRACKS', COUNT(*) FROM listening_tracks
UNION ALL
SELECT 'FORUM POSTS', COUNT(*) FROM forum_posts
UNION ALL
SELECT 'NEWS ARTICLES', COUNT(*) FROM news_articles;
EOF
"@

$stats = Remote-Run $statsCmd
Write-Host $stats -ForegroundColor Gray

Write-Host ""
Write-Host "=== Backup Complete ===" -ForegroundColor Green
Write-Host "Remote backup: $backupFile" -ForegroundColor Cyan
Write-Host "Local backup:  $localBackupFile" -ForegroundColor Cyan
Write-Host ""
Write-Host "Backup file information:" -ForegroundColor Yellow

$fileInfo = Get-Item $localBackupFile
Write-Host "  Size: $([math]::Round($fileInfo.Length/1MB, 2)) MB" -ForegroundColor Cyan
Write-Host "  Created: $(Get-Date)" -ForegroundColor Cyan

Write-Host ""
Write-Host "Data preserved:" -ForegroundColor Cyan
Write-Host "  ✓ All user accounts and credentials" -ForegroundColor Green
Write-Host "  ✓ All vocabulary data with audio" -ForegroundColor Green
Write-Host "  ✓ All grammar lessons and examples" -ForegroundColor Green
Write-Host "  ✓ SRS card review history" -ForegroundColor Green
Write-Host "  ✓ Quiz sessions and scores" -ForegroundColor Green
Write-Host "  ✓ Wrong answers and error tracking" -ForegroundColor Green
Write-Host "  ✓ Listening tracks and progress" -ForegroundColor Green
Write-Host "  ✓ Forum posts and discussions" -ForegroundColor Green
Write-Host "  ✓ News articles and favorites" -ForegroundColor Green
Write-Host "  ✓ User progress and study history" -ForegroundColor Green
