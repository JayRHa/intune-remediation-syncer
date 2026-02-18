# Remediation: Start Office Click-to-Run service and set to automatic
$serviceName = "ClickToRunSvc"
$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

if ($null -eq $service) {
    Write-Output "Service '$serviceName' not found. Cannot remediate."
    exit 1
}

# Set startup type to automatic if needed
if ($service.StartType -ne "Automatic") {
    Set-Service -Name $serviceName -StartupType Automatic
    Write-Output "Set '$serviceName' startup type to Automatic."
}

# Start the service if not running
if ($service.Status -ne "Running") {
    Start-Service -Name $serviceName
    Write-Output "Started service '$serviceName'."
} else {
    Write-Output "Service '$serviceName' is already running."
}

exit 0
