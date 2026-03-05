$f = "d:\PROJECT\JapaneseLearn\backend\public\app\index.html"
$enc = [System.Text.Encoding]::UTF8
$lines = [System.IO.File]::ReadAllLines($f, $enc)

# Find game block start (line with "GAME v3")
$gameStartIdx = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match 'GAME v3') {
        # Go back 2 lines to include the preceding comment lines
        $gameStartIdx = $i - 2
        break
    }
}

# Find AUDIO section start  
$audioIdx = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^//\s+AUDIO\s*$') {
        $audioIdx = $i
        break
    }
}

Write-Host "Game block: 0-based lines $gameStartIdx to $($audioIdx - 1)"
Write-Host "Line $gameStartIdx : $($lines[$gameStartIdx])"
Write-Host "Line $audioIdx : $($lines[$audioIdx])"

# Build new file:
# part1: lines before game block
$part1 = $lines[0..($gameStartIdx - 1)]
# injection: close old script, load game_v3.js, reopen script  
$inject = @(
    '</script>',
    '<script src="/app/game_v3.js"></script>',
    '<script>'
)
# part2: lines from AUDIO onward
$part2 = $lines[$audioIdx..($lines.Count - 1)]

$newLines = $part1 + $inject + $part2
[System.IO.File]::WriteAllLines($f, $newLines, $enc)
Write-Host "Done! New line count: $($newLines.Count)"
