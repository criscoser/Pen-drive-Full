param(
    [ValidateSet('inicio','pos','otimizar','relatorio')][string]$Modo = 'inicio',
    [switch]$Auto
)
# =====================================================================
#  PAINEL - Pendrive Full
#  Janela unica: pos-formatacao, otimizar, relatorio e ferramentas.
#  Monta um "plano" (o que fazer, instalar e remover) e chama o
#  pos-formatacao.ps1 com -Plano, mostrando o andamento ao vivo.
# =====================================================================

# Eleva para administrador (uma vez so; o motor herda)
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $a = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -STA -File `"$PSCommandPath`" -Modo $Modo" + $(if ($Auto) { ' -Auto' } else { '' })
    Start-Process powershell.exe -Verb RunAs -ArgumentList $a
    exit
}

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$Raiz     = Split-Path -Parent $PSCommandPath          # ...\PosFormatacao
$Pendrive = Split-Path -Parent $Raiz                    # raiz do pendrive
$Motor    = Join-Path $Raiz 'pos-formatacao.ps1'
$Work     = 'C:\PosFormatacao'
New-Item -ItemType Directory -Force -Path $Work | Out-Null
# Registro passo a passo (para descobrir problemas sem precisar ver a janela do PowerShell)
$LogP = Join-Path $Work 'painel-log.txt'
function Log-P($m) { try { "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') $m" | Out-File $script:LogP -Append -Encoding utf8 } catch {} }
try { if ((Test-Path $LogP) -and (Get-Item $LogP).Length -gt 512KB) { Remove-Item $LogP -Force } } catch {}
Log-P "---- painel iniciado: Modo=$Modo Auto=$Auto PS=$($PSVersionTable.PSVersion) pasta=$PSScriptRoot"

# Se o painel falhar, cai no modo antigo (janela simples) para a maquina nunca ficar sem pos-formatacao
function Usa-ModoAntigo($erro) {
    try { "$(Get-Date) $erro" | Out-File (Join-Path $Work 'painel-erro.txt') -Append -Encoding utf8 } catch {}
    Log-P "ERRO GERAL: $erro"
    if ($script:Modo -eq 'inicio') {
        try { Add-Type -AssemblyName System.Windows.Forms; [void][System.Windows.Forms.MessageBox]::Show("O painel nao abriu:`n$erro`n`nUse POS-FORMATACAO.bat, OTIMIZAR.bat ou RELATORIO.bat.", 'Pendrive Full') } catch {}
        return
    }
    $env:PF_SEM_PAINEL = '1'
    $f = switch ($script:Modo) { 'otimizar' { ' -SoOtimizar' } 'relatorio' { ' -SoRelatorio' } default { '' } }
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$Motor`"$f"
}

try {
# ------------------------------------------------------------------
# Ajudantes nativos: DPI nitido, barra de titulo escura e execucao do
# motor com a saida lida linha a linha (sem travar a janela)
# ------------------------------------------------------------------
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
if (-not ('PFNativo' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Collections.Concurrent;
public static class PFNativo {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int val, int size);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hwnd, int cmd);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hwnd);
    public static void Mostrar(IntPtr hwnd) { ShowWindow(hwnd, 9); ShowWindow(hwnd, 5); SetForegroundWindow(hwnd); }
    public static void TituloEscuro(IntPtr hwnd) {
        int on = 1;
        try { if (DwmSetWindowAttribute(hwnd, 20, ref on, 4) != 0) DwmSetWindowAttribute(hwnd, 19, ref on, 4); } catch {}
    }
}
public class PFExecutor {
    public ConcurrentQueue<string> Fila = new ConcurrentQueue<string>();
    public Process Proc;
    public void Iniciar(string exe, string args) {
        ProcessStartInfo si = new ProcessStartInfo(exe, args);
        si.UseShellExecute = false; si.CreateNoWindow = true;
        si.RedirectStandardOutput = true; si.RedirectStandardError = true;
        si.StandardOutputEncoding = System.Text.Encoding.UTF8;
        si.StandardErrorEncoding = System.Text.Encoding.UTF8;
        Proc = new Process(); Proc.StartInfo = si;
        Proc.OutputDataReceived += (s, e) => { if (e.Data != null) Fila.Enqueue(e.Data); };
        Proc.ErrorDataReceived  += (s, e) => { if (e.Data != null && e.Data.Trim().Length > 0) Fila.Enqueue("!! " + e.Data); };
        Proc.Start(); Proc.BeginOutputReadLine(); Proc.BeginErrorReadLine();
    }
    public bool Terminou { get { return Proc != null && Proc.HasExited; } }
    public void Esperar() { if (Proc != null) Proc.WaitForExit(); }
}
'@
}
[void][PFNativo]::SetProcessDPIAware()
[System.Windows.Forms.Application]::EnableVisualStyles()
# Erros dentro dos eventos da janela vao para o registro em vez de fechar tudo
try { [System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException) } catch {}
[System.Windows.Forms.Application]::add_ThreadException({ Log-P "ERRO NA JANELA: $($_.Exception.Message)" })
Log-P 'componentes carregados'


# ------------------------------------------------------------------
# Configuracao do pendrive (mesmo config.json do motor)
# ------------------------------------------------------------------
$Cfg = [ordered]@{ WifiNome=''; WifiSenha=''; OfficeProduto=''; Otimizar=$true; PerguntarProgramas=$true
                   Programas=@('Google.Chrome','7zip.7zip','Adobe.Acrobat.Reader.64-bit','VideoLAN.VLC') }
$cfgArq = Join-Path $Raiz 'config.json'
if (Test-Path $cfgArq) {
    try {
        $c = Get-Content $cfgArq -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($k in @($Cfg.Keys)) { if ($null -ne $c.$k) { $Cfg[$k] = $c.$k } }
        $Cfg.Programas = @($Cfg.Programas)
    } catch {}
}
$prefArq = Join-Path $Raiz 'painel-prefs.json'
$L = 'pt'
try { if (Test-Path $prefArq) { $pp = Get-Content $prefArq -Raw | ConvertFrom-Json; if ($pp.Idioma -in 'pt','en') { $L = $pp.Idioma } } } catch {}

# ------------------------------------------------------------------
# Textos PT / EN
# ------------------------------------------------------------------
$TX = @{
pt = @{
  sub='> formatar · otimizar · diagnosticar'; scan='> analisando este PC...'
  m1='[1] PÓS-FORMAT'; m1d='PC recém-formatado'; m1k='tudo marcado'
  m2='[2] OTIMIZAR';   m2d='PC em uso';          m2k='nada removido'
  m3='[3] RELATÓRIO';  m3d='avaliar o PC';       m3k='não altera nada'
  tools='tools:'; t_rel='Relatórios'
  tab1='otimizar'; tab2='instalar'; tab3='remover'
  voltar='voltar'; executar='EXECUTAR ▶'; fechar='fechar'; abrirRel='abrir relatório'; abrirLog='log'
  semNet='sem internet · rede:'; senha='senha:'; salvar='salvar no pendrive'
  o_Ponto='ponto de restauração'; o_Privacidade='privacidade: telemetria, Bing, Copilot, Recall'
  o_Propagandas='propagandas e sugestões'; o_Visual='visual leve (sem transparência e animações)'
  o_Temporarios='limpar temporários'; o_InicioRapido='desligar inicialização rápida'
  o_Aparencia='barra à esquerda + extensões visíveis'; o_Chrome='Chrome padrão + barra de tarefas'
  o_Drivers='drivers e BIOS do fabricante'; o_WindowsUpdate='Windows Update'; o_Renomear='renomear PC → MODELO-SÉRIE'
  obrig='obrigatório'; instalado='instalado'
  hintInst='> o que já está no PC aparece apagado e não é baixado de novo'
  hintRem='> {0} apps encontrados neste PC · marque o que quer tirar'; hintRem0='> nenhum app desnecessário encontrado neste PC'
  resumo='+{0} instalar · -{1} remover'; conta='EXECUTAR ▶ ({0})'
  execTit='[>] EXECUTANDO'; concl='[ OK ] concluído'; falhou='[FALHA] terminou com erro (código {0})'
  sairQ='Ainda está executando. Fechar a janela NÃO para o processo, ele continua escondido.`n`nFechar mesmo assim?'
  semBat='sem bateria'; desktop='desktop'; ativado='ativado'; naoAtivado='NÃO ativado'
  drvOk='drivers ok'; drvFalta='{0} sem driver'
  cat_prop='propaganda'; cat_jogo='jogos'; cat_com='comunicação'; cat_vid='vídeo'; cat_mus='música'; cat_soc='rede social'; cat_ia='IA'; cat_app='app'
}
en = @{
  sub='> install · optimize · diagnose'; scan='> scanning this PC...'
  m1='[1] POST-INSTALL'; m1d='freshly installed PC'; m1k='everything ticked'
  m2='[2] OPTIMIZE';     m2d='PC in use';            m2k='nothing removed'
  m3='[3] REPORT';       m3d='assess the PC';        m3k='changes nothing'
  tools='tools:'; t_rel='Reports'
  tab1='optimize'; tab2='install'; tab3='remove'
  voltar='back'; executar='RUN ▶'; fechar='close'; abrirRel='open report'; abrirLog='log'
  semNet='no internet · network:'; senha='password:'; salvar='save on the drive'
  o_Ponto='restore point'; o_Privacidade='privacy: telemetry, Bing, Copilot, Recall'
  o_Propagandas='ads and suggestions'; o_Visual='lighter visuals (no transparency/animations)'
  o_Temporarios='clean temporary files'; o_InicioRapido='turn off fast startup'
  o_Aparencia='taskbar left + file extensions'; o_Chrome='Chrome as default + taskbar'
  o_Drivers='manufacturer drivers and BIOS'; o_WindowsUpdate='Windows Update'; o_Renomear='rename PC → MODEL-SERIAL'
  obrig='required'; instalado='installed'
  hintInst='> apps already on this PC are greyed out and not downloaded again'
  hintRem='> {0} apps found on this PC · tick what to remove'; hintRem0='> no unnecessary apps found on this PC'
  resumo='+{0} install · -{1} remove'; conta='RUN ▶ ({0})'
  execTit='[>] RUNNING'; concl='[ OK ] done'; falhou='[FAIL] ended with an error (code {0})'
  sairQ='Still running. Closing the window does NOT stop it, it keeps running hidden.`n`nClose anyway?'
  semBat='no battery'; desktop='desktop'; ativado='activated'; naoAtivado='NOT activated'
  drvOk='drivers ok'; drvFalta='{0} missing driver(s)'
  cat_prop='ads'; cat_jogo='games'; cat_com='communication'; cat_vid='video'; cat_mus='music'; cat_soc='social'; cat_ia='AI'; cat_app='app'
}
}
function T($k) { $v = $script:TX[$script:L][$k]; if ($null -eq $v) { $v = $script:TX['pt'][$k] }; if ($null -eq $v) { $v = $k }; return ($v -replace '`n', "`n") }

# ------------------------------------------------------------------
# Tema ciano
# ------------------------------------------------------------------
function Cor($hex) { return [System.Drawing.ColorTranslator]::FromHtml($hex) }
$C = @{
  Fundo = Cor '#0a0f12'; Painel = Cor '#0f161a'; Linha = Cor '#1c2a30'; Hover = Cor '#132026'
  Texto = Cor '#c9d6d0'; Mudo = Cor '#5f7470'; Acento = Cor '#22e5ff'; Roxo = Cor '#c084fc'
  Ok = Cor '#3ddc84'; Aviso = Cor '#ffb020'; Ruim = Cor '#ff4d5e'; Escuro = Cor '#05080a'
}
$familia = 'Consolas'
try { if ((New-Object System.Drawing.Text.InstalledFontCollection).Families.Name -contains 'Cascadia Mono') { $familia = 'Cascadia Mono' } } catch {}
function Fonte($pt, [switch]$Negrito) { New-Object System.Drawing.Font($script:familia, [single]$pt, $(if ($Negrito) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular })) }
$F  = Fonte 9.5
$FP = Fonte 8.25
$FN = Fonte 9.5 -Negrito
$g0 = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero); $E = $g0.DpiX / 96.0; $g0.Dispose()
function S($n) { return [int][Math]::Round($n * $script:E) }
function Pt($x, $y) { New-Object System.Drawing.Point((S $x), (S $y)) }
function Tam($w, $h) { New-Object System.Drawing.Size((S $w), (S $h)) }

function Novo-Rotulo($pai, $texto, $x, $y, $cor, $fonte, [int]$w = 0, [int]$h = 0) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $texto; $l.ForeColor = $cor; $l.BackColor = [System.Drawing.Color]::Transparent
    $l.Font = $(if ($fonte) { $fonte } else { $script:F })
    if ($w -gt 0) { $l.AutoSize = $false; $l.Size = Tam $w $(if ($h -gt 0) { $h } else { 18 }) } else { $l.AutoSize = $true }
    $l.Location = Pt $x $y
    $pai.Controls.Add($l); return $l
}
function Novo-Botao($pai, $texto, $x, $y, $w, $h, [switch]$Principal) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $texto; $b.Font = $(if ($Principal) { $script:FN } else { $script:F })
    $b.FlatStyle = 'Flat'; $b.Location = Pt $x $y; $b.Size = Tam $w $h; $b.Cursor = 'Hand'
    $b.FlatAppearance.BorderSize = 1
    if ($Principal) {
        $b.BackColor = $script:C.Acento; $b.ForeColor = $script:C.Escuro; $b.FlatAppearance.BorderColor = $script:C.Acento
        $b.FlatAppearance.MouseOverBackColor = Cor '#7af0ff'
    } else {
        $b.BackColor = $script:C.Fundo; $b.ForeColor = $script:C.Texto; $b.FlatAppearance.BorderColor = $script:C.Linha
        $b.FlatAppearance.MouseOverBackColor = $script:C.Hover
    }
    $pai.Controls.Add($b); return $b
}
# Caixa com borda de 1 px (painel de fora na cor da linha, de dentro na cor do painel)
function Nova-Caixa($pai, $x, $y, $w, $h) {
    $fora = New-Object System.Windows.Forms.Panel
    $fora.Location = Pt $x $y; $fora.Size = Tam $w $h; $fora.BackColor = $script:C.Linha; $fora.Padding = New-Object System.Windows.Forms.Padding(1)
    $dentro = New-Object System.Windows.Forms.Panel
    $dentro.Dock = 'Fill'; $dentro.BackColor = $script:C.Painel
    $fora.Controls.Add($dentro); $pai.Controls.Add($fora)
    return @($fora, $dentro)
}
# Texto colorido numa RichTextBox
function Escreve($rtb, $texto, $cor, [switch]$Linha) {
    $rtb.SelectionStart = $rtb.TextLength; $rtb.SelectionLength = 0
    $rtb.SelectionColor = $cor
    $rtb.AppendText($texto + $(if ($Linha) { "`n" } else { '' }))
}
function Barra($pct, $tam = 10) {
    $n = [int][Math]::Round([Math]::Max(0, [Math]::Min(100, $pct)) / 100 * $tam)
    return ('█' * $n) + ('░' * ($tam - $n))
}

# ------------------------------------------------------------------
# Janela
# ------------------------------------------------------------------
$W = 480; $H = 450
$form = New-Object System.Windows.Forms.Form
$form.Text = 'pendrive-full'
$form.ClientSize = Tam $W $H
$form.FormBorderStyle = 'FixedSingle'; $form.MaximizeBox = $false
$form.StartPosition = 'CenterScreen'
$form.BackColor = $C.Fundo; $form.ForeColor = $C.Texto; $form.Font = $F
$form.KeyPreview = $true
try { $form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon((Get-Command powershell.exe).Source) } catch {}

$telaInicio = New-Object System.Windows.Forms.Panel; $telaInicio.Dock = 'Fill'
$telaConfig = New-Object System.Windows.Forms.Panel; $telaConfig.Dock = 'Fill'; $telaConfig.Visible = $false
$telaExec   = New-Object System.Windows.Forms.Panel; $telaExec.Dock = 'Fill';   $telaExec.Visible = $false
$form.Controls.AddRange(@($telaInicio, $telaConfig, $telaExec))
function Mostra-Tela($t) {
    foreach ($x in $script:telaInicio, $script:telaConfig, $script:telaExec) { $x.Visible = ($x -eq $t) }
}

# Lista de controles com texto traduzivel: @{ C = controle; K = chave }
$Traduz = New-Object System.Collections.Generic.List[object]
function Reg-Texto($ctl, $k) { $script:Traduz.Add(@{ C = $ctl; K = $k }); $ctl.Text = T $k; return $ctl }

# ================== TELA 1: INICIO ==================
$x0 = 16
$lT1 = Novo-Rotulo $telaInicio 'PENDRIVE' $x0 10 $C.Acento (Fonte 17 -Negrito)
$lT2 = Novo-Rotulo $telaInicio '://'      0   10 $C.Roxo   (Fonte 17 -Negrito)
$lT3 = Novo-Rotulo $telaInicio 'FULL'     0   10 $C.Acento (Fonte 17 -Negrito)
$lVer = Novo-Rotulo $telaInicio 'v1.0'    0   22 $C.Mudo $FP
$telaInicio.Add_Layout({
    $script:lT2.Left = $script:lT1.Right - (S 4); $script:lT3.Left = $script:lT2.Right - (S 4); $script:lVer.Left = $script:lT3.Right
})
$lSub = Reg-Texto (Novo-Rotulo $telaInicio '' $x0 42 $C.Mudo $FP) 'sub'

# Idioma
$bPT = Novo-Botao $telaInicio 'PT' ($W - 82) 12 32 22
$bEN = Novo-Botao $telaInicio 'EN' ($W - 48) 12 32 22
$bPT.Font = $FP; $bEN.Font = $FP

$lHost = Novo-Rotulo $telaInicio '' $x0 64 $C.Mudo $FP ($W - 32) 18

$cxStat = Nova-Caixa $telaInicio $x0 86 ($W - 32) 74
$rtbStat = New-Object System.Windows.Forms.RichTextBox
$rtbStat.Dock = 'Fill'; $rtbStat.BorderStyle = 'None'; $rtbStat.ReadOnly = $true; $rtbStat.BackColor = $C.Painel
$rtbStat.ForeColor = $C.Texto; $rtbStat.Font = $F; $rtbStat.ScrollBars = 'None'; $rtbStat.TabStop = $false; $rtbStat.Cursor = 'Default'
$cxStat[1].Padding = New-Object System.Windows.Forms.Padding((S 8), (S 5), (S 4), (S 2))
$cxStat[1].Controls.Add($rtbStat)

# Cartoes dos modos
$Cartoes = @()
$wc = [int](($W - 32 - 16) / 3)
$defs = @(@('pos','m1','m1d','m1k',$C.Aviso), @('otimizar','m2','m2d','m2k',$C.Ok), @('relatorio','m3','m3d','m3k',$C.Ok))
for ($i = 0; $i -lt 3; $i++) {
    $d = $defs[$i]
    $cx = Nova-Caixa $telaInicio ($x0 + $i * ($wc + 8)) 172 $wc 68
    $cx[0].Cursor = 'Hand'; $cx[1].Cursor = 'Hand'
    $a = Reg-Texto (Novo-Rotulo $cx[1] '' 7 6  $C.Texto $FN) $d[1]
    $b = Reg-Texto (Novo-Rotulo $cx[1] '' 7 27 $C.Mudo  $FP) $d[2]
    $k = Reg-Texto (Novo-Rotulo $cx[1] '' 7 45 $d[4]    $FP) $d[3]
    foreach ($ctl in @($cx[0], $cx[1], $a, $b, $k)) {
        $ctl.Tag = $d[0]
        $ctl.Add_Click({ Abre-Modo $this.Tag })
        $ctl.Add_MouseEnter({ Destaca-Cartao $this.Tag $true })
        $ctl.Add_MouseLeave({ Destaca-Cartao $this.Tag $false })
    }
    $Cartoes += [pscustomobject]@{ Modo = $d[0]; Fora = $cx[0]; Dentro = $cx[1]; Titulo = $a }
}
function Destaca-Cartao($modo, $on) {
    foreach ($c in $script:Cartoes) {
        if ($c.Modo -eq $modo) {
            $c.Fora.BackColor = $(if ($on) { $script:C.Acento } else { $script:C.Linha })
            $c.Dentro.BackColor = $(if ($on) { $script:C.Hover } else { $script:C.Painel })
            $c.Titulo.ForeColor = $(if ($on) { $script:C.Acento } else { $script:C.Texto })
        }
    }
}

# Ferramentas do pendrive
$lTools = Reg-Texto (Novo-Rotulo $telaInicio '' $x0 254 $C.Mudo $FP) 'tools'
function Acha-Exe($nome) {
    $base = Join-Path $script:Pendrive 'Portateis'
    if (-not (Test-Path $base)) { return $null }
    $f = Get-ChildItem $base -Recurse -Filter $nome -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($f) { return $f.FullName } else { return $null }
}
$Ferramentas = @(
    @('CrystalDiskInfo', (Acha-Exe 'DiskInfo64.exe')),
    @('HWiNFO',          (Acha-Exe 'HWiNFO64.exe')),
    @('USB',             (Acha-Exe 'UsbTreeView.exe')),
    @('DiskMark',        (Acha-Exe 'DiskMark64.exe')),
    @('Prime95',         (Acha-Exe 'prime95.exe')),
    @('FurMark',         (Acha-Exe 'FurMark_GUI.exe')),
    @('t_rel',           (Join-Path $Pendrive 'Relatorios'))
)
$fx = $x0; $fy = 272
foreach ($fe in $Ferramentas) {
    $nome = if ($fe[0] -eq 't_rel') { T 't_rel' } else { $fe[0] }
    $wb = [int](([System.Windows.Forms.TextRenderer]::MeasureText($nome, $FP).Width / $E) + 14)
    if ($fx + $wb -gt $W - 16) { $fx = $x0; $fy += 28 }
    $b = Novo-Botao $telaInicio $nome $fx $fy $wb 24
    $b.Font = $FP; $b.Tag = $fe[1]
    if ($fe[0] -eq 't_rel') { [void](Reg-Texto $b 't_rel') }
    if (-not $fe[1] -or -not (Test-Path $fe[1])) { $b.Enabled = $false; $b.ForeColor = $C.Mudo }
    $b.Add_Click({
        $alvo = [string]$this.Tag
        if ((Test-Path $alvo -PathType Container)) {
            $res = Join-Path $alvo 'Resumo-das-maquinas.html'
            if (Test-Path $res) { Start-Process $res } else { Start-Process explorer.exe $alvo }
        } else { Start-Process $alvo -WorkingDirectory (Split-Path -Parent $alvo) }
    })
    $fx += $wb + 6
}
$lRodape = Novo-Rotulo $telaInicio '' $x0 ($H - 26) $C.Mudo $FP ($W - 32) 18
$lRodape.Text = "pendrive: $Pendrive  ·  log: $Work"

# ------------------------------------------------------------------
# Leitura rapida da saude da maquina (para a tela inicial)
# ------------------------------------------------------------------
function Tem-Internet {
    try { (Invoke-WebRequest 'http://www.msftconnecttest.com/connecttest.txt' -UseBasicParsing -TimeoutSec 4).Content -like 'Microsoft Connect Test*' } catch { $false }
}
$Saude = $null
function Le-Saude {
    $s = [ordered]@{}
    try {
        $cs = Get-CimInstance Win32_ComputerSystem; $pr = Get-CimInstance Win32_ComputerSystemProduct
        $bi = Get-CimInstance Win32_BIOS; $os = Get-CimInstance Win32_OperatingSystem
        $s.Modelo = if ($cs.Manufacturer -match 'LENOVO' -and $pr.Version) { "Lenovo $($pr.Version)" } else { "$($cs.Manufacturer) $($cs.Model)".Trim() }
        $s.Serie = ([string]$bi.SerialNumber).Trim()
        $s.Bios = [string]$bi.SMBIOSBIOSVersion
        $s.Win = (($os.Caption -replace 'Microsoft\s*','') -replace 'Windows\s*','win').ToLower()
        $s.Host = $env:COMPUTERNAME
        $s.Ram = [Math]::Round(((Get-CimInstance Win32_PhysicalMemory | Measure-Object Capacity -Sum).Sum / 1GB))
    } catch {}
    try {
        $lic = Get-CimInstance SoftwareLicensingProduct -Filter "ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f' AND PartialProductKey IS NOT NULL" | Select-Object -First 1
        $s.Ativado = ([int]$lic.LicenseStatus -eq 1)
    } catch { $s.Ativado = $null }
    # SSD: desgaste informado pelo proprio disco (o relatorio completo usa o CrystalDiskInfo)
    $s.Disco = $null
    try {
        $dsk = Get-PhysicalDisk | Where-Object { $_.BusType -notin 'USB','SD','MMC' } | Sort-Object DeviceId | Select-Object -First 1
        if ($dsk) {
            $rc = $dsk | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
            $s.DiscoTipo = $(if ($dsk.MediaType -eq 'HDD') { 'HD' } else { 'SSD' })
            if ($rc -and $null -ne $rc.Wear) { $s.Disco = 100 - [int]$rc.Wear }
            elseif ($dsk.HealthStatus -eq 'Healthy') { $s.Disco = -1 } else { $s.Disco = -2 }
        }
    } catch {}
    $s.Bateria = $null
    try {
        $full = (Get-CimInstance -Namespace root\wmi -ClassName BatteryFullChargedCapacity -ErrorAction Stop | Measure-Object FullChargedCapacity -Sum).Sum
        $proj = (Get-CimInstance -Namespace root\wmi -ClassName BatteryStaticData -ErrorAction Stop | Measure-Object DesignedCapacity -Sum).Sum
        if ($proj -gt 0) { $s.Bateria = [int][Math]::Min(100, [Math]::Round($full / $proj * 100)) }
    } catch {}
    try { $s.SemDriver = @(Get-CimInstance Win32_PnPEntity | Where-Object { $_.ConfigManagerErrorCode -ne 0 -and $_.ConfigManagerErrorCode -ne 22 }).Count } catch { $s.SemDriver = 0 }
    $s.Internet = Tem-Internet
    return $s
}
function Mostra-Saude {
    $s = $script:Saude; $r = $script:rtbStat; $r.Clear()
    if (-not $s) { Escreve $r (T 'scan') $script:C.Mudo; return }
    $script:lHost.Text = "host $($s.Host) · $($s.Modelo) · $($s.Win) · " + $(if ($s.Ativado) { T 'ativado' } elseif ($null -eq $s.Ativado) { '?' } else { T 'naoAtivado' })
    # Disco
    $tipo = $(if ($s.DiscoTipo) { $s.DiscoTipo } else { 'SSD' })
    if ($null -eq $s.Disco) { Escreve $r '[ ?? ] ' $script:C.Mudo; Escreve $r "$tipo" $script:C.Texto -Linha }
    elseif ($s.Disco -lt 0) {
        $ok = ($s.Disco -eq -1)
        Escreve $r $(if ($ok) { '[ OK ] ' } else { '[FAIL] ' }) $(if ($ok) { $script:C.Acento } else { $script:C.Ruim })
        Escreve $r ("{0,-8} {1}" -f $tipo, $(if ($ok) { 'saudável / healthy' } else { 'com problema / failing' })) $script:C.Texto -Linha
    } else {
        $cor = if ($s.Disco -ge 80) { $script:C.Acento } elseif ($s.Disco -ge 50) { $script:C.Aviso } else { $script:C.Ruim }
        Escreve $r $(if ($s.Disco -ge 80) { '[ OK ] ' } elseif ($s.Disco -ge 50) { '[WARN] ' } else { '[FAIL] ' }) $cor
        Escreve $r ("{0,-8} " -f $tipo) $script:C.Texto; Escreve $r (Barra $s.Disco) $cor; Escreve $r " $($s.Disco)%" $script:C.Texto -Linha
    }
    # Bateria
    $nb = if ($script:L -eq 'en') { 'BATTERY' } else { 'BATERIA' }
    if ($null -eq $s.Bateria) { Escreve $r '[ -- ] ' $script:C.Mudo; Escreve $r ("{0,-8} {1}" -f $nb, (T 'semBat')) $script:C.Mudo -Linha }
    else {
        $cor = if ($s.Bateria -ge 80) { $script:C.Acento } elseif ($s.Bateria -ge 60) { $script:C.Aviso } else { $script:C.Ruim }
        Escreve $r $(if ($s.Bateria -ge 80) { '[ OK ] ' } elseif ($s.Bateria -ge 60) { '[WARN] ' } else { '[FAIL] ' }) $cor
        Escreve $r ("{0,-8} " -f $nb) $script:C.Texto; Escreve $r (Barra $s.Bateria) $cor; Escreve $r " $($s.Bateria)%" $script:C.Texto -Linha
    }
    # RAM, drivers, BIOS
    $okDrv = ($s.SemDriver -eq 0)
    Escreve $r $(if ($okDrv) { '[ OK ] ' } else { '[WARN] ' }) $(if ($okDrv) { $script:C.Acento } else { $script:C.Aviso })
    $dtxt = if ($okDrv) { T 'drvOk' } else { (T 'drvFalta') -f $s.SemDriver }
    Escreve $r ("RAM $($s.Ram) GB · $dtxt · BIOS $($s.Bios)") $script:C.Texto
}

# ================== TELA 2: CONFIGURACAO ==================
$lModo = Novo-Rotulo $telaConfig '' $x0 12 $C.Acento $FN
$lModoD = Novo-Rotulo $telaConfig '' 0 13 $C.Mudo $FP
$telaConfig.Add_Layout({ $script:lModoD.Left = $script:lModo.Right + (S 6) })

# Wi-Fi (so aparece sem internet)
$pWifi = New-Object System.Windows.Forms.Panel
$pWifi.Location = Pt $x0 36; $pWifi.Size = Tam ($W - 32) 50; $pWifi.Visible = $false
$telaConfig.Controls.Add($pWifi)
$lWifi = Reg-Texto (Novo-Rotulo $pWifi '' 0 3 $C.Aviso $FP) 'semNet'
$cbRede = New-Object System.Windows.Forms.ComboBox
$cbRede.Location = Pt 170 0; $cbRede.Size = Tam 278 22; $cbRede.FlatStyle = 'Flat'
$cbRede.BackColor = $C.Painel; $cbRede.ForeColor = $C.Texto; $cbRede.Font = $FP
$pWifi.Controls.Add($cbRede)
$lSenha = Reg-Texto (Novo-Rotulo $pWifi '' 0 29 $C.Mudo $FP) 'senha'
$txtSenha = New-Object System.Windows.Forms.TextBox
$txtSenha.Location = Pt 70 26; $txtSenha.Size = Tam 160 22; $txtSenha.UseSystemPasswordChar = $true
$txtSenha.BackColor = $C.Painel; $txtSenha.ForeColor = $C.Texto; $txtSenha.BorderStyle = 'FixedSingle'; $txtSenha.Font = $FP
$pWifi.Controls.Add($txtSenha)
$chkSalvar = New-Object System.Windows.Forms.CheckBox
$chkSalvar.Location = Pt 244 27; $chkSalvar.AutoSize = $true; $chkSalvar.Font = $FP; $chkSalvar.ForeColor = $C.Mudo
$chkSalvar.FlatStyle = 'Flat'
[void](Reg-Texto $chkSalvar 'salvar')
$pWifi.Controls.Add($chkSalvar)

# Abas
$Abas = @()
$yAbas = 40
for ($i = 0; $i -lt 3; $i++) {
    $b = Novo-Botao $telaConfig '' ($x0 + $i * 104) $yAbas 100 24
    $b.FlatAppearance.BorderSize = 0; $b.Tag = $i
    $b.Add_Click({ Para-Contagem; Mostra-Aba ([int]$this.Tag) })
    $Abas += $b
}
$cxLista = Nova-Caixa $telaConfig $x0 ($yAbas + 30) ($W - 32) 250
$Paginas = @()
for ($i = 0; $i -lt 3; $i++) {
    $p = New-Object System.Windows.Forms.Panel
    $p.Dock = 'Fill'; $p.AutoScroll = $true; $p.BackColor = $C.Painel; $p.Visible = ($i -eq 0)
    $cxLista[1].Controls.Add($p); $Paginas += $p
}
$AbaAtual = 0
function Mostra-Aba($n) {
    $script:AbaAtual = $n
    for ($i = 0; $i -lt 3; $i++) {
        $script:Paginas[$i].Visible = ($i -eq $n)
        $b = $script:Abas[$i]
        if ($i -eq $n) { $b.BackColor = $script:C.Acento; $b.ForeColor = $script:C.Escuro; $b.Font = $script:FN }
        else { $b.BackColor = $script:C.Fundo; $b.ForeColor = $script:C.Mudo; $b.Font = $script:F }
    }
}
function Atualiza-Abas {
    $ni = @($script:LinhasInst | Where-Object { $_.Marcado -and -not $_.Travado }).Count
    $nr = @($script:LinhasRem  | Where-Object { $_.Marcado }).Count
    $script:Abas[0].Text = T 'tab1'
    $script:Abas[1].Text = "$(T 'tab2')($ni)"
    $script:Abas[2].Text = "$(T 'tab3')($nr)"
    $script:lResumo.Text = (T 'resumo') -f $ni, $nr
}

$lResumo = Novo-Rotulo $telaConfig '' $x0 ($yAbas + 292) $C.Mudo $FP
$bVoltar = Reg-Texto (Novo-Botao $telaConfig '' ($W - 252) ($yAbas + 286) 90 28) 'voltar'
$bExec   = Novo-Botao $telaConfig '' ($W - 156) ($yAbas + 286) 140 28 -Principal
$bExec.Text = T 'executar'

# Linha com caixinha estilo terminal: [x] texto ........ etiqueta
$Linhas = New-Object System.Collections.Generic.List[object]
function Nova-Linha($pagina, $y, $chave, $texto, $etiqueta, $marcado, $travado, $tipo) {
    $r = [pscustomobject]@{ Chave=$chave; Texto=$texto; Etiqueta=$etiqueta; Marcado=[bool]$marcado; Travado=[bool]$travado; Tipo=$tipo; Cx=$null; Tx=$null; Et=$null; Painel=$null }
    $p = New-Object System.Windows.Forms.Panel
    $p.Location = Pt 0 $y; $p.Size = Tam ($script:W - 56) 22; $p.BackColor = $script:C.Painel; $p.Cursor = $(if ($travado) { 'Default' } else { 'Hand' })
    $r.Painel = $p
    $r.Cx = Novo-Rotulo $p '' 8 3 $script:C.Acento $script:FN
    $r.Tx = Novo-Rotulo $p '' 40 3 $script:C.Texto $script:F
    $r.Et = Novo-Rotulo $p '' 0 4 $script:C.Mudo $script:FP
    $r.Et.Anchor = 'Top,Right'
    foreach ($ctl in @($p, $r.Cx, $r.Tx, $r.Et)) {
        $ctl.Tag = $r
        $ctl.Add_Click({ $lin = $this.Tag; if (-not $lin.Travado) { Para-Contagem; $lin.Marcado = -not $lin.Marcado; Desenha-Linha $lin; Atualiza-Abas } })
        $ctl.Add_MouseEnter({ if (-not $this.Tag.Travado) { $this.Tag.Painel.BackColor = $script:C.Hover } })
        $ctl.Add_MouseLeave({ $this.Tag.Painel.BackColor = $script:C.Painel })
    }
    $pagina.Controls.Add($p)
    $script:Linhas.Add($r)
    Desenha-Linha $r
    return $r
}
function Desenha-Linha($r) {
    $txt = if ($r.Tipo -eq 'opcao') { T ('o_' + $r.Chave) } else { $r.Texto }
    $et = if ($r.Etiqueta) { T $r.Etiqueta } else { '' }
    if ($r.Tipo -eq 'inst' -and $r.Travado) {
        $r.Cx.Text = '[✓]'; $r.Cx.ForeColor = $script:C.Mudo; $r.Tx.ForeColor = $script:C.Mudo; $r.Et.ForeColor = $script:C.Ok
    } elseif ($r.Travado) {
        $r.Cx.Text = '[■]'; $r.Cx.ForeColor = $script:C.Roxo; $r.Tx.ForeColor = $script:C.Texto; $r.Et.ForeColor = $script:C.Roxo
    } elseif ($r.Marcado) {
        $r.Cx.Text = '[x]'; $r.Cx.ForeColor = $script:C.Acento; $r.Tx.ForeColor = $script:C.Texto; $r.Et.ForeColor = $script:C.Mudo
    } else {
        $r.Cx.Text = '[ ]'; $r.Cx.ForeColor = $script:C.Mudo; $r.Tx.ForeColor = $script:C.Texto; $r.Et.ForeColor = $script:C.Mudo
    }
    $r.Tx.Text = $txt; $r.Et.Text = $et
    $r.Et.Left = $r.Painel.Width - $r.Et.PreferredWidth - (S 8)
}

# Opcoes (aba otimizar): chave, padrao na pos-formatacao, padrao no otimizar
$Opcoes = @(
    @('Ponto',$false,$true), @('Privacidade',$true,$true), @('Propagandas',$true,$true), @('Visual',$true,$true),
    @('Temporarios',$true,$true), @('InicioRapido',$true,$false), @('Aparencia',$true,$false), @('Chrome',$true,$false),
    @('Drivers',$true,$false), @('WindowsUpdate',$true,$false), @('Renomear',$true,$false)
)
# Programas (aba instalar). Reg = nome em "Aplicativos instalados"; mesmo catalogo do pos-formatacao.ps1
$CatInst = @(
    @('Google Chrome','Google.Chrome','^Google Chrome$'), @('Mozilla Firefox','Mozilla.Firefox','^Mozilla Firefox'),
    @('7-Zip','7zip.7zip','^7-Zip'), @('Adobe Acrobat Reader','Adobe.Acrobat.Reader.64-bit','^Adobe Acrobat'),
    @('VLC','VideoLAN.VLC','^VLC media player'), @('AnyDesk','AnyDesk.AnyDesk','^AnyDesk'),
    @('TeamViewer','TeamViewer.TeamViewer','^TeamViewer'), @('Zoom','Zoom.Zoom','^Zoom'),
    @('Microsoft Teams','Microsoft.Teams','APPX:MSTeams'), @('LibreOffice','TheDocumentFoundation.LibreOffice','^LibreOffice'),
    @('Notepad++','Notepad++.Notepad++','^Notepad\+\+'), @('Microsoft 365 (Office)','OFFICE','OFFICE')
)
# Apps removiveis (aba remover): so aparecem se existirem no PC. Padroes = nomes dos pacotes da Microsoft Store
$CatRem = @(
    @('Notícias (Bing)',      @('Microsoft.BingNews'), 'cat_prop'),
    @('Pesquisa Bing',        @('Microsoft.BingSearch'), 'cat_prop'),
    @('Dicas do Windows',     @('Microsoft.Getstarted'), 'cat_prop'),
    @('Microsoft 365 (atalho)', @('Microsoft.MicrosoftOfficeHub'), 'cat_prop'),
    @('Candy Crush',          @('*CandyCrush*'), 'cat_prop'),
    @('Xbox',                 @('Microsoft.GamingApp','Microsoft.XboxApp','Microsoft.Xbox.TCUI'), 'cat_jogo'),
    @('Barra de jogo Xbox',   @('Microsoft.XboxGamingOverlay','Microsoft.XboxGameOverlay','Microsoft.XboxSpeechToTextOverlay'), 'cat_jogo'),
    @('Paciência',            @('Microsoft.MicrosoftSolitaireCollection'), 'cat_jogo'),
    @('Microsoft Teams',      @('MSTeams','MicrosoftTeams'), 'cat_com'),
    @('Skype',                @('Microsoft.SkypeApp'), 'cat_com'),
    @('Pessoas',              @('Microsoft.People'), 'cat_com'),
    @('Clipchamp',            @('Clipchamp.Clipchamp'), 'cat_vid'),
    @('Filmes e TV',          @('Microsoft.ZuneVideo'), 'cat_vid'),
    @('Disney+',              @('*Disney*'), 'cat_vid'),
    @('Spotify',              @('*Spotify*'), 'cat_mus'),
    @('TikTok',               @('*TikTok*'), 'cat_soc'),
    @('Instagram',            @('*Instagram*'), 'cat_soc'),
    @('Facebook',             @('*Facebook*'), 'cat_soc'),
    @('LinkedIn',             @('7EE7776C.LinkedInforWindows'), 'cat_soc'),
    @('Copilot',              @('Microsoft.Copilot','Microsoft.Windows.Ai.Copilot.Provider'), 'cat_ia'),
    @('Cortana',              @('Microsoft.549981C3F5F10'), 'cat_ia'),
    @('Clima',                @('Microsoft.BingWeather'), 'cat_app'),
    @('Mapas',                @('Microsoft.WindowsMaps'), 'cat_app'),
    @('Hub de Comentários',   @('Microsoft.WindowsFeedbackHub'), 'cat_app'),
    @('Power Automate',       @('Microsoft.PowerAutomateDesktop'), 'cat_app'),
    @('Realidade Misturada',  @('Microsoft.MixedReality.Portal'), 'cat_app')
)

$LinhasOpc = @(); $LinhasInst = @(); $LinhasRem = @()
$Varrido = $false; $RegNomes = @(); $AppxNomes = @()
$ModoAtual = 'pos'
$lHintInst = $null; $lHintRem = $null

function Monta-Config($modo) {
    $script:ModoAtual = $modo
    if (-not $script:Varrido) {
        $script:lModo.Text = T 'scan'; $script:lModoD.Text = ''
        Mostra-Tela $script:telaConfig; $script:form.Refresh()
        $script:RegNomes = @(foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*','HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*') {
            Get-ItemProperty $k -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName } | ForEach-Object { $_.DisplayName } })
        $script:AppxNomes = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | ForEach-Object { $_.Name } | Select-Object -Unique)
        $script:Varrido = $true
    }
    foreach ($pg in $script:Paginas) { $pg.Controls.Clear() }
    $script:Linhas.Clear()
    $pos = ($modo -eq 'pos')

    # --- aba otimizar ---
    $y = 4; $lo = @()
    foreach ($o in $script:Opcoes) {
        $marc = $(if ($pos) { $o[1] } else { $o[2] })
        if ($pos -and -not $script:Cfg.Otimizar -and $o[0] -in 'Privacidade','Visual','Temporarios','InicioRapido') { $marc = $false }
        $trav = (-not $pos -and $o[0] -eq 'Ponto')
        $lo += Nova-Linha $script:Paginas[0] $y $o[0] '' $(if ($trav) { 'obrig' } else { '' }) $marc $trav 'opcao'
        $y += 22
    }
    $script:LinhasOpc = $lo

    # --- aba instalar ---
    $temWord = (Test-Path "$env:ProgramFiles\Microsoft Office\root\Office16\WINWORD.EXE") -or (Test-Path "${env:ProgramFiles(x86)}\Microsoft Office\root\Office16\WINWORD.EXE")
    $script:lHintInst = Reg-Texto (Novo-Rotulo $script:Paginas[1] '' 8 4 $script:C.Mudo $script:FP) 'hintInst'
    $y = 24; $li = @()
    foreach ($c in $script:CatInst) {
        $inst = $false
        if ($c[2] -eq 'OFFICE') { $inst = $temWord }
        elseif ($c[2] -like 'APPX:*') { $inst = ($script:AppxNomes -contains $c[2].Substring(5)) }
        else { $re = $c[2]; $inst = [bool]($script:RegNomes | Where-Object { $_ -match $re } | Select-Object -First 1) }
        $padrao = $pos -and (($script:Cfg.Programas -contains $c[1]) -or ($c[1] -eq 'OFFICE' -and [bool]$script:Cfg.OfficeProduto))
        $lin = Nova-Linha $script:Paginas[1] $y $c[1] $c[0] $(if ($inst) { 'instalado' } else { '' }) $(if ($inst) { $false } else { $padrao }) $inst 'inst'
        $li += $lin; $y += 22
    }
    # programas extras do config.json que nao estao no catalogo
    foreach ($id in $script:Cfg.Programas) {
        if (-not ($script:CatInst | Where-Object { $_[1] -eq $id })) { $li += Nova-Linha $script:Paginas[1] $y $id $id '' $pos $false 'inst'; $y += 22 }
    }
    $script:LinhasInst = $li

    # --- aba remover: so o que existe neste PC ---
    $y = 24; $lr = @()
    foreach ($c in $script:CatRem) {
        $existe = $false
        foreach ($pad in $c[1]) { if ($script:AppxNomes | Where-Object { $_ -like $pad } | Select-Object -First 1) { $existe = $true; break } }
        if (-not $existe) { continue }
        $lin = Nova-Linha $script:Paginas[2] $y ($c[1] -join '|') $c[0] $c[2] $pos $false 'rem'
        $lr += $lin; $y += 22
    }
    $script:LinhasRem = $lr
    $script:lHintRem = Novo-Rotulo $script:Paginas[2] '' 8 4 $script:C.Mudo $script:FP
    $script:lHintRem.Text = $(if ($lr.Count) { (T 'hintRem') -f $lr.Count } else { T 'hintRem0' })

    # --- cabecalho, Wi-Fi e abas ---
    $script:lModo.Text = $(if ($pos) { T 'm1' } else { T 'm2' })
    $script:lModoD.Text = '· ' + $(if ($pos) { T 'm1d' } else { T 'm2d' })
    $semNet = ($script:Saude -and -not $script:Saude.Internet)
    $script:pWifi.Visible = [bool]$semNet
    $dy = $(if ($semNet) { 56 } else { 0 })
    for ($i = 0; $i -lt 3; $i++) { $script:Abas[$i].Top = S ($script:yAbas + $dy) }
    $script:cxLista[0].Top = S ($script:yAbas + 30 + $dy)
    $script:cxLista[0].Height = S (250 - $dy)
    if ($semNet -and $script:cbRede.Items.Count -eq 0) {
        $redes = @()
        try { $redes = @(netsh wlan show networks | Select-String '^\s*SSID\s+\d+\s*:\s*(.+)$' | ForEach-Object { $_.Matches[0].Groups[1].Value.Trim() } | Where-Object { $_ } | Select-Object -Unique) } catch {}
        foreach ($rd in $redes) { [void]$script:cbRede.Items.Add($rd) }
        if ($script:Cfg.WifiNome) { $script:cbRede.Text = $script:Cfg.WifiNome; $script:txtSenha.Text = $script:Cfg.WifiSenha }
        elseif ($redes.Count) { $script:cbRede.SelectedIndex = 0 }
    }
    $script:form.Text = "pendrive-full / $(if ($pos) { 'pos' } else { 'otimizar' })"
    Mostra-Aba 0
    Atualiza-Abas
    Mostra-Tela $script:telaConfig
}

# Contagem regressiva (pos-formatacao automatica no primeiro login)
$Contagem = @{ Resta = 0 }
$timerConta = New-Object System.Windows.Forms.Timer; $timerConta.Interval = 1000
$timerConta.Add_Tick({
    $script:Contagem.Resta--
    if ($script:Contagem.Resta -le 0) { $script:timerConta.Stop(); $script:bExec.Text = T 'executar'; Executa }
    else { $script:bExec.Text = (T 'conta') -f $script:Contagem.Resta }
})
function Para-Contagem { if ($script:timerConta.Enabled) { $script:timerConta.Stop(); $script:bExec.Text = T 'executar' } }
$cbRede.Add_TextChanged({ Para-Contagem }); $txtSenha.Add_TextChanged({ Para-Contagem }); $chkSalvar.Add_Click({ Para-Contagem })
$form.Add_KeyDown({ Para-Contagem })

# ================== TELA 3: EXECUCAO ==================
$lExec = Novo-Rotulo $telaExec '' $x0 12 $C.Acento $FN
$lBarra = Novo-Rotulo $telaExec '' $x0 36 $C.Acento $F ($W - 32) 20
$lPasso = Novo-Rotulo $telaExec '' $x0 58 $C.Mudo $FP ($W - 32) 18
$cxLog = Nova-Caixa $telaExec $x0 80 ($W - 32) 314
$rtbLog = New-Object System.Windows.Forms.RichTextBox
$rtbLog.Dock = 'Fill'; $rtbLog.BorderStyle = 'None'; $rtbLog.ReadOnly = $true; $rtbLog.BackColor = $C.Escuro
$rtbLog.ForeColor = $C.Texto; $rtbLog.Font = $FP; $rtbLog.WordWrap = $true
$cxLog[1].BackColor = $C.Escuro; $cxLog[1].Padding = New-Object System.Windows.Forms.Padding((S 6), (S 4), (S 2), (S 2))
$cxLog[1].Controls.Add($rtbLog)
$bLog    = Novo-Botao $telaExec '' $x0 ($H - 46) 60 28
$bAbreRel = Novo-Botao $telaExec '' ($W - 312) ($H - 46) 170 28
$bFechar = Novo-Botao $telaExec '' ($W - 136) ($H - 46) 120 28 -Principal
[void](Reg-Texto $bLog 'abrirLog'); [void](Reg-Texto $bAbreRel 'abrirRel'); [void](Reg-Texto $bFechar 'fechar')
$bAbreRel.Visible = $false; $bFechar.Enabled = $false
$bLog.Add_Click({ $lg = Join-Path $script:Work 'log.txt'; if (Test-Path $lg) { Start-Process notepad.exe $lg } })
$bAbreRel.Add_Click({ if ($script:Exec.Relatorio -and (Test-Path $script:Exec.Relatorio)) { Start-Process $script:Exec.Relatorio } })
$bFechar.Add_Click({ $script:form.Close() })

$Exec = @{ Runner = $null; Rodando = $false; Inicio = $null; Passo = 0; Total = 1; Relatorio = $null; Fim = $false; Plano = $null }
$timerExec = New-Object System.Windows.Forms.Timer; $timerExec.Interval = 200

function Atualiza-Barra {
    $ex = $script:Exec
    $pct = if ($ex.Fim) { 100 } else { [int](100 * [Math]::Max(0, $ex.Passo - 1) / [Math]::Max(1, $ex.Total)) }
    $dt = (Get-Date) - $ex.Inicio
    $script:lBarra.Text = "$(Barra $pct 30) $pct% · {0:00}:{1:00}" -f [int][Math]::Floor($dt.TotalMinutes), $dt.Seconds
}
function Linha-Log($t) {
    $r = $script:rtbLog
    $t = $t -replace "\x1b\[[0-9;]*m", ''
    if ($t -match '^##PASSO\|(\d+)\|(\d+)\|(.+)$') {
        $script:Exec.Passo = [int]$Matches[1]; $script:Exec.Total = [int]$Matches[2]
        $script:lPasso.Text = "> [$($Matches[1])/$($Matches[2])] $($Matches[3])"
        Escreve $r ("`n" + (Get-Date -Format 'HH:mm:ss') + ' ') $script:C.Mudo
        Escreve $r "[$($Matches[1])/$($Matches[2])] $($Matches[3])" $script:C.Acento -Linha
        return
    }
    if ($t -match '^##RELATORIO\|(.+)$') { $script:Exec.Relatorio = $Matches[1].Trim(); return }
    if ($t -eq '##FIM') { $script:Exec.Fim = $true; return }
    if ($t -match '^\s*=====') { return }                        # cabecalho de etapa (ja mostrado pelo ##PASSO)
    if ($t -match '^\*{5,}|^Transcri|^Windows PowerShell|^Start time|^End time|^Username|^RunAs|^Configuration|^Machine|^Host Application|^Process ID|^PSVersion|^PSEdition|^PSCompatible|^BuildVersion|^CLRVersion|^WSManStack|^PSRemoting|^SerializationVersion|^Hora de|^Nome de usu') { return }
    if (-not $t.Trim()) { return }
    $cor = $script:C.Texto
    if ($t -match '\[OK\]') { $cor = $script:C.Ok }
    elseif ($t -match '\[FALHA\]|ATENCAO|^!! ') { $cor = $script:C.Ruim }
    elseif ($t -match '\(aviso\)|\[vai baixar\]') { $cor = $script:C.Aviso }
    elseif ($t -match '\(levou ') { $cor = $script:C.Mudo }
    elseif ($t -match '^={10,}') { $cor = $script:C.Acento }
    Escreve $r ((Get-Date -Format 'HH:mm:ss') + ' ') $script:C.Mudo
    Escreve $r ($t.TrimEnd()) $cor -Linha
}
$timerExec.Add_Tick({
    $ex = $script:Exec
    if (-not $ex.Runner) { return }
    $linha = $null; $n = 0
    while ($n -lt 200 -and $ex.Runner.Fila.TryDequeue([ref]$linha)) { Linha-Log $linha; $n++ }
    if ($n) { $script:rtbLog.SelectionStart = $script:rtbLog.TextLength; $script:rtbLog.ScrollToCaret() }
    if ($ex.Rodando -and $ex.Runner.Terminou) {
        $ex.Runner.Esperar()
        while ($ex.Runner.Fila.TryDequeue([ref]$linha)) { Linha-Log $linha }
        $ex.Rodando = $false
        $cod = $ex.Runner.Proc.ExitCode
        if ($ex.Fim -or $cod -eq 0) {
            $ex.Fim = $true
            Escreve $script:rtbLog ("`n" + (Get-Date -Format 'HH:mm:ss') + ' ') $script:C.Mudo; Escreve $script:rtbLog (T 'concl') $script:C.Acento -Linha
            $script:lExec.Text = T 'concl'
        } else {
            Escreve $script:rtbLog ("`n" + ((T 'falhou') -f $cod)) $script:C.Ruim -Linha
            $script:lExec.Text = (T 'falhou') -f $cod; $script:lExec.ForeColor = $script:C.Ruim
        }
        $script:rtbLog.SelectionStart = $script:rtbLog.TextLength; $script:rtbLog.ScrollToCaret()
        $script:lPasso.Text = ''
        $script:bFechar.Enabled = $true
        $script:bAbreRel.Visible = [bool]$ex.Relatorio
        if ($ex.Plano) { Remove-Item $ex.Plano -Force -ErrorAction SilentlyContinue }   # o plano pode ter a senha do Wi-Fi
    }
    if ($ex.Inicio -and ($ex.Rodando -or $ex.Fim)) { Atualiza-Barra }
})

function Executa {
    Para-Contagem
    $modo = $script:ModoAtual
    $op = [ordered]@{}
    foreach ($o in $script:Opcoes) { $op[$o[0]] = $false }
    $inst = @(); $office = $false; $rem = @(); $wifi = @{ Ssid = ''; Senha = ''; Salvar = $false }
    if ($modo -ne 'relatorio') {
        foreach ($l in $script:LinhasOpc) { $op[$l.Chave] = [bool]$l.Marcado }
        foreach ($l in $script:LinhasInst) { if ($l.Marcado -and -not $l.Travado) { if ($l.Chave -eq 'OFFICE') { $office = $true } else { $inst += $l.Chave } } }
        foreach ($l in $script:LinhasRem) { if ($l.Marcado) { $rem += ($l.Chave -split '\|') } }
        if ($script:pWifi.Visible -and $script:cbRede.Text.Trim()) {
            $wifi = @{ Ssid = $script:cbRede.Text.Trim(); Senha = $script:txtSenha.Text; Salvar = $script:chkSalvar.Checked }
        }
    }
    $op['Energia'] = ($modo -eq 'pos')
    if ($modo -eq 'otimizar') { $op['Ponto'] = $true }
    $plano = [ordered]@{ Modo = $modo; Opcoes = $op; Instalar = $inst; Office = $office; Remover = $rem; Wifi = $wifi }
    $arq = Join-Path $script:Work 'plano.json'
    $plano | ConvertTo-Json -Depth 5 | Set-Content -Path $arq -Encoding UTF8

    $script:Exec.Plano = $arq; $script:Exec.Inicio = Get-Date; $script:Exec.Rodando = $true; $script:Exec.Fim = $false
    $script:Exec.Passo = 0; $script:Exec.Total = 1; $script:Exec.Relatorio = $null
    $script:lExec.Text = T 'execTit'; $script:lExec.ForeColor = $script:C.Acento
    $script:rtbLog.Clear(); $script:lPasso.Text = ''
    $script:bFechar.Enabled = $false; $script:bAbreRel.Visible = $false
    $script:form.Text = "pendrive-full / $modo"
    Mostra-Tela $script:telaExec
    Escreve $script:rtbLog ((Get-Date -Format 'HH:mm:ss') + ' ') $script:C.Mudo
    Escreve $script:rtbLog "> pos-formatacao.ps1 -Plano $modo" $script:C.Acento -Linha

    $runner = New-Object PFExecutor
    $runner.Iniciar("$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe", "-NoProfile -ExecutionPolicy Bypass -File `"$($script:Motor)`" -Plano `"$arq`"")
    $script:Exec.Runner = $runner
    $script:timerExec.Start()
}

function Abre-Modo($m) {
    if ($m -eq 'relatorio') { $script:ModoAtual = 'relatorio'; Executa }
    else { Monta-Config $m }
}

# ------------------------------------------------------------------
# Idioma
# ------------------------------------------------------------------
function Aplica-Idioma {
    foreach ($t in $script:Traduz) { try { $t.C.Text = T $t.K } catch {} }
    foreach ($r in $script:Linhas) { try { Desenha-Linha $r } catch {} }
    $script:bPT.ForeColor = $(if ($script:L -eq 'pt') { $script:C.Acento } else { $script:C.Mudo })
    $script:bEN.ForeColor = $(if ($script:L -eq 'en') { $script:C.Acento } else { $script:C.Mudo })
    $script:bPT.FlatAppearance.BorderColor = $(if ($script:L -eq 'pt') { $script:C.Acento } else { $script:C.Linha })
    $script:bEN.FlatAppearance.BorderColor = $(if ($script:L -eq 'en') { $script:C.Acento } else { $script:C.Linha })
    if (-not $script:timerConta.Enabled) { $script:bExec.Text = T 'executar' }
    if ($script:telaConfig.Visible) {
        $pos = ($script:ModoAtual -eq 'pos')
        $script:lModo.Text = $(if ($pos) { T 'm1' } else { T 'm2' })
        $script:lModoD.Text = '· ' + $(if ($pos) { T 'm1d' } else { T 'm2d' })
        if ($script:lHintRem) { $script:lHintRem.Text = $(if ($script:LinhasRem.Count) { (T 'hintRem') -f $script:LinhasRem.Count } else { T 'hintRem0' }) }
        Atualiza-Abas
    }
    Mostra-Saude
    try { @{ Idioma = $script:L } | ConvertTo-Json | Set-Content $script:prefArq -Encoding UTF8 } catch {}
}
$bPT.Add_Click({ $script:L = 'pt'; Aplica-Idioma })
$bEN.Add_Click({ $script:L = 'en'; Aplica-Idioma })

# Botoes da configuracao
$bVoltar.Add_Click({ Para-Contagem; $script:form.Text = 'pendrive-full'; Mostra-Tela $script:telaInicio })
$bExec.Add_Click({ Executa })

# Fechar durante a execucao
$form.Add_FormClosing({
    Log-P "fechando a janela (motivo: $($_.CloseReason))"
    if ($script:Exec.Rodando) {
        $r = [System.Windows.Forms.MessageBox]::Show((T 'sairQ'), 'pendrive-full', 'YesNo', 'Warning')
        if ($r -ne 'Yes') { $_.Cancel = $true }
    }
})

# Ao abrir: barra de titulo escura, le a saude e vai para o modo pedido
$form.Add_Shown({
    Log-P 'janela exibida'
    # Garante que a janela aparece na frente (mesmo se o processo foi aberto escondido)
    try { [PFNativo]::TituloEscuro($script:form.Handle); [PFNativo]::Mostrar($script:form.Handle) } catch {}
    $script:form.TopMost = $true; $script:form.Activate(); $script:form.TopMost = $false
    try {
        Aplica-Idioma
        $script:form.Refresh()
        $script:Saude = Le-Saude
        Log-P "saude lida: $(($script:Saude.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join '; ')"
        Mostra-Saude
        switch ($script:Modo) {
            'pos'       { Monta-Config 'pos' }
            'otimizar'  { Monta-Config 'otimizar' }
            'relatorio' { Abre-Modo 'relatorio' }
        }
        if ($script:Auto -and $script:Modo -eq 'pos') {
            $script:Contagem.Resta = $(if ($script:Cfg.PerguntarProgramas) { 60 } else { 5 })
            $script:bExec.Text = (T 'conta') -f $script:Contagem.Resta
            $script:timerConta.Start()
        }
        Log-P 'pronto para uso'
    } catch {
        Log-P "ERRO ao abrir: $($_.Exception.Message) @ linha $($_.InvocationInfo.ScriptLineNumber)"
        [void][System.Windows.Forms.MessageBox]::Show("Erro ao preparar o painel:`n$($_.Exception.Message)`n`nDetalhes em $($script:LogP)", 'pendrive-full')
    }
})

Mostra-Tela $telaInicio
$form.WindowState = 'Normal'
Log-P 'abrindo a janela'
$res = $form.ShowDialog()
Log-P "janela fechada ($res)"
$timerExec.Stop(); $timerConta.Stop()
$form.Dispose()
}
catch {
    Usa-ModoAntigo ($_.Exception.Message + ' @ linha ' + $_.InvocationInfo.ScriptLineNumber)
}
