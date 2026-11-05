@echo off
title PAINEL - Pendrive Full
echo Abrindo o painel... aceite a permissao de administrador (Sim).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0PosFormatacao\pos-formatacao.ps1" -Painel
