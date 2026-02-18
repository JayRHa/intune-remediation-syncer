<#
.SYNOPSIS
    Syncs Intune Proactive Remediation scripts between a Git repository and Microsoft Intune.

.DESCRIPTION
    RemediationSyncer supports two modes:
    - Export: Downloads all remediation scripts from Intune into local folders (Intune -> Repo)
    - Import: Uploads remediation scripts from local folders into Intune (Repo -> Intune)

    Each remediation script is stored as a folder containing:
    - script.yaml    (metadata: displayName, description, runAsAccount, assignments, etc.)
    - DetectionScript.ps1
    - RemediationScript.ps1

.PARAMETER Mode
    Sync direction. "Export" downloads from Intune, "Import" uploads to Intune.

.PARAMETER TenantId
    Azure AD tenant ID for Microsoft Graph authentication.

.PARAMETER ScriptsPath
    Path to the local remediation-scripts folder. Defaults to .\remediation-scripts.

.PARAMETER WhatIf
    Import mode only. Shows what would be created or updated without making changes.

.EXAMPLE
    .\remediation_syncer.ps1 -Mode Export -TenantId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

.EXAMPLE
    .\remediation_syncer.ps1 -Mode Import -TenantId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" -WhatIf

.NOTES
    Version: 3.0
    Author:  Jannik Reinhard (jannikreinhard.com)
#>

param(
    [Parameter(Mandatory)]
    [ValidateSet("Export", "Import")]
    [string]$Mode,

    [Parameter(Mandatory)]
    [string]$TenantId,

    [string]$ScriptsPath = ".\remediation-scripts",

    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"

###############################################################################################################
# Module Check ################################################################################################
###############################################################################################################

function Ensure-ModuleInstalled {
    param([string]$Name)
    if (-not (Get-Module -Name $Name -ListAvailable)) {
        Write-Host "Installing module '$Name'..." -ForegroundColor Yellow
        Microsoft.PowerShell.Core\Install-Module -Name $Name -Scope CurrentUser -Force -AllowClobber
        Import-Module $Name -Global
    } else {
        Write-Host "Module '$Name' is available." -ForegroundColor DarkGray
    }
}

Ensure-ModuleInstalled -Name "Microsoft.Graph"
Ensure-ModuleInstalled -Name "powershell-yaml"

###############################################################################################################
# Authentication ##############################################################################################
###############################################################################################################

Write-Host ""
Write-Host "Connecting to Microsoft Graph (Tenant: $TenantId)..." -ForegroundColor Cyan
Connect-MgGraph -TenantId $TenantId -Scopes "DeviceManagementConfiguration.ReadWrite.All" -NoWelcome
Write-Host "Connected successfully." -ForegroundColor Green
Write-Host ""

###############################################################################################################
# Configuration ###############################################################################################
###############################################################################################################

$graphApiVersion = "Beta"
$graphUrl = "https://graph.microsoft.com/$graphApiVersion"

# Properties to exclude from the YAML metadata (read-only or binary fields)
$yamlExcludeProperties = @(
    'id', '@odata.type', '@odata.context', 'createdDateTime', 'lastModifiedDateTime',
    'detectionScriptContent', 'remediationScriptContent', 'isGlobalScript', 'version'
)

###############################################################################################################
# Helper Functions ############################################################################################
###############################################################################################################

function Invoke-GraphRequest {
    param(
        [string]$Uri,
        [string]$Method = "GET",
        [object]$Body = $null
    )
    $params = @{
        Uri    = $Uri
        Method = $Method
    }
    if ($Body) {
        $params.Body = ($Body | ConvertTo-Json -Depth 20)
        $params.ContentType = "application/json"
    }
    try {
        return Invoke-MgGraphRequest @params
    } catch {
        Write-Host "  ERROR: Graph API call failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  URI: $Uri | Method: $Method" -ForegroundColor Red
        throw
    }
}

function ConvertTo-Base64 {
    param([string]$Text)
    return [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Text))
}

function ConvertFrom-Base64 {
    param([string]$Base64)
    if ([string]::IsNullOrEmpty($Base64)) { return "" }
    return [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Base64))
}

###############################################################################################################
# Export Functions (Intune -> Repo) ###########################################################################
###############################################################################################################

function Get-AllRemediationScripts {
    Write-Host "Fetching remediation scripts from Intune..." -ForegroundColor Cyan
    $response = Invoke-GraphRequest -Uri "$graphUrl/deviceManagement/deviceHealthScripts"
    $scripts = $response.value

    # Handle pagination
    while ($response.'@odata.nextLink') {
        $response = Invoke-GraphRequest -Uri $response.'@odata.nextLink'
        $scripts += $response.value
    }

    Write-Host "Found $($scripts.Count) remediation script(s) in Intune." -ForegroundColor Green
    return $scripts
}

function Get-ScriptDetails {
    param([string]$ScriptId)
    return Invoke-GraphRequest -Uri "$graphUrl/deviceManagement/deviceHealthScripts/$ScriptId"
}

function Get-ScriptAssignments {
    param([string]$ScriptId)
    $response = Invoke-GraphRequest -Uri "$graphUrl/deviceManagement/deviceHealthScripts/$ScriptId/assignments"
    return $response.value
}

function Export-ScriptToFolder {
    param(
        [object]$Script,
        [string]$BasePath
    )

    $displayName = $Script.displayName
    # Sanitize folder name (remove characters invalid for file paths)
    $folderName = $displayName -replace '[<>:"/\\|?*]', '_'
    $folderPath = Join-Path $BasePath $folderName

    Write-Host "  Exporting '$displayName'..." -ForegroundColor White

    # Create folder if it doesn't exist
    if (-not (Test-Path $folderPath)) {
        New-Item -Path $folderPath -ItemType Directory -Force | Out-Null
    }

    # Fetch full script details (includes script content)
    $details = Get-ScriptDetails -ScriptId $Script.id

    # Save detection script
    $detectionContent = ConvertFrom-Base64 -Base64 $details.detectionScriptContent
    if ($detectionContent) {
        $detectionContent | Out-File -FilePath (Join-Path $folderPath "DetectionScript.ps1") -Encoding UTF8 -Force
    }

    # Save remediation script
    $remediationContent = ConvertFrom-Base64 -Base64 $details.remediationScriptContent
    if ($remediationContent) {
        $remediationContent | Out-File -FilePath (Join-Path $folderPath "RemediationScript.ps1") -Encoding UTF8 -Force
    }

    # Fetch assignments
    $assignments = Get-ScriptAssignments -ScriptId $Script.id

    # Build metadata for YAML (exclude read-only and binary fields)
    $metadata = [ordered]@{}
    $metadata.displayName            = $details.displayName
    $metadata.description            = $details.description
    $metadata.publisher              = $details.publisher
    $metadata.runAsAccount           = $details.runAsAccount
    $metadata.runAs32Bit             = $details.runAs32Bit
    $metadata.enforceSignatureCheck  = $details.enforceSignatureCheck
    $metadata.deviceHealthScriptType = $details.deviceHealthScriptType
    $metadata.roleScopeTagIds        = @($details.roleScopeTagIds)
    $metadata.detectionScriptParameters   = @($details.detectionScriptParameters)
    $metadata.remediationScriptParameters = @($details.remediationScriptParameters)

    # Clean up assignments for YAML (remove read-only fields)
    $cleanAssignments = @()
    foreach ($assignment in $assignments) {
        $cleanAssignment = [ordered]@{}
        if ($assignment.target) {
            $cleanAssignment.target = [ordered]@{}
            if ($assignment.target.'@odata.type') {
                $cleanAssignment.target.'@odata.type' = $assignment.target.'@odata.type'
            }
            if ($assignment.target.groupId) {
                $cleanAssignment.target.groupId = $assignment.target.groupId
            }
            if ($assignment.target.deviceAndAppManagementAssignmentFilterId) {
                $cleanAssignment.target.deviceAndAppManagementAssignmentFilterId = $assignment.target.deviceAndAppManagementAssignmentFilterId
            }
            if ($assignment.target.deviceAndAppManagementAssignmentFilterType) {
                $cleanAssignment.target.deviceAndAppManagementAssignmentFilterType = $assignment.target.deviceAndAppManagementAssignmentFilterType
            }
        }
        if ($null -ne $assignment.runRemediationScript) {
            $cleanAssignment.runRemediationScript = $assignment.runRemediationScript
        }
        if ($assignment.runSchedule) {
            $cleanAssignment.runSchedule = [ordered]@{}
            if ($assignment.runSchedule.'@odata.type') {
                $cleanAssignment.runSchedule.'@odata.type' = $assignment.runSchedule.'@odata.type'
            }
            if ($null -ne $assignment.runSchedule.interval) {
                $cleanAssignment.runSchedule.interval = $assignment.runSchedule.interval
            }
            if ($null -ne $assignment.runSchedule.useUtc) {
                $cleanAssignment.runSchedule.useUtc = $assignment.runSchedule.useUtc
            }
            if ($assignment.runSchedule.time) {
                $cleanAssignment.runSchedule.time = $assignment.runSchedule.time
            }
        }
        $cleanAssignments += $cleanAssignment
    }
    $metadata.assignments = $cleanAssignments

    # Write YAML
    $metadata | ConvertTo-Yaml | Out-File -FilePath (Join-Path $folderPath "script.yaml") -Encoding UTF8 -Force

    Write-Host "  OK: '$displayName' -> $folderPath" -ForegroundColor Green
}

function Start-Export {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host " EXPORT: Intune -> Repository" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    # Ensure scripts folder exists
    if (-not (Test-Path $ScriptsPath)) {
        New-Item -Path $ScriptsPath -ItemType Directory -Force | Out-Null
        Write-Host "Created scripts folder: $ScriptsPath" -ForegroundColor Yellow
    }

    $scripts = Get-AllRemediationScripts

    if ($scripts.Count -eq 0) {
        Write-Host "No remediation scripts found in Intune. Nothing to export." -ForegroundColor Yellow
        return
    }

    # Export each script
    $exportCount = 0
    foreach ($script in $scripts) {
        # Skip global/built-in Microsoft scripts
        if ($script.isGlobalScript -eq $true) {
            Write-Host "  Skipping built-in script: '$($script.displayName)'" -ForegroundColor DarkGray
            continue
        }
        Export-ScriptToFolder -Script $script -BasePath $ScriptsPath
        $exportCount++
    }

    # Check for orphaned local folders
    Write-Host ""
    Write-Host "Checking for orphaned local folders..." -ForegroundColor Cyan
    $localFolders = Get-ChildItem -Path $ScriptsPath -Directory
    $intuneNames = $scripts | ForEach-Object { $_.displayName -replace '[<>:"/\\|?*]', '_' }
    foreach ($folder in $localFolders) {
        if ($folder.Name -notin $intuneNames) {
            Write-Host "  WARNING: Local folder '$($folder.Name)' has no matching Intune script." -ForegroundColor Yellow
        }
    }

    Write-Host ""
    Write-Host "Export complete. $exportCount script(s) exported to '$ScriptsPath'." -ForegroundColor Green
}

###############################################################################################################
# Import Functions (Repo -> Intune) ###########################################################################
###############################################################################################################

function Read-LocalScript {
    param([string]$FolderPath)

    $yamlPath = Join-Path $FolderPath "script.yaml"
    if (-not (Test-Path $yamlPath)) {
        Write-Host "  WARNING: No script.yaml found in '$FolderPath'. Skipping." -ForegroundColor Yellow
        return $null
    }

    $metadata = Get-Content -Path $yamlPath -Raw | ConvertFrom-Yaml

    # Read detection script
    $detectionPath = Join-Path $FolderPath "DetectionScript.ps1"
    $detectionContent = ""
    if (Test-Path $detectionPath) {
        $detectionContent = Get-Content -Path $detectionPath -Raw
    }

    # Read remediation script
    $remediationPath = Join-Path $FolderPath "RemediationScript.ps1"
    $remediationContent = ""
    if (Test-Path $remediationPath) {
        $remediationContent = Get-Content -Path $remediationPath -Raw
    }

    return @{
        Metadata           = $metadata
        DetectionScript    = $detectionContent
        RemediationScript  = $remediationContent
        FolderPath         = $FolderPath
        FolderName         = (Split-Path $FolderPath -Leaf)
    }
}

function New-IntuneScript {
    param([hashtable]$LocalScript)

    $metadata = $LocalScript.Metadata
    $displayName = $metadata.displayName

    $body = @{
        '@odata.type'                = "#microsoft.graph.deviceHealthScript"
        displayName                  = $displayName
        description                  = if ($metadata.description) { $metadata.description } else { "" }
        publisher                    = if ($metadata.publisher) { $metadata.publisher } else { "" }
        runAsAccount                 = if ($metadata.runAsAccount) { $metadata.runAsAccount } else { "system" }
        runAs32Bit                   = if ($null -ne $metadata.runAs32Bit) { $metadata.runAs32Bit } else { $false }
        enforceSignatureCheck        = if ($null -ne $metadata.enforceSignatureCheck) { $metadata.enforceSignatureCheck } else { $false }
        detectionScriptContent       = ConvertTo-Base64 -Text $LocalScript.DetectionScript
        roleScopeTagIds              = if ($metadata.roleScopeTagIds) { @($metadata.roleScopeTagIds) } else { @("0") }
    }

    # Only add remediation script if it exists
    if ($LocalScript.RemediationScript) {
        $body.remediationScriptContent = ConvertTo-Base64 -Text $LocalScript.RemediationScript
    }

    # Add script parameters if defined
    if ($metadata.detectionScriptParameters) {
        $body.detectionScriptParameters = @($metadata.detectionScriptParameters)
    }
    if ($metadata.remediationScriptParameters) {
        $body.remediationScriptParameters = @($metadata.remediationScriptParameters)
    }

    Write-Host "  Creating '$displayName' in Intune..." -ForegroundColor White
    $result = Invoke-GraphRequest -Uri "$graphUrl/deviceManagement/deviceHealthScripts" -Method POST -Body $body
    Write-Host "  CREATED: '$displayName' (ID: $($result.id))" -ForegroundColor Green

    return $result
}

function Update-IntuneScript {
    param(
        [string]$ScriptId,
        [hashtable]$LocalScript
    )

    $metadata = $LocalScript.Metadata
    $displayName = $metadata.displayName

    $body = @{
        '@odata.type'                = "#microsoft.graph.deviceHealthScript"
        displayName                  = $displayName
        description                  = if ($metadata.description) { $metadata.description } else { "" }
        publisher                    = if ($metadata.publisher) { $metadata.publisher } else { "" }
        runAsAccount                 = if ($metadata.runAsAccount) { $metadata.runAsAccount } else { "system" }
        runAs32Bit                   = if ($null -ne $metadata.runAs32Bit) { $metadata.runAs32Bit } else { $false }
        enforceSignatureCheck        = if ($null -ne $metadata.enforceSignatureCheck) { $metadata.enforceSignatureCheck } else { $false }
        detectionScriptContent       = ConvertTo-Base64 -Text $LocalScript.DetectionScript
        roleScopeTagIds              = if ($metadata.roleScopeTagIds) { @($metadata.roleScopeTagIds) } else { @("0") }
    }

    if ($LocalScript.RemediationScript) {
        $body.remediationScriptContent = ConvertTo-Base64 -Text $LocalScript.RemediationScript
    }

    if ($metadata.detectionScriptParameters) {
        $body.detectionScriptParameters = @($metadata.detectionScriptParameters)
    }
    if ($metadata.remediationScriptParameters) {
        $body.remediationScriptParameters = @($metadata.remediationScriptParameters)
    }

    Write-Host "  Updating '$displayName' in Intune..." -ForegroundColor White
    $result = Invoke-GraphRequest -Uri "$graphUrl/deviceManagement/deviceHealthScripts/$ScriptId" -Method PATCH -Body $body
    Write-Host "  UPDATED: '$displayName' (ID: $ScriptId)" -ForegroundColor Green

    return $result
}

function Set-ScriptAssignments {
    param(
        [string]$ScriptId,
        [string]$DisplayName,
        [array]$Assignments
    )

    if (-not $Assignments -or $Assignments.Count -eq 0) {
        Write-Host "  No assignments defined for '$DisplayName'. Skipping assignment." -ForegroundColor DarkGray
        return
    }

    # Build assignment body
    $assignmentList = @()
    foreach ($assignment in $Assignments) {
        $assignmentObj = @{
            '@odata.type' = "#microsoft.graph.deviceHealthScriptAssignment"
        }

        # Target
        if ($assignment.target) {
            $targetObj = @{}
            if ($assignment.target.'@odata.type') {
                $targetObj.'@odata.type' = $assignment.target.'@odata.type'
            } else {
                $targetObj.'@odata.type' = "#microsoft.graph.groupAssignmentTarget"
            }
            if ($assignment.target.groupId) {
                $targetObj.groupId = $assignment.target.groupId
            }
            if ($assignment.target.deviceAndAppManagementAssignmentFilterId) {
                $targetObj.deviceAndAppManagementAssignmentFilterId = $assignment.target.deviceAndAppManagementAssignmentFilterId
            }
            if ($assignment.target.deviceAndAppManagementAssignmentFilterType) {
                $targetObj.deviceAndAppManagementAssignmentFilterType = $assignment.target.deviceAndAppManagementAssignmentFilterType
            } else {
                $targetObj.deviceAndAppManagementAssignmentFilterType = "none"
            }
            $assignmentObj.target = $targetObj
        }

        # Run remediation script flag
        if ($null -ne $assignment.runRemediationScript) {
            $assignmentObj.runRemediationScript = $assignment.runRemediationScript
        } else {
            $assignmentObj.runRemediationScript = $true
        }

        # Schedule
        if ($assignment.runSchedule) {
            $scheduleObj = @{}
            if ($assignment.runSchedule.'@odata.type') {
                $scheduleObj.'@odata.type' = $assignment.runSchedule.'@odata.type'
            } else {
                $scheduleObj.'@odata.type' = "#microsoft.graph.deviceHealthScriptDailySchedule"
            }
            if ($null -ne $assignment.runSchedule.interval) {
                $scheduleObj.interval = $assignment.runSchedule.interval
            }
            if ($null -ne $assignment.runSchedule.useUtc) {
                $scheduleObj.useUtc = $assignment.runSchedule.useUtc
            }
            if ($assignment.runSchedule.time) {
                $scheduleObj.time = $assignment.runSchedule.time
            }
            $assignmentObj.runSchedule = $scheduleObj
        }

        $assignmentList += $assignmentObj
    }

    $body = @{
        deviceHealthScriptAssignments = $assignmentList
    }

    Write-Host "  Setting $($assignmentList.Count) assignment(s) for '$DisplayName'..." -ForegroundColor White
    Invoke-GraphRequest -Uri "$graphUrl/deviceManagement/deviceHealthScripts/$ScriptId/assign" -Method POST -Body $body
    Write-Host "  ASSIGNED: '$DisplayName' -> $($assignmentList.Count) group(s)" -ForegroundColor Green
}

function Start-Import {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host " IMPORT: Repository -> Intune" -ForegroundColor Cyan
    if ($WhatIf) {
        Write-Host " (DRY RUN - no changes will be made)" -ForegroundColor Yellow
    }
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    if (-not (Test-Path $ScriptsPath)) {
        Write-Host "ERROR: Scripts folder not found: $ScriptsPath" -ForegroundColor Red
        exit 1
    }

    # Read local folders
    $localFolders = Get-ChildItem -Path $ScriptsPath -Directory
    if ($localFolders.Count -eq 0) {
        Write-Host "No script folders found in '$ScriptsPath'. Nothing to import." -ForegroundColor Yellow
        return
    }

    Write-Host "Found $($localFolders.Count) local script folder(s)." -ForegroundColor Cyan

    # Fetch existing Intune scripts for comparison
    $intuneScripts = Get-AllRemediationScripts
    Write-Host ""

    $createdCount = 0
    $updatedCount = 0
    $skippedCount = 0

    foreach ($folder in $localFolders) {
        $localScript = Read-LocalScript -FolderPath $folder.FullName
        if (-not $localScript) {
            $skippedCount++
            continue
        }

        $displayName = $localScript.Metadata.displayName
        if (-not $displayName) {
            Write-Host "  WARNING: No displayName in script.yaml for '$($folder.Name)'. Skipping." -ForegroundColor Yellow
            $skippedCount++
            continue
        }

        # Check if detection script exists
        if (-not $localScript.DetectionScript) {
            Write-Host "  WARNING: No DetectionScript.ps1 for '$displayName'. Skipping." -ForegroundColor Yellow
            $skippedCount++
            continue
        }

        # Find matching Intune script
        $existingScript = $intuneScripts | Where-Object { $_.displayName -eq $displayName }

        if ($existingScript) {
            # Update existing script
            if ($WhatIf) {
                Write-Host "  WOULD UPDATE: '$displayName' (ID: $($existingScript.id))" -ForegroundColor Magenta
            } else {
                $result = Update-IntuneScript -ScriptId $existingScript.id -LocalScript $localScript
                if ($localScript.Metadata.assignments) {
                    Set-ScriptAssignments -ScriptId $existingScript.id -DisplayName $displayName -Assignments $localScript.Metadata.assignments
                }
            }
            $updatedCount++
        } else {
            # Create new script
            if ($WhatIf) {
                Write-Host "  WOULD CREATE: '$displayName'" -ForegroundColor Magenta
            } else {
                $result = New-IntuneScript -LocalScript $localScript
                if ($localScript.Metadata.assignments -and $result.id) {
                    Set-ScriptAssignments -ScriptId $result.id -DisplayName $displayName -Assignments $localScript.Metadata.assignments
                }
            }
            $createdCount++
        }
    }

    Write-Host ""
    Write-Host "Import complete." -ForegroundColor Green
    if ($WhatIf) { Write-Host "(DRY RUN - no changes were made)" -ForegroundColor Yellow }
    Write-Host "  Created: $createdCount | Updated: $updatedCount | Skipped: $skippedCount" -ForegroundColor Cyan
}

###############################################################################################################
# Main ########################################################################################################
###############################################################################################################

switch ($Mode) {
    "Export" { Start-Export }
    "Import" { Start-Import }
}

Write-Host ""
Write-Host "Done." -ForegroundColor Green
