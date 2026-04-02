param(
    [string]$ServerHost = "139.196.44.6",
    [string]$SshUser    = "root",
    [string]$SshPasswd  = "Xiaoyun@123",
    [string]$DbUser     = "root",
    [string]$DbPasswd   = "6586156",
    [string]$DbName     = "japanese_learn",
    [string]$BackupDir  = "/home/japanese-learn/backups"
)

Write-Host "=== Backing up grammar data ===" -ForegroundColor Cyan

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

Write-Host "[1/4] Creating backup directory..." -ForegroundColor Yellow
Remote-Run "mkdir -p $BackupDir"

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupFile = "$BackupDir/grammar_backup_${timestamp}.sql"

Write-Host "[2/4] Executing database backup..." -ForegroundColor Yellow
Write-Host "  Backup file: $backupFile" -ForegroundColor Gray

$dumpCmd = "mysqldump -u$DbUser -p$DbPasswd $DbName grammar_lessons grammar_examples grammar_version > $backupFile 2>&1"

Remote-Run $dumpCmd

Write-Host "[3/4] Verifying backup..." -ForegroundColor Yellow

$verifyCmd = "ls -lh $backupFile && echo 'Lines:' && wc -l $backupFile"
$verifyOutput = & plink -batch -hostkey $HostKey -pw $Passwd -P 22 "${User}@${ServerHost}" $verifyCmd
Write-Host $verifyOutput -ForegroundColor Gray

Write-Host "[4/4] Downloading backup to local..." -ForegroundColor Yellow
$localBackupDir = Join-Path $PSScriptRoot "backups"
if (-not (Test-Path $localBackupDir)) {
    New-Item -Type Directory -Path $localBackupDir | Out-Null
}
$localBackupFile = Join-Path $localBackupDir "grammar_backup_${timestamp}.sql"

Remote-Download-File $backupFile $localBackupFile

Write-Host ""
Write-Host "[OK] Backup completed!" -ForegroundColor Green
Write-Host "  Server backup: $backupFile" -ForegroundColor Cyan
Write-Host "  Local backup: $localBackupFile" -ForegroundColor Cyan

Write-Host ""
Write-Host "Backup statistics:" -ForegroundColor Yellow
$statsCmd = "mysql -u$DbUser -p$DbPasswd $DbName -e 'SELECT COUNT(*) as courses FROM grammar_lessons; SELECT COUNT(*) as examples FROM grammar_examples;'"
$stats = & plink -batch -hostkey $HostKey -pw $SshPasswd -P 22 "${SshUser}@${ServerHost}" $statsCmd
Write-Host $stats -ForegroundColor Gray

Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. cleanup_grammar.ps1" -ForegroundColor Gray
Write-Host "  2. import_grammar.ps1" -ForegroundColor Gray

