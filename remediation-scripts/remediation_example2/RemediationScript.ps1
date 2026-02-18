# Remediation: Clear Microsoft Teams cache
$cachePath = "$env:APPDATA\Microsoft\Teams\Cache"

if (-not (Test-Path $cachePath)) {
    Write-Output "Teams cache folder not found. Nothing to clear."
    exit 0
}

try {
    Remove-Item -Path "$cachePath\*" -Recurse -Force -ErrorAction Stop
    Write-Output "Teams cache cleared successfully."
    exit 0
} catch {
    Write-Output "Failed to clear Teams cache: $($_.Exception.Message)"
    exit 1
}
