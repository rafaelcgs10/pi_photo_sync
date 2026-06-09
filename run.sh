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

gphoto2 --set-config capturetarget=1

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
            find "$DIRECTORY" -mindepth 1 -maxdepth 1 -type d -mmin +"$CLEANUP_OLDER_THAN_MINUTES" -print -exec rm -rf -- {} +
        fi
    fi

    CAMERA=$(gphoto2 --auto-detect | awk 'FNR == 3 {print $1, $2, $3}')

    if [ ! -z "$CAMERA" ]; then
        echo "Camera detected: $CAMERA"
        
        paths=$(gphoto2 --list-folders | grep DCIM | tail -n 1 | awk '{print $(NF)}')
        while IFS= read -r p; do
            pc="${p//\'/}"
            pc="${pc%.}"

            echo "Checking path: $pc"

            # Get list of all CR3 files on camera (supports CR3, JPG, and other common formats)
            camera_files=$(gphoto2 --folder "$pc" --list-files | awk '{print $2}' | egrep '\.(CR3|JPG|JPEG|PNG|RAW|NEF|ARW)$')
            
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
                if is_downloaded "$filename" ; then
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
                    if gphoto2 --folder "$pc" --get-file "$filename" --filename "%Y-%m-%d/%f.%C" --skip-existing; then
                        # Mark as downloaded in database
                        mark_downloaded "$filename"
                        echo "Successfully downloaded and tracked: $filename"
                    else
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
