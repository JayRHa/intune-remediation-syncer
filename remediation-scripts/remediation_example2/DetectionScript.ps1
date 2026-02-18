# Detection: Check if Teams cache exceeds 500 MB
$cachePath = "$env:APPDATA\Microsoft\Teams\Cache"
$thresholdMB = 500

if (-not (Test-Path $cachePath)) {
    Write-Output "Teams cache folder not found."
    exit 0
}

$sizeMB = [math]::Round((Get-ChildItem -Path $cachePath -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB, 2)

if ($sizeMB -gt $thresholdMB) {
    Write-Output "Teams cache is $sizeMB MB (threshold: $thresholdMB MB). Remediation needed."
    exit 1
}

Write-Output "Teams cache is $sizeMB MB. Within threshold."
exit 0
