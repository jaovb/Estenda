# Cria a parte Android do projeto (flutter create) e ajusta o que o app precisa:
# internet, conexão sem HTTPS na rede de casa, nome "Estenda" e o ícone.
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

if (-not (Test-Path "android")) {
    flutter create --platforms=android --org br.unb.ponte --project-name ponte_remota .
    if ($LASTEXITCODE -ne 0) { throw "flutter create falhou" }
    # o flutter create cria um teste de exemplo que não serve para este app
    if (Test-Path "test\widget_test.dart") { Remove-Item "test\widget_test.dart" }
}

$m = "android\app\src\main\AndroidManifest.xml"
$x = Get-Content $m -Raw
if ($x -notmatch "android.permission.INTERNET") {
    $x = $x -replace "<application", "<uses-permission android:name=`"android.permission.INTERNET`"/>`r`n    <application"
}
if ($x -notmatch "usesCleartextTraffic") {
    $x = $x -replace "<application", "<application android:usesCleartextTraffic=`"true`""
}
$x = $x -replace 'android:label="[^"]*"', 'android:label="Estenda"'
Set-Content $m $x -Encoding UTF8

# o Kotlin se perde no cache incremental quando o projeto e o cache do Flutter ficam em discos
# diferentes (C: e D:), o que acontece no GitHub e em muitos PCs: desliga só esse cache
$gp = "android\gradle.properties"
if ((Test-Path $gp) -and -not (Select-String -Path $gp -Pattern "kotlin.incremental" -Quiet)) {
    Add-Content $gp "`nkotlin.incremental=false"
}

$icone = Join-Path $PSScriptRoot "..\interface\icone-512.png"
if (-not (Test-Path $icone)) { $icone = Join-Path $PSScriptRoot "..\interface\icone.png" }
if (Test-Path $icone) {
    Get-ChildItem "android\app\src\main\res" -Directory -Filter "mipmap-*" | ForEach-Object {
        Copy-Item $icone (Join-Path $_.FullName "ic_launcher.png") -Force
    }
}
Write-Host "Projeto Android pronto."
