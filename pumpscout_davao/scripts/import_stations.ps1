param(
  [string]$CsvPath = "C:\Users\johnl\Downloads\PumpScout_Davao_Data_Updated.csv",
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

function New-FirestoreDocumentId {
  param($Row)

  $base = "{0}-{1}-{2}" -f $Row.brand, $Row.lat, $Row.lng
  $id = $base.ToLowerInvariant() -replace "[^a-z0-9]+", "-"
  return $id.Trim("-")
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

if (!(Test-Path -LiteralPath $CsvPath)) {
  throw "CSV file was not found: $CsvPath"
}

if (!(Test-Path -LiteralPath $ServiceAccountPath)) {
  throw "Firebase service account file was not found: $ServiceAccountPath"
}

$requiredColumns = @("brand", "name", "diesel", "gasoline", "premium", "lat", "lng")
$rows = Import-Csv -LiteralPath $CsvPath
if ($rows.Count -eq 0) {
  throw "CSV has no station rows."
}

$headers = ($rows[0].PSObject.Properties | ForEach-Object { $_.Name })
foreach ($column in $requiredColumns) {
  if ($headers -notcontains $column) {
    throw "CSV is missing required column: $column"
  }
}

$serviceAccount = Get-Content -LiteralPath $ServiceAccountPath -Raw | ConvertFrom-Json
$projectId = $serviceAccount.project_id

Write-Host "Found $($rows.Count) station rows for project '$projectId'."

if ($DryRun) {
  foreach ($row in $rows) {
    $docId = New-FirestoreDocumentId $row
    Write-Host "DRY RUN: $docId -> $($row.brand), diesel=$($row.diesel), gasoline=$($row.gasoline), premium=$($row.premium)"
  }
  exit 0
}

$accessToken = Get-AccessToken $serviceAccount
$baseUri = "https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/$Collection"

foreach ($row in $rows) {
  $fields = @{}

  foreach ($column in $requiredColumns) {
    $value = ConvertTo-FirestoreValue $row.$column
    if ($null -ne $value) {
      $fields[$column] = $value
    }
  }

  $docId = New-FirestoreDocumentId $row
  $uri = "$baseUri/$([uri]::EscapeDataString($docId))"
  $body = @{ fields = $fields } | ConvertTo-Json -Depth 10 -Compress

  Invoke-RestMethod `
    -Method Patch `
    -Uri $uri `
    -Headers @{ Authorization = "Bearer $accessToken" } `
    -ContentType "application/json" `
    -Body $body | Out-Null

  Write-Host "Imported $docId"
}

Write-Host "Done. Imported $($rows.Count) station documents into '$Collection'."
