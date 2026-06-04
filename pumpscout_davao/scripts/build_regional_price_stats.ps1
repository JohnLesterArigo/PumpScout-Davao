param(
  [string]$CsvPath = "C:\Users\johnl\OneDrive\Desktop\PumpScout Davao\data\reference\Real_Data_fuelprice_june22026.csv",
  [string]$OutputPath = "C:\Users\johnl\OneDrive\Desktop\PumpScout Davao\pumpscout_davao\assets\data\regional_price_stats.json"
)

$ErrorActionPreference = "Stop"

function Get-FuelCategory {
  param([string]$Text)

  $normalized = $Text.ToLowerInvariant()
  if ($normalized -match "diesel") { return "diesel" }
  if ($normalized -match "premium|platinum|vpower gas|turbo|xcs|super|extreme 95|dx premium|accel rate") {
    return "premium"
  }
  return "gasoline"
}

function Get-Stats {
  param([double[]]$Values)

  if ($Values.Count -eq 0) {
    return $null
  }

  $sorted = $Values | Sort-Object
  $count = $sorted.Count
  $mid = [math]::Floor(($count - 1) / 2)
  $median = if ($count % 2 -eq 0) {
    ($sorted[$mid] + $sorted[$mid + 1]) / 2
  } else {
    $sorted[$mid]
  }

  return [ordered]@{
    min = [math]::Round($sorted[0], 2)
    max = [math]::Round($sorted[-1], 2)
    median = [math]::Round($median, 2)
    mean = [math]::Round(($sorted | Measure-Object -Average).Average, 2)
    count = $count
  }
}

if (!(Test-Path -LiteralPath $CsvPath)) {
  throw "CSV not found: $CsvPath"
}

$rows = Import-Csv -LiteralPath $CsvPath
$diesel = New-Object System.Collections.Generic.List[double]
$gasoline = New-Object System.Collections.Generic.List[double]
$premium = New-Object System.Collections.Generic.List[double]

foreach ($row in $rows) {
  $priceText = "$($row.prices)"
  if ($priceText.Trim().Length -eq 0) { continue }

  $matches = [regex]::Matches($priceText, "(\d+(?:\.\d+)?)")
  if ($matches.Count -eq 0) { continue }

  $value = [double]$matches[$matches.Count - 1].Value
  if ($value -lt 35 -or $value -gt 150) { continue }

  switch (Get-FuelCategory $priceText) {
    "diesel" { $diesel.Add($value) }
    "premium" { $premium.Add($value) }
    default { $gasoline.Add($value) }
  }
}

$output = [ordered]@{
  region = "Davao City"
  source = "Real_Data_fuelprice_june22026.csv"
  updatedAt = (Get-Date).ToString("yyyy-MM-dd")
  modelVersion = "regional-prior-v1"
  gasoline = Get-Stats $gasoline.ToArray()
  diesel = Get-Stats $diesel.ToArray()
  premium = Get-Stats $premium.ToArray()
}

$outputDir = Split-Path -Parent $OutputPath
if (!(Test-Path -LiteralPath $outputDir)) {
  New-Item -ItemType Directory -Path $outputDir | Out-Null
}

$output | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
Write-Host "Wrote regional stats to $OutputPath"
Write-Host "gasoline=$($output.gasoline.count) diesel=$($output.diesel.count) premium=$($output.premium.count)"
