#!/usr/bin/env bash

shopt -s extglob

DIRECTORY=~/photos
DB_FILE="$DIRECTORY/.downloaded_photos.db"
CLEANUP_MIN_FREE_PERCENT=20
CLEANUP_OLDER_THAN_MINUTES=1440

if command -v gphoto2 > /dev/null 2>&1; then
    echo "gphoto2 detected"
else
    echo "gphoto2 missing"
    exit 1
fi

if [ ! -d "$DIRECTORY" ]; then
    echo "Creating photos folder at $DIRECTORY"
    mkdir -p "$DIRECTORY"
fi

cd "$DIRECTORY" || exit 1

# Initialize the database file if it doesn't exist
if [ ! -f "$DB_FILE" ]; then
    echo "Creating download tracking database at $DB_FILE"
    touch "$DB_FILE"
fi

# --- gphoto2 output hygiene -------------------------------------------------
# gphoto2 wraps every failure in a dozen lines of boilerplate telling you to
# re-run with --debug. Park its stderr in a scratch file and report only the
# "*** Error ... ***" summary. Emptying the card while a download is in flight
# produces one identical failure per remaining file, so a run of the same error
# collapses to one line plus a count once it passes GPHOTO_ERR_QUIET_AFTER.
GPHOTO_ERR_FILE=$(mktemp)
GPHOTO_ERR_QUIET_AFTER=3
gphoto_last_err=""
gphoto_err_count=0

trap 'rm -f "$GPHOTO_ERR_FILE"' EXIT
# These need an explicit exit. A handler that only cleans up leaves the `while :`
# loop running, which makes the script immune to `kill` and lets a restart end
# up with two copies racing over the camera and the database.
trap 'exit 130' INT
trap 'exit 143' TERM

# Emit the tally for a run of suppressed errors. Called once things recover, so
# a flood is always accounted for even though it was not printed line by line.
flush_gphoto_errors() {
    if [ "$gphoto_err_count" -gt "$GPHOTO_ERR_QUIET_AFTER" ]; then
        echo "gphoto2: previous error repeated $gphoto_err_count times"
    fi
    gphoto_last_err=""
    gphoto_err_count=0
    : > "$GPHOTO_ERR_FILE"
}

# Condense whatever gphoto2 last wrote to stderr into a single line, or nothing
# if it did not complain. Must run in the parent shell rather than inside $(),
# otherwise the repeat counter is lost with the subshell.
report_gphoto_error() {
    local line err

    line=$(grep -m1 -F '*** Error' "$GPHOTO_ERR_FILE" 2>/dev/null)
    : > "$GPHOTO_ERR_FILE"
    [ -z "$line" ] && return

    case "$line" in
        # "*** Error (-108: 'File not found') ***" -> "-108: 'File not found'"
        *'('*')'*) err=$(printf '%s' "$line" | sed -E 's/.*\(([^)]*)\).*/\1/') ;;
        # "*** Error: No camera found. ***"        -> "No camera found."
        *)         err=$(printf '%s' "$line" | sed -E 's/^\*\*\* Error:? ?//; s/\*\*\*.*$//; s/[[:space:]]+$//') ;;
    esac
    [ -z "$err" ] && err="unspecified error"

    if [ "$err" = "$gphoto_last_err" ]; then
        gphoto_err_count=$((gphoto_err_count + 1))
        if [ "$gphoto_err_count" -eq "$GPHOTO_ERR_QUIET_AFTER" ]; then
            echo "gphoto2: $err (repeating; further identical errors suppressed)"
        fi
        return
    fi

    flush_gphoto_errors
    gphoto_last_err="$err"
    gphoto_err_count=1
    echo "gphoto2: $err"
}

gphoto2 --set-config capturetarget=1 >/dev/null 2>"$GPHOTO_ERR_FILE"
report_gphoto_error

# Files are tracked by their full camera path, not by basename. The camera
# restarts numbering at IMG_0001 in each new folder, so a bare name like
# IMG_0001.CR3 is not unique across folders and would make every photo whose
# number was already used in a previous folder look "already downloaded".

# Function to check if a file was already downloaded
is_downloaded() {
    local filename="$1"
    grep -qFx "$filename" "$DB_FILE"
}

# Function to mark a file as downloaded
mark_downloaded() {
    local filename="$1"
    echo "$filename" >> "$DB_FILE"
}

while :
do
    # Cleanup old folders if disk free space is below the configured threshold
    disk_info=$(df -Pk "$DIRECTORY" | awk 'NR == 2 {print $2, $4}')
    read -r total_blocks available_blocks <<< "$disk_info"

    if [ -z "$total_blocks" ] || [ "$total_blocks" -eq 0 ]; then
        echo "Unable to determine disk space for $DIRECTORY"
    else
        free_percent=$((available_blocks * 100 / total_blocks))

        if [ "$free_percent" -lt "$CLEANUP_MIN_FREE_PERCENT" ]; then
            echo "Disk free space is ${free_percent}%, below ${CLEANUP_MIN_FREE_PERCENT}%; removing folders older than 1 day"
            # Only the YYYY-MM-DD folders we create ourselves. Without the
            # -name test this also matches Syncthing's .stfolder marker, and
            # removing that makes Syncthing declare the folder unavailable and
            # stop syncing -- disabling the very offloading that makes deleting
            # local photos safe.
            find "$DIRECTORY" -mindepth 1 -maxdepth 1 -type d \
                -name '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' \
                -mmin +"$CLEANUP_OLDER_THAN_MINUTES" -print -exec rm -rf -- {} +
        fi
    fi

    # Only trust stdout when gphoto2 succeeded: its failure boilerplate also
    # goes to stdout, and line 3 of that would parse as a camera named
    # "If you intend", sending the script off looking for folders that do not
    # exist.
    if detect_out=$(gphoto2 --auto-detect 2>"$GPHOTO_ERR_FILE"); then
        CAMERA=$(printf '%s\n' "$detect_out" | awk 'FNR == 3 {print $1, $2, $3}')
    else
        CAMERA=""
    fi
    report_gphoto_error

    if [ ! -z "$CAMERA" ]; then
        echo "Camera detected: $CAMERA"
        
        # Every image folder under DCIM, not just one. `gphoto2 --list-folders`
        # prints a "There are N folders in folder 'PATH'." line per folder it
        # walks; matching "DCIM/" keeps exactly the folders *inside* DCIM and
        # skips both the bare " - DCIM" listing entry and DCIM itself. The
        # previous `tail -n 1` kept only the last line, which is
        # indistinguishable while the card holds a single folder but silently
        # hides the rest once the camera rolls the counter over into a new one.
        paths=$(gphoto2 --list-folders 2>"$GPHOTO_ERR_FILE" | grep "DCIM/" | awk '{print $(NF)}')
        report_gphoto_error
        while IFS= read -r p; do
            pc="${p//\'/}"
            pc="${pc%.}"

            echo "Checking path: $pc"

            # Get list of all CR3 files on camera (supports CR3, JPG, and other common formats)
            camera_files=$(gphoto2 --folder "$pc" --list-files 2>"$GPHOTO_ERR_FILE" | awk '{print $2}' | egrep '\.(CR3|JPG|JPEG|PNG|RAW|NEF|ARW)$')
            report_gphoto_error
            
            if [ -z "$camera_files" ]; then
                echo "No files found in $pc"
                continue
            fi

            # Count total files on camera
            total_files=$(echo "$camera_files" | wc -l)
            echo "Found $total_files files on camera in $pc"

            # Build list of files to download (not in DB and not in storage)
            files_to_download=""
            new_count=0
            skipped_count=0

            while IFS= read -r filename; do
                if [ -z "$filename" ]; then
                    continue
                fi

                # Check if already downloaded (in DB or exists in storage)
                if is_downloaded "$pc/$filename" ; then
                    skipped_count=$((skipped_count + 1))
                else
                    files_to_download="$files_to_download$filename"$'\n'
                    new_count=$((new_count + 1))
                fi
            done <<< "$camera_files"

            echo "Files to download: $new_count, Already downloaded: $skipped_count"

            if [ $new_count -eq 0 ]; then
                echo "No new files to download"
            else
                # Download only new files
                while IFS= read -r filename; do
                    if [ -z "$filename" ]; then
                        continue
                    fi

                    echo "Downloading: $filename"
                    
                    # Download with date-based folder organization
                    # stdout is only the progress bar; we log our own outcome below.
                    if gphoto2 --folder "$pc" --get-file "$filename" --filename "%Y-%m-%d/%f.%C" --skip-existing >/dev/null 2>"$GPHOTO_ERR_FILE"; then
                        # Mark as downloaded in database
                        mark_downloaded "$pc/$filename"
                        flush_gphoto_errors
                        echo "Successfully downloaded and tracked: $filename"
                    else
                        report_gphoto_error
                        echo "Failed to download: $filename"
                    fi
                done <<< "$files_to_download"
                
                echo "Download complete for $pc"
            fi

        done < <(printf "%s\n" "$paths")
    else
        echo "No camera detected, waiting..."
    fi
    
    sleep 5
done
