@echo off
title Coletor de Inventario - Clinica
echo Lendo hardware e enviando para o servidor...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0collector.ps1"
echo.
pause