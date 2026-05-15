<!-- unified-readme:start -->
    <div align="center">

    # Remediation Syncer

    **Synchronizes Microsoft Intune Proactive Remediation scripts between repositories and environments.**

    Sync. Version. Deploy.

    [![GitHub stars](https://img.shields.io/github/stars/JayRHa/RemediationSyncer?style=for-the-badge&logo=github&color=f4c542)](https://github.com/JayRHa/RemediationSyncer/stargazers)
[![GitHub forks](https://img.shields.io/github/forks/JayRHa/RemediationSyncer?style=for-the-badge&logo=github&color=4078c0)](https://github.com/JayRHa/RemediationSyncer/network/members)
[![GitHub issues](https://img.shields.io/github/issues/JayRHa/RemediationSyncer?style=for-the-badge&logo=github&color=d73a4a)](https://github.com/JayRHa/RemediationSyncer/issues)
[![Contributors](https://img.shields.io/github/contributors/JayRHa/RemediationSyncer?style=for-the-badge&logo=github&color=28a745)](https://github.com/JayRHa/RemediationSyncer/graphs/contributors)

    ---

    `Endpoint Management` | `PowerShell` | `Public` | `Maintained`

    </div>

    ## What is this?

    This repository contains synchronizes Microsoft Intune Proactive Remediation scripts between repositories and environments.

    > Browse the documentation below for setup notes, usage details, and project-specific context.

    ---

    ## Quick Start

    1. Review the project documentation below.
2. Clone the repository:

   ```bash
   git clone https://github.com/JayRHa/RemediationSyncer.git
   ```

3. Follow the setup, deployment, or usage notes in the preserved documentation section.

    ---
    <!-- unified-readme:end -->


## Existing Documentation

# RemediationSyncer

**Keep your Intune Proactive Remediations in Git -- bidirectional.**

RemediationSyncer is a PowerShell-based tool that synchronizes Microsoft Intune Remediation Scripts (Proactive Remediations) with a local Git repository. It supports two modes: **Export** (Intune to Git) and **Import** (Git to Intune), giving you full version control over your remediation scripts.

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Repository Structure](#repository-structure)
- [Prerequisites](#prerequisites)
- [Setup](#setup)
- [Usage](#usage)
  - [Export (Intune to Repo)](#export-intune---repo)
  - [Import (Repo to Intune)](#import-repo---intune)
  - [Dry Run](#dry-run)
- [Parameters](#parameters)
- [Script YAML Schema](#script-yaml-schema)
- [How the Sync Works](#how-the-sync-works)
- [CI/CD Integration](#cicd-integration)
- [Contributing](#contributing)
- [License](#license)

---

## Overview

- **Export** all Proactive Remediation scripts from Intune into a Git-friendly folder structure
- **Import** remediation scripts from your repository back into Intune (create new or update existing)
- Stores script metadata and assignments in a `script.yaml` definition file per remediation
- Supports group assignments with schedules (daily, hourly)
- **Dry run mode** (`-WhatIf`) to preview import changes without modifying Intune
- Skips built-in Microsoft global scripts during export
- Warns about orphaned local folders that no longer exist in Intune
- Tenant ID passed as parameter -- no hardcoded values

---

## Architecture

```
                         Export (Intune -> Repo)
              +-----------------------------------------+
              |                                         |
              v                                         |
+---------------------+                    +------------------------+
|                     |  Microsoft Graph   |                        |
|  Microsoft Intune   | <----------------> |   remediation_syncer   |
|  (Proactive         |  Beta API          |         .ps1           |
|   Remediations)     |                    |                        |
|                     |  GET / POST /      +------------+-----------+
+---------------------+  PATCH / assign                 |
              ^                                         |
              |                                         v
              |                            +------------------------+
              +-----------------------------------------+           |
                         Import (Repo -> Intune)        |           |
                                           | Git Repository        |
                                           |------------------------|
                                           | remediation-scripts/   |
                                           |   Script_Name_1/       |
                                           |     script.yaml        |
                                           |     DetectionScript.ps1|
                                           |     Remediation...ps1  |
                                           |   Script_Name_2/       |
                                           |     ...                |
                                           +------------------------+
```

---

## Repository Structure

```
RemediationSyncer/
|-- .pipeline/
|   +-- remediation_syncer.ps1         # Main sync script (Export + Import)
|-- remediation-scripts/
|   |-- remediation_example1/
|   |   |-- script.yaml                # Script metadata and assignments
|   |   |-- DetectionScript.ps1        # Detection logic
|   |   +-- RemediationScript.ps1      # Remediation logic
|   |-- remediation_example2/
|   |   |-- script.yaml
|   |   |-- DetectionScript.ps1
|   |   +-- RemediationScript.ps1
|   +-- ...
|-- LICENSE
+-- README.md
```

Each remediation script in Intune maps to a folder under `remediation-scripts/`. The folder name corresponds to the `displayName` from the YAML metadata.

---

## Prerequisites

| Requirement | Details |
|---|---|
| **PowerShell** | 5.1 or later (PowerShell 7+ recommended) |
| **Microsoft.Graph** | Core module for `Connect-MgGraph` and `Invoke-MgGraphRequest` |
| **powershell-yaml** | YAML serialization (`ConvertTo-Yaml` / `ConvertFrom-Yaml`) |

### Graph API Permissions

| Permission | Mode | Type |
|---|---|---|
| `DeviceManagementConfiguration.ReadWrite.All` | Export + Import | Delegated or Application |

> For export-only usage, `DeviceManagementConfiguration.Read.All` is sufficient.

---

## Setup

### 1. Clone the repository

```bash
git clone https://github.com/JayRHa/RemediationSyncer.git
cd RemediationSyncer
```

### 2. Install required PowerShell modules

```powershell
Install-Module -Name Microsoft.Graph -Scope CurrentUser -Force
Install-Module -Name powershell-yaml -Scope CurrentUser -Force
```

That's it. The script handles Graph authentication via `Connect-MgGraph` with your tenant ID as a parameter.

---

## Usage

### Export (Intune -> Repo)

Download all remediation scripts from Intune into the local folder:

```powershell
.\.pipeline\remediation_syncer.ps1 -Mode Export -TenantId "your-tenant-id"
```

This will:
1. Authenticate against Microsoft Graph (interactive login prompt)
2. Fetch all Proactive Remediation scripts from Intune
3. For each script: create a folder with `script.yaml`, `DetectionScript.ps1`, and `RemediationScript.ps1`
4. Overwrite existing folders if the script already exists locally
5. Warn about orphaned local folders that have no matching Intune script

After export, commit and push the changes:

```bash
git add remediation-scripts/
git commit -m "Export remediation scripts from Intune"
git push
```

### Import (Repo -> Intune)

Upload all remediation scripts from the local folder into Intune:

```powershell
.\.pipeline\remediation_syncer.ps1 -Mode Import -TenantId "your-tenant-id"
```

This will:
1. Authenticate against Microsoft Graph
2. Read all local script folders (each must have a `script.yaml` and `DetectionScript.ps1`)
3. Compare with existing Intune scripts by `displayName`:
   - **New script** (no match in Intune) -> Creates the script via Graph API
   - **Existing script** (match found) -> Updates the script via Graph API
4. Apply group assignments and schedules from `script.yaml`

### Dry Run

Preview what the import would do without making any changes:

```powershell
.\.pipeline\remediation_syncer.ps1 -Mode Import -TenantId "your-tenant-id" -WhatIf
```

Output example:
```
  WOULD CREATE: 'New Remediation Script'
  WOULD UPDATE: 'Existing Script Name' (ID: abc123-...)

Import complete.
(DRY RUN - no changes were made)
  Created: 1 | Updated: 1 | Skipped: 0
```

### Custom Scripts Path

By default the script uses `.\remediation-scripts`. You can override this:

```powershell
.\.pipeline\remediation_syncer.ps1 -Mode Export -TenantId "your-tenant-id" -ScriptsPath "C:\MyScripts"
```

---

## Parameters

| Parameter | Required | Default | Description |
|---|---|---|---|
| `-Mode` | Yes | -- | `Export` (Intune -> Repo) or `Import` (Repo -> Intune) |
| `-TenantId` | Yes | -- | Azure AD tenant ID for authentication |
| `-ScriptsPath` | No | `.\remediation-scripts` | Local folder path for script storage |
| `-WhatIf` | No | `$false` | Import only: preview changes without modifying Intune |

---

## Script YAML Schema

Every remediation folder contains a `script.yaml` file with metadata and assignment configuration:

```yaml
displayName: Restart stopped Office C2R svc
description: >-
  If the Click-to-Run service is stopped, attempt to start it.
publisher: Microsoft
runAsAccount: system            # system | user
runAs32Bit: false
enforceSignatureCheck: false
deviceHealthScriptType: deviceHealthScript
roleScopeTagIds: []
detectionScriptParameters: []
remediationScriptParameters: []
assignments:
  - target:
      '@odata.type': '#microsoft.graph.groupAssignmentTarget'
      groupId: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
    runRemediationScript: true
    runSchedule:
      '@odata.type': '#microsoft.graph.deviceHealthScriptDailySchedule'
      interval: 1
      useUtc: true
      time: '08:00:00.0000000'
```

### Key Fields

| Field | Type | Description |
|---|---|---|
| `displayName` | string | Script name in Intune. Used as the folder name and for matching during import. |
| `runAsAccount` | string | `system` runs as SYSTEM, `user` runs as the logged-in user. |
| `runAs32Bit` | boolean | Forces 32-bit PowerShell execution. |
| `enforceSignatureCheck` | boolean | Requires scripts to be signed. |
| `assignments` | array | Group targets with schedules. See example above. |
| `assignments[].target.groupId` | string | Azure AD group ID to assign the script to. |
| `assignments[].runRemediationScript` | boolean | `true` = run detection + remediation, `false` = detection only. |
| `assignments[].runSchedule` | object | Schedule type: `deviceHealthScriptDailySchedule` or `deviceHealthScriptHourlySchedule`. |

---

## How the Sync Works

### Export Mode

```
For each remediation script in Intune (excluding built-in/global):
    1. Fetch full script details (includes base64-encoded script content)
    2. Fetch assignments (groups, schedules)
    3. Create/overwrite local folder:
       - Decode and save DetectionScript.ps1
       - Decode and save RemediationScript.ps1
       - Generate script.yaml with metadata + assignments

After export:
    Check for orphaned local folders (no Intune match) -> warn
```

### Import Mode

```
For each folder in remediation-scripts/:
    1. Read script.yaml (must exist, must have displayName)
    2. Read DetectionScript.ps1 (must exist)
    3. Read RemediationScript.ps1 (optional)
    4. Fetch all existing Intune scripts
    5. Match by displayName:
       +-- NO MATCH  -> POST to create new script
       +-- MATCH     -> PATCH to update existing script
    6. Apply assignments from script.yaml (if defined)
```

---

## CI/CD Integration

### Azure DevOps Pipeline (Example)

```yaml
trigger:
  branches:
    include:
      - main
  paths:
    include:
      - remediation-scripts/**

pool:
  vmImage: 'windows-latest'

steps:
  - task: PowerShell@2
    displayName: 'Install PowerShell modules'
    inputs:
      targetType: 'inline'
      script: |
        Install-Module -Name Microsoft.Graph -Scope CurrentUser -Force
        Install-Module -Name powershell-yaml -Scope CurrentUser -Force

  - task: PowerShell@2
    displayName: 'Import remediation scripts to Intune'
    inputs:
      filePath: '.pipeline/remediation_syncer.ps1'
      arguments: '-Mode Import -TenantId "$(TENANT_ID)"'
    env:
      AZURE_CLIENT_ID: $(CLIENT_ID)
      AZURE_CLIENT_SECRET: $(CLIENT_SECRET)
```

### GitHub Actions (Example)

```yaml
name: Sync Remediation Scripts
on:
  push:
    branches: [main]
    paths: ['remediation-scripts/**']

jobs:
  import:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install modules
        shell: pwsh
        run: |
          Install-Module -Name Microsoft.Graph -Scope CurrentUser -Force
          Install-Module -Name powershell-yaml -Scope CurrentUser -Force

      - name: Import to Intune
        shell: pwsh
        run: |
          .\.pipeline\remediation_syncer.ps1 -Mode Import -TenantId "${{ secrets.TENANT_ID }}"
```

> **Note:** For non-interactive CI/CD authentication, configure a service principal or managed identity with `Connect-MgGraph` using certificate or client secret auth.

---

## Contributing

Contributions are welcome. To get started:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Make your changes
4. Test against a non-production Intune tenant
5. Submit a Pull Request with a clear description

Please keep in mind:
- Follow the existing folder and naming conventions
- Test with both PowerShell 5.1 and PowerShell 7+ where possible
- Do not commit real tenant IDs, secrets, or credentials

---

## License

This project is licensed under the **MIT License**. See [LICENSE](LICENSE) for details.

Copyright (c) 2024 Jannik Reinhard
