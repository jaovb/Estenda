# Prepara o projeto Android: cria a parte Android (flutter create) na primeira vez, copia a tela
# remota (../interface) para dentro do app e ajusta permissões, nome, ícone e motor gráfico.
# Funciona no Windows e no Linux (PowerShell 7).
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

if (-not (Test-Path "android")) {
    flutter create --platforms=android --org br.unb.ponte --project-name ponte_remota .
    if ($LASTEXITCODE -ne 0) { throw "flutter create falhou" }
    # o flutter create cria um teste de exemplo que não serve para este app
    if (Test-Path "test/widget_test.dart") { Remove-Item "test/widget_test.dart" }
}

# a tela remota vai embutida no app (é servida dentro do tablet em 127.0.0.1)
$web = "assets/web"
New-Item -ItemType Directory -Force $web | Out-Null
foreach ($f in "remoto.html", "base.js", "icone-192.png", "icone-512.png") {
    Copy-Item "../interface/$f" "$web/$f" -Force
}

$m = "android/app/src/main/AndroidManifest.xml"
$x = Get-Content $m -Raw
if ($x -notmatch "android.permission.INTERNET") {
    $x = $x -replace "<application", "<uses-permission android:name=`"android.permission.INTERNET`"/>`n    <application"
}
if ($x -notmatch "ACCESS_NETWORK_STATE") {
    $x = $x -replace "<application", "<uses-permission android:name=`"android.permission.ACCESS_NETWORK_STATE`"/>`n    <application"
}
if ($x -notmatch "usesCleartextTraffic") {
    $x = $x -replace "<application", "<application android:usesCleartextTraffic=`"true`""
}
$x = $x -replace 'android:label="[^"]*"', 'android:label="Estenda"'
# motor gráfico antigo (Skia): mais estável em tablets mais simples
if ($x -notmatch "EnableImpeller") {
    $x = $x -replace "</application>", "    <meta-data android:name=`"io.flutter.embedding.android.EnableImpeller`" android:value=`"false`" />`n    </application>"
}
Set-Content $m $x -Encoding UTF8

# o Kotlin se perde no cache incremental quando o projeto e o cache do Flutter ficam em discos
# diferentes (C: e D:), o que acontece no GitHub e em muitos PCs: desliga só esse cache
$gp = "android/gradle.properties"
if ((Test-Path $gp) -and -not (Select-String -Path $gp -Pattern "kotlin.incremental" -Quiet)) {
    Add-Content $gp "`nkotlin.incremental=false"
}

# o verificador "lint" do Android trava ao analisar a biblioteca do WebView (erro interno dele, não
# do app): desliga só essa verificação na compilação final
$bg = @("android/build.gradle.kts", "android/build.gradle") | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($bg -and -not (Select-String -Path $bg -Pattern "lintVital" -Quiet)) {
    Add-Content $bg "`nsubprojects {`n    tasks.matching { it.name.contains(`"lintVital`") }.configureEach { enabled = false }`n}"
}

$icone = "../interface/icone-512.png"
if (Test-Path $icone) {
    Get-ChildItem "android/app/src/main/res" -Directory -Filter "mipmap-*" | ForEach-Object {
        Copy-Item $icone (Join-Path $_.FullName "ic_launcher.png") -Force
    }
}
Write-Host "Projeto Android pronto."
