#Requires -Version 5.1
<#
.SYNOPSIS
    Post-provisioning script: applies the LHG site theme and wires up List web parts
    on each IT GRC page.

.DESCRIPTION
    Run this after Apply-ITGRC-Provisioning.ps1 has completed successfully.

    1. Applies the LHG custom theme (teal primary / navy secondary).
    2. For each page, adds the correct List web part(s) pointing at the
       provisioned lists and views.

.NOTES
    Author:  GM Information Technology, Lutheran Homes Group
    Version: 1.0
    Date:    June 2026
    Requires: PnP.PowerShell 3.x, Windows PowerShell 5.1
#>

# ── Configuration ─────────────────────────────────────────────────────────────

$SiteUrl  = "https://lutheranhomesgroup.sharepoint.com/sites/itgovernance/"
$ClientId = ""    # same client ID used in Apply-ITGRC-Provisioning.ps1

# ── Helpers ───────────────────────────────────────────────────────────────────

function Write-Step   { param([string]$m) Write-Host "`n[$([datetime]::Now.ToString('HH:mm:ss'))] $m" -ForegroundColor Cyan }
function Write-Ok     { param([string]$m) Write-Host "  ✔  $m" -ForegroundColor Green }
function Write-Warn   { param([string]$m) Write-Host "  ⚠  $m" -ForegroundColor Yellow }
function Write-Fail   { param([string]$m) Write-Host "  ✘  $m" -ForegroundColor Red }

# ── STEP 1 — Connect ──────────────────────────────────────────────────────────

Write-Step "STEP 1 — Connecting to SharePoint Online"
try {
    if ($ClientId -ne "") {
        Connect-PnPOnline -Url $SiteUrl -Interactive -ClientId $ClientId -ErrorAction Stop
    } else {
        Connect-PnPOnline -Url $SiteUrl -Interactive -ErrorAction Stop
    }
    Write-Ok "Connected to $SiteUrl"
} catch {
    Write-Fail "Connection failed: $($_.Exception.Message)"
    exit 1
}

# ── STEP 2 — Apply custom theme ───────────────────────────────────────────────
# LHG colour palette: teal primary (#0F6E56), navy secondary (#1F3864)

Write-Step "STEP 2 — Applying LHG custom theme"

$themeSlots = @{
    "themePrimary"         = "#0F6E56"
    "themeSecondary"       = "#1F3864"
    "themeDarker"          = "#085041"
    "themeDark"            = "#0a5a45"
    "themeDarkAlt"         = "#0d6350"
    "themeLight"           = "#c7e8df"
    "themeLighter"         = "#e1f5ee"
    "themeLighterAlt"      = "#f0faf6"
    "themeTertiary"        = "#4fa98d"
    "neutralPrimary"       = "#222222"
    "neutralPrimaryAlt"    = "#3c3c3c"
    "neutralSecondary"     = "#666666"
    "neutralTertiary"      = "#a6a6a6"
    "neutralTertiaryAlt"   = "#c8c8c8"
    "neutralQuaternary"    = "#d0d0d0"
    "neutralQuaternaryAlt" = "#dadada"
    "neutralLight"         = "#f5f5f5"
    "neutralLighter"       = "#f8f8f8"
    "neutralLighterAlt"    = "#fafafa"
    "white"                = "#ffffff"
    "black"                = "#000000"
    "neutralDark"          = "#212121"
    "accent"               = "#BA7517"
}

try {
    # Add theme to tenant palette then apply to this site
    Add-PnPTenantTheme -Identity "LHG-ITGRC" -Palette $themeSlots -IsInverted $false -Overwrite -ErrorAction Stop
    Set-PnPWebTheme -Theme "LHG-ITGRC" -ErrorAction Stop
    Write-Ok "LHG custom theme applied."
} catch {
    Write-Warn "Could not apply theme via tenant: $($_.Exception.Message)"
    Write-Warn "Apply manually: Site Settings > Change the look > Theme."
}

# ── STEP 3 — Wire up List web parts on each page ─────────────────────────────
# Each entry: PageName | ListTitle | ViewName | WebPartTitle | Order (within page)
# Multiple entries for the same page are added top-to-bottom by Order.

Write-Step "STEP 3 — Adding List web parts to pages"

$PageListMap = @(
    # Executive Dashboard
    [PSCustomObject]@{ Page="Executive-Dashboard.aspx";          List="IT Risk Register";                         View="Executive View";      Title="IT Risk Register — High & Critical Risks"; Order=1 }
    [PSCustomObject]@{ Page="Executive-Dashboard.aspx";          List="Projects & Programme";                     View="Active Projects";     Title="Projects & Programme — Active Projects";    Order=2 }

    # Risk & Compliance
    [PSCustomObject]@{ Page="Risk-Compliance.aspx";              List="IT Risk Register";                         View="All Items";           Title="IT Risk Register";                          Order=1 }
    [PSCustomObject]@{ Page="Risk-Compliance.aspx";              List="Incident Register";                        View="Open Incidents";      Title="Incident Register — Open Incidents";        Order=2 }

    # Policy, Standards & Principles
    [PSCustomObject]@{ Page="Policy-Standards-Principles.aspx";  List="Policy, Standards & Principles Library";  View="All Items";           Title="Policy, Standards & Principles Library";    Order=1 }

    # Projects & Programme
    [PSCustomObject]@{ Page="Projects-Programme.aspx";           List="Projects & Programme";                     View="All Items";           Title="Projects & Programme";                      Order=1 }
    [PSCustomObject]@{ Page="Projects-Programme.aspx";           List="Change Log";                               View="All Items";           Title="Change Log";                                Order=2 }

    # Cyber & Security
    [PSCustomObject]@{ Page="Cyber-Security.aspx";               List="Essential Eight Maturity";                 View="Assessment Summary";  Title="Essential Eight — Assessment Summary";      Order=1 }
    [PSCustomObject]@{ Page="Cyber-Security.aspx";               List="Incident Register";                        View="All Items";           Title="Incident Register";                         Order=2 }

    # IT Operations & Architecture
    [PSCustomObject]@{ Page="IT-Operations-Architecture.aspx";   List="CMDB — Asset & Configuration Register";   View="All Items";           Title="CMDB — Asset & Configuration Register";     Order=1 }
    [PSCustomObject]@{ Page="IT-Operations-Architecture.aspx";   List="Change Log";                               View="Class 1 Changes";     Title="Change Log — Class 1 Changes";              Order=2 }

    # Training & Awareness
    [PSCustomObject]@{ Page="Training-Awareness.aspx";           List="Training & Awareness Register";            View="All Items";           Title="Training & Awareness Register";             Order=1 }

    # Essential Eight Maturity
    [PSCustomObject]@{ Page="Essential-Eight-Maturity.aspx";     List="Essential Eight Maturity";                 View="Assessment Summary";  Title="Essential Eight — Assessment Summary";      Order=1 }
    [PSCustomObject]@{ Page="Essential-Eight-Maturity.aspx";     List="Essential Eight Maturity";                 View="Gaps Only";           Title="Essential Eight — Gaps Only";               Order=2 }
)

# Group by page so we process one page at a time
$pages = $PageListMap | Select-Object -ExpandProperty Page | Sort-Object -Unique

foreach ($pageName in $pages) {
    Write-Host "`n  Page: $pageName" -ForegroundColor White
    $entries = $PageListMap | Where-Object { $_.Page -eq $pageName } | Sort-Object Order

    try {
        $page = Get-PnPPage -Identity $pageName -ErrorAction Stop
    } catch {
        Write-Fail "  Could not load page $pageName`: $($_.Exception.Message)"
        continue
    }

    foreach ($entry in $entries) {
        try {
            # Resolve list ID
            $list = Get-PnPList -Identity $entry.List -ErrorAction Stop

            # Resolve view ID
            $view = Get-PnPView -List $list -Identity $entry.View -ErrorAction Stop

            # Build List web part properties
            $wpProps = @{
                "selectedListId"  = $list.Id.ToString()
                "selectedViewId"  = $view.Id.ToString()
                "isDocumentLibrary" = "false"
                "showDefaultDocumentLibrary" = "false"
            }

            # Add a new section to the page for each list web part
            Add-PnPPageSection -Page $page -SectionTemplate OneColumn -Order $entry.Order -ErrorAction Stop | Out-Null

            Add-PnPPageWebPart -Page $page `
                               -DefaultWebPartType List `
                               -Section $entry.Order `
                               -Column 1 `
                               -WebPartProperties $wpProps `
                               -ErrorAction Stop | Out-Null

            Write-Ok "$($entry.List) / $($entry.View) → $pageName (section $($entry.Order))"
        } catch {
            Write-Warn "$($entry.List) / $($entry.View) → $pageName FAILED: $($_.Exception.Message)"
        }
    }

    # Save and publish the page
    try {
        Set-PnPPage -Identity $pageName -Published -ErrorAction Stop
        Write-Ok "$pageName saved and published."
    } catch {
        Write-Warn "Could not publish $pageName`: $($_.Exception.Message)"
    }
}

# ── Summary ───────────────────────────────────────────────────────────────────

Write-Host "`n" -NoNewline
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Post-provisioning complete." -ForegroundColor Green
Write-Host "  Review the site at: $SiteUrl" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Remaining manual steps:" -ForegroundColor White
Write-Host "  1. Site Settings > Language and region > locale English (Australia)," -ForegroundColor Gray
Write-Host "     timezone (UTC+10:00) Canberra, Melbourne, Sydney." -ForegroundColor Gray
Write-Host "  2. Assign members to the four permission groups:" -ForegroundColor Gray
Write-Host "     IT-GRC-IT (Edit) | IT-GRC-Risk (Contribute) | IT-GRC-PMO (Contribute) | IT-GRC-Exec (Read)" -ForegroundColor Gray
Write-Host "  3. Set each group's permission level via Site Permissions." -ForegroundColor Gray
Write-Host ""
