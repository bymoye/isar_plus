#!/bin/bash

if [ -z "$ISAR_VERSION" ]; then
    echo "ISAR_VERSION is not set";
    exit 2;
fi

github="https://github.com/ahmtydn/isar_plus/releases/download/$ISAR_VERSION"


curl "${github}/libisar_plus_android_arm64.so" -o packages/isar_plus_flutter_libs/android/src/main/jniLibs/arm64-v8a/libisar_plus.so --create-dirs -L -f
curl "${github}/libisar_plus_android_armv7.so" -o packages/isar_plus_flutter_libs/android/src/main/jniLibs/armeabi-v7a/libisar_plus.so --create-dirs -L -f
curl "${github}/libisar_plus_android_x64.so" -o packages/isar_plus_flutter_libs/android/src/main/jniLibs/x86_64/libisar_plus.so --create-dirs -L


curl "${github}/libisar_plus_linux_x64.so" -o packages/isar_plus_flutter_libs/linux/libisar_plus.so --create-dirs -L -f
curl "${github}/isar_plus_windows_x64.dll" -o packages/isar_plus_flutter_libs/windows/isar_plus.dll --create-dirs -L -f

curl "${github}/isar_plus.wasm" -o isar_plus.wasm -L -f
curl "${github}/isar_plus.js" -o isar_plus.js -L -f