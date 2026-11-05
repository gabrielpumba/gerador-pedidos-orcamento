@echo off
title Instalador - Okada Pedidos

echo =============================================================
echo               INSTALACAO DO OKADA PEDIDOS
echo =============================================================
echo.
echo  Configurando o atalho na Area de Trabalho com o icone...
echo.

start "" wscript.exe "%~dp0instalar.vbs"
exit
