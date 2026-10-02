#!/bin/bash
set -u
cd "$(dirname "$0")"
export CLANG_MODULE_CACHE_PATH=/tmp/macremote-modcache
if xcode-select -p | grep -q 'Xcode.app'; then
    swift test --disable-sandbox
else
    F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
    swift test --disable-sandbox -Xswiftc -F"$F" -Xlinker -F"$F" -Xlinker -rpath -Xlinker "$F"
fi
exit $?
