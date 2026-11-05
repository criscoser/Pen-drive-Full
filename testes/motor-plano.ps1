# Teste: roda o trecho real do pos-formatacao.ps1 (config -> plano -> catalogo -> passos) com um plano do painel.
# Uso (pwsh 7): pwsh -File testes/motor-plano.ps1 -Motor pendrive/PosFormatacao/pos-formatacao.ps1 -ModoPlano otimizar
# Pegou o defeito de 05/11/2026: $p (programas) sobrescrevia $P (plano), porque o PowerShell ignora maiusculas.
param($Motor, $ModoPlano)
$ErrorActionPreference = 'Continue'
$src = Get-Content $Motor -Raw
# Trecho REAL do motor, na ordem real: configuracao, carregamento do plano, catalogo, escolhas, lista de passos
$cfgIni = $src.IndexOf("`$WifiNome      = '")
$cfgFim = $src.IndexOf('$cfgArq = ')
$ini = $src.IndexOf('# Plano vindo do painel')
$fim = $src.IndexOf('# ---------------- 1. PONTO DE RESTAURACAO E ENERGIA')
$trecho = $src.Substring($cfgIni, $cfgFim - $cfgIni) + "`n" + $src.Substring($ini, $fim - $ini) + "`n}`n"
$trecho = $trecho -replace '(?m)^Start-Transcript.*$', ''
$trecho = $trecho.Replace("`$Work = 'C:\PosFormatacao'", "`$Work = '$PWD/work'")
function Tem-Internet { $true }
$dadosPlano = [ordered]@{ Modo=$ModoPlano; Opcoes=[ordered]@{Ponto=($ModoPlano -eq 'otimizar');Privacidade=$true;Propagandas=$true;Visual=$true;Temporarios=$true;InicioRapido=$false;Aparencia=$false;Chrome=$false;Drivers=$false;WindowsUpdate=$false;Renomear=$false;Energia=($ModoPlano -eq 'pos')}; Instalar=@(); Office=$false; Remover=@(); Wifi=@{Ssid='';Senha='';Salvar=$false} }
$arqPlano = "$PWD/plano.json"; $dadosPlano | ConvertTo-Json -Depth 5 | Set-Content $arqPlano -Encoding UTF8
$Plano = $arqPlano; $SoRelatorio = $false; $SoOtimizar = $false
. ([scriptblock]::Create($trecho)) 6>$null 3>$null | Out-Null
"modo=$ModoPlano  plano ainda e o plano? $($null -ne $PlanoPF.Opcoes)"
"Quer: " + ((@('Ponto','Energia','Privacidade','Propagandas','Visual','Temporarios','Chrome','Drivers','Renomear') | Where-Object { Quer $_ }) -join ',')
"Programas a instalar: " + ($Programas -join ',')
"Passos: " + ($Passos -join ' > ')
