#Requires -Version 5.1
<#
.SYNOPSIS
    Provisions the LHG IT GRC SharePoint site from the PnP template and applies column formatting.

.DESCRIPTION
    1. Validates PnP.PowerShell module is installed.
    2. Connects to the target SharePoint site using interactive authentication.
    3. Applies LHG-ITGRC-Provisioning.xml via PnP Provisioning.
    4. Iterates Column-Formatting/ JSON files and applies each to the correct list and field.
    5. Outputs a provisioning summary.

.NOTES
    Author:  GM Information Technology, Lutheran Homes Group
    Version: 1.0
    Date:    June 2026
    Requires: PnP.PowerShell 2.x or later
              SharePoint Online — site must be pre-created before running this script
#>

# ── Configuration ─────────────────────────────────────────────────────────────

$SiteUrl        = "https://lutheranhomesgroup.sharepoint.com/sites/itgovernance/"
$ScriptRoot     = $PSScriptRoot
$TemplateFile   = Join-Path $ScriptRoot "LHG-ITGRC-Provisioning.xml"
$FormattingDir  = Join-Path $ScriptRoot "Column-Formatting"

# Test site — uncomment to target a staging environment instead of production
# $SiteUrl = "https://lutheranhomesgroup.sharepoint.com/sites/itgovernance-test/"

# ── Column formatting map ──────────────────────────────────────────────────────
# Each entry: FileName | ListTitle | InternalFieldName
# Applied via Set-PnPField -CustomFormatter after provisioning completes.

$ColumnFormattingMap = @(
    [PSCustomObject]@{ File = "RiskRegister-RiskRating.json";    List = "IT Risk Register";                          Field = "RiskRating" }
    [PSCustomObject]@{ File = "RiskRegister-Likelihood.json";    List = "IT Risk Register";                          Field = "Likelihood" }
    [PSCustomObject]@{ File = "RiskRegister-CareImpact.json";    List = "IT Risk Register";                          Field = "CareImpactClass" }
    [PSCustomObject]@{ File = "RiskRegister-Escalate.json";      List = "IT Risk Register";                          Field = "EscalateToEnterprise" }
    [PSCustomObject]@{ File = "CMDB-CareImpact.json";            List = "CMDB — Asset & Configuration Register";     Field = "CareImpactClass" }
    [PSCustomObject]@{ File = "CMDB-LifecycleStatus.json";       List = "CMDB — Asset & Configuration Register";     Field = "LifecycleStatus" }
    [PSCustomObject]@{ File = "CMDB-Criticality.json";           List = "CMDB — Asset & Configuration Register";     Field = "ITCriticality" }
    [PSCustomObject]@{ File = "EssentialEight-Status.json";      List = "Essential Eight Maturity";                  Field = "AssessmentStatus" }
    [PSCustomObject]@{ File = "EssentialEight-CurrentMaturity.json"; List = "Essential Eight Maturity";              Field = "CurrentMaturity" }
    [PSCustomObject]@{ File = "EssentialEight-MaturityGap.json"; List = "Essential Eight Maturity";                  Field = "MaturityGap" }
    [PSCustomObject]@{ File = "Policy-Status.json";              List = "Policy, Standards & Principles Library";    Field = "PolicyStatus" }
    [PSCustomObject]@{ File = "Projects-RAG.json";               List = "Projects & Programme";                      Field = "RAGStatus" }
    [PSCustomObject]@{ File = "Projects-Status.json";            List = "Projects & Programme";                      Field = "ProjectStatus" }
    [PSCustomObject]@{ File = "Incidents-Severity.json";         List = "Incident Register";                         Field = "Severity" }
    [PSCustomObject]@{ File = "Incidents-Status.json";           List = "Incident Register";                         Field = "IncidentStatus" }
    [PSCustomObject]@{ File = "Incidents-Notifiable.json";       List = "Incident Register";                         Field = "NotifiableIncident" }
    [PSCustomObject]@{ File = "Change-CareImpact.json";          List = "Change Log";                                Field = "CareImpactClass" }
)

# ── Tracking ───────────────────────────────────────────────────────────────────

$Summary = [PSCustomObject]@{
    TemplateApplied    = $false
    FormattingApplied  = [System.Collections.Generic.List[string]]::new()
    FormattingFailed   = [System.Collections.Generic.List[string]]::new()
    Errors             = [System.Collections.Generic.List[string]]::new()
}

# ── Helper: Write-Step ─────────────────────────────────────────────────────────

function Write-Step {
    param([string]$Message, [string]$Colour = "Cyan")
    Write-Host "`n[$([datetime]::Now.ToString('HH:mm:ss'))] $Message" -ForegroundColor $Colour
}

function Write-Success {
    param([string]$Message)
    Write-Host "  ✔  $Message" -ForegroundColor Green
}

function Write-Fail {
    param([string]$Message)
    Write-Host "  ✘  $Message" -ForegroundColor Red
}

# ══════════════════════════════════════════════════════════════════════════════
# STEP 1 — Validate PnP.PowerShell module
# ══════════════════════════════════════════════════════════════════════════════

Write-Step "STEP 1 — Checking PnP.PowerShell module"

if (-not (Get-Module -ListAvailable -Name "PnP.PowerShell")) {
    Write-Fail "PnP.PowerShell module is not installed."
    Write-Host @"

    To install PnP.PowerShell, run the following in an elevated PowerShell session:

        Install-Module -Name PnP.PowerShell -Scope CurrentUser -Force

    After installation, re-run this script.
    Documentation: https://pnp.github.io/powershell/

"@ -ForegroundColor Yellow
    exit 1
}

$pnpVersion = (Get-Module -ListAvailable -Name "PnP.PowerShell" | Select-Object -First 1).Version
Write-Success "PnP.PowerShell $pnpVersion found."

# ══════════════════════════════════════════════════════════════════════════════
# STEP 2 — Validate local files exist
# ══════════════════════════════════════════════════════════════════════════════

Write-Step "STEP 2 — Validating local files"

if (-not (Test-Path $TemplateFile)) {
    Write-Fail "Template file not found: $TemplateFile"
    exit 1
}
Write-Success "Template file found: $TemplateFile"

if (-not (Test-Path $FormattingDir)) {
    Write-Fail "Column-Formatting directory not found: $FormattingDir"
    exit 1
}
Write-Success "Column-Formatting directory found: $FormattingDir"

$missingFiles = $ColumnFormattingMap | Where-Object { -not (Test-Path (Join-Path $FormattingDir $_.File)) }
if ($missingFiles) {
    foreach ($m in $missingFiles) {
        Write-Fail "Missing formatting file: $($m.File)"
    }
    Write-Host "  Some column formatting files are missing. Continue with provisioning anyway? (Y/N)" -ForegroundColor Yellow
    $continue = Read-Host
    if ($continue -ne "Y") { exit 1 }
}
else {
    Write-Success "All $($ColumnFormattingMap.Count) column formatting files found."
}

# ══════════════════════════════════════════════════════════════════════════════
# STEP 3 — Connect to SharePoint Online
# ══════════════════════════════════════════════════════════════════════════════

Write-Step "STEP 3 — Connecting to SharePoint Online"
Write-Host "  Target: $SiteUrl" -ForegroundColor Gray

try {
    Connect-PnPOnline -Url $SiteUrl -Interactive -ErrorAction Stop
    Write-Success "Connected to $SiteUrl"
}
catch {
    Write-Fail "Failed to connect to SharePoint Online."
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
    $Summary.Errors.Add("STEP 3 — Connection failed: $($_.Exception.Message)")
    exit 1
}

# ══════════════════════════════════════════════════════════════════════════════
# STEP 4 — Apply PnP Provisioning Template
# ══════════════════════════════════════════════════════════════════════════════

Write-Step "STEP 4 — Applying PnP Provisioning Template"
Write-Host "  Template: $TemplateFile" -ForegroundColor Gray
Write-Host "  This may take several minutes — lists, views, and pages are being created." -ForegroundColor Gray

try {
    Invoke-PnPSiteTemplate -Path $TemplateFile -ErrorAction Stop
    $Summary.TemplateApplied = $true
    Write-Success "PnP template applied successfully."
}
catch {
    Write-Fail "PnP template application failed."
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
    $Summary.Errors.Add("STEP 4 — Template apply failed: $($_.Exception.Message)")
    Write-Host "`n  The template failed to apply. Resolve the error above and re-run the script." -ForegroundColor Yellow
    exit 1
}

# ══════════════════════════════════════════════════════════════════════════════
# STEP 5 — Apply column formatting JSON to each field
# ══════════════════════════════════════════════════════════════════════════════

Write-Step "STEP 5 — Applying column formatting"
Write-Host "  Applying $($ColumnFormattingMap.Count) column formatting definitions." -ForegroundColor Gray

foreach ($entry in $ColumnFormattingMap) {
    $jsonPath = Join-Path $FormattingDir $entry.File

    if (-not (Test-Path $jsonPath)) {
        Write-Fail "Skipping — file not found: $($entry.File)"
        $Summary.FormattingFailed.Add("$($entry.File) — file not found")
        continue
    }

    try {
        $jsonContent = Get-Content -Path $jsonPath -Raw -ErrorAction Stop

        # Retrieve the list to confirm it exists before applying formatting
        $list = Get-PnPList -Identity $entry.List -ErrorAction Stop

        Set-PnPField -List $list `
                     -Identity $entry.Field `
                     -Values @{ CustomFormatter = $jsonContent } `
                     -ErrorAction Stop

        Write-Success "$($entry.List) → $($entry.Field) — formatting applied ($($entry.File))"
        $Summary.FormattingApplied.Add("$($entry.List) / $($entry.Field)")
    }
    catch {
        Write-Fail "$($entry.List) → $($entry.Field) — formatting FAILED ($($entry.File))"
        Write-Host "    Error: $($_.Exception.Message)" -ForegroundColor Red
        $Summary.FormattingFailed.Add("$($entry.List) / $($entry.Field) — $($_.Exception.Message)")
    }
}

# ══════════════════════════════════════════════════════════════════════════════
# STEP 6 — Provisioning Summary
# ══════════════════════════════════════════════════════════════════════════════

Write-Step "STEP 6 — Provisioning Summary" "White"

Write-Host "`n  Template applied:          " -NoNewline
if ($Summary.TemplateApplied) { Write-Host "Yes" -ForegroundColor Green } else { Write-Host "No" -ForegroundColor Red }

Write-Host "  Column formatting applied:  $($Summary.FormattingApplied.Count) / $($ColumnFormattingMap.Count)"

if ($Summary.FormattingFailed.Count -gt 0) {
    Write-Host "`n  Failed formatting fields:" -ForegroundColor Yellow
    foreach ($f in $Summary.FormattingFailed) {
        Write-Host "    - $f" -ForegroundColor Yellow
    }
}

if ($Summary.Errors.Count -gt 0) {
    Write-Host "`n  Errors encountered:" -ForegroundColor Red
    foreach ($e in $Summary.Errors) {
        Write-Host "    - $e" -ForegroundColor Red
    }
}

# Lists provisioned by the template
Write-Host "`n  Lists provisioned by template:" -ForegroundColor Gray
@(
    "IT Risk Register"
    "CMDB — Asset & Configuration Register"
    "Policy, Standards & Principles Library"
    "Projects & Programme"
    "Essential Eight Maturity"
    "Change Log"
    "Incident Register"
    "Training & Awareness Register"
) | ForEach-Object { Write-Host "    - $_" -ForegroundColor Gray }

# Pages provisioned by the template
Write-Host "`n  Pages provisioned by template:" -ForegroundColor Gray
@(
    "Home.aspx"
    "Executive-Dashboard.aspx"
    "Risk-Compliance.aspx"
    "Policy-Standards-Principles.aspx"
    "Projects-Programme.aspx"
    "Cyber-Security.aspx"
    "IT-Operations-Architecture.aspx"
    "Training-Awareness.aspx"
    "Essential-Eight-Maturity.aspx"
) | ForEach-Object { Write-Host "    - $_" -ForegroundColor Gray }

Write-Host "`n" -NoNewline
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Provisioning complete." -ForegroundColor Green
Write-Host "  Review the site at: $SiteUrl" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
