#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'

$ApiUrl = 'https://api.github.com/repos/ViTwix/twix.production.drives/contents/data/drives.json'
$PagesUrl = 'https://twix-production-drives.pages.dev'

function Get-ErrorResponseBody {
  param(
    [Parameter(Mandatory = $true)]
    [System.Net.WebResponse]$Response
  )

  $reader = New-Object System.IO.StreamReader($Response.GetResponseStream())
  return $reader.ReadToEnd()
}

function Invoke-GitHubRequest {
  param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('GET', 'PUT')]
    [string]$Method,
    [string]$Body = ''
  )

  $headers = @{
    Accept                 = 'application/vnd.github+json'
    Authorization          = "Bearer $($env:GITHUB_TOKEN)"
    'X-GitHub-Api-Version' = '2026-03-10'
    'User-Agent'           = 'twix-drives-scanner'
  }

  try {
    if ($Method -eq 'GET') {
      $response = Invoke-WebRequest -Method Get -Uri $ApiUrl -Headers $headers
    } else {
      $response = Invoke-WebRequest -Method Put -Uri $ApiUrl -Headers $headers -Body $Body -ContentType 'application/json'
    }

    return @{
      StatusCode = [int]$response.StatusCode
      Body       = $response.Content
    }
  } catch {
    if ($_.Exception.Response) {
      $statusCode = [int]$_.Exception.Response.StatusCode
      $responseBody = Get-ErrorResponseBody -Response $_.Exception.Response
      return @{
        StatusCode = $statusCode
        Body       = $responseBody
      }
    }

    throw
  }
}

function Get-RemoteState {
  $response = Invoke-GitHubRequest -Method GET

  switch ($response.StatusCode) {
    200 {
      $parsed = $response.Body | ConvertFrom-Json
      $sha = [string]$parsed.sha
      $contentRaw = [string]$parsed.content
      $contentBase64 = $contentRaw -replace '\s', ''

      if (-not $contentBase64) {
        throw "GitHub повернув порожній content для data/drives.json.`n$($response.Body)"
      }

      $decoded = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($contentBase64))
      return @{
        Sha  = $sha
        Json = $decoded
      }
    }
    404 {
      return @{
        Sha  = ''
        Json = '{"updatedAt": null, "drives": []}'
      }
    }
    default {
      throw "Помилка GET GitHub API (HTTP $($response.StatusCode)).`n$($response.Body)"
    }
  }
}

function Test-IsSkippedItem {
  param(
    [Parameter(Mandatory = $true)]
    [System.IO.FileSystemInfo]$Item
  )

  $skipNames = @(
    'System Volume Information',
    '$RECYCLE.BIN',
    '$Recycle.Bin',
    'RECYCLER'
  )

  if ($skipNames -contains $Item.Name) {
    return $true
  }

  if ($Item.Attributes -band [IO.FileAttributes]::Hidden) {
    return $true
  }

  if ($Item.Attributes -band [IO.FileAttributes]::System) {
    return $true
  }

  return $false
}

if (-not $env:GITHUB_TOKEN) {
  Write-Error 'Set GITHUB_TOKEN env var (see scripts/README.md)'
  exit 1
}

$volumes = Get-Volume |
  Where-Object {
    $_.DriveLetter -and
    ($_.DriveType -eq 'Fixed' -or $_.DriveType -eq 'Removable') -and
    ("$($_.DriveLetter):" -ne $env:SystemDrive)
  }

if (-not $volumes -or $volumes.Count -eq 0) {
  Write-Error 'Не знайдено зовнішніх томів для сканування.'
  exit 1
}

Write-Host 'Доступні томи:'
for ($i = 0; $i -lt $volumes.Count; $i += 1) {
  $label = $volumes[$i].FileSystemLabel
  $title = if ($label) { "$($volumes[$i].DriveLetter): ($label)" } else { "$($volumes[$i].DriveLetter):" }
  Write-Host ("  {0}) {1}" -f ($i + 1), $title)
}

$choiceRaw = Read-Host 'Оберіть номер тому'
$choice = 0
if (-not [int]::TryParse($choiceRaw, [ref]$choice) -or $choice -lt 1 -or $choice -gt $volumes.Count) {
  Write-Error 'Некоректний вибір тому.'
  exit 1
}

$selectedVolume = $volumes[$choice - 1]
$rootPath = '{0}:\' -f $selectedVolume.DriveLetter
$defaultDriveName = if ($selectedVolume.FileSystemLabel) { $selectedVolume.FileSystemLabel } else { "$($selectedVolume.DriveLetter):" }
$driveNameInput = Read-Host "Назва диска [$defaultDriveName]"
$driveName = if ([string]::IsNullOrWhiteSpace($driveNameInput)) { $defaultDriveName } else { $driveNameInput.Trim() }
$machineName = 'PC'
$nowIso = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

$entries = @()
$rootItems = Get-ChildItem -LiteralPath $rootPath -Force -ErrorAction SilentlyContinue |
  Where-Object { -not (Test-IsSkippedItem -Item $_) }

$totalItems = $rootItems.Count
for ($i = 0; $i -lt $totalItems; $i += 1) {
  $item = $rootItems[$i]
  Write-Host ("[{0}/{1}] {2}..." -f ($i + 1), $totalItems, $item.Name)

  if ($item.PSIsContainer) {
    try {
      $folderSize = (Get-ChildItem -LiteralPath $item.FullName -Recurse -File -Force -ErrorAction SilentlyContinue |
          Measure-Object -Property Length -Sum).Sum
      if ($null -eq $folderSize) {
        $folderSize = 0
      }

      $entries += [ordered]@{
        type      = 'folder'
        name      = $item.Name
        sizeBytes = [int64]$folderSize
      }
    } catch {
      Write-Warning "Пропускаю папку без доступу: $($item.Name)"
    }

    continue
  }

  try {
    $fileSize = (Get-Item -LiteralPath $item.FullName -ErrorAction Stop).Length
    $ext = $item.Extension.TrimStart('.').ToLowerInvariant()

    if ($ext) {
      $entries += [ordered]@{
        type      = 'file'
        name      = $item.Name
        ext       = $ext
        sizeBytes = [int64]$fileSize
      }
    } else {
      $entries += [ordered]@{
        type      = 'file'
        name      = $item.Name
        sizeBytes = [int64]$fileSize
      }
    }
  } catch {
    Write-Warning "Пропускаю файл без доступу: $($item.Name)"
  }
}

$entriesSorted = @(
  $entries | Sort-Object `
    @{ Expression = { if ($_.type -eq 'folder') { 0 } else { 1 } } }, `
    @{ Expression = { $_.name.ToLowerInvariant() } }
)
$totalBytes = [int64]$selectedVolume.Size
$freeBytes = [int64]$selectedVolume.SizeRemaining
$usedBytes = $totalBytes - $freeBytes

$driveRecord = [ordered]@{
  name       = $driveName
  scannedAt  = $nowIso
  scannedFrom = $machineName
  filesystem = [string]$selectedVolume.FileSystemType
  totalBytes = $totalBytes
  freeBytes  = $freeBytes
  usedBytes  = $usedBytes
  entries    = $entriesSorted
}

function Build-NextJson {
  param(
    [Parameter(Mandatory = $true)]
    [string]$CurrentJson,
    [Parameter(Mandatory = $true)]
    [hashtable]$DriveRecord,
    [Parameter(Mandatory = $true)]
    [string]$NowIso
  )

  $currentObj = $CurrentJson | ConvertFrom-Json
  $existingDrives = @($currentObj.drives)
  $filtered = @($existingDrives | Where-Object { $_.name -ne $DriveRecord.name })
  $merged = @($filtered + ([pscustomobject]$DriveRecord) | Sort-Object -Property name)

  $nextObj = [ordered]@{
    updatedAt = $NowIso
    drives    = $merged
  }

  return ($nextObj | ConvertTo-Json -Depth 10)
}

function Build-PutPayload {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Message,
    [Parameter(Mandatory = $true)]
    [string]$ContentBase64,
    [string]$Sha = ''
  )

  $payload = [ordered]@{
    message = $Message
    content = $ContentBase64
    branch  = 'main'
  }

  if ($Sha) {
    $payload.sha = $Sha
  }

  return ($payload | ConvertTo-Json -Depth 5 -Compress)
}

$commitMessage = "scan: $driveName from $machineName at $nowIso"
$remoteState = Get-RemoteState
$nextJson = Build-NextJson -CurrentJson $remoteState.Json -DriveRecord $driveRecord -NowIso $nowIso
$nextBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($nextJson))
$payload = Build-PutPayload -Message $commitMessage -ContentBase64 $nextBase64 -Sha $remoteState.Sha
$putResult = Invoke-GitHubRequest -Method PUT -Body $payload

if ($putResult.StatusCode -eq 409) {
  Write-Warning 'Отримано 409 Conflict. Повторюю один раз...'
  $remoteState = Get-RemoteState
  $nextJson = Build-NextJson -CurrentJson $remoteState.Json -DriveRecord $driveRecord -NowIso $nowIso
  $nextBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($nextJson))
  $payload = Build-PutPayload -Message $commitMessage -ContentBase64 $nextBase64 -Sha $remoteState.Sha
  $putResult = Invoke-GitHubRequest -Method PUT -Body $payload
}

if ($putResult.StatusCode -eq 200 -or $putResult.StatusCode -eq 201) {
  Write-Host "Готово. Дані оновлено успішно (HTTP $($putResult.StatusCode))."
  Write-Host "Веб: $PagesUrl"
  exit 0
}

Write-Error "Помилка PUT GitHub API (HTTP $($putResult.StatusCode)).`n$($putResult.Body)"
Write-Host 'Нижче надруковано JSON, який не вдалося записати:'
Write-Output $nextJson
exit 1
