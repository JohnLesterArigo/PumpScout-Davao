param(
  [string]$CsvPath = "C:\Users\johnl\Downloads\Dummy_Gas_Prices_100_Stations.csv",
  [string]$ServiceAccountPath = "C:\Users\johnl\Downloads\pumpscout-davao-firebase-adminsdk-fbsvc-e3b8b4b999.json",
  [string]$Collection = "stations",
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

function ConvertTo-Base64Url {
  param([byte[]]$Bytes)

  return [Convert]::ToBase64String($Bytes).TrimEnd("=").Replace("+", "-").Replace("/", "_")
}

function ConvertTo-FirestoreValue {
  param($Value)

  if ($null -eq $Value) {
    return $null
  }

  $text = "$Value".Trim()
  if ($text.Length -eq 0) {
    return $null
  }

  $number = 0.0
  if ([double]::TryParse($text, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$number)) {
    return @{ doubleValue = $number }
  }

  return @{ stringValue = $text }
}

function New-TimestampValue {
  param([DateTime]$Value)
  return @{ timestampValue = $Value.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ") }
}

function Get-AccessToken {
  param($ServiceAccount)

  $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  $headerJson = @{ alg = "RS256"; typ = "JWT" } | ConvertTo-Json -Compress
  $payloadJson = @{
    iss = $ServiceAccount.client_email
    sub = $ServiceAccount.client_email
    aud = $ServiceAccount.token_uri
    iat = $now
    exp = $now + 3600
    scope = "https://www.googleapis.com/auth/datastore"
  } | ConvertTo-Json -Compress

  $header = ConvertTo-Base64Url ([Text.Encoding]::UTF8.GetBytes($headerJson))
  $payload = ConvertTo-Base64Url ([Text.Encoding]::UTF8.GetBytes($payloadJson))
  $unsignedJwt = "$header.$payload"

  $privateKeyBase64 = $ServiceAccount.private_key `
    -replace "-----BEGIN PRIVATE KEY-----", "" `
    -replace "-----END PRIVATE KEY-----", "" `
    -replace "\s", ""
  $privateKeyBytes = [Convert]::FromBase64String($privateKeyBase64)

  $rsa = [Security.Cryptography.RSA]::Create()
  if ($rsa.GetType().GetMethod("ImportPkcs8PrivateKey")) {
    $bytesRead = 0
    $rsa.ImportPkcs8PrivateKey($privateKeyBytes, [ref]$bytesRead)
  } else {
    $key = [Security.Cryptography.CngKey]::Import(
      $privateKeyBytes,
      [Security.Cryptography.CngKeyBlobFormat]::Pkcs8PrivateBlob
    )
    $rsa = [Security.Cryptography.RSACng]::new($key)
  }
  $signatureBytes = $rsa.SignData(
    [Text.Encoding]::UTF8.GetBytes($unsignedJwt),
    [Security.Cryptography.HashAlgorithmName]::SHA256,
    [Security.Cryptography.RSASignaturePadding]::Pkcs1
  )
  $signature = ConvertTo-Base64Url $signatureBytes
  $assertion = "$unsignedJwt.$signature"

  $tokenResponse = Invoke-RestMethod `
    -Method Post `
    -Uri $ServiceAccount.token_uri `
    -ContentType "application/x-www-form-urlencoded" `
    -Body @{
      grant_type = "urn:ietf:params:oauth:grant-type:jwt-bearer"
      assertion = $assertion
    }

  return $tokenResponse.access_token
}

function New-StationDocumentId {
  param($Row)

  $stationId = "$($Row.'Station ID')".Trim()
  if ($stationId.Length -gt 0) {
    return ($stationId.ToLowerInvariant() -replace "[^a-z0-9]+", "-").Trim("-")
  }

  $base = "{0}-{1}-{2}" -f $Row.Brand, $Row.Latitude, $Row.Longitude
  return ($base.ToLowerInvariant() -replace "[^a-z0-9]+", "-").Trim("-")
}

function Test-RowHasRequiredData {
  param($Row)

  $name = "$($Row.'Station Name')".Trim()
  $brand = "$($Row.Brand)".Trim()
  $lat = "$($Row.Latitude)".Trim()
  $lng = "$($Row.Longitude)".Trim()

  return $name.Length -gt 0 -and $brand.Length -gt 0 -and $lat.Length -gt 0 -and $lng.Length -gt 0
}

if (!(Test-Path -LiteralPath $CsvPath)) {
  throw "CSV file was not found: $CsvPath"
}

if (!(Test-Path -LiteralPath $ServiceAccountPath)) {
  throw "Firebase service account JSON was not found: $ServiceAccountPath"
}

$rows = Import-Csv -LiteralPath $CsvPath
if ($rows.Count -eq 0) {
  throw "CSV has no data rows."
}

$requiredColumns = @(
  "Station ID",
  "Station Name",
  "Brand",
  "Latitude",
  "Longitude",
  "Regular Gasoline",
  "Premium Gasoline",
  "Diesel"
)
$headers = ($rows[0].PSObject.Properties | ForEach-Object { $_.Name })
foreach ($column in $requiredColumns) {
  if ($headers -notcontains $column) {
    throw "CSV is missing required column: $column"
  }
}

$serviceAccount = Get-Content -LiteralPath $ServiceAccountPath -Raw | ConvertFrom-Json
$projectId = $serviceAccount.project_id
$updatedAt = [DateTime]::UtcNow

Write-Host "Found $($rows.Count) rows for project '$projectId'."

if (!$DryRun) {
  $accessToken = Get-AccessToken $serviceAccount
  $baseUri = "https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/$Collection"
}

$imported = 0
foreach ($row in $rows) {
  if (!(Test-RowHasRequiredData $row)) {
    Write-Warning "Skipping row with missing name/brand/coordinates: $($row.'Station ID')"
    continue
  }

  $docId = New-StationDocumentId $row
  $fields = @{
    name = ConvertTo-FirestoreValue $row.'Station Name'
    brand = ConvertTo-FirestoreValue $row.Brand
    lat = ConvertTo-FirestoreValue $row.Latitude
    lng = ConvertTo-FirestoreValue $row.Longitude
    gasoline = ConvertTo-FirestoreValue $row.'Regular Gasoline'
    premium = ConvertTo-FirestoreValue $row.'Premium Gasoline'
    diesel = ConvertTo-FirestoreValue $row.Diesel
    updatedAt = New-TimestampValue $updatedAt
    isDummyData = @{ booleanValue = $true }
  }

  if ("$($row.City)".Trim().Length -gt 0) {
    $fields.city = ConvertTo-FirestoreValue $row.City
  }

  if ($DryRun) {
    Write-Host ("DRY RUN: {0} -> {1} ({2}) gasoline={3} diesel={4} premium={5}" -f `
      $docId, $row.'Station Name', $row.Brand, $row.'Regular Gasoline', $row.Diesel, $row.'Premium Gasoline')
    $imported++
    continue
  }

  $uri = "$baseUri/$([uri]::EscapeDataString($docId))"
  $body = @{ fields = $fields } | ConvertTo-Json -Depth 10 -Compress

  Invoke-RestMethod `
    -Method Patch `
    -Uri $uri `
    -Headers @{ Authorization = "Bearer $accessToken" } `
    -ContentType "application/json" `
    -Body $body | Out-Null

  Write-Host "Imported stations/$docId"
  $imported++
}

Write-Host "Done. Wrote $imported documents into '$Collection'."
