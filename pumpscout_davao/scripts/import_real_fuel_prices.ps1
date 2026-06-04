param(
  [string]$CsvPath = "C:\Users\johnl\Downloads\Real_Data_fuelprice_june22026.csv",
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

  if ($Value -is [bool]) {
    return @{ booleanValue = $Value }
  }

  if ($Value -is [DateTime]) {
    return @{ timestampValue = $Value.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ") }
  }

  if ($Value -is [hashtable]) {
    $fields = @{}
    foreach ($key in $Value.Keys) {
      $converted = ConvertTo-FirestoreValue $Value[$key]
      if ($null -ne $converted) {
        $fields[$key] = $converted
      }
    }
    return @{ mapValue = @{ fields = $fields } }
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
  param(
    [string]$Brand,
    [string]$Name,
    [double]$Lat,
    [double]$Lng
  )

  $base = "{0}-{1}-{2}-{3}" -f $Brand, $Name, $Lat.ToString("0.00000", [Globalization.CultureInfo]::InvariantCulture), $Lng.ToString("0.00000", [Globalization.CultureInfo]::InvariantCulture)
  return ($base.ToLowerInvariant() -replace "[^a-z0-9]+", "-").Trim("-")
}

function Get-FuelSlot {
  param([string]$ProductName)

  $name = $ProductName.Trim().ToLowerInvariant()
  if ($name -match "diesel") {
    return "diesel"
  }

  if ($name -match "xcs|platinum|premium|extreme\s*95|jx\s*premium|v[- ]?power|vp\s*gasoline|blaze") {
    return "premium"
  }

  return "gasoline"
}

function Read-CoordinatePair {
  param([string]$Value)

  $parts = $Value.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -gt 0 }
  if ($parts.Count -lt 2) {
    return $null
  }

  $first = 0.0
  $second = 0.0
  if (!([double]::TryParse($parts[0], [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$first))) {
    return $null
  }
  if (!([double]::TryParse($parts[1], [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$second))) {
    return $null
  }

  # The file header says longitude, latitude, but the rows are Davao lat, lng.
  if ([math]::Abs($first) -le 20 -and [math]::Abs($second) -gt 100) {
    return @{ lat = $first; lng = $second }
  }

  return @{ lat = $second; lng = $first }
}

function Read-PriceLine {
  param([string]$Value)

  if ([string]::IsNullOrWhiteSpace($Value)) {
    return $null
  }

  $match = [regex]::Match($Value.Trim(), "^(?<product>.+?)\s*=\s*(?<price>[0-9]+(?:\.[0-9]+)?)$")
  if (!$match.Success) {
    Write-Warning "Skipping price value with unexpected format: $Value"
    return $null
  }

  return @{
    product = $match.Groups["product"].Value.Trim()
    price = [double]::Parse($match.Groups["price"].Value, [Globalization.CultureInfo]::InvariantCulture)
  }
}

function Add-FirestoreField {
  param(
    [hashtable]$Fields,
    [string]$Name,
    $Value
  )

  $converted = ConvertTo-FirestoreValue $Value
  if ($null -ne $converted) {
    $Fields[$Name] = $converted
  }
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

$stations = @()
$current = $null

foreach ($row in $rows) {
  $brand = "$($row.Station)".Trim()
  $name = "$($row.name)".Trim()
  $coordinates = "$($row.'longitude, latitude')".Trim()

  if ($brand.Length -gt 0 -and $name.Length -gt 0) {
    if ($null -ne $current) {
      $stations += $current
    }

    $pair = Read-CoordinatePair $coordinates
    if ($null -eq $pair) {
      Write-Warning "Skipping station with missing or invalid coordinates: $name"
      $current = $null
      continue
    }

    $current = @{
      brand = $brand
      name = $name
      lat = [double]$pair.lat
      lng = [double]$pair.lng
      products = @{}
      gasoline = $null
      diesel = $null
      premium = $null
    }
  }

  if ($null -eq $current) {
    continue
  }

  $priceLine = Read-PriceLine "$($row.prices)"
  if ($null -eq $priceLine) {
    continue
  }

  $product = [string]$priceLine.product
  $price = [double]$priceLine.price
  $slot = Get-FuelSlot $product

  $current.products[$product] = $price
  $current[$slot] = $price
}

if ($null -ne $current) {
  $stations += $current
}

if ($stations.Count -eq 0) {
  throw "No stations were parsed from the CSV."
}

$serviceAccount = Get-Content -LiteralPath $ServiceAccountPath -Raw | ConvertFrom-Json
$projectId = $serviceAccount.project_id
$updatedAt = [DateTime]::UtcNow

Write-Host "Parsed $($stations.Count) stations from '$CsvPath' for project '$projectId'."

if (!$DryRun) {
  $accessToken = Get-AccessToken $serviceAccount
  $baseUri = "https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/$Collection"
}

$imported = 0
foreach ($station in $stations) {
  $docId = New-StationDocumentId $station.brand $station.name $station.lat $station.lng
  $fields = @{}
  Add-FirestoreField $fields "name" $station.name
  Add-FirestoreField $fields "brand" $station.brand
  Add-FirestoreField $fields "lat" $station.lat
  Add-FirestoreField $fields "lng" $station.lng
  Add-FirestoreField $fields "gasoline" $station.gasoline
  Add-FirestoreField $fields "premium" $station.premium
  Add-FirestoreField $fields "diesel" $station.diesel
  Add-FirestoreField $fields "fuelProducts" $station.products
  Add-FirestoreField $fields "updatedAt" $updatedAt
  Add-FirestoreField $fields "source" "Real_Data_fuelprice_june22026.csv"
  Add-FirestoreField $fields "isDummyData" $false

  if ($DryRun) {
    Write-Host ("DRY RUN: {0} -> {1} ({2}) regular={3} diesel={4} premium={5}" -f `
      $docId, $station.name, $station.brand, $station.gasoline, $station.diesel, $station.premium)
    $imported++
    continue
  }

  $uri = "$baseUri/$([uri]::EscapeDataString($docId))"
  $body = @{ fields = $fields } | ConvertTo-Json -Depth 12 -Compress

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
