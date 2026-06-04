param(
  [string]$ProjectId = "pumpscout-davao",
  [string]$ServiceAccountPath = "C:\Users\johnl\Downloads\pumpscout-davao-firebase-adminsdk-fbsvc-e3b8b4b999.json",
  [string]$OutputPath = "data\training\GasPrice_Reviewed_Reports.csv",
  [switch]$IncludePending
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
  $jwt = "$unsignedJwt.$signature"

  $response = Invoke-RestMethod `
    -Method Post `
    -Uri $ServiceAccount.token_uri `
    -ContentType "application/x-www-form-urlencoded" `
    -Body @{
      grant_type = "urn:ietf:params:oauth:grant-type:jwt-bearer"
      assertion = $jwt
    }

  return $response.access_token
}

function Get-FirestoreValue {
  param($Value)

  if ($null -eq $Value) {
    return $null
  }

  if ($null -ne $Value.stringValue) { return $Value.stringValue }
  if ($null -ne $Value.integerValue) { return [double]$Value.integerValue }
  if ($null -ne $Value.doubleValue) { return [double]$Value.doubleValue }
  if ($null -ne $Value.booleanValue) { return [bool]$Value.booleanValue }
  if ($null -ne $Value.timestampValue) { return $Value.timestampValue }
  if ($null -ne $Value.nullValue) { return $null }

  return $Value
}

function Get-DocId {
  param([string]$Name)

  if ([string]::IsNullOrWhiteSpace($Name)) {
    return ""
  }

  return ($Name -split "/")[-1]
}

function Get-SpamType {
  param(
    [string]$Status,
    [string]$AiClassification,
    [string]$RejectionReason
  )

  if ($Status -ne "rejected") {
    return ""
  }

  $reason = $RejectionReason.ToLowerInvariant()
  if ($reason -match "photo|image|receipt|pump") { return "photo_issue" }
  if ($reason -match "station|location|wrong") { return "wrong_station" }
  if ($reason -match "duplicate|repeat") { return "duplicate" }
  if ($AiClassification -eq "spam") { return "ai_flagged_spam" }
  return "admin_rejected"
}

if (!(Test-Path -Path $ServiceAccountPath)) {
  throw "Service account file not found: $ServiceAccountPath"
}

$serviceAccount = Get-Content -Raw -Path $ServiceAccountPath | ConvertFrom-Json
$accessToken = Get-AccessToken $serviceAccount
$headers = @{ Authorization = "Bearer $accessToken" }
$baseUri = "https://firestore.googleapis.com/v1/projects/$ProjectId/databases/(default)/documents/priceReports"
$pageToken = $null
$rows = @()

do {
  $uri = "$baseUri`?pageSize=300"
  if ($pageToken) {
    $uri = "$uri&pageToken=$pageToken"
  }

  $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers

  foreach ($doc in @($response.documents)) {
    if ($null -eq $doc) {
      continue
    }

    $fields = $doc.fields
    $status = [string](Get-FirestoreValue $fields.status)

    if (!$IncludePending -and $status -eq "pending") {
      continue
    }

    $aiClassification = [string](Get-FirestoreValue $fields.aiClassification)
    $rejectionReason = [string](Get-FirestoreValue $fields.rejectionReason)
    $isSpam = if ($status -eq "rejected") { "True" } elseif ($status -eq "verified") { "False" } else { "" }

    $rows += [pscustomobject]@{
      report_id = Get-DocId $doc.name
      station_id = Get-FirestoreValue $fields.stationId
      station_name = Get-FirestoreValue $fields.stationName
      brand = Get-FirestoreValue $fields.brand
      regular_price = Get-FirestoreValue $fields.gasoline
      premium_price = Get-FirestoreValue $fields.premium
      diesel_price = Get-FirestoreValue $fields.diesel
      status = $status
      spam_type = Get-SpamType $status $aiClassification $rejectionReason
      is_spam = $isSpam
      ai_classification = $aiClassification
      ai_confidence = Get-FirestoreValue $fields.aiConfidence
      rejection_reason = $rejectionReason
      created_at = Get-FirestoreValue $fields.createdAt
      reviewed_at = Get-FirestoreValue $fields.reviewedAt
      user_id = Get-FirestoreValue $fields.userId
      has_photo = -not [string]::IsNullOrWhiteSpace([string](Get-FirestoreValue $fields.photoUrl))
      photo_upload_failed = Get-FirestoreValue $fields.photoUploadFailed
    }
  }

  $pageToken = $response.nextPageToken
} while ($pageToken)

$outputFullPath = Resolve-Path -Path "." | ForEach-Object {
  Join-Path $_.Path $OutputPath
}
$outputDir = Split-Path -Parent $outputFullPath
if (!(Test-Path -Path $outputDir)) {
  New-Item -ItemType Directory -Path $outputDir | Out-Null
}

$rows | Export-Csv -Path $outputFullPath -NoTypeInformation -Encoding UTF8
Write-Host "Exported $($rows.Count) reviewed reports to $outputFullPath"
