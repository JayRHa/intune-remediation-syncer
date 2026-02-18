# Detection: Check if Office Click-to-Run service is running
$serviceName = "ClickToRunSvc"
$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

if ($null -eq $service) {
    Write-Output "Service '$serviceName' not found."
    exit 0
}

if ($service.Status -ne "Running") {
    Write-Output "Service '$serviceName' is not running. Status: $($service.Status)"
    exit 1
}

Write-Output "Service '$serviceName' is running."
exit 0
