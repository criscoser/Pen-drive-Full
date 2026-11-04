@echo off
title POS-FORMATACAO
echo Iniciando a pos-formatacao... aceite a permissao de administrador (Sim).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0PosFormatacao\pos-formatacao.ps1"
