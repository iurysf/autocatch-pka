@echo off
title Instalador AutoCatch PokeAlliance
color 0A

echo =======================================================
echo    INSTALADOR DO AUTOCATCH PKA
echo =======================================================
echo.

where python >nul 2>nul
if %errorlevel% neq 0 (
    color 0C
    echo [ERRO] Python nao foi encontrado instalado no sistema!
    echo Por favor, instale o Python em python.org marcando a opcao "Add Python to PATH".
    echo.
    pause
    exit /b 1
)

python "%~dp0patch_notebook.py"

echo.
pause
