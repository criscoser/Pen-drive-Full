@echo off
title RELATORIO DA MAQUINA
echo Gerando o relatorio desta maquina... aceite a permissao de administrador (Sim).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0PosFormatacao\pos-formatacao.ps1" -SoRelatorio
