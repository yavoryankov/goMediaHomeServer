@echo off
cd /d "%~dp0"
py -3 -m pip install --user -r requirements.txt
if errorlevel 1 python -m pip install --user -r requirements.txt
py -3 bridge.py
if errorlevel 1 python bridge.py
