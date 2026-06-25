#Requires -Version 5.1
<#
.SYNOPSIS
    Post-provisioning script: applies LHG theme and builds properly-laid-out pages.

.DESCRIPTION
    Run after Apply-ITGRC-Provisioning.ps1 has completed.

    1. Applies the LHG custom theme (teal primary / navy secondary).
    2. Clears all placeholder content from each page.
    3. Rebuilds each page with the correct visual layout:
         Executive Dashboard: 4 coloured KPI tiles + two-column layout
           Left  (67%): IT Risk Register (Executive View)
           Right (33%): Governance Cadence panel + Quick Links navigation
         All content pages: two-column layout
           Left  (67%): primary list web part
           Right (33%): Quick Links navigation sidebar
         Secondary list (where applicable) in a OneColumn section below.

    Safe to re-run — existing page content is cleared before each rebuild.

.NOTES
    Author:  GM Information Technology, Lutheran Homes Group
    Version: 2.0
    Date:    June 2026
    Requires: PnP.PowerShell 3.x, Windows PowerShell 5.1
#>

# ── Configuration ─────────────────────────────────────────────────────────────

$SiteUrl  = "https://lutheranhomesgroup.sharepoint.com/sites/itgovernance/"
$ClientId = ""    # Entra app registration Client ID (same as Apply-ITGRC-Provisioning.ps1)

# ── Helpers ───────────────────────────────────────────────────────────────────

function Write-Step { param([string]$m) Write-Host "`n[$([datetime]::Now.ToString('HH:mm:ss'))] $m" -ForegroundColor Cyan }
function Write-Ok   { param([string]$m) Write-Host "  ✔  $m" -ForegroundColor Green }
function Write-Warn { param([string]$m) Write-Host "  ⚠  $m" -ForegroundColor Yellow }
function Write-Fail { param([string]$m) Write-Host "  ✘  $m" -ForegroundColor Red }

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

# ── STEP 2 — Apply LHG custom theme ──────────────────────────────────────────

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
    Add-PnPTenantTheme -Identity "LHG-ITGRC" -Palette $themeSlots -IsInverted $false -Overwrite -ErrorAction Stop
    Set-PnPWebTheme -Theme "LHG-ITGRC" -ErrorAction Stop
    Write-Ok "LHG custom theme applied."
} catch {
    Write-Warn "Could not apply theme: $($_.Exception.Message)"
    Write-Warn "Apply manually: Site Settings > Change the look > Theme."
}

# ── STEP 3 — Prepare shared content ──────────────────────────────────────────

Write-Step "STEP 3 — Preparing shared web part content"

$Base = $SiteUrl.TrimEnd('/')

# ── KPI status tiles for Executive Dashboard ─────────────────────────────────
# Edit the value and subtitle text here when risk posture or project count changes.

$kpiHtml = @"
<table width="100%" style="border-collapse:separate;border-spacing:6px 0;margin:0;table-layout:fixed;">
  <tr>
    <td style="background:#B71C1C;color:#ffffff;padding:20px 22px;border-radius:4px;width:25%;vertical-align:top;">
      <div style="font-size:10px;font-weight:700;letter-spacing:1.5px;text-transform:uppercase;opacity:.85;margin-bottom:6px;">Cyber Risk Rating</div>
      <div style="font-size:30px;font-weight:700;line-height:1.1;margin-bottom:5px;">HIGH</div>
      <div style="font-size:12px;opacity:.75;">Filtering &amp; nurse call gaps</div>
    </td>
    <td style="background:#8D4E00;color:#ffffff;padding:20px 22px;border-radius:4px;width:25%;vertical-align:top;">
      <div style="font-size:10px;font-weight:700;letter-spacing:1.5px;text-transform:uppercase;opacity:.85;margin-bottom:6px;">Programme Status</div>
      <div style="font-size:30px;font-weight:700;line-height:1.1;margin-bottom:5px;">IN PROGRESS</div>
      <div style="font-size:12px;opacity:.75;">FY26/27 cyber uplift</div>
    </td>
    <td style="background:#1B5E20;color:#ffffff;padding:20px 22px;border-radius:4px;width:25%;vertical-align:top;">
      <div style="font-size:10px;font-weight:700;letter-spacing:1.5px;text-transform:uppercase;opacity:.85;margin-bottom:6px;">Budget Status</div>
      <div style="font-size:30px;font-weight:700;line-height:1.1;margin-bottom:5px;">ON TRACK</div>
      <div style="font-size:12px;opacity:.75;">Within approved envelope</div>
    </td>
    <td style="background:#1F3864;color:#ffffff;padding:20px 22px;border-radius:4px;width:25%;vertical-align:top;">
      <div style="font-size:10px;font-weight:700;letter-spacing:1.5px;text-transform:uppercase;opacity:.85;margin-bottom:6px;">Active Projects</div>
      <div style="font-size:30px;font-weight:700;line-height:1.1;margin-bottom:5px;">3</div>
      <div style="font-size:12px;opacity:.75;">2 pending budget</div>
    </td>
  </tr>
</table>
"@

# ── Governance Cadence panel for Executive Dashboard right column ─────────────
# Edit dates each quarter.

$cadenceHtml = @"
<div style="font-size:14px;font-weight:600;color:#1F3864;margin:0 0 10px;">Governance cadence</div>
<table width="100%" style="border-collapse:collapse;font-size:13px;">
  <tr style="border-bottom:1px solid #eeeeee;">
    <td style="padding:10px 0 10px;">
      <div style="font-weight:600;color:#222222;">GM IT + COO 1:1</div>
      <div style="font-size:11px;color:#999999;margin-top:2px;">Monthly</div>
    </td>
    <td style="text-align:right;color:#0F6E56;font-weight:600;white-space:nowrap;padding-left:8px;">1 Jul 2026</td>
  </tr>
  <tr style="border-bottom:1px solid #eeeeee;">
    <td style="padding:10px 0 10px;">
      <div style="font-weight:600;color:#222222;">Board / Risk Committee report</div>
      <div style="font-size:11px;color:#999999;margin-top:2px;">Bimonthly</div>
    </td>
    <td style="text-align:right;color:#0F6E56;font-weight:600;white-space:nowrap;padding-left:8px;">14 Jul 2026</td>
  </tr>
  <tr style="border-bottom:1px solid #eeeeee;">
    <td style="padding:10px 0 10px;">
      <div style="font-weight:600;color:#222222;">IT risk register review</div>
      <div style="font-size:11px;color:#999999;margin-top:2px;">Quarterly</div>
    </td>
    <td style="text-align:right;color:#0F6E56;font-weight:600;white-space:nowrap;padding-left:8px;">30 Sep 2026</td>
  </tr>
  <tr style="border-bottom:1px solid #eeeeee;">
    <td style="padding:10px 0 10px;">
      <div style="font-weight:600;color:#222222;">Essential Eight self-assessment</div>
      <div style="font-size:11px;color:#999999;margin-top:2px;">Quarterly</div>
    </td>
    <td style="text-align:right;color:#0F6E56;font-weight:600;white-space:nowrap;padding-left:8px;">30 Sep 2026</td>
  </tr>
  <tr>
    <td style="padding:10px 0 10px;">
      <div style="font-weight:600;color:#222222;">MSP performance review</div>
      <div style="font-size:11px;color:#999999;margin-top:2px;">Quarterly</div>
    </td>
    <td style="text-align:right;color:#0F6E56;font-weight:600;white-space:nowrap;padding-left:8px;">15 Jul 2026</td>
  </tr>
</table>
"@

# ── Coloured callout banners (design's per-section info boxes) ────────────────
# Each section in the design opens with a coloured callout, NOT KPI tiles.
# (KPI tiles are an Executive-Dashboard-only element.)

function New-Callout {
    param([string]$Fill, [string]$Accent, [string]$Kicker, [string]$Body)
    return @"
<div style="background:$Fill;border-left:4px solid $Accent;padding:14px 18px;border-radius:4px;">
  <div style="font-size:11px;font-weight:700;letter-spacing:.7px;text-transform:uppercase;color:$Accent;margin-bottom:6px;">$Kicker</div>
  <div style="font-size:13.5px;line-height:1.6;color:#333333;">$Body</div>
</div>
"@
}

$calloutHome  = New-Callout "#FAEEDA" "#9A5E10" "Current state" "LHG has no formal GRC framework in place today. Cyber risk rating is currently <strong>High</strong>, driven by a CVSS 9.8 vulnerability in the nurse call infrastructure. The FY2026/27 IT programme establishes governance, uplifts Essential Eight maturity, and remediates critical risks."
$calloutRisk  = New-Callout "#E1F5EE" "#0F6E56" "Key insight" "Aged-care technology dependency is a clinical governance risk. LHG runs a two-tier risk model &mdash; Tier&nbsp;1 IT risks escalate to the enterprise register when they materially threaten care delivery or compliance."
$calloutCyber = New-Callout "#FBE3E1" "#B3261E" "Critical risk" "The nurse call infrastructure carries a CVSS&nbsp;9.8 vulnerability. A failure or compromise is a notifiable Serious Incident under Aged Care Quality &amp; Safety obligations. Remediation is the programme's top priority."

# ── Navigation sidebar — Markdown link list (used on every content page right column)
# The MarkDown web part serialises reliably; QuickLinks with nested hashtables does not.

$navMd = @"
**Quick links**

- [Executive Dashboard]($Base/SitePages/Executive-Dashboard.aspx)
- [Risk & Compliance]($Base/SitePages/Risk-Compliance.aspx)
- [Policy, Standards & Principles]($Base/SitePages/Policy-Standards-Principles.aspx)
- [Projects & Programme]($Base/SitePages/Projects-Programme.aspx)
- [Cyber & Security]($Base/SitePages/Cyber-Security.aspx)
- [IT Operations & Architecture]($Base/SitePages/IT-Operations-Architecture.aspx)
- [Training & Awareness]($Base/SitePages/Training-Awareness.aspx)
- [Essential Eight Maturity]($Base/SitePages/Essential-Eight-Maturity.aspx)
"@

Write-Ok "Shared content prepared."

# ── Helper: clear all canvas controls from a page ────────────────────────────

function Clear-PageContent {
    param([string]$PageName)
    try {
        $pg = Get-PnPPage -Identity $PageName -ErrorAction Stop
        # Try native ClearPage() first (exposed by PnP.Framework on the page object)
        try { $pg.ClearPage(); $pg.Save() } catch { }
        # Fallback: remove every control individually
        $ctrls = @($pg.Controls)
        foreach ($c in $ctrls) {
            Remove-PnPPageComponent -Page $PageName -InstanceId $c.InstanceId -Force -ErrorAction SilentlyContinue
        }
        Write-Ok "Cleared $PageName"
        # Remove the ColorBlock header set by the provisioning template — use a clean header
        Set-PnPPage -Identity $PageName -HeaderLayoutType NoImage -ErrorAction SilentlyContinue
    } catch {
        Write-Warn "Could not clear ${PageName}: $($_.Exception.Message)"
    }
}

# ── Helper: add a List web part (resolves list + view GUIDs at runtime) ───────

function Add-ListWP {
    param(
        [string]$PageName,
        [int]$Section,
        [int]$Column,
        [string]$ListTitle,
        [string]$ViewName
    )
    try {
        $list = Get-PnPList -Identity $ListTitle -ErrorAction Stop
        $view = Get-PnPView -List $list -Identity $ViewName -ErrorAction Stop
        Add-PnPPageWebPart -Page $PageName `
            -DefaultWebPartType List `
            -Section $Section -Column $Column `
            -WebPartProperties @{
                "selectedListId"             = $list.Id.ToString()
                "selectedViewId"             = $view.Id.ToString()
                "isDocumentLibrary"          = "false"
                "showDefaultDocumentLibrary" = "false"
            } -ErrorAction Stop | Out-Null
        Write-Ok "$ListTitle / $ViewName → S$Section C$Column"
    } catch {
        Write-Warn "$ListTitle / $ViewName FAILED: $($_.Exception.Message)"
    }
}

# ── Helper: add a Text web part ───────────────────────────────────────────────

function Add-TextWP {
    param([string]$PageName, [int]$Section, [int]$Column, [string]$Html)
    # Text web parts use the dedicated cmdlet (DefaultWebPartType has no "Text" member)
    Add-PnPPageTextPart -Page $PageName `
        -Section $Section -Column $Column `
        -Text $Html `
        -ErrorAction SilentlyContinue | Out-Null
}

# ── Helper: publish a page (Set-PnPPage has no -Published; use the page object) ─

function Publish-Page {
    param([string]$PageName)
    try {
        $pg = Get-PnPPage -Identity $PageName -ErrorAction Stop
        $pg.Publish()
        Write-Ok "$PageName published."
    } catch {
        Write-Warn "Could not publish ${PageName}: $($_.Exception.Message)"
    }
}

# ── Helper: add the shared Quick Links sidebar ────────────────────────────────

function Add-NavSidebar {
    param([string]$PageName, [int]$Section, [int]$Column)
    Add-PnPPageWebPart -Page $PageName -DefaultWebPartType MarkDown `
        -Section $Section -Column $Column `
        -WebPartProperties @{ "content" = $navMd } `
        -ErrorAction SilentlyContinue | Out-Null
    Write-Ok "Navigation sidebar → S$Section C$Column"
}

# ── STEP 4 — Rebuild each page ────────────────────────────────────────────────

Write-Step "STEP 4 — Rebuilding page layouts"

# ═══════════════════════════════════════════════════════════════════════════════
# Home
#   S1 OneColumn      amber "Current state" callout
#   S2 TwoColumnLeft  [Left] intro text   [Right] Quick Links
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host "`n  ── Home.aspx" -ForegroundColor White
Clear-PageContent "Home.aspx"

Add-PnPPageSection -Page "Home.aspx" -SectionTemplate OneColumn     -Order 1 | Out-Null
Add-TextWP "Home.aspx" 1 1 $calloutHome

Add-PnPPageSection -Page "Home.aspx" -SectionTemplate TwoColumnLeft -Order 2 | Out-Null
Add-TextWP    "Home.aspx" 2 1 "<p style='color:#555555;font-size:14px;margin:0;'>Welcome to the IT Governance, Risk &amp; Compliance portal for Lutheran Homes Group. Use the navigation to reach each programme area &mdash; risk, policy, projects, cyber, operations, and training.</p>"
Add-NavSidebar "Home.aspx" 2 2

Publish-Page "Home.aspx"

# ═══════════════════════════════════════════════════════════════════════════════
# Executive Dashboard
#   S1 OneColumn      subtitle text
#   S2 OneColumn      4 KPI status tiles (HTML table)
#   S3 TwoColumnLeft  [Left] IT Risk Register — Executive View
#                     [Right] Governance Cadence panel + Quick Links
#   S4 OneColumn      Projects & Programme — Active Projects
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host "`n  ── Executive-Dashboard.aspx" -ForegroundColor White
Clear-PageContent "Executive-Dashboard.aspx"

Add-PnPPageSection -Page "Executive-Dashboard.aspx" -SectionTemplate OneColumn    -Order 1 | Out-Null
Add-TextWP "Executive-Dashboard.aspx" 1 1 "<p style='color:#555555;font-size:14px;margin:0;'>Cyber risk posture, programme status, and the IT risk register at a glance.&nbsp; Audience: COO, Risk Committee, Board.</p>"

Add-PnPPageSection -Page "Executive-Dashboard.aspx" -SectionTemplate OneColumn    -Order 2 | Out-Null
Add-TextWP "Executive-Dashboard.aspx" 2 1 $kpiHtml
Write-Ok "KPI status tiles added"

Add-PnPPageSection -Page "Executive-Dashboard.aspx" -SectionTemplate TwoColumnLeft -Order 3 | Out-Null
Add-ListWP  "Executive-Dashboard.aspx" 3 1 "IT Risk Register" "Executive View"
Add-TextWP  "Executive-Dashboard.aspx" 3 2 $cadenceHtml
Write-Ok "Governance cadence panel added"
Add-NavSidebar "Executive-Dashboard.aspx" 3 2

Add-PnPPageSection -Page "Executive-Dashboard.aspx" -SectionTemplate OneColumn    -Order 4 | Out-Null
Add-ListWP  "Executive-Dashboard.aspx" 4 1 "Projects & Programme" "Active Projects"

Publish-Page "Executive-Dashboard.aspx"

# ═══════════════════════════════════════════════════════════════════════════════
# Risk & Compliance
#   S1 OneColumn      subtitle text
#   S2 TwoColumnLeft  [Left] IT Risk Register — All Items   [Right] Quick Links
#   S3 OneColumn      Incident Register — Open Incidents
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host "`n  ── Risk-Compliance.aspx" -ForegroundColor White
Clear-PageContent "Risk-Compliance.aspx"

Add-PnPPageSection -Page "Risk-Compliance.aspx" -SectionTemplate OneColumn     -Order 1 | Out-Null
Add-TextWP "Risk-Compliance.aspx" 1 1 "<p style='color:#555555;font-size:14px;margin:0;'>Complete IT risk register and all open incidents. Manage risk ratings, escalations, and regulatory incident reporting.</p>"
Add-TextWP "Risk-Compliance.aspx" 1 1 $calloutRisk

Add-PnPPageSection -Page "Risk-Compliance.aspx" -SectionTemplate TwoColumnLeft -Order 2 | Out-Null
Add-ListWP    "Risk-Compliance.aspx" 2 1 "IT Risk Register" "All Items"
Add-NavSidebar "Risk-Compliance.aspx" 2 2

Add-PnPPageSection -Page "Risk-Compliance.aspx" -SectionTemplate OneColumn     -Order 3 | Out-Null
Add-ListWP "Risk-Compliance.aspx" 3 1 "Incident Register" "Open Incidents"

Publish-Page "Risk-Compliance.aspx"

# ═══════════════════════════════════════════════════════════════════════════════
# Policy, Standards & Principles
#   S1 OneColumn      subtitle text
#   S2 TwoColumnLeft  [Left] Policy Library — All Items   [Right] Quick Links
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host "`n  ── Policy-Standards-Principles.aspx" -ForegroundColor White
Clear-PageContent "Policy-Standards-Principles.aspx"

Add-PnPPageSection -Page "Policy-Standards-Principles.aspx" -SectionTemplate OneColumn     -Order 1 | Out-Null
Add-TextWP "Policy-Standards-Principles.aspx" 1 1 "<p style='color:#555555;font-size:14px;margin:0;'>Authoritative library of IT policies, standards, and design principles. Track status, review cycles, and ownership.</p>"

Add-PnPPageSection -Page "Policy-Standards-Principles.aspx" -SectionTemplate TwoColumnLeft -Order 2 | Out-Null
Add-ListWP    "Policy-Standards-Principles.aspx" 2 1 "Policy, Standards & Principles Library" "All Items"
Add-NavSidebar "Policy-Standards-Principles.aspx" 2 2

Publish-Page "Policy-Standards-Principles.aspx"

# ═══════════════════════════════════════════════════════════════════════════════
# Projects & Programme
#   S1 OneColumn      subtitle text
#   S2 TwoColumnLeft  [Left] Projects — All Items   [Right] Quick Links
#   S3 OneColumn      Change Log — All Items
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host "`n  ── Projects-Programme.aspx" -ForegroundColor White
Clear-PageContent "Projects-Programme.aspx"

Add-PnPPageSection -Page "Projects-Programme.aspx" -SectionTemplate OneColumn     -Order 1 | Out-Null
Add-TextWP "Projects-Programme.aspx" 1 1 "<p style='color:#555555;font-size:14px;margin:0;'>IT programme portfolio, project status, and the change log. Track RAG status, milestones, and Class 1/2 changes.</p>"

Add-PnPPageSection -Page "Projects-Programme.aspx" -SectionTemplate TwoColumnLeft -Order 2 | Out-Null
Add-ListWP    "Projects-Programme.aspx" 2 1 "Projects & Programme" "All Items"
Add-NavSidebar "Projects-Programme.aspx" 2 2

Add-PnPPageSection -Page "Projects-Programme.aspx" -SectionTemplate OneColumn     -Order 3 | Out-Null
Add-ListWP "Projects-Programme.aspx" 3 1 "Change Log" "All Items"

Publish-Page "Projects-Programme.aspx"

# ═══════════════════════════════════════════════════════════════════════════════
# Cyber & Security  (single home for Essential Eight — matches design IA)
#   S1 OneColumn      subtitle + red "Critical risk" callout
#   S2 TwoColumnLeft  [Left] Essential Eight — Assessment Summary   [Right] Quick Links
#   S3 OneColumn      Essential Eight — Gaps Only
#   S4 OneColumn      Incident Register — All Items
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host "`n  ── Cyber-Security.aspx" -ForegroundColor White
Clear-PageContent "Cyber-Security.aspx"

Add-PnPPageSection -Page "Cyber-Security.aspx" -SectionTemplate OneColumn     -Order 1 | Out-Null
Add-TextWP "Cyber-Security.aspx" 1 1 "<p style='color:#555555;font-size:14px;margin:0;'>Essential Eight maturity assessment and cyber security incident register. Monitor ACSC compliance posture and security events.</p>"
Add-TextWP "Cyber-Security.aspx" 1 1 $calloutCyber

Add-PnPPageSection -Page "Cyber-Security.aspx" -SectionTemplate TwoColumnLeft -Order 2 | Out-Null
Add-ListWP    "Cyber-Security.aspx" 2 1 "Essential Eight Maturity" "Assessment Summary"
Add-NavSidebar "Cyber-Security.aspx" 2 2

Add-PnPPageSection -Page "Cyber-Security.aspx" -SectionTemplate OneColumn     -Order 3 | Out-Null
Add-ListWP "Cyber-Security.aspx" 3 1 "Essential Eight Maturity" "Gaps Only"

Add-PnPPageSection -Page "Cyber-Security.aspx" -SectionTemplate OneColumn     -Order 4 | Out-Null
Add-ListWP "Cyber-Security.aspx" 4 1 "Incident Register" "All Items"

Publish-Page "Cyber-Security.aspx"

# ═══════════════════════════════════════════════════════════════════════════════
# IT Operations & Architecture
#   S1 OneColumn      subtitle text
#   S2 TwoColumnLeft  [Left] CMDB — All Items   [Right] Quick Links
#   S3 OneColumn      Change Log — Class 1 Changes
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host "`n  ── IT-Operations-Architecture.aspx" -ForegroundColor White
Clear-PageContent "IT-Operations-Architecture.aspx"

Add-PnPPageSection -Page "IT-Operations-Architecture.aspx" -SectionTemplate OneColumn     -Order 1 | Out-Null
Add-TextWP "IT-Operations-Architecture.aspx" 1 1 "<p style='color:#555555;font-size:14px;margin:0;'>CMDB asset and configuration register, and Class 1 change log. Manage infrastructure inventory, lifecycle status, and change control.</p>"

Add-PnPPageSection -Page "IT-Operations-Architecture.aspx" -SectionTemplate TwoColumnLeft -Order 2 | Out-Null
Add-ListWP    "IT-Operations-Architecture.aspx" 2 1 "CMDB — Asset & Configuration Register" "All Items"
Add-NavSidebar "IT-Operations-Architecture.aspx" 2 2

Add-PnPPageSection -Page "IT-Operations-Architecture.aspx" -SectionTemplate OneColumn     -Order 3 | Out-Null
Add-ListWP "IT-Operations-Architecture.aspx" 3 1 "Change Log" "Class 1 Changes"

Publish-Page "IT-Operations-Architecture.aspx"

# ═══════════════════════════════════════════════════════════════════════════════
# Training & Awareness
#   S1 OneColumn      subtitle text
#   S2 TwoColumnLeft  [Left] Training Register — All Items   [Right] Quick Links
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host "`n  ── Training-Awareness.aspx" -ForegroundColor White
Clear-PageContent "Training-Awareness.aspx"

Add-PnPPageSection -Page "Training-Awareness.aspx" -SectionTemplate OneColumn     -Order 1 | Out-Null
Add-TextWP "Training-Awareness.aspx" 1 1 "<p style='color:#555555;font-size:14px;margin:0;'>IT security training and awareness register. Track mandatory training, completion rates, and staff acknowledgements.</p>"

Add-PnPPageSection -Page "Training-Awareness.aspx" -SectionTemplate TwoColumnLeft -Order 2 | Out-Null
Add-ListWP    "Training-Awareness.aspx" 2 1 "Training & Awareness Register" "All Items"
Add-NavSidebar "Training-Awareness.aspx" 2 2

Publish-Page "Training-Awareness.aspx"

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 5 — Remove the standalone Essential Eight nav item
#   The design has 8 sections only; Essential Eight lives on Cyber & Security.
#   The provisioning template added a 9th page/nav node — remove it from the
#   left navigation so E8 no longer appears twice. (The page itself is left in
#   place but unlinked; delete it manually from Site Contents if desired.)
# ═══════════════════════════════════════════════════════════════════════════════

Write-Step "STEP 5 — Removing duplicate Essential Eight nav item"
try {
    $nodes = Get-PnPNavigationNode -Location QuickLaunch -ErrorAction Stop
    $target = $nodes | Where-Object { $_.Title -match "Essential Eight" }
    if ($target) {
        foreach ($n in $target) {
            Remove-PnPNavigationNode -Identity $n.Id -Force -ErrorAction Stop
            Write-Ok "Removed nav node: $($n.Title)"
        }
    } else {
        Write-Warn "No 'Essential Eight' nav node found (already removed)."
    }
} catch {
    Write-Warn "Could not remove nav node: $($_.Exception.Message)"
    Write-Warn "Remove manually: Edit left navigation > '...' next to Essential Eight Maturity > Remove."
}

# ── Summary ───────────────────────────────────────────────────────────────────

Write-Host "`n" -NoNewline
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Page rebuild complete." -ForegroundColor Green
Write-Host "  Review the site at: $SiteUrl" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Executive Dashboard layout:" -ForegroundColor White
Write-Host "    KPI tiles  (full width) — Cyber Risk Rating | Programme Status | Budget Status | Active Projects" -ForegroundColor Gray
Write-Host "    Left 67%   — IT Risk Register (Executive View, High & Critical risks only)" -ForegroundColor Gray
Write-Host "    Right 33%  — Governance Cadence panel + Quick Links to all sections" -ForegroundColor Gray
Write-Host "    Full width — Projects & Programme (Active Projects)" -ForegroundColor Gray
Write-Host ""
Write-Host "  All other pages: coloured callout + primary list left (67%), nav sidebar right (33%)." -ForegroundColor Gray
Write-Host "  Essential Eight now appears ONLY on Cyber & Security (duplicate nav item removed)." -ForegroundColor Gray
Write-Host ""
Write-Host "  To update the 4 KPI tile values on the Executive Dashboard:" -ForegroundColor White
Write-Host "    Option A (in SharePoint, no re-run):" -ForegroundColor Gray
Write-Host "      Open Executive Dashboard > Edit (top right) > click the coloured KPI tile block >" -ForegroundColor Gray
Write-Host "      the toolbar 'Edit HTML' (</>) lets you change HIGH / IN PROGRESS / ON TRACK / 3" -ForegroundColor Gray
Write-Host "      and the sub-captions, then Republish." -ForegroundColor Gray
Write-Host "    Option B (re-run this script): edit the \$kpiHtml block near the top of this" -ForegroundColor Gray
Write-Host "      file, then run .\Add-ListWebParts.ps1 again (it clears and rebuilds safely)." -ForegroundColor Gray
Write-Host "    Or re-run this script after editing the `$kpiHtml block at the top." -ForegroundColor Gray
Write-Host ""
Write-Host "  Remaining manual steps:" -ForegroundColor White
Write-Host "  1. Site Settings > Language and region: English (Australia), UTC+10 Canberra/Melbourne/Sydney" -ForegroundColor Gray
Write-Host "  2. Assign members to: IT-GRC-IT (Edit) | IT-GRC-Risk (Contribute) | IT-GRC-PMO (Contribute) | IT-GRC-Exec (Read)" -ForegroundColor Gray
Write-Host "  3. Site Permissions > set each group's permission level" -ForegroundColor Gray
Write-Host ""
