#!/usr/bin/env sh


DIRECTORY=~/photos

if command -v gphoto2 > /dev/null 2>&1; then
    echo "gphoto2 detected"
else
    echo "gphoto2 missing "
    exit 1
fi

if [ ! -d "$DIRECTORY" ]; then
    echo "Creating photos folder at" $DIRECTORY
    mkdir -p $DIRECTORY
fi

cd $DIRECTORY

while :
do
    CAMERA=$(gphoto2 --auto-detect | awk 'FNR == 3 {print $1, $2, $3}')
    if [ ! -z "$CAMERA" ]; then
        echo "Pulling previous photos"
        gphoto2 --get-all-files  --skip-existing --filename "%d-%m-%Y/%H-%M-%S-%n.%C" | grep -v "Skip"
        echo "Done!"
        gphoto2 --wait-event-and-download  --skip-existing --filename "%d-%m-%Y/%H-%M-%S-%n.%C" | grep -v "UNKNOWN"
    fi
    sleep 10
done
