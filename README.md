# RemediationSyncer

**Keep your Intune Proactive Remediations in Git -- automatically.**

RemediationSyncer is a PowerShell-based tool that synchronizes Microsoft Intune Remediation Scripts (Proactive Remediations) with a local Git repository. It connects to the Microsoft Graph Beta API, compares what exists in Intune against what is stored on disk, and keeps both sides in sync.

> **Status:** Work in progress. The tool currently supports downloading from Intune to Git. Upload (Git to Intune) is on the roadmap.

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Repository Structure](#repository-structure)
- [Definition YAML Schema](#definition-yaml-schema)
- [Prerequisites](#prerequisites)
- [Setup and Configuration](#setup-and-configuration)
- [Usage](#usage)
- [How the Sync Works](#how-the-sync-works)
- [Known Limitations and Roadmap](#known-limitations-and-roadmap)
- [Contributing](#contributing)
- [License](#license)

---

## Overview

- Connects to Microsoft Graph Beta API to read Intune Proactive Remediations
- Downloads detection and remediation scripts as `.ps1` files
- Stores script metadata in a `script.yaml` definition file per remediation
- Compares Intune scripts against local folders by `displayName`
- Creates missing folders and downloads scripts automatically
- Designed to run in a CI/CD pipeline for continuous synchronization

---

## Architecture

```
+---------------------+                          +---------------------+
|                     |   Microsoft Graph Beta    |                     |
|   Microsoft Intune  | <------------------------ |  remediation_syncer |
|   (Proactive        |   GET /deviceManagement/  |       .ps1          |
|    Remediations)    |   deviceHealthScripts     |                     |
|                     |                           +----------+----------+
+---------------------+                                      |
                                                             |  read / write
                                                             v
                                                  +---------------------+
                                                  |    Git Repository   |
                                                  |---------------------|
                                                  | remediation-scripts/|
                                                  |   script_name_1/    |
                                                  |     script.yaml     |
                                                  |     Detection...ps1 |
                                                  |     Remediation.ps1 |
                                                  |   script_name_2/    |
                                                  |     ...             |
                                                  +---------------------+
```

**Flow:**

1. The syncer authenticates against Microsoft Graph using `Connect-MgGraph`.
2. It retrieves all Proactive Remediation scripts and their assignments from Intune.
3. It compares Intune script names with local folder names under `remediation-scripts/`.
4. Missing scripts are downloaded; missing YAML definitions are generated.
5. Changes can then be committed and pushed via standard Git workflows.

---

## Repository Structure

```
RemediationSyncer/
|-- .pipeline/
|   +-- remediation_syncer.ps1      # Main sync script
|-- remediation-scripts/
|   |-- <script_display_name>/
|   |   |-- script.yaml             # Script metadata (synced from Intune)
|   |   |-- detection_script.ps1    # Detection script content
|   |   +-- remediation_script.ps1  # Remediation script content
|   +-- ...
|-- LICENSE
+-- README.md
```

Each remediation script in Intune is represented as a folder under `remediation-scripts/`. The folder name corresponds to the `displayName` property from Intune.

---

## Definition YAML Schema

Every remediation folder contains a `script.yaml` file that captures the script's metadata from Intune. Below is the schema with descriptions:

```yaml
displayName: "Restart stopped Office C2R svc"   # Name shown in Intune
description: "Descriptive text about the script" # Purpose of the remediation
publisher: "Microsoft"                           # Publisher / author
runAsAccount: system                             # Execution context: system | user
runAs32Bit: true                                 # Run in 32-bit PowerShell: true | false
enforceSignatureCheck: false                     # Require signed scripts: true | false
deviceHealthScriptType: deviceHealthScript       # Script type identifier
detectionScriptContent: detection_script.ps1     # Filename of the detection script
remediationScriptContent: remediation_script.ps1 # Filename of the remediation script
detectionScriptParameters: []                    # Parameters passed to detection script
remediationScriptParameters: []                  # Parameters passed to remediation script
roleScopeTagIds: []                              # Intune RBAC scope tag IDs
highestAvailableVersion: null                    # Highest available script version
assignments: []                                  # Group assignment and schedule info
```

### Key Fields

| Field | Type | Description |
|---|---|---|
| `displayName` | string | The script name as it appears in Intune. Also used as the folder name. |
| `runAsAccount` | string | `system` runs as SYSTEM, `user` runs as the logged-in user. |
| `runAs32Bit` | boolean | Forces 32-bit PowerShell execution when `true`. |
| `enforceSignatureCheck` | boolean | Requires scripts to be signed when `true`. |
| `assignments` | array | Contains target group IDs and schedule configuration. |

---

## Prerequisites

The following PowerShell modules are required:

| Module | Purpose |
|---|---|
| **Microsoft.Graph** | Core module for `Connect-MgGraph` and `Invoke-MgGraphRequest` |
| **Microsoft.Graph.Intune** | Intune-specific Graph helpers |
| **powershell-yaml** | YAML serialization (`ConvertTo-Yaml` / `ConvertFrom-Yaml`) |

**Environment:**
- PowerShell 5.1 or later (PowerShell 7+ recommended)
- An Azure AD App Registration or interactive login with sufficient permissions
- Microsoft Graph API permissions: `DeviceManagementConfiguration.Read.All` (minimum)

---

## Setup and Configuration

### 1. Clone the repository

```bash
git clone https://github.com/JayRHa/RemediationSyncer.git
cd RemediationSyncer
```

### 2. Install required modules

```powershell
Install-Module -Name Microsoft.Graph -Scope CurrentUser -Force
Install-Module -Name Microsoft.Graph.Intune -Scope CurrentUser -Force
Install-Module -Name powershell-yaml -Scope CurrentUser -Force
```

> **Note:** Install the modules manually using the commands above. The built-in `Install-Module` wrapper in the script has a known issue (see [Known Limitations](#known-limitations-and-roadmap)).

### 3. Configure tenant authentication

Open `.pipeline/remediation_syncer.ps1` and replace the hardcoded tenant ID on line 37:

```powershell
# Before (hardcoded example value):
Connect-MgGraph -tenantid f849cde7-f11d-4ef5-a31d-7fca98b21bf5

# After (replace with your tenant ID):
Connect-MgGraph -tenantid <YOUR-TENANT-ID>
```

You will be prompted to authenticate interactively, or you can configure app-based authentication as described in the [Microsoft Graph PowerShell documentation](https://learn.microsoft.com/en-us/powershell/microsoftgraph/authentication-commands).

---

## Usage

### Run the sync manually

```powershell
cd RemediationSyncer
.\.pipeline\remediation_syncer.ps1
```

The script will:
1. Connect to Microsoft Graph (interactive login prompt)
2. Retrieve all Proactive Remediation scripts from Intune
3. Compare them with local folders in `remediation-scripts/`
4. Download missing scripts and create YAML definitions
5. Report matches and mismatches to the console

### Run in a CI/CD pipeline

Place the script in your pipeline of choice (Azure DevOps, GitHub Actions, etc.) and ensure:
- The required PowerShell modules are installed in the pipeline agent
- Authentication is handled via a service principal or managed identity
- The working directory is set to the repository root

After the sync completes, commit and push any changes:

```bash
git add remediation-scripts/
git commit -m "Sync remediation scripts from Intune"
git push
```

---

## How the Sync Works

The synchronization follows a two-phase comparison process:

### Phase 1: Intune to Local (Download)

```
For each script in Intune:
    Does a local folder with the same displayName exist?
    +-- YES --> Log match, check for script.yaml
    +-- NO  --> Create folder
                Download DetectionScript.ps1 (base64-decoded)
                Download RemediationScript.ps1 (base64-decoded)
                Generate script.yaml from Intune metadata
```

### Phase 2: Local to Intune (Comparison)

```
For each folder in remediation-scripts/:
    Does an Intune script with the same displayName exist?
    +-- YES --> Check for script.yaml
    |           +-- EXISTS --> (TODO: compare YAML with Intune state)
    |           +-- MISSING --> Generate script.yaml from Intune metadata
    +-- NO  --> Log orphaned folder (no upload yet)
```

> **Note:** Phase 2 currently only performs detection. Uploading new or changed scripts to Intune is not yet implemented.

---

## Known Limitations and Roadmap

### Current Limitations

| Issue | Description |
|---|---|
| **One-way sync only** | Scripts are downloaded from Intune but not uploaded back. Folders without a matching Intune script are logged but not acted upon. |
| **Hardcoded tenant ID** | The tenant ID in the script must be manually replaced before use. A parameter or environment variable would be more flexible. |
| **Module install wrapper** | The `Install-Module` function in the script shadows PowerShell's built-in `Install-Module` cmdlet. This causes infinite recursion if the modules are not already installed. Install modules manually before running the script. |
| **YAML filename mismatch** | The example folders contain `definition.yaml`, but the script reads and writes `script.yaml`. Use `script.yaml` as the authoritative name. |
| **Example folder typo** | The folder `remedation_example1` has a misspelling (missing an "i" in "remediation"). |
| **No YAML diffing** | When both Intune and local YAML exist, the script does not yet compare them for drift. |

### Roadmap

Based on the TODOs in the source code:

- [ ] **YAML comparison** -- Detect drift between local YAML definitions and Intune state
- [ ] **Upload to Intune** -- Push local changes (new scripts, updated metadata) to Intune via Graph API
- [ ] **Multi-group assignments** -- Support assigning scripts to multiple Azure AD groups
- [ ] **Multi-schedule support** -- Configure multiple run schedules per script
- [ ] **Log file output** -- Write structured logs for pipeline auditing
- [ ] **Parameterized tenant ID** -- Accept tenant ID as a parameter or environment variable
- [ ] **Fix module installation** -- Remove the shadowing `Install-Module` wrapper

---

## Contributing

Contributions are welcome. To get started:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Make your changes
4. Test against a non-production Intune tenant
5. Submit a Pull Request with a clear description of the change

Please keep the following in mind:
- Follow the existing folder and naming conventions
- Test with both PowerShell 5.1 and PowerShell 7+ where possible
- Do not commit real tenant IDs, secrets, or credentials

---

## License

This project is licensed under the **MIT License**. See [LICENSE](LICENSE) for details.

Copyright (c) 2024 Jannik Reinhard
