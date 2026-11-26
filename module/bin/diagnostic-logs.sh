rotate_diagnostic_log() (
    log_file="$1"
    rotation_time="${2:-$(date +%s)}"
    case "$rotation_time" in ''|*[!0-9]*) exit 1;; esac
    [ "$rotation_time" -gt 0 ] || exit 1
    rotation_day=$((rotation_time / 86400))
    previous_day="$(cat "$log_file.day" 2>/dev/null || :)"
    case "$previous_day" in ''|*[!0-9]*) previous_day=0;; esac
    [ "$rotation_day" -gt "$previous_day" ] || exit 0
    if [ "$previous_day" -gt 0 ] && [ -s "$log_file" ]; then
        [ ! -e "$log_file.$rotation_time" ] || exit 1
        mv "$log_file" "$log_file.$rotation_time" || exit 1
    fi
    cutoff=$((rotation_time - 172800))
    for archive in "$log_file".[0-9]*; do
        [ -f "$archive" ] || continue
        archive_time="${archive##*.}"
        case "$archive_time" in *[!0-9]*) continue;; esac
        [ "$archive_time" -le "$cutoff" ] || continue
        modified="$(stat -c %Y "$archive" 2>/dev/null || :)"
        case "$modified" in ''|*[!0-9]*) continue;; esac
        [ "$modified" -gt "$cutoff" ] || rm -f "$archive"
    done
    printf '%s\n' "$rotation_day" > "$log_file.day.tmp" && mv -f "$log_file.day.tmp" "$log_file.day"
)

read_diagnostic_log() (
    for archive in "$1".[0-9]* "$1"; do
        [ ! -f "$archive" ] || cat "$archive"
    done
    exit 0
)
