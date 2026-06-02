param(
  [string]$ServiceAccountPath = "C:\Users\johnl\Downloads\pumpscout-davao-firebase-adminsdk-fbsvc-e3b8b4b999.json",
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

function ConvertTo-Base64Url {
  param([byte[]]$Bytes)

  return [Convert]::ToBase64String($Bytes).TrimEnd("=").Replace("+", "-").Replace("/", "_")
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

function New-StringValue {
  param([string]$Value)
  return @{ stringValue = $Value }
}

function New-DoubleValue {
  param([double]$Value)
  return @{ doubleValue = $Value }
}

function New-BoolValue {
  param([bool]$Value)
  return @{ booleanValue = $Value }
}

function New-TimestampValue {
  param([DateTime]$Value)
  return @{ timestampValue = $Value.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ") }
}

function Invoke-FirestorePatch {
  param(
    [string]$Uri,
    [hashtable]$Fields,
    [string]$AccessToken
  )

  $body = @{ fields = $Fields } | ConvertTo-Json -Depth 20 -Compress
  Invoke-RestMethod `
    -Method Patch `
    -Uri $Uri `
    -Headers @{ Authorization = "Bearer $AccessToken" } `
    -ContentType "application/json" `
    -Body $body | Out-Null
}

if (!(Test-Path -LiteralPath $ServiceAccountPath)) {
  throw "Firebase service account file was not found: $ServiceAccountPath"
}

$serviceAccount = Get-Content -LiteralPath $ServiceAccountPath -Raw | ConvertFrom-Json
$projectId = $serviceAccount.project_id
$baseUri = "https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents"

$stations = @(
  @{
    id = "demo-shell-bajada"
    name = "Shell Bajada Demo"
    brand = "Shell"
    lat = 7.0916
    lng = 125.6135
    gasolineStart = 63.20
    dieselStart = 58.10
    premiumStart = 68.40
    weeklyChange = 1.20
  },
  @{
    id = "demo-petron-matina"
    name = "Petron Matina Demo"
    brand = "Petron"
    lat = 7.0592
    lng = 125.5908
    gasolineStart = 62.80
    dieselStart = 57.90
    premiumStart = 67.95
    weeklyChange = 0.75
  },
  @{
    id = "demo-phoenix-lanang"
    name = "Phoenix Lanang Demo"
    brand = "Phoenix"
    lat = 7.1048
    lng = 125.6472
    gasolineStart = 64.10
    dieselStart = 58.70
    premiumStart = 69.25
    weeklyChange = -0.35
  }
)

$startDate = [DateTime]::UtcNow.Date.AddDays(-42).AddHours(8)
$reportCountPerStation = 7
$demoUserId = "demo-data-seed"
$demoUserName = "Demo Price History"
$demoUserEmail = "demo@pumpscout.local"

Write-Host "Preparing demo price history for Firestore project '$projectId'."
Write-Host "This creates verified DEMO reports for trend/forecast testing."

if (!$DryRun) {
  $accessToken = Get-AccessToken $serviceAccount
}

foreach ($station in $stations) {
  $latestGasoline = 0.0
  $latestDiesel = 0.0
  $latestPremium = 0.0
  $latestDate = $startDate

  for ($index = 0; $index -lt $reportCountPerStation; $index++) {
    $createdAt = $startDate.AddDays($index * 7)
    $noise = (($index % 3) - 1) * 0.15
    $trend = $station.weeklyChange * $index

    $gasoline = [Math]::Round($station.gasolineStart + $trend + $noise, 2)
    $diesel = [Math]::Round($station.dieselStart + ($trend * 0.85) + $noise, 2)
    $premium = [Math]::Round($station.premiumStart + ($trend * 1.05) + $noise, 2)
    $reportId = "{0}-week-{1}" -f $station.id, ($index + 1)

    $reportFields = @{
      stationId = New-StringValue $station.id
      stationKey = New-StringValue "station:$($station.id)"
      stationName = New-StringValue $station.name
      brand = New-StringValue $station.brand
      lat = New-DoubleValue $station.lat
      lng = New-DoubleValue $station.lng
      gasoline = New-DoubleValue $gasoline
      diesel = New-DoubleValue $diesel
      premium = New-DoubleValue $premium
      status = New-StringValue "verified"
      userId = New-StringValue $demoUserId
      userDisplayName = New-StringValue $demoUserName
      userEmail = New-StringValue $demoUserEmail
      aiClassification = New-StringValue "usable"
      aiConfidence = New-DoubleValue 0.92
      needsAdminAttention = New-BoolValue $false
      aiModelVersion = New-StringValue "demo-seed"
      createdAt = New-TimestampValue $createdAt
      updatedAt = New-TimestampValue $createdAt
      reviewedAt = New-TimestampValue $createdAt
      reviewedBy = New-StringValue "demo-admin"
      reviewedByEmail = New-StringValue "demo-admin@pumpscout.local"
      isDemoData = New-BoolValue $true
    }

    $latestGasoline = $gasoline
    $latestDiesel = $diesel
    $latestPremium = $premium
    $latestDate = $createdAt

    if ($DryRun) {
      Write-Host "DRY RUN: priceReports/$reportId $($station.name) gasoline=$gasoline diesel=$diesel premium=$premium date=$($createdAt.ToString("yyyy-MM-dd"))"
    } else {
      $reportUri = "$baseUri/priceReports/$reportId"
      Invoke-FirestorePatch -Uri $reportUri -Fields $reportFields -AccessToken $accessToken
      Write-Host "Seeded priceReports/$reportId"
    }
  }

  $stationFields = @{
    name = New-StringValue $station.name
    brand = New-StringValue $station.brand
    lat = New-DoubleValue $station.lat
    lng = New-DoubleValue $station.lng
    gasoline = New-DoubleValue $latestGasoline
    diesel = New-DoubleValue $latestDiesel
    premium = New-DoubleValue $latestPremium
    updatedAt = New-TimestampValue $latestDate
    verifiedFromReportId = New-StringValue "$($station.id)-week-$reportCountPerStation"
    isDemoData = New-BoolValue $true
  }

  if ($DryRun) {
    Write-Host "DRY RUN: stations/$($station.id) latest gasoline=$latestGasoline diesel=$latestDiesel premium=$latestPremium"
  } else {
    $stationUri = "$baseUri/stations/$($station.id)"
    Invoke-FirestorePatch -Uri $stationUri -Fields $stationFields -AccessToken $accessToken
    Write-Host "Seeded stations/$($station.id)"
  }
}

Write-Host "Done. Demo data is marked with isDemoData=true."
