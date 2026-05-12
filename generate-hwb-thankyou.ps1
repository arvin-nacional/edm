<#
.SYNOPSIS
  Generates per-attendee Heritage Without Borders thank-you/downloads emails
  by reusing the name, QR code URL, and attendee profile link from the
  existing confirmation HTML files.

.DESCRIPTION
  - Reads every .html file (except templates) from:
      * hwb-confirmations/
      * hwb-confirmations-balance/
  - Extracts: greeting name, QR code image URL, attendee profile URL
  - Generates a new file with the same filename in:
      * hwb-thankyou-downloads/
    populated from hwb-thankyou-downloads/_TEMPLATE.html
#>

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$templatePath = Join-Path $root 'hwb-thankyou-downloads\_TEMPLATE.html'
$outDir = Join-Path $root 'hwb-thankyou-downloads'

if (-not (Test-Path $templatePath)) {
    throw "Template not found at $templatePath"
}

if (-not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir | Out-Null
}

$template = Get-Content -Path $templatePath -Raw -Encoding UTF8

$sourceFolders = @(
    (Join-Path $root 'hwb-confirmations'),
    (Join-Path $root 'hwb-confirmations-balance')
)

# Regex patterns to pull the personalized fields out of each existing email
$nameRegex     = '(?s)Hello,\s*<strong>(.+?)</strong>'
$qrRegex       = '(?s)<img\s+alt="Event QR Code"\s+src="([^"]+)"'
$linkRegex     = '(?s)<a\s+href="([^"]+)"[^>]*>\s*Access Your Attendee Profile'

$generated = 0
$skipped   = @()

foreach ($folder in $sourceFolders) {
    if (-not (Test-Path $folder)) {
        Write-Warning "Folder not found: $folder"
        continue
    }

    $files = Get-ChildItem -Path $folder -Filter '*.html' -File | Where-Object { $_.Name -notlike '_TEMPLATE*' }

    foreach ($file in $files) {
        $content = Get-Content -Path $file.FullName -Raw -Encoding UTF8

        $nameMatch = [regex]::Match($content, $nameRegex)
        $qrMatch   = [regex]::Match($content, $qrRegex)
        $linkMatch = [regex]::Match($content, $linkRegex)

        if (-not ($nameMatch.Success -and $qrMatch.Success -and $linkMatch.Success)) {
            $missing = @()
            if (-not $nameMatch.Success) { $missing += 'name' }
            if (-not $qrMatch.Success)   { $missing += 'qr' }
            if (-not $linkMatch.Success) { $missing += 'link' }
            $skipped += [pscustomobject]@{ File = $file.Name; Missing = ($missing -join ',') }
            continue
        }

        $name = $nameMatch.Groups[1].Value.Trim()
        $qr   = $qrMatch.Groups[1].Value.Trim()
        $link = $linkMatch.Groups[1].Value.Trim()

        $output = $template
        $output = $output -replace '\{\{NAME\}\}',          [System.Text.RegularExpressions.Regex]::Escape($name).Replace('\','\\')
        # The above escape approach is brittle for replacement strings; use simpler literal substitution instead:
        $output = $template.Replace('{{NAME}}', $name).Replace('{{QR_CODE_URL}}', $qr).Replace('{{ATTENDEE_LINK}}', $link)

        $outPath = Join-Path $outDir $file.Name
        Set-Content -Path $outPath -Value $output -Encoding UTF8 -NoNewline
        $generated++
    }
}

Write-Host ""
Write-Host "Generated $generated file(s) in: $outDir"

if ($skipped.Count -gt 0) {
    Write-Host ""
    Write-Host "Skipped files (missing extractable fields):"
    $skipped | Format-Table -AutoSize
}
