@echo off
title Create Bootable VHD (UEFI + BIOS Dual Support - PE Ultra Safe)
color 1f
setlocal enabledelayedexpansion

:: -------------------------------------------------------
:: 설정
:: -------------------------------------------------------
set "SRC_VHD=E:\VHD\BASE.vhdx"
set "DST_VHD_DIR=C:\VHD"
set "DISK_NUM=0"

if defined ENV_SRC_VHD set "SRC_VHD=%ENV_SRC_VHD%"
if defined ENV_DST_VHD_DIR set "DST_VHD_DIR=%ENV_DST_VHD_DIR%"
if defined ENV_DISK_NUM set "DISK_NUM=%ENV_DISK_NUM%"

if "%SRC_VHD%"=="" set /p SRC_VHD="원본 VHD 경로 입력 (예: E:\VHD\BASE.vhdx): "
if "%DST_VHD_DIR%"=="" set /p DST_VHD_DIR="대상 VHD 디렉터리 입력 (예: C:\VHD): "
if "%DISK_NUM%"=="" set /p DISK_NUM="초기화할 디스크 번호 입력 (예: 0): "

set "DST_VHD=%DST_VHD_DIR%\BASE.vhdx"

echo =====================================================
echo   BIOS + UEFI 듀얼 부팅 지원 VHD 구성
echo =====================================================
echo [INFO] 원본 VHD : %SRC_VHD%
echo [INFO] 대상 경로: %DST_VHD%
echo [INFO] 초기화 디스크: Disk %DISK_NUM%
echo =====================================================
echo.

:: -------------------------------------------------------
:: 경고 및 확인
:: -------------------------------------------------------
echo [주의] Disk %DISK_NUM% 의 모든 데이터가 삭제됩니다!
echo.
set /p CONFIRM="계속하려면 YES 입력 후 Enter: "
if /I not "%CONFIRM%"=="YES" (
  echo [중단됨] 사용자가 취소했습니다.
  pause
  exit /b
)
echo [확인] Disk 초기화를 시작합니다...
echo.

:: -------------------------------------------------------
:: 1. Disk 초기화 (GPT + BIOS/UEFI 혼용 구조)
:: -------------------------------------------------------
echo [STEP 1] Disk 파티션 생성 (GPT, UEFI+BIOS 지원)...
set "DP_SCRIPT=%TEMP%\create_disk_%DISK_NUM%.txt"
> "%DP_SCRIPT%" (
  echo select disk %DISK_NUM%
  echo clean
  echo convert gpt
  echo create partition efi size=100
  echo format fs=fat32 quick label=EFI
  echo assign letter=S
  echo create partition msr size=16
  echo create partition primary size=100
  echo format fs=ntfs quick label=System
  echo assign letter=B
  echo create partition primary
  echo format fs=ntfs quick label=Windows
  echo assign letter=C
  echo exit
)
diskpart /s "%DP_SCRIPT%" > "%TEMP%\diskpart_create.log" 2>&1
if errorlevel 1 (
  echo [ERROR] Disk 초기화 실패. 로그: %TEMP%\diskpart_create.log
  pause
  exit /b
)
del "%DP_SCRIPT%" >nul 2>&1
echo [OK] Disk 초기화 완료.
echo.

:: -------------------------------------------------------
:: 2. VHD 복사 (별도 콘솔 창에서 진행)
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

set "RC_SCRIPT=%TEMP%\run_robocopy_%RANDOM%.cmd"
(
  echo @echo off
  echo title VHD 복사 중 - robocopy
  echo color 0A
  echo echo [INFO] 복사 시작: %%date%% %%time%%
  echo robocopy "%SRC_DIR%" "%DST_VHD_DIR%" "%SRC_NAME%" /ETA /R:1 /W:1 /NFL /NDL /TEE /LOG+:"%TEMP%\robocopy.log"
  echo echo [INFO] 복사 완료. 창이 자동으로 닫힙니다.
  echo timeout /t 2 ^>nul
) > "%RC_SCRIPT%"

start "VHD_COPY_WINDOW" cmd /c "%RC_SCRIPT%"
echo [INFO] 복사 진행 중입니다. 창이 닫히면 다음 단계로 이동합니다.
:WAIT_COPY
timeout /t 2 >nul
tasklist /FI "WINDOWTITLE eq VHD 복사 중 - robocopy" | find "cmd.exe" >nul
if %errorlevel%==0 goto WAIT_COPY
del "%RC_SCRIPT%" >nul 2>&1
echo [OK] VHD 복사 완료.
echo.

:: -------------------------------------------------------
:: 3. VHD Attach → V: 할당
:: -------------------------------------------------------
echo [STEP 3] VHD 마운트 중...
set "DP_ATTACH=%TEMP%\attach_vhd_%RANDOM%.txt"
> "%DP_ATTACH%" (
  echo select vdisk file="%DST_VHD%"
  echo attach vdisk readonly
  echo select partition 1
  echo assign letter=V
)
diskpart /s "%DP_ATTACH%" > "%TEMP%\diskpart_attach.log" 2>&1
if errorlevel 1 (
  echo [ERROR] VHD 마운트 실패.
  goto CLEAN
)
del "%DP_ATTACH%" >nul 2>&1
if not exist "V:\Windows\System32" (
  echo [ERROR] VHD 내 Windows\System32 폴더 없음.
  goto CLEAN
)
echo [OK] VHD 마운트 성공.
echo.

:: -------------------------------------------------------
:: 4. BCDBOOT 듀얼 부팅 구성 (UEFI + BIOS 둘 다)
:: -------------------------------------------------------
echo [STEP 4] bcdboot 듀얼 구성 중...
bcdboot V:\Windows /s S: /f UEFI /l ko-kr /addlast > "%TEMP%\bcdboot_uefi.log" 2>&1
bcdboot V:\Windows /s B: /f BIOS /l ko-kr /addlast > "%TEMP%\bcdboot_bios.log" 2>&1

if errorlevel 1 (
  echo [ERROR] bcdboot 구성 중 오류 발생.
  goto CLEAN
)
echo [OK] BIOS/UEFI 부팅 파일 구성 완료.
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
diskpart /s "%DP_DET%" >nul 2>&1
del "%DP_DET%" >nul 2>&1

echo.
echo =====================================================
echo [완료] 모든 과정 완료!
echo =====================================================
echo - 복사된 VHD : %DST_VHD%
echo - 초기화 디스크 : Disk %DISK_NUM%
echo - 부팅 지원 : BIOS + UEFI 모두
echo =====================================================
pause
exit /b
