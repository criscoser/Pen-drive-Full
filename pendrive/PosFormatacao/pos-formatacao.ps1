param([switch]$SoRelatorio)
# =====================================================================
#  POS-FORMATACAO - pendrive Ventoy
#  Roda sozinho no 1o login (autounattend) ou com dois cliques em
#  POS-FORMATACAO.bat na raiz do pendrive.
#  Log: C:\PosFormatacao\log.txt
# =====================================================================

# ---------------- CONFIGURACAO ----------------
# Valores padrao. Para personalizar (Wi-Fi, programas, Office) crie o arquivo
# config.json nesta pasta, a partir do config.example.json. O config.json NAO vai
# para o GitHub (tem senha de Wi-Fi).
$WifiNome      = ''
$WifiSenha     = ''
# Produto do Office: O365BusinessRetail | O365ProPlusRetail | O365HomePremRetail | '' (nao instalar)
$OfficeProduto = 'O365BusinessRetail'
# $true = tambem atualiza programas que ja existem (mais lento). $false = so instala o que falta
$AtualizarProgramas = $false
# $true = aplica privacidade (sem telemetria) e otimizacoes do Windows
$Otimizar = $true
$Programas = @(
    'Google.Chrome',
    '7zip.7zip',
    'Adobe.Acrobat.Reader.64-bit',
    'VideoLAN.VLC',
    'AnyDesk.AnyDesk'
)
$cfgArq = Join-Path (Split-Path -Parent $PSCommandPath) 'config.json'
if (Test-Path $cfgArq) {
    try {
        $cfg = Get-Content $cfgArq -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -ne $cfg.WifiNome)           { $WifiNome = [string]$cfg.WifiNome }
        if ($null -ne $cfg.WifiSenha)          { $WifiSenha = [string]$cfg.WifiSenha }
        if ($null -ne $cfg.OfficeProduto)      { $OfficeProduto = [string]$cfg.OfficeProduto }
        if ($null -ne $cfg.AtualizarProgramas) { $AtualizarProgramas = [bool]$cfg.AtualizarProgramas }
        if ($null -ne $cfg.Otimizar)           { $Otimizar = [bool]$cfg.Otimizar }
        if ($cfg.Programas)                    { $Programas = @($cfg.Programas) }
    } catch { Write-Host "  (aviso) config.json invalido - usando valores padrao" -ForegroundColor DarkYellow }
}
# ----------------------------------------------

# Eleva para administrador se precisar
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" + $(if ($SoRelatorio) { ' -SoRelatorio' } else { '' }))
    exit
}

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$Pendrive = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$Work = 'C:\PosFormatacao'
New-Item -ItemType Directory -Force -Path $Work | Out-Null
Start-Transcript -Path (Join-Path $Work 'log.txt') -Append | Out-Null
$Host.UI.RawUI.WindowTitle = 'POS-FORMATACAO - nao feche esta janela'
$resumo = New-Object System.Collections.Generic.List[string]

function Etapa($t) { Write-Host "`n===== $t =====" -ForegroundColor Cyan }
function Ok($t)    { Write-Host "  [OK] $t" -ForegroundColor Green; $resumo.Add("[OK]    $t") }
function Falha($t) { Write-Host "  [FALHA] $t" -ForegroundColor Yellow; $resumo.Add("[FALHA] $t") }

function Set-Reg($path, $name, $value, $type = 'DWord') {
    try {
        if (-not (Test-Path $path)) { New-Item -Path $path -Force -ErrorAction Stop | Out-Null }
        New-ItemProperty -Path $path -Name $name -Value $value -PropertyType $type -Force -ErrorAction Stop | Out-Null
    } catch {
        # Algumas chaves sao protegidas pelo proprio Windows (ex.: Widgets). Apenas registra e segue.
        Write-Host "  (aviso) Windows nao permitiu alterar $name - ignorado" -ForegroundColor DarkYellow
    }
}

function Tem-Internet {
    try { (Invoke-WebRequest 'http://www.msftconnecttest.com/connecttest.txt' -UseBasicParsing -TimeoutSec 5).Content -like 'Microsoft Connect Test*' } catch { $false }
}

Write-Host "POS-FORMATACAO iniciado em $(Get-Date). Pode levar de 30 a 60 minutos." -ForegroundColor White
Write-Host "Deixe o carregador LIGADO e nao feche esta janela." -ForegroundColor White
Write-Host "Se o notebook reiniciar sozinho e abrir o menu do Ventoy, NAO escolha nada: ele entra no Windows em 10 s." -ForegroundColor Yellow

if (-not $SoRelatorio) {
# ---------------- 1. ENERGIA ----------------
Etapa '1/10 Energia'
powercfg /change standby-timeout-ac 0 | Out-Null
powercfg /change hibernate-timeout-ac 0 | Out-Null
powercfg /change monitor-timeout-ac 15 | Out-Null
Ok 'Na tomada o notebook nao dorme (tela apaga em 15 min)'
$naTomada = $true
try { $b = Get-CimInstance Win32_Battery -ErrorAction Stop; if ($b -and $b.BatteryStatus -eq 1) { $naTomada = $false } } catch {}
if (-not $naTomada) { Write-Host '  ATENCAO: o notebook esta na BATERIA. Ligue o carregador.' -ForegroundColor Red }

# ---------------- 2. WI-FI ----------------
Etapa '2/10 Wi-Fi'
function Novo-PerfilWifi($ssid, $senha) {
    $hex = -join ($ssid.ToCharArray() | ForEach-Object { '{0:X2}' -f [int]$_ })
    $esc = [System.Security.SecurityElement]::Escape($ssid)
    if ($senha) {
        $seg = "<authEncryption><authentication>WPA2PSK</authentication><encryption>AES</encryption><useOneX>false</useOneX></authEncryption><sharedKey><keyType>passPhrase</keyType><protected>false</protected><keyMaterial>$([System.Security.SecurityElement]::Escape($senha))</keyMaterial></sharedKey>"
    } else {
        $seg = "<authEncryption><authentication>open</authentication><encryption>none</encryption><useOneX>false</useOneX></authEncryption>"
    }
    $xml = "<?xml version=`"1.0`"?><WLANProfile xmlns=`"http://www.microsoft.com/networking/WLAN/profile/v1`"><name>$esc</name><SSIDConfig><SSID><hex>$hex</hex><name>$esc</name></SSID></SSIDConfig><connectionType>ESS</connectionType><connectionMode>auto</connectionMode><MSM><security>$seg</security></MSM></WLANProfile>"
    $arq = Join-Path $Work 'wifi.xml'
    $xml | Out-File -FilePath $arq -Encoding utf8
    netsh wlan add profile filename="$arq" user=all | Out-Null
    Remove-Item $arq -Force -ErrorAction SilentlyContinue
    netsh wlan connect name="$ssid" | Out-Null
}
function Espera-Internet($segundos) {
    for ($i = 0; $i -lt [math]::Ceiling($segundos/5); $i++) { if (Tem-Internet) { return $true }; Start-Sleep 5 }
    return $false
}
function Ler-ComTempo($pergunta, $segundos) {
    # Le uma resposta; se ninguem digitar nada em $segundos, devolve $null
    Write-Host -NoNewline $pergunta
    $txt = ''; $fim = (Get-Date).AddSeconds($segundos)
    try {
        while ((Get-Date) -lt $fim) {
            if ([Console]::KeyAvailable) {
                $k = [Console]::ReadKey($true)
                if ($k.Key -eq 'Enter') { Write-Host ''; return $txt }
                if ($k.Key -eq 'Backspace') { if ($txt.Length) { $txt = $txt.Substring(0, $txt.Length-1); Write-Host -NoNewline "`b `b" } ; continue }
                $txt += $k.KeyChar; Write-Host -NoNewline $k.KeyChar
                $fim = (Get-Date).AddSeconds($segundos)
            } else { Start-Sleep -Milliseconds 200 }
        }
    } catch { Write-Host ''; return (Read-Host) }
    Write-Host ''; return $null
}
function Salvar-WifiNoConfig($ssid, $senha) {
    try {
        $c = if (Test-Path $cfgArq) { Get-Content $cfgArq -Raw -Encoding UTF8 | ConvertFrom-Json } else { [pscustomobject]@{} }
        $c | Add-Member -NotePropertyName WifiNome -NotePropertyValue $ssid -Force
        $c | Add-Member -NotePropertyName WifiSenha -NotePropertyValue $senha -Force
        $c | ConvertTo-Json -Depth 5 | Out-File $cfgArq -Encoding utf8
        Write-Host "  Rede salva no pendrive (PosFormatacao\config.json)." -ForegroundColor Green
    } catch { Write-Host "  (aviso) nao foi possivel salvar no pendrive" -ForegroundColor DarkYellow }
}

$internet = Tem-Internet
if ($internet) {
    Ok 'Internet ja funcionando (cabo ou Wi-Fi ja conectado)'
} elseif ($WifiNome) {
    Novo-PerfilWifi $WifiNome $WifiSenha
    Write-Host "  Conectando em $WifiNome (ate 2 minutos)..."
    $internet = Espera-Internet 120
    if ($internet) { Ok "Rede $WifiNome configurada e internet funcionando" }
}
if (-not $internet -and -not $SoRelatorio) {
    Write-Host ''
    Write-Host '  Sem internet. Vamos conectar no Wi-Fi.' -ForegroundColor Yellow
    for ($tentativa = 1; $tentativa -le 3 -and -not $internet; $tentativa++) {
        $redes = @()
        try {
            netsh wlan disconnect | Out-Null
            Start-Sleep 3
            $redes = @(netsh wlan show networks mode=bssid | Select-String '^\s*SSID\s+\d+\s*:\s*(.+)$' | ForEach-Object { $_.Matches[0].Groups[1].Value.Trim() } | Where-Object { $_ } | Select-Object -Unique)
        } catch {}
        if ($redes.Count) {
            Write-Host '  Redes encontradas:'
            for ($i = 0; $i -lt $redes.Count; $i++) { Write-Host ("    {0,2}) {1}" -f ($i+1), $redes[$i]) }
            Write-Host '     D) Digitar o nome da rede (rede oculta)'
        } else {
            Write-Host '  Nao consegui listar as redes. Digite o nome da rede.'
        }
        Write-Host '     0) Pular (vou usar cabo / sem internet)'
        $resp = Ler-ComTempo '  Escolha e aperte ENTER (60 s para pular): ' 60
        if ($null -eq $resp -or $resp -eq '0') { break }
        $ssid = $null
        if ($resp -match '^\d+$' -and [int]$resp -ge 1 -and [int]$resp -le $redes.Count) { $ssid = $redes[[int]$resp-1] }
        elseif ($resp -match '^[Dd]$' -or -not $redes.Count) { $ssid = if ($redes.Count) { Read-Host '  Nome da rede' } else { $resp } }
        else { $ssid = $resp }
        if (-not $ssid) { continue }
        $sec = Read-Host "  Senha de $ssid (ENTER se for rede aberta)" -AsSecureString
        $senha = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
        Novo-PerfilWifi $ssid $senha
        Write-Host "  Conectando em $ssid..."
        $internet = Espera-Internet 40
        if ($internet) {
            Ok "Rede $ssid configurada e internet funcionando"
            $s = Ler-ComTempo '  Salvar esta rede no pendrive para as proximas maquinas? (S/N): ' 30
            if ($s -match '^[Ss]') { Salvar-WifiNoConfig $ssid $senha }
        } else {
            Write-Host '  Nao conectou. Confira a senha e tente de novo.' -ForegroundColor Yellow
            netsh wlan delete profile name="$ssid" | Out-Null
        }
        $senha = $null
    }
}
if (-not $internet) { Falha "Sem internet. Programas, drivers e Office nao serao instalados agora. Conecte e rode o script de novo." }

# ---------------- 3. LIMPEZA DO WINDOWS ----------------
Etapa '3/10 Limpeza do Windows'
$lixo = @(
    'Microsoft.BingNews','Microsoft.BingSearch','Microsoft.GamingApp','Microsoft.XboxApp',
    'Microsoft.XboxGamingOverlay','Microsoft.XboxGameOverlay','Microsoft.XboxSpeechToTextOverlay',
    'Microsoft.Xbox.TCUI','Clipchamp.Clipchamp','Microsoft.MicrosoftSolitaireCollection',
    'Microsoft.People','Microsoft.Getstarted','Microsoft.WindowsFeedbackHub',
    'Microsoft.MicrosoftOfficeHub','MSTeams','MicrosoftTeams','Microsoft.549981C3F5F10',
    'Microsoft.PowerAutomateDesktop','Microsoft.Copilot','Microsoft.Windows.Ai.Copilot.Provider','Microsoft.BingWeather','Microsoft.ZuneVideo','Microsoft.MixedReality.Portal',
    'Microsoft.SkypeApp','Microsoft.WindowsMaps','7EE7776C.LinkedInforWindows',
    '*CandyCrush*','*Spotify*','*Disney*','*TikTok*','*Instagram*','*Facebook*'
)
$removidos = 0
foreach ($n in $lixo) {
    Get-AppxPackage -AllUsers -Name $n -ErrorAction SilentlyContinue | ForEach-Object {
        try { Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction Stop; $removidos++ } catch {}
    }
    Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like $n } | ForEach-Object {
        try { Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction Stop | Out-Null } catch {}
    }
}
Ok "$removidos aplicativos desnecessarios removidos"

# Politicas da maquina: sem propaganda/apps sugeridos, sem Widgets
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 1
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableConsumerAccountStateContent' 1
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableSoftLanding' 1
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0
# Edge quieto (nao pede para ser padrao, nao abre sozinho)
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'HideFirstRunExperience' 1
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'DefaultBrowserSettingEnabled' 0
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'StartupBoostEnabled' 0
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'BackgroundModeEnabled' 0
Remove-Item "$env:PUBLIC\Desktop\Microsoft Edge.lnk" -Force -ErrorAction SilentlyContinue

# Preferencias do usuario atual e dos proximos usuarios
function Ajusta-Usuario($raiz) {
    $cdm = "$raiz\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    foreach ($v in 'SystemPaneSuggestionsEnabled','SilentInstalledAppsEnabled','SoftLandingEnabled','PreInstalledAppsEnabled','OemPreInstalledAppsEnabled','SubscribedContent-338388Enabled','SubscribedContent-338389Enabled','SubscribedContent-353694Enabled','SubscribedContent-353696Enabled','SubscribedContent-310093Enabled') { Set-Reg $cdm $v 0 }
    $adv = "$raiz\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    Set-Reg $adv 'HideFileExt' 0                 # mostrar extensoes
    Set-Reg $adv 'TaskbarAl' 0                   # barra a esquerda
    Set-Reg $adv 'Start_IrisRecommendations' 0   # sem dicas no Iniciar
    Set-Reg $adv 'Start_AccountNotifications' 0
    Set-Reg $adv 'ShowSyncProviderNotifications' 0
    Set-Reg "$raiz\Software\Microsoft\Windows\CurrentVersion\Search" 'SearchboxTaskbarMode' 1  # pesquisa so com icone
}
Ajusta-Usuario 'HKCU:'
reg.exe load 'HKU\PFDefault' 'C:\Users\Default\NTUSER.DAT' | Out-Null
if ($LASTEXITCODE -eq 0) {
    Ajusta-Usuario 'Registry::HKEY_USERS\PFDefault'
    [gc]::Collect(); Start-Sleep 1
    reg.exe unload 'HKU\PFDefault' | Out-Null
}
Ok 'Propagandas e sugestoes desligadas, extensoes visiveis, barra a esquerda'

# ---------------- 4. PRIVACIDADE E OTIMIZACAO ----------------
Etapa '4/10 Privacidade e otimizacao'
if (-not $Otimizar) { Ok 'Otimizacao desligada no config.json - pulada' }
else {
    # --- Telemetria e envio de dados (o minimo que o Windows aceita) ---
    $dc = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
    Set-Reg $dc 'AllowTelemetry' 0                      # Home/Pro tratam como o minimo ("Obrigatorio")
    Set-Reg $dc 'MaxTelemetryAllowed' 0
    Set-Reg $dc 'DoNotShowFeedbackNotifications' 1
    Set-Reg $dc 'AllowDeviceNameInTelemetry' 0
    Set-Reg $dc 'DisableOneSettingsDownloads' 1
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo' 'DisabledByGroupPolicy' 1
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'EnableActivityFeed' 0
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'PublishUserActivities' 0
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'UploadUserActivities' 0
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'AllowCrossDeviceClipboard' 0
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting' 'Disabled' 1
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows' 'CEIPEnable' 0
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat' 'AITEnable' 0
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat' 'DisableInventory' 1
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\TabletPC' 'PreventHandwritingDataSharing' 1
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\InputPersonalization' 'AllowInputPersonalization' 0
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Speech' 'AllowSpeechModelUpdate' 0
    # Copilot e Recall (IA que analisa a tela)
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 1
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'AllowRecallEnablement' 0
    # Pesquisa do Iniciar sem internet/Bing
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'DisableWebSearch' 1
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'ConnectedSearchUseWeb' 0
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'AllowCloudSearch' 0
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'AllowCortana' 0
    # Atualizacoes: nao enviar pedacos de update para outros PCs da internet
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' 0
    # Defender continua ligado e protegendo; so nao envia arquivos do usuario
    try { Set-MpPreference -SubmitSamplesConsent 2 -ErrorAction Stop } catch {}
    # Edge e Office sem relatorios de uso
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'DiagnosticData' 0
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'PersonalizationReportingEnabled' 0
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'ShowRecommendationsEnabled' 0
    Set-Reg 'HKLM:\SOFTWARE\Policies\Google\Chrome' 'MetricsReportingEnabled' 0
    # Servicos de telemetria (nao afetam Windows Update nem o funcionamento)
    foreach ($sv in 'DiagTrack','dmwappushservice') {
        try { Stop-Service $sv -Force -ErrorAction SilentlyContinue; Set-Service $sv -StartupType Disabled -ErrorAction Stop } catch {}
    }
    # Tarefas agendadas que coletam e enviam dados
    $tarefas = @(
        @('\Microsoft\Windows\Application Experience\','Microsoft Compatibility Appraiser'),
        @('\Microsoft\Windows\Application Experience\','Microsoft Compatibility Appraiser Exp'),
        @('\Microsoft\Windows\Application Experience\','ProgramDataUpdater'),
        @('\Microsoft\Windows\Application Experience\','StartupAppTask'),
        @('\Microsoft\Windows\Customer Experience Improvement Program\','Consolidator'),
        @('\Microsoft\Windows\Customer Experience Improvement Program\','UsbCeip'),
        @('\Microsoft\Windows\Autochk\','Proxy'),
        @('\Microsoft\Windows\DiskDiagnostic\','Microsoft-Windows-DiskDiagnosticDataCollector'),
        @('\Microsoft\Windows\Feedback\Siuf\','DmClient'),
        @('\Microsoft\Windows\Feedback\Siuf\','DmClientOnScenarioDownload'),
        @('\Microsoft\Windows\Windows Error Reporting\','QueueReporting')
    )
    $nt = 0
    foreach ($t in $tarefas) { try { Disable-ScheduledTask -TaskPath $t[0] -TaskName $t[1] -ErrorAction Stop | Out-Null; $nt++ } catch {} }

    # --- Preferencias por usuario (atual e proximos) ---
    function Otimiza-Usuario($raiz) {
        $pol = "$raiz\Software\Policies\Microsoft"
        Set-Reg "$pol\Windows\CloudContent" 'DisableTailoredExperiencesWithDiagnosticData' 1
        Set-Reg "$pol\Windows\Explorer" 'DisableSearchBoxSuggestions' 1
        Set-Reg "$pol\Windows\WindowsCopilot" 'TurnOffWindowsCopilot' 1
        Set-Reg "$raiz\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" 'Enabled' 0
        Set-Reg "$raiz\Software\Microsoft\Windows\CurrentVersion\Privacy" 'TailoredExperiencesWithDiagnosticDataEnabled' 0
        Set-Reg "$raiz\Software\Microsoft\Windows\CurrentVersion\Search" 'BingSearchEnabled' 0
        Set-Reg "$raiz\Software\Microsoft\Windows\CurrentVersion\Search" 'CortanaConsent' 0
        Set-Reg "$raiz\Software\Microsoft\Siuf\Rules" 'NumberOfSIUFInPeriod' 0
        Set-Reg "$raiz\Software\Microsoft\InputPersonalization" 'RestrictImplicitTextCollection' 1
        Set-Reg "$raiz\Software\Microsoft\InputPersonalization" 'RestrictImplicitInkCollection' 1
        Set-Reg "$raiz\Software\Microsoft\InputPersonalization\TrainedDataStore" 'HarvestContacts' 0
        Set-Reg "$raiz\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy" 'HasAccepted' 0
        Set-Reg "$raiz\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement" 'ScoobeSystemSettingEnabled' 0
        $cdm = "$raiz\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
        Set-Reg $cdm 'RotatingLockScreenOverlayEnabled' 0
        Set-Reg $cdm 'SubscribedContent-338387Enabled' 0
        # Office: sem telemetria e sem "experiencias conectadas" opcionais
        Set-Reg "$pol\Office\16.0\Common\ClientTelemetry" 'SendTelemetry' 3
        Set-Reg "$pol\Office\16.0\Common\ClientTelemetry" 'DisableTelemetry' 1
        Set-Reg "$pol\Office\16.0\Common\Privacy" 'controllerconnectedservicesenabled' 2
        Set-Reg "$pol\Office\Common\ClientTelemetry" 'SendTelemetry' 3
        # Jogos: sem gravacao em segundo plano
        Set-Reg "$raiz\System\GameConfigStore" 'GameDVR_Enabled' 0
        Set-Reg "$raiz\Software\Microsoft\Windows\CurrentVersion\GameDVR" 'AppCaptureEnabled' 0
        # Visual mais leve (mantem fonte suavizada e miniaturas)
        Set-Reg "$raiz\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" 'EnableTransparency' 0
        Set-Reg "$raiz\Control Panel\Desktop\WindowMetrics" 'MinAnimate' '0' 'String'
        Set-Reg "$raiz\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" 'TaskbarAnimations' 0
        Set-Reg "$raiz\Software\Microsoft\Windows\DWM" 'EnableAeroPeek' 0
        Set-Reg "$raiz\Control Panel\Desktop" 'MenuShowDelay' '100' 'String'
    }
    Otimiza-Usuario 'HKCU:'
    reg.exe load 'HKU\PFDefault' 'C:\Users\Default\NTUSER.DAT' 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { Otimiza-Usuario 'Registry::HKEY_USERS\PFDefault'; [gc]::Collect(); Start-Sleep 1; reg.exe unload 'HKU\PFDefault' | Out-Null }
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' 0

    # --- Desempenho e manutencao (vale para qualquer marca) ---
    # Inicializacao Rapida desligada: evita problemas de driver e de atualizacao
    Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' 0
    # Sensor de Armazenamento: limpa temporarios e lixeira com mais de 30 dias (Downloads nao e tocado)
    $ss = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\StorageSense'
    Set-Reg $ss 'AllowStorageSenseGlobal' 1
    Set-Reg $ss 'ConfigStorageSenseGlobalCadence' 7
    Set-Reg $ss 'AllowStorageSenseTemporaryFilesCleanup' 1
    Set-Reg $ss 'ConfigStorageSenseRecycleBinCleanupThreshold' 30
    Set-Reg $ss 'ConfigStorageSenseDownloadsCleanupThreshold' 0
    # SSD: garante TRIM ligado e otimiza; HD: desfragmentacao continua agendada pelo Windows
    fsutil behavior set DisableDeleteNotify 0 | Out-Null
    try {
        $tipo = (Get-PhysicalDisk | Where-Object { $_.DeviceId -eq ((Get-Partition -DriveLetter C | Get-Disk).Number) }).MediaType
        if ($tipo -eq 'SSD') { Optimize-Volume -DriveLetter C -ReTrim -ErrorAction SilentlyContinue | Out-Null }
    } catch {}
    # Limpa temporarios da instalacao
    Remove-Item "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "$env:WINDIR\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue

    Ok "Telemetria no minimo, sem propaganda/Bing/Copilot/Recall, $nt tarefas de coleta desligadas"
    Ok 'Visual mais leve, Inicializacao Rapida desligada, limpeza automatica e TRIM do SSD'
}

# ---------------- 5. PROGRAMAS ----------------
Etapa '5/10 Programas'
if ($internet) {
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) {
        try { Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction Stop } catch {}
        for ($i = 0; $i -lt 12 -and -not $winget; $i++) { Start-Sleep 10; $winget = Get-Command winget.exe -ErrorAction SilentlyContinue }
    }
    if (-not $winget) {
        $w = Get-ChildItem "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction SilentlyContinue | Sort-Object FullName | Select-Object -Last 1
        if ($w) { $winget = Get-Command $w.FullName }
    }
    if ($winget) {
        & $winget.Source source update | Out-Null
        # Verifica antes o que ja esta instalado (qualquer que seja a origem)
        $instalados = @{}
        foreach ($p in $Programas) {
            & $winget.Source list --id $p -e --accept-source-agreements --disable-interactivity | Out-Null
            $instalados[$p] = ($LASTEXITCODE -eq 0)
        }
        if (Test-Path "$env:ProgramFiles\Google\Chrome\Application\chrome.exe") { $instalados['Google.Chrome'] = $true }
        if ((Test-Path "$env:ProgramFiles\AnyDesk\AnyDesk.exe") -or (Test-Path "${env:ProgramFiles(x86)}\AnyDesk\AnyDesk.exe")) { $instalados['AnyDesk.AnyDesk'] = $true }
        Write-Host '  Situacao antes de instalar:'
        foreach ($p in $Programas) { if ($instalados[$p]) { Write-Host "    [ja instalado] $p" -ForegroundColor Green } else { Write-Host "    [vai baixar]   $p" -ForegroundColor Yellow } }
        foreach ($p in $Programas) {
            if ($instalados[$p] -and -not $AtualizarProgramas) { Ok "$p ja estava instalado (pulado)"; continue }
            Write-Host "  Instalando $p ..."
            & $winget.Source install --id $p -e --silent --scope machine --accept-package-agreements --accept-source-agreements --disable-interactivity | Out-Null
            if ($LASTEXITCODE -ne 0) {
                & $winget.Source install --id $p -e --silent --accept-package-agreements --accept-source-agreements --disable-interactivity | Out-Null
            }
            # -1978335189 = ja instalado/sem atualizacao
            if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq -1978335189) { Ok "$p instalado" } else { Falha "$p (codigo $LASTEXITCODE)" }
        }
    } else { Falha 'Instalador de programas (winget) indisponivel' }

    # Garante o Chrome mesmo se o winget falhar
    if (-not (Test-Path "$env:ProgramFiles\Google\Chrome\Application\chrome.exe")) {
        try {
            $msi = Join-Path $Work 'chrome.msi'
            Invoke-WebRequest 'https://dl.google.com/chrome/install/googlechromestandaloneenterprise64.msi' -OutFile $msi -UseBasicParsing
            Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /qn /norestart" -Wait
            if (Test-Path "$env:ProgramFiles\Google\Chrome\Application\chrome.exe") { Ok 'Google Chrome instalado (instalador da Google)' }
        } catch { Falha 'Google Chrome' }
    }
} else { Falha 'Programas nao instalados (sem internet)' }

# ---------------- 5. OFFICE ----------------
Etapa '6/10 Microsoft Office (demora 10-20 min)'
$temOffice = (Test-Path "$env:ProgramFiles\Microsoft Office\root\Office16\WINWORD.EXE") -or (Test-Path "${env:ProgramFiles(x86)}\Microsoft Office\root\Office16\WINWORD.EXE") -or (Test-Path "$env:ProgramFiles\Microsoft Office\Office16\WINWORD.EXE") -or (Test-Path "${env:ProgramFiles(x86)}\Microsoft Office\Office16\WINWORD.EXE")
if (-not $OfficeProduto) { Ok 'Office desativado no config.json - pulado' }
elseif ($temOffice) { Ok 'Office ja estava instalado' }
elseif ($internet) {
    try {
        $odt = Join-Path $Work 'office'
        New-Item -ItemType Directory -Force -Path $odt | Out-Null
        Invoke-WebRequest 'https://officecdn.microsoft.com/pr/wsus/setup.exe' -OutFile "$odt\setup.exe" -UseBasicParsing
        @"
<Configuration>
  <Add OfficeClientEdition="64" Channel="Current">
    <Product ID="$OfficeProduto">
      <Language ID="pt-br" />
      <ExcludeApp ID="Groove" />
      <ExcludeApp ID="Lync" />
      <ExcludeApp ID="Bing" />
      <ExcludeApp ID="Teams" />
    </Product>
  </Add>
  <Updates Enabled="TRUE" />
  <RemoveMSI />
  <Display Level="None" AcceptEULA="TRUE" />
</Configuration>
"@ | Out-File "$odt\config.xml" -Encoding utf8
        Start-Process "$odt\setup.exe" -ArgumentList "/configure `"$odt\config.xml`"" -Wait
        if (Test-Path "$env:ProgramFiles\Microsoft Office\root\Office16\WINWORD.EXE") { Ok "Office instalado ($OfficeProduto) - ative entrando com a conta da licenca" }
        else { Falha 'Office nao foi instalado' }
    } catch { Falha "Office: $($_.Exception.Message)" }
} else { Falha 'Office nao instalado (sem internet)' }

# ---------------- 6. CHROME PADRAO E BARRA DE TAREFAS ----------------
Etapa '7/10 Chrome como padrao e barra de tarefas'
if (Test-Path "$env:ProgramFiles\Google\Chrome\Application\chrome.exe") {
    # Chrome sem perguntas: sem tela de boas-vindas, sem pedir para ser padrao
    $cp = 'HKLM:\SOFTWARE\Policies\Google\Chrome'
    Set-Reg $cp 'DefaultBrowserSettingEnabled' 0
    Set-Reg $cp 'PromotionalTabsEnabled' 0
    Set-Reg $cp 'MetricsReportingEnabled' 0
    Set-Reg $cp 'PrivacySandboxPromptEnabled' 0
    $ip = "$env:ProgramFiles\Google\Chrome\Application\initial_preferences"
    '{"distribution":{"skip_first_run_ui":true,"do_not_launch_chrome":true,"suppress_first_run_default_browser_prompt":true,"make_chrome_default_for_user":false,"suppress_first_run_bubble":true},"browser":{"check_default_browser":false}}' | Out-File $ip -Encoding ascii
    @'
<?xml version="1.0" encoding="UTF-8"?>
<DefaultAssociations>
  <Association Identifier=".htm" ProgId="ChromeHTML" ApplicationName="Google Chrome" />
  <Association Identifier=".html" ProgId="ChromeHTML" ApplicationName="Google Chrome" />
  <Association Identifier="http" ProgId="ChromeHTML" ApplicationName="Google Chrome" />
  <Association Identifier="https" ProgId="ChromeHTML" ApplicationName="Google Chrome" />
</DefaultAssociations>
'@ | Out-File "$Work\NavegadorPadrao.xml" -Encoding utf8
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'DefaultAssociationsConfiguration' "$Work\NavegadorPadrao.xml" 'String'

    @'
<?xml version="1.0" encoding="utf-8"?>
<LayoutModificationTemplate xmlns="http://schemas.microsoft.com/Start/2014/LayoutModification" xmlns:defaultlayout="http://schemas.microsoft.com/Start/2014/FullDefaultLayout" xmlns:start="http://schemas.microsoft.com/Start/2014/StartLayout" xmlns:taskbar="http://schemas.microsoft.com/Start/2014/TaskbarLayout" Version="1">
  <CustomTaskbarLayoutCollection PinListPlacement="Replace">
    <defaultlayout:TaskbarLayout>
      <taskbar:TaskbarPinList>
        <taskbar:DesktopApp DesktopApplicationID="Microsoft.Windows.Explorer" />
        <taskbar:DesktopApp DesktopApplicationLinkPath="%ALLUSERSPROFILE%\Microsoft\Windows\Start Menu\Programs\Google Chrome.lnk" />
      </taskbar:TaskbarPinList>
    </defaultlayout:TaskbarLayout>
  </CustomTaskbarLayoutCollection>
</LayoutModificationTemplate>
'@ | Out-File "$Work\BarraDeTarefas.xml" -Encoding utf8
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer' 'StartLayoutFile' "$Work\BarraDeTarefas.xml" 'ExpandString'
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer' 'LockedStartLayout' 1
    Ok 'Chrome sera o navegador padrao e ficara na barra (Edge sai da barra) - vale a partir do proximo login'
} else { Falha 'Chrome nao instalado, padrao nao alterado' }

# ---------------- 7. DRIVERS E BIOS LENOVO ----------------
Etapa '8/10 Drivers e BIOS do fabricante'
$fab = (Get-CimInstance Win32_ComputerSystem).Manufacturer
$tvsu = "${env:ProgramFiles(x86)}\Lenovo\System Update\tvsu.exe"
if ($fab -notmatch 'LENOVO') { Ok "Fabricante $fab - drivers ficam com o Windows Update" }
elseif (-not $internet) { Falha 'Drivers Lenovo nao instalados (sem internet)' }
elseif (-not (Test-Path $tvsu) -and -not (Get-Command winget.exe -ErrorAction SilentlyContinue)) { Falha 'Lenovo System Update nao encontrado' }
else {
    if (-not (Test-Path $tvsu)) {
        Write-Host '  Instalando Lenovo System Update (so em computadores Lenovo)...'
        winget install --id Lenovo.SystemUpdate -e --silent --accept-package-agreements --accept-source-agreements --disable-interactivity | Out-Null
    }
    $g = 'HKLM:\SOFTWARE\Policies\Lenovo\System Update\UserSettings\General'
    Set-Reg $g 'AdminCommandLine' '/CM -search A -action INSTALL -includerebootpackages 1,3,4,5 -noicon -noreboot -nolicense' 'String'
    Set-Reg $g 'AskBeforeClosing' 'NO' 'String'
    Set-Reg $g 'DisplayLicenseNotice' 'NO' 'String'
    Set-Reg $g 'MetricsEnabled' 'NO' 'String'
    if (-not $naTomada) { Write-Host '  Notebook na bateria: a BIOS so sera atualizada com o carregador ligado.' -ForegroundColor Yellow }
    if (Test-Path $tvsu) { Start-Process $tvsu -ArgumentList '/CM' -Wait; Ok 'Lenovo System Update executado (drivers e BIOS)' } else { Falha 'Lenovo System Update nao instalado' }
}

# ---------------- 8. WINDOWS UPDATE ----------------
Etapa '9/10 Windows Update'
if ($internet) { Start-Process UsoClient.exe -ArgumentList 'StartInteractiveScan' -ErrorAction SilentlyContinue; Ok 'Busca do Windows Update iniciada (continua em segundo plano)' }

} # fim das etapas 1-8
if ($SoRelatorio) { $internet = $false; $resumo.Add('[OK]    Somente relatorio (pos-formatacao nao foi executada agora)') }
# ---------------- 9. RELATORIO E NOME ----------------
Etapa '10/10 Relatorio da maquina'
function Esc($t) { [System.Net.WebUtility]::HtmlEncode([string]$t) }

$cs   = Get-CimInstance Win32_ComputerSystem
$prod = Get-CimInstance Win32_ComputerSystemProduct
$bios = Get-CimInstance Win32_BIOS
$os   = Get-CimInstance Win32_OperatingSystem
$cpu  = Get-CimInstance Win32_Processor | Select-Object -First 1
$serie = ([string]$bios.SerialNumber).Trim()
$modelo = ($prod.Version -replace 'ThinkPad\s*','').Trim()
if (-not $modelo) { $modelo = 'PC' }
$novoNome = (($modelo + '-' + $serie) -replace '[^A-Za-z0-9-]','')
if ($novoNome.Length -gt 15) { $novoNome = $novoNome.Substring(0,15) }

# Cada item: Nome, Valor, Status (ok/atencao/ruim/info), Dica
$cards = New-Object System.Collections.Generic.List[object]
function Card($nome, $valor, $status, $dica) { $cards.Add([pscustomobject]@{ Nome=$nome; Valor=$valor; Status=$status; Dica=$dica }) }

# Ativacao
$ativ = '?'
try {
    $lic = Get-CimInstance SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL AND Name LIKE 'Windows%'" | Select-Object -First 1
    $ativ = @{0='Nao licenciado';1='Ativado';2='Periodo inicial';3='Periodo adicional';4='Nao original';5='Notificacao';6='Periodo estendido'}[[int]$lic.LicenseStatus]
} catch {}

# SSD (CrystalDiskInfo do pendrive; se faltar, usa o Windows)
$ssd = [ordered]@{ Modelo='?'; Saude=$null; Erros=$null; Horas=$null; Gravado=$null; Temp=$null; Desligamentos=$null }
$cdiOrig = Join-Path $Pendrive 'Portateis\CrystalDiskInfo9_9_4'
if (Test-Path "$cdiOrig\DiskInfo64.exe") {
    try {
        $cdi = Join-Path $Work 'cdi'
        Copy-Item $cdiOrig $cdi -Recurse -Force
        Start-Process "$cdi\DiskInfo64.exe" -ArgumentList '/CopyExit' -Wait
        if (Test-Path "$cdi\DiskInfo.txt") {
            $txt = Get-Content "$cdi\DiskInfo.txt" -Encoding UTF8
            Copy-Item "$cdi\DiskInfo.txt" "$Work\CrystalDiskInfo-completo.txt" -Force
            $l = $txt | Select-String '^\s*Model\s*:' | Select-Object -First 1; if ($l) { $ssd.Modelo = ($l.Line -split ':',2)[1].Trim() }
            $l = $txt | Select-String '\((\d{1,3})\s*%\)' | Select-Object -First 1; if ($l) { $ssd.Saude = [int]$l.Matches[0].Groups[1].Value }
            $l = $txt | Select-String '^\s*0E\s+([0-9A-Fa-f_]+)\s+Media and Data Integrity' | Select-Object -First 1
            if ($l) { $ssd.Erros = [Convert]::ToInt64(($l.Matches[0].Groups[1].Value -replace '_',''),16) }
            $l = $txt | Select-String '^\s*0D\s+([0-9A-Fa-f_]+)\s+Unsafe Shutdowns' | Select-Object -First 1
            if ($l) { $ssd.Desligamentos = [Convert]::ToInt64(($l.Matches[0].Groups[1].Value -replace '_',''),16) }
            $l = $txt | Select-String '^\s*Power On Hours\s*:\s*(\d+)' | Select-Object -First 1; if ($l) { $ssd.Horas = [int]$l.Matches[0].Groups[1].Value }
            $l = $txt | Select-String '^\s*Host Writes\s*:\s*(\d+)' | Select-Object -First 1; if ($l) { $ssd.Gravado = [int]$l.Matches[0].Groups[1].Value }
            $l = $txt | Select-String '^\s*Temperature\s*:\s*(\d+)' | Select-Object -First 1; if ($l) { $ssd.Temp = [int]$l.Matches[0].Groups[1].Value }
            if ($ssd.Modelo -eq '?') { $l = $txt | Select-String 'Model\s*:\s*(.+)' | Select-Object -First 1; if ($l) { $ssd.Modelo = $l.Matches[0].Groups[1].Value.Trim() } }
        }
    } catch {}
}
if ($null -eq $ssd.Saude) {
    try {
        $pd = Get-PhysicalDisk | Select-Object -First 1
        $c = $pd | Get-StorageReliabilityCounter
        $ssd.Modelo = $pd.FriendlyName
        if ($null -ne $c.Wear) { $ssd.Saude = 100 - [int]$c.Wear }
        $ssd.Horas = $c.PowerOnHours; $ssd.Temp = $c.Temperature
    } catch {}
}
$st = 'info'; $dica = 'Não foi possível ler a saúde do SSD'
if ($null -ne $ssd.Saude) {
    if ($ssd.Saude -ge 70) { $st = 'ok'; $dica = 'Vida útil boa' } elseif ($ssd.Saude -ge 30) { $st = 'atencao'; $dica = 'Desgaste médio - acompanhe' } else { $st = 'ruim'; $dica = 'Pouca vida útil - planeje a troca' }
}
if ($ssd.Erros -gt 0) { $st = 'ruim'; $dica = "$('{0:N0}' -f $ssd.Erros) erros de leitura/gravação - TROCAR o SSD e não guardar nada importante nele" }
Card 'SSD' $(if ($null -ne $ssd.Saude) { "$($ssd.Saude)% de vida útil" } else { '?' }) $st $dica

# Bateria
$bat = $null
try {
    $bx = Join-Path $Work 'bateria.xml'
    powercfg /batteryreport /xml /output "$bx" | Out-Null
    [xml]$x = Get-Content $bx
    $bt = @($x.BatteryReport.Batteries.Battery)[0]
    if ($bt -and [double]$bt.DesignCapacity -gt 0) {
        $bat = [ordered]@{ Pct=[math]::Round(100*[double]$bt.FullChargeCapacity/[double]$bt.DesignCapacity); Original=[int]$bt.DesignCapacity; Atual=[int]$bt.FullChargeCapacity; Ciclos=[int]$bt.CycleCount; Modelo="$($bt.Manufacturer) $($bt.Id)" }
    }
    powercfg /batteryreport /output "$Work\bateria.html" | Out-Null
} catch {}
if ($bat) {
    $st = if ($bat.Pct -ge 80) { 'ok' } elseif ($bat.Pct -ge 60) { 'atencao' } else { 'ruim' }
    $dica = if ($st -eq 'ok') { 'Autonomia boa' } elseif ($st -eq 'atencao') { 'Autonomia reduzida' } else { 'Bateria gasta - considerar troca' }
    Card 'Bateria' "$($bat.Pct)% da original" $st "$dica ($($bat.Ciclos) ciclos)"
} else { Card 'Bateria' 'Sem bateria' 'info' 'Desktop ou bateria não detectada' }

# Memoria
$mem = @(Get-CimInstance Win32_PhysicalMemory)
$memGB = [math]::Round(($mem | Measure-Object Capacity -Sum).Sum/1GB)
$slots = (Get-CimInstance Win32_PhysicalMemoryArray | Measure-Object MemoryDevices -Sum).Sum
$canal = if ($mem.Count -ge 2) { 'dois canais' } else { 'canal único' }
$st = if ($memGB -ge 16) { 'ok' } elseif ($memGB -ge 8) { 'atencao' } else { 'ruim' }
$dica = if ($memGB -ge 16) { 'Memória suficiente' } elseif ($mem.Count -lt 2 -and $slots -ge 2) { 'Colocar +1 pente de 8 GB deixa a máquina bem mais rápida' } else { 'Pouca memória para o uso atual' }
Card 'Memória' "$memGB GB ($canal)" $st $dica

# Drivers
$semDriver = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Error' -or ($_.ConfigManagerErrorCode -and $_.ConfigManagerErrorCode -ne 0) })
if ($semDriver.Count -eq 0) { Card 'Drivers' 'Todos instalados' 'ok' 'Nenhum dispositivo sem driver' }
else { Card 'Drivers' "$($semDriver.Count) faltando" 'atencao' 'Rode o Windows Update ou a ferramenta do fabricante' }

# Windows
$st = if ($ativ -eq 'Ativado') { 'ok' } else { 'ruim' }
Card 'Windows' $ativ $st "$($os.Caption -replace 'Microsoft ','') build $($os.BuildNumber)"

# BIOS
$biosVer = (([string]$bios.SMBIOSBIOSVersion) -replace '\s+', ' ' -replace ' \)', ')').Trim()
$idade = ((Get-Date) - $bios.ReleaseDate).TotalDays / 365
$st = if ($idade -le 2) { 'ok' } else { 'atencao' }
$dica = if ($st -eq 'ok') { 'Atualizada' } else { 'Antiga - atualize pelo site ou ferramenta do fabricante' }
Card 'BIOS' "$biosVer ($($bios.ReleaseDate.ToString('MM/yyyy')))" $st $dica

# ---------- monta o HTML ----------
$cor = @{ ok='#1f9d55'; atencao='#d4880f'; ruim='#d33a2c'; info='#6b7280' }
$fundo = @{ ok='#e8f6ee'; atencao='#fdf3e1'; ruim='#fbe9e7'; info='#f1f2f4' }
$rotulo = @{ ok='OK'; atencao='ATENÇÃO'; ruim='PROBLEMA'; info='INFO' }
$geral = if ($cards.Status -contains 'ruim') { 'ruim' } elseif ($cards.Status -contains 'atencao') { 'atencao' } else { 'ok' }
$geralTxt = @{ ok='Máquina aprovada'; atencao='Aprovada com observações'; ruim='Precisa de manutenção' }[$geral]

$htmlCards = ($cards | ForEach-Object {
    "<div class='card' style='border-top:5px solid $($cor[$_.Status]);background:$($fundo[$_.Status])'><div class='cn'>$(Esc $_.Nome)<span class='tag' style='background:$($cor[$_.Status])'>$($rotulo[$_.Status])</span></div><div class='cv'>$(Esc $_.Valor)</div><div class='cd'>$(Esc $_.Dica)</div></div>"
}) -join "`n"

$linhasMem = ($mem | ForEach-Object { "<tr><td>$(Esc $_.DeviceLocator)</td><td>$([math]::Round($_.Capacity/1GB)) GB</td><td>$($_.ConfiguredClockSpeed) MHz</td><td>$(Esc (([string]$_.Manufacturer).Trim() + ' ' + ([string]$_.PartNumber).Trim()))</td></tr>" }) -join ''
$linhasDrv = if ($semDriver.Count) { ($semDriver | ForEach-Object { "<li>$(Esc $_.FriendlyName)</li>" }) -join '' } else { '<li>Nenhum</li>' }
$linhasPassos = ($resumo | ForEach-Object {
    $ok = $_.StartsWith('[OK]'); $t = $_ -replace '^\[(OK|FALHA)\]\s*',''
    "<li><span class='p' style='background:$(if ($ok) { $cor.ok } else { $cor.atencao })'>$(if ($ok) { 'OK' } else { 'FALHA' })</span>$(Esc $t)</li>"
}) -join "`n"
function N($v, $suf) { if ($null -eq $v) { '?' } else { "$('{0:N0}' -f $v)$suf" } }

$html = @"
<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Relatório $(Esc $novoNome)</title>
<style>
*{box-sizing:border-box} body{margin:0;font-family:'Segoe UI',Arial,sans-serif;background:#f4f5f7;color:#1f2933}
.wrap{max-width:1000px;margin:0 auto;padding:24px 16px}
header{background:#1f2933;color:#fff;border-radius:14px;padding:22px 26px;display:flex;justify-content:space-between;flex-wrap:wrap;gap:12px;align-items:center}
header h1{margin:0;font-size:26px} header .sub{opacity:.8;font-size:14px;margin-top:4px}
.veredito{padding:10px 18px;border-radius:999px;font-weight:700;font-size:16px;color:#fff;background:$($cor[$geral])}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:14px;margin:20px 0}
.card{border-radius:12px;padding:16px 18px;box-shadow:0 1px 2px rgba(0,0,0,.06)}
.cn{font-size:13px;font-weight:600;text-transform:uppercase;letter-spacing:.04em;color:#52606d;display:flex;justify-content:space-between;align-items:center}
.tag{color:#fff;font-size:11px;padding:2px 8px;border-radius:999px;letter-spacing:.03em}
.cv{font-size:24px;font-weight:700;margin:8px 0 4px} .cd{font-size:13px;color:#3e4c59}
section{background:#fff;border-radius:12px;padding:18px 22px;margin-bottom:14px;box-shadow:0 1px 2px rgba(0,0,0,.06)}
h2{font-size:16px;margin:0 0 12px;color:#1f2933}
table{width:100%;border-collapse:collapse;font-size:14px} td,th{padding:7px 8px;border-bottom:1px solid #e4e7eb;text-align:left;vertical-align:top} th{color:#52606d;font-weight:600;width:38%}
ul{margin:0;padding-left:0;list-style:none} li{padding:5px 0;font-size:14px}
.p{display:inline-block;min-width:56px;text-align:center;color:#fff;font-size:11px;font-weight:700;border-radius:6px;padding:2px 6px;margin-right:10px}
footer{text-align:center;color:#7b8794;font-size:12px;margin:18px 0}
@media print{body{background:#fff} section,.card{box-shadow:none;border:1px solid #ddd}}
</style></head><body><div class="wrap">
<header><div><h1>$(Esc $novoNome)</h1><div class="sub">$(Esc "$($cs.Manufacturer) $($prod.Version)") &middot; Série $(Esc $serie) &middot; $(Get-Date -Format 'dd/MM/yyyy HH:mm')</div></div>
<div class="veredito">$geralTxt</div></header>
<div class="grid">
$htmlCards
</div>
<section><h2>Máquina</h2><table>
<tr><th>Modelo</th><td>$(Esc "$($cs.Manufacturer) $($prod.Version) ($($cs.Model))")</td></tr>
<tr><th>Processador</th><td>$(Esc $cpu.Name.Trim())</td></tr>
<tr><th>Windows</th><td>$(Esc "$($os.Caption) build $($os.BuildNumber) - $ativ")</td></tr>
<tr><th>BIOS</th><td>$(Esc "$biosVer de $($bios.ReleaseDate.ToString('dd/MM/yyyy'))")</td></tr>
</table></section>
<section><h2>SSD</h2><table>
<tr><th>Modelo</th><td>$(Esc $ssd.Modelo)</td></tr>
<tr><th>Vida útil restante</th><td>$(N $ssd.Saude '%')</td></tr>
<tr><th>Erros de dados (tem que ser 0)</th><td>$(N $ssd.Erros '')</td></tr>
<tr><th>Horas ligado</th><td>$(N $ssd.Horas ' h')</td></tr>
<tr><th>Total gravado</th><td>$(N $ssd.Gravado ' GB')</td></tr>
<tr><th>Desligamentos inesperados</th><td>$(N $ssd.Desligamentos '')</td></tr>
<tr><th>Temperatura</th><td>$(N $ssd.Temp ' &deg;C')</td></tr>
</table></section>
<section><h2>Bateria</h2><table>
$(if ($bat) { "<tr><th>Bateria</th><td>$(Esc $bat.Modelo)</td></tr><tr><th>Capacidade original</th><td>$(N $bat.Original ' mWh')</td></tr><tr><th>Capacidade atual</th><td>$(N $bat.Atual ' mWh') ($($bat.Pct)%)</td></tr><tr><th>Ciclos de carga</th><td>$(N $bat.Ciclos '')</td></tr>" } else { '<tr><td>Não detectada</td></tr>' })
</table></section>
<section><h2>Memória - $memGB GB, $(Esc $canal), $slots slot(s)</h2><table>
<tr><th>Slot</th><th>Tamanho</th><th>Velocidade</th><th>Fabricante / modelo</th></tr>$linhasMem
</table></section>
<section><h2>Dispositivos sem driver</h2><ul>$linhasDrv</ul></section>
<section><h2>O que a pós-formatação fez</h2><ul>
$linhasPassos
</ul></section>
<footer>Gerado pelo pendrive de manutenção &middot; detalhes técnicos em C:\PosFormatacao</footer>
</div></body></html>
"@

$arqRel = "Relatorio-$novoNome.html"
$desk = [Environment]::GetFolderPath('Desktop')
$html | Out-File (Join-Path $desk $arqRel) -Encoding utf8
$html | Out-File (Join-Path $Work $arqRel) -Encoding utf8

# Copia para o pendrive + dados para o painel geral de maquinas
try {
    $pasta = Join-Path $Pendrive 'Relatorios'
    $pastaDados = Join-Path $pasta 'dados'
    New-Item -ItemType Directory -Force -Path $pastaDados | Out-Null
    $html | Out-File (Join-Path $pasta $arqRel) -Encoding utf8
    [pscustomobject]@{
        Nome=$novoNome; Modelo="$($prod.Version)"; Serie=$serie; Data=(Get-Date -Format 'dd/MM/yyyy HH:mm'); Geral=$geral; GeralTxt=$geralTxt
        Cards=$cards.ToArray(); Arquivo=$arqRel
    } | ConvertTo-Json -Depth 5 | Out-File (Join-Path $pastaDados "$novoNome.json") -Encoding utf8

    # Painel geral com todas as maquinas ja feitas
    $todas = Get-ChildItem $pastaDados -Filter *.json | ForEach-Object { Get-Content $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json } | Sort-Object Nome
    $colunas = @('SSD','Bateria','Memória','Drivers','Windows','BIOS')
    $cab = ($colunas | ForEach-Object { "<th>$_</th>" }) -join ''
    $linhas = ($todas | ForEach-Object {
        $m = $_
        $cel = ($colunas | ForEach-Object { $n = $_; $c = @($m.Cards) | Where-Object { $_.Nome -eq $n } | Select-Object -First 1
            if ($c) { "<td><span class='dot' style='background:$($cor[$c.Status])'></span>$(Esc $c.Valor)</td>" } else { '<td>-</td>' } }) -join ''
        "<tr><td><a href='$(Esc $m.Arquivo)'><b>$(Esc $m.Nome)</b></a><div class='s'>$(Esc $m.Modelo) &middot; $(Esc $m.Data)</div></td><td><span class='v' style='background:$($cor[$m.Geral])'>$(Esc $m.GeralTxt)</span></td>$cel</tr>"
    }) -join "`n"
    @"
<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><title>Resumo das máquinas</title>
<style>body{margin:0;font-family:'Segoe UI',Arial,sans-serif;background:#f4f5f7;color:#1f2933}.wrap{max-width:1200px;margin:0 auto;padding:24px 16px}
h1{margin:0 0 4px}.sub{color:#52606d;margin-bottom:18px}table{width:100%;border-collapse:collapse;background:#fff;border-radius:12px;overflow:hidden;box-shadow:0 1px 2px rgba(0,0,0,.06);font-size:14px}
th{background:#1f2933;color:#fff;text-align:left;padding:10px;font-weight:600}td{padding:10px;border-bottom:1px solid #e4e7eb;vertical-align:top}a{color:#1f2933}
.s{color:#7b8794;font-size:12px}.dot{display:inline-block;width:10px;height:10px;border-radius:50%;margin-right:6px}.v{color:#fff;font-size:12px;font-weight:700;padding:3px 10px;border-radius:999px;white-space:nowrap}</style></head>
<body><div class="wrap"><h1>Resumo das máquinas</h1><div class="sub">$($todas.Count) máquina(s) &middot; clique no nome para ver o relatório completo</div>
<table><tr><th>Máquina</th><th>Situação</th>$cab</tr>
$linhas
</table></div></body></html>
"@ | Out-File (Join-Path $pasta 'Resumo-das-maquinas.html') -Encoding utf8
} catch { Write-Host "  (aviso) nao foi possivel gravar no pendrive: $($_.Exception.Message)" -ForegroundColor DarkYellow }
Write-Host "  Relatorio salvo na Area de Trabalho e no pendrive (pasta Relatorios)" -ForegroundColor Green
try { Start-Process (Join-Path $desk $arqRel) } catch {}

if ($env:COMPUTERNAME -ne $novoNome) {
    try { Rename-Computer -NewName $novoNome -Force -ErrorAction Stop; Write-Host "  Nome do computador sera $novoNome apos reiniciar" -ForegroundColor Green } catch { Write-Host "  Nao foi possivel renomear: $($_.Exception.Message)" -ForegroundColor Yellow }
}

Stop-Transcript | Out-Null
Write-Host "`n============================================================" -ForegroundColor Green
Write-Host " PRONTO! O relatorio abriu no navegador (e esta na Area de Trabalho)." -ForegroundColor Green
Write-Host " 1) TIRE O PENDRIVE." -ForegroundColor Yellow
Write-Host " 2) Com o CARREGADOR LIGADO, reinicie o notebook para concluir" -ForegroundColor Green
Write-Host " drivers, BIOS e o novo nome do computador." -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Read-Host "`nAperte ENTER para fechar"
