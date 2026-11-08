# Acha o endereco publicado no registro do deploy e configura o Estenda sozinho.
param([string]$Registro = "deploy.log")
$ErrorActionPreference = "Stop"
$texto = Get-Content -Raw -Path $Registro
$m = [regex]::Match($texto, "https://[A-Za-z0-9.-]+\.workers\.dev")
if (-not $m.Success) { Write-Host "  Nao achei o endereco workers.dev no resultado."; exit 2 }
$url = $m.Value
Write-Host "  Endereco: $url"
$pasta = if ($env:PONTE_REMOTA_CONFIG) { $env:PONTE_REMOTA_CONFIG } else { Join-Path $env:USERPROFILE ".ponte-remota" }
$corpo = '{"encontro": "' + $url + '"}'
$inst = Join-Path $pasta "instancia.json"
if (Test-Path $inst) {
  # o Estenda esta aberto: configura pelo painel local
  try {
    $i = Get-Content -Raw $inst | ConvertFrom-Json
    $wc = New-Object System.Net.WebClient
    $wc.Proxy = $null
    $wc.Headers.Add("X-Token", $i.token)
    $wc.Headers.Add("Content-Type", "application/json")
    $wc.Encoding = [System.Text.Encoding]::UTF8
    [void]$wc.UploadString("http://127.0.0.1:$($i.porta)/api/config", "POST", $corpo)
    Write-Host "  Pronto: o Estenda aberto ja esta usando este endereco."
    exit 0
  } catch { Write-Host "  O Estenda nao respondeu; vou gravar na configuracao." }
}
# o Estenda esta fechado: grava na configuracao para a proxima vez
New-Item -ItemType Directory -Force -Path $pasta | Out-Null
$arq = Join-Path $pasta "config.json"
$cfg = @{}
if (Test-Path $arq) {
  $lido = Get-Content -Raw $arq | ConvertFrom-Json
  foreach ($p in $lido.PSObject.Properties) { $cfg[$p.Name] = $p.Value }
}
$cfg["encontro"] = $url
[System.IO.File]::WriteAllText($arq, ($cfg | ConvertTo-Json), (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  Pronto: gravado. Ao abrir o Estenda, o acesso de longe ja vem configurado."
