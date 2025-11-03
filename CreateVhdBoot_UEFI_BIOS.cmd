@echo off
title Create Bootable VHD (UEFI / BIOS Auto - PE Ultra Safe)
color 1f
setlocal enabledelayedexpansion

:: -------------------------------------------------------
:: 설정 (config.ini 내용 내장)
:: -------------------------------------------------------
set "SRC_VHD=E:\VHD\BASE.vhdx"
set "DST_VHD_DIR=C:\VHD"
set "DISK_NUM=0"

:: 환경 변수 오버라이드
if defined ENV_SRC_VHD set "SRC_VHD=%ENV_SRC_VHD%"
if defined ENV_DST_VHD_DIR set "DST_VHD_DIR=%ENV_DST_VHD_DIR%"
if defined ENV_DISK_NUM set "DISK_NUM=%ENV_DISK_NUM%"

:: 사용자 입력 유도
if "%SRC_VHD%"=="" set /p SRC_VHD="원본 VHD 경로 입력 (예: E:\VHD\BASE.vhdx): "
if "%DST_VHD_DIR%"=="" set /p DST_VHD_DIR="대상 VHD 디렉터리 입력 (예: C:\VHD): "
if "%DISK_NUM%"=="" set /p DISK_NUM="초기화할 디스크 번호 (예: 0): "

set "DST_VHD=%DST_VHD_DIR%\BASE.vhdx"

echo =====================================================
echo   BIOS / UEFI 자동 감지형 VHD 부팅 구성
echo =====================================================
echo [INFO] 원본 VHD : %SRC_VHD%
echo [INFO] 대상 경로: %DST_VHD%
echo [INFO] 초기화 디스크: Disk %DISK_NUM%
echo =====================================================
echo.

:: -------------------------------------------------------
:: 삭제 경고
:: -------------------------------------------------------
echo [주의] Disk %DISK_NUM% 의 모든 데이터가 삭제됩니다!
echo.
set /p CONFIRM="계속하려면 YES 입력 후 Enter: "
if /I not "%CONFIRM%"=="YES" (
  echo [중단됨] 사용자가 취소했습니다.
  pause
  exit /b
)

:: -------------------------------------------------------
:: 부팅 모드 감지
:: -------------------------------------------------------
set "BOOTMODE=UEFI"
reg query "HKLM\SYSTEM\CurrentControlSet\Control" /v PEFirmwareType >nul 2>&1
if not errorlevel 1 (
  for /f "tokens=3" %%V in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control" /v PEFirmwareType 2^>nul') do (
    if /I "%%V"=="0x1" set "BOOTMODE=BIOS"
  )
)
echo [INFO] 현재 부팅 모드: %BOOTMODE%
echo.

:: -------------------------------------------------------
:: 1. Disk 초기화 및 파티션 구성
:: -------------------------------------------------------
echo [STEP 1] Disk %DISK_NUM% 초기화 및 파티션 구성 중...
set "DP_SCRIPT=%TEMP%\create_disk_%DISK_NUM%.txt"

if /I "%BOOTMODE%"=="UEFI" (
  > "%DP_SCRIPT%" (
    echo select disk %DISK_NUM%
    echo clean
    echo convert gpt
    echo create partition efi size=100
    echo format fs=fat32 quick label=System
    echo assign letter=S
    echo create partition primary
    echo format fs=ntfs quick label=Windows
    echo assign letter=C
    echo exit
  )
) else (
  > "%DP_SCRIPT%" (
    echo select disk %DISK_NUM%
    echo clean
    echo convert mbr
    echo create partition primary size=100
    echo format fs=ntfs quick label=System
    echo assign letter=S
    echo active
    echo create partition primary
    echo format fs=ntfs quick label=Windows
    echo assign letter=C
    echo exit
  )
)

diskpart /s "%DP_SCRIPT%" > "%TEMP%\diskpart_create_%DISK_NUM%.log" 2>&1
if errorlevel 1 (
  echo [ERROR] Disk 초기화 실패. 로그: %TEMP%\diskpart_create_%DISK_NUM%.log
  del "%DP_SCRIPT%" >nul 2>&1
  pause
  exit /b
)
del "%DP_SCRIPT%" >nul 2>&1
echo [OK] Disk 초기화 완료.
echo.

:: -------------------------------------------------------
:: 2. VHD 복사
:: -------------------------------------------------------
echo [STEP 2] VHD 복사 중...
if not exist "%SRC_VHD%" (
  echo [ERROR] 원본 VHD 파일이 없습니다: %SRC_VHD%
  pause
  exit /b
)
if not exist "%DST_VHD_DIR%" mkdir "%DST_VHD_DIR%" >nul 2>&1

for %%F in ("%SRC_VHD%") do (
  set "SRC_DIR=%%~dpF"
  set "SRC_NAME=%%~nxF"
)

echo [INFO] 복사: !SRC_NAME! -> %DST_VHD_DIR%
robocopy "!SRC_DIR!" "%DST_VHD_DIR%" "!SRC_NAME!" /ETA /R:1 /W:1
set "RC=%ERRORLEVEL%"
if %RC% GEQ 8 (
  echo [ERROR] VHD 복사 실패. 코드: %RC%
  pause
  exit /b
)
echo [OK] 복사 완료.
echo.

:: -------------------------------------------------------
:: 3. VHD Attach → S: (EFI) + V: (Windows) 자동 마운트
:: -------------------------------------------------------
echo [STEP 3] VHD 마운트 중...
set "DP_ATTACH=%TEMP%\attach_vhd_%RANDOM%.txt"
> "%DP_ATTACH%" (
  echo select vdisk file="%DST_VHD%"
  echo attach vdisk
  echo list partition
  echo select partition 1
  echo assign letter=S
  echo select partition 2
  echo assign letter=V
)
diskpart /s "%DP_ATTACH%" > "%TEMP%\diskpart_attach.log" 2>&1
if errorlevel 1 (
  echo [경고] 기본 2파티션 마운트 실패 → 단일 파티션 시도...
  > "%DP_ATTACH%" (
    echo select vdisk file="%DST_VHD%"
    echo attach vdisk
    echo select partition 1
    echo assign letter=V
  )
  diskpart /s "%DP_ATTACH%" >> "%TEMP%\diskpart_attach.log" 2>&1
)
del "%DP_ATTACH%" >nul 2>&1

if not exist "V:\Windows\System32" (
  echo [ERROR] Windows 폴더를 찾을 수 없습니다.
  goto CLEAN
)
echo [OK] VHD 마운트 성공.
echo.

:: -------------------------------------------------------
:: 4. bcdboot 구성
:: -------------------------------------------------------
echo [STEP 4] bcdboot 실행 중...
if /I "%BOOTMODE%"=="UEFI" (
  bcdboot V:\Windows /s S: /f UEFI /l ko-kr /addlast > "%TEMP%\bcdboot.log" 2>&1
) else (
  bcdboot V:\Windows /s S: /f BIOS /l ko-kr /addlast > "%TEMP%\bcdboot.log" 2>&1
)
if errorlevel 1 (
  echo [ERROR] bcdboot 구성 실패. 로그: %TEMP%\bcdboot.log
  goto CLEAN
)
echo [OK] bcdboot 구성 완료.
echo.

:: -------------------------------------------------------
:: 5. 정리
:: -------------------------------------------------------
:CLEAN
echo [STEP 5] 정리 중...
set "DP_DET=%TEMP%\detach_vhd_%RANDOM%.txt"
> "%DP_DET%" (
  echo select vdisk file="%DST_VHD%"
  echo detach vdisk
)
diskpart /s "%DP_DET%" > "%TEMP%\diskpart_detach.log" 2>&1
del "%DP_DET%" >nul 2>&1

rem del "%TEMP%\diskpart_create_%DISK_NUM%.log" >nul 2>&1
rem del "%TEMP%\diskpart_attach.log" >nul 2>&1
rem del "%TEMP%\bcdboot.log" >nul 2>&1
rem del "%TEMP%\diskpart_detach.log" >nul 2>&1

echo.
echo =====================================================
echo [완료] 모든 과정이 정상적으로 완료되었습니다!
echo =====================================================
echo - 복사된 VHD : %DST_VHD%
echo - 초기화 대상 : Disk %DISK_NUM%
echo - 부팅 모드 : %BOOTMODE%
echo =====================================================
pause
exit /b
