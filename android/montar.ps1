# Monta o Magen de Android: sai em android\dist\Magen-<versão>-android.apk
# Uso (no PowerShell, dentro da pasta android):  .\montar.ps1
# Para só rodar os testes do núcleo:               .\montar.ps1 -Testes

param([switch]$Testes)
# (Sem "Stop": no PowerShell 5.1, qualquer aviso do Java em stderr pararia o script.)
Set-Location $PSScriptRoot

# Java 17. Sem JAVA_HOME, procura o zip descompactado em AppData\Local\Programs.
if (-not $env:JAVA_HOME) {
    $jdk = Get-ChildItem "$env:LOCALAPPDATA\Programs" -Directory -Filter "jdk-17*" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $jdk) { throw "Falta o Java 17. Veja ANDROID.md, em 'Preparar o computador'." }
    $env:JAVA_HOME = $jdk.FullName
}

# Neste notebook, o Java não consegue usar a pasta temporária do Windows para a conversa interna
# dele ("Unable to establish loopback connection"). Usar outra pasta resolve.
$tmp = "C:\Users\Public\magen-tmp"
New-Item -ItemType Directory -Force $tmp | Out-Null
$env:JAVA_TOOL_OPTIONS = "-Djdk.net.unixdomain.tmpdir=$tmp"

if (-not (Test-Path "local.properties")) {
    "sdk.dir=$($env:LOCALAPPDATA -replace '\\','/')/Android/Sdk" | Set-Content -Encoding ascii local.properties
}

if ($Testes) { .\gradlew.bat --console=plain :app:testDebugUnitTest; exit $LASTEXITCODE }
.\gradlew.bat --console=plain :app:magenApk
if ($LASTEXITCODE -eq 0) { Get-ChildItem dist\*.apk | Select-Object Name, Length }
exit $LASTEXITCODE
