param(
  [string]$ProjectId = "pumpscout-davao",
  [string]$ServiceAccountPath = "C:\Users\johnl\Downloads\pumpscout-davao-firebase-adminsdk-fbsvc-e3b8b4b999.json",
  [string[]]$Collections = @("stations", "priceReports", "users", "contributionFeedback"),
  [switch]$ShowSample
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

function Get-DocId {
  param([string]$Name)

  if ([string]::IsNullOrWhiteSpace($Name)) {
    return ""
  }

  return ($Name -split "/")[-1]
}

function Read-Collection {
  param(
    [string]$Collection,
    [hashtable]$Headers
  )

  $baseUri = "https://firestore.googleapis.com/v1/projects/$ProjectId/databases/(default)/documents/$Collection"
  $pageToken = $null
  $count = 0
  $sampleIds = @()

  do {
    $uri = "$baseUri`?pageSize=300"
    if ($pageToken) {
      $uri = "$uri&pageToken=$pageToken"
    }

    try {
      $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $Headers
    } catch {
      return [pscustomobject]@{
        collection = $Collection
        count = "error"
        sample_ids = $_.Exception.Message
      }
    }

    foreach ($doc in @($response.documents)) {
      if ($null -eq $doc) {
        continue
      }

      $count += 1
      if ($sampleIds.Count -lt 5) {
        $sampleIds += Get-DocId $doc.name
      }
    }

    $pageToken = $response.nextPageToken
  } while ($pageToken)

  return [pscustomobject]@{
    collection = $Collection
    count = $count
    sample_ids = if ($ShowSample) { $sampleIds -join ", " } else { "" }
  }
}

if (!(Test-Path -Path $ServiceAccountPath)) {
  throw "Service account file not found: $ServiceAccountPath"
}

$serviceAccount = Get-Content -Raw -Path $ServiceAccountPath | ConvertFrom-Json
$accessToken = Get-AccessToken $serviceAccount
$headers = @{ Authorization = "Bearer $accessToken" }

$Collections | ForEach-Object {
  Read-Collection -Collection $_ -Headers $headers
} | Format-Table -AutoSize
