---
name: flutter-troubleshooting
description: >-
  Use this skill when encountering Flutter compilation errors, dependency conflicts with record/record_linux, permission errors, or Android build failures.
---

# Flutter Troubleshooting Guide

## 1. Error: `RecordLinux is missing implementations for ... startStream`

### Root Cause
`record: ^5.1.2` resolves `record_linux: 0.7.2` which lacks `startStream` introduced by `record_platform_interface: 1.6.0`. Newer `record_linux: >=2.0.0` requires Dart `>=3.12.0`, which is incompatible with Dart `3.11.5`.

### Resolution
Ensure `pubspec.yaml` contains:
```yaml
dependency_overrides:
  record_linux: ^1.3.1
```
Then run:
```bash
flutter pub get
```

## 2. Error: Microphone permission denied or crashed on scan

### Check Android Permissions
Ensure `android/app/src/main/AndroidManifest.xml` includes:
```xml
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.INTERNET"/>
```

### Check Runtime Permission Prompt
Make sure `AudioRecorderService.hasPermission()` is awaited before calling `startRecording()`.

## 3. Analyzer Warnings: `withOpacity is deprecated`
- These are `info` level notices in Flutter 3.19+ recommending `.withValues(alpha: ...)`.
- They do NOT fail builds unless `--fatal-infos` is set.
- To run analyzer cleanly without fatal info exit codes:
  ```bash
  flutter analyze --no-fatal-infos
  ```

## 4. Resetting State and Cleaning Cache
If dependencies get corrupted or locked:
```bash
flutter clean
flutter pub get
```
