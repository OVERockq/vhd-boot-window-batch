@echo off
title Create Bootable VHD (UEFI / BIOS Auto)
color 1f
setlocal enabledelayedexpansion

:: =====================================================
::  VHD 부팅 자동화 스크립트 (INI 설정 기반)
::  작성자: AiKKCU / ChatGPT5
:: =====================================================

set "CONFIG_FILE=config.ini"
if not exist "%CONFIG_FILE%" (
  echo [ERROR] 설정 파일(config.ini)이 없습니다.
  echo 예시:
  echo.
  echo [Settings]
  echo VHD_SOURCE=E:\VHD\BASE.vhdx
  echo VHD_DEST_DIR=C:\VHD
  echo TARGET_DISK=0
  pause
  exit /b
)

:: -------------------------------------------------------
:: 설정값 읽기
:: -------------------------------------------------------
for /f "tokens=1,2 delims== " %%A in ('findstr /i "=" "%CONFIG_FILE%"') do (
  if /i "%%A"=="VHD_SOURCE" set "SRC_VHD=%%B"
  if /i "%%A"=="VHD_DEST_DIR" set "DST_VHD_DIR=%%B"
  if /i "%%A"=="TARGET_DISK" set "DISK_NUM=%%B"
)

set "DST_VHD=%DST_VHD_DIR%\BASE.vhdx"

echo =====================================================
echo   BIOS / UEFI 자동 감지형 VHD 부팅 구성
echo =====================================================
echo [INFO] 설정 파일: %CONFIG_FILE%
echo [INFO] 원본 VHD : %SRC_VHD%
echo [INFO] 대상 경로: %DST_VHD%
echo [INFO] 초기화 디스크: Disk %DISK_NUM%
echo =====================================================
echo.

:: -------------------------------------------------------
:: 삭제 경고
:: -------------------------------------------------------
echo ⚠️  주의! Disk %DISK_NUM% 의 모든 데이터가 삭제됩니다!
echo.
set /p CONFIRM="계속하려면 YES 를 입력하고 Enter 키를 누르세요: "
if /I not "%CONFIRM%"=="YES" (
  echo [중단됨] 사용자가 Disk %DISK_NUM% 삭제를 취소했습니다.
  pause
  exit /b
)
echo [확인] Disk %DISK_NUM% 초기화를 시작합니다...
echo.

:: -------------------------------------------------------
:: 1. Disk 초기화 및 파티션 구성
:: -------------------------------------------------------
echo [STEP 1] Disk %DISK_NUM% 파티션 생성 중...
set "DP_SCRIPT=%TEMP%\create_disk%DISK_NUM%.txt"
> "%DP_SCRIPT%" (
  echo select disk %DISK_NUM%
  echo clean
  echo convert gpt
  echo create partition efi size=100
  echo format fs=fat32 quick label="System"
  echo assign letter=S
  echo create partition primary
  echo format fs=ntfs quick label="Windows"
  echo assign letter=C
  echo exit
)
diskpart /s "%DP_SCRIPT%" >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Disk 초기화 실패. 디스크 확인 필요.
  pause
  exit /b
)
echo [OK] Disk %DISK_NUM% 초기화 완료.
echo.

:: -------------------------------------------------------
:: 2. VHD 복사 (진행률 표시)
:: -------------------------------------------------------
echo [STEP 2] VHD 복사 중...

if not exist "%SRC_VHD%" (
  echo [ERROR] 원본 VHD 파일이 없습니다: %SRC_VHD%
  pause
  exit /b
)
if not exist "%DST_VHD_DIR%" mkdir "%DST_VHD_DIR%" >nul 2>&1

for %%I in ("%SRC_VHD%") do set "SRC_SIZE=%%~zI"
echo 원본 파일 크기: !SRC_SIZE! bytes
echo.

set "DEST_FILE=%DST_VHD%"
del "%DEST_FILE%" >nul 2>&1

start /b cmd /c "xcopy "%SRC_VHD%" "%DST_VHD%" /H /R /Y >nul"
:WAITCOPY
timeout /t 1 >nul
if exist "%DEST_FILE%" (
    for %%A in ("%DEST_FILE%") do set "DST_SIZE=%%~zA"
    set /a PROG=(!DST_SIZE!*100)/!SRC_SIZE!
    if !PROG! lss 100 (
        <nul set /p="진행률: !PROG!%% 완료`r"
        goto WAITCOPY
    )
)
echo.
echo [OK] VHD 복사 완료.
echo.

:: -------------------------------------------------------
:: 3. VHD Attach → V: 할당
:: -------------------------------------------------------
echo [STEP 3] VHD 마운트 중...
set "DP_ATTACH=%TEMP%\attach_vhd.txt"
> "%DP_ATTACH%" (
  echo select vdisk file="%DST_VHD%"
  echo attach vdisk readonly
  echo select partition 1
  echo assign letter=V
)
diskpart /s "%DP_ATTACH%" >nul 2>&1
if errorlevel 1 (
  echo [ERROR] VHD 마운트 실패.
  pause
  exit /b
)
if not exist V:\Windows\System32 (
  echo [ERROR] VHD 내 Windows 폴더를 찾을 수 없습니다.
  goto CLEAN
)
echo [OK] VHD 마운트 성공.
echo.

:: -------------------------------------------------------
:: 4. 부팅 모드 감지
:: -------------------------------------------------------
echo [STEP 4] 부팅 모드 감지 중...
set "BOOTMODE=UEFI"
reg query HKLM\System\CurrentControlSet\Control /v PEFirmwareType | find "0x1" >nul 2>&1 && set "BOOTMODE=BIOS"
echo [INFO] 현재 부팅 모드: %BOOTMODE%
echo.

:: -------------------------------------------------------
:: 5. bcdboot 구성
:: -------------------------------------------------------
echo [STEP 5] bcdboot 실행 중...
if /I "%BOOTMODE%"=="UEFI" (
  bcdboot V:\Windows /s S: /f UEFI /l ko-kr /addlast >nul 2>&1
) else (
  bcdboot V:\Windows /s C: /f BIOS /l ko-kr /addlast >nul 2>&1
)
if errorlevel 1 (
  echo [ERROR] bcdboot 구성 실패.
  goto CLEAN
)
echo [OK] bcdboot 구성 완료.
echo.

:: -------------------------------------------------------
:: 6. 정리 (VHD Detach)
:: -------------------------------------------------------
:CLEAN
echo [STEP 6] VHD 해제 중...
set "DP_DET=%TEMP%\detach_vhd.txt"
> "%DP_DET%" (
  echo select vdisk file="%DST_VHD%"
  echo detach vdisk
)
diskpart /s "%DP_DET%" >nul 2>&1

echo.
echo =====================================================
echo ✅ 모든 과정 완료!
echo =====================================================
echo - 복사된 VHD: %DST_VHD%
echo - 초기화 대상: Disk %DISK_NUM%
echo - 부팅 모드: %BOOTMODE%
echo =====================================================
echo.
pause
exit /b
