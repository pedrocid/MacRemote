#!/bin/bash
set -u
cd "$(dirname "$0")"
allowed_root=/Users/pr/github/MacRemote
status=0
while IFS= read -r -d '' file; do
    if [ ! -L "$file" ]; then
        printf 'Not a symlink: %s\n' "$file" >&2
        status=1
        continue
    fi
    resolved=$(realpath "$file") || {
        printf 'Broken symlink: %s\n' "$file" >&2
        status=1
        continue
    }
    case "$resolved" in
        "$allowed_root"/Shared/*|"$allowed_root"/MacRemoteServer/Sources/*|"$allowed_root"/MacRemoteClient/Sources/*) ;;
        *) printf 'Symlink resolves outside allowed production sources: %s -> %s\n' "$file" "$resolved" >&2; status=1 ;;
    esac
done < <(find Sources \( -type f -o -type l \) -name '*.swift' -print0)
exit "$status"
