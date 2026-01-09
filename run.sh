#!/usr/bin/env sh

TODAY=$(date +'%Y-%m-%d') 

DIRECTORY=~/photos

if command -v gphoto2 > /dev/null 2>&1; then
    echo "gphoto2 detected"
else
    echo "gphoto2 missing "
    exit 1
fi

if command -v syncthing > /dev/null 2>&1; then
    echo "syncthing detected"
else
    echo "syncthing missing "
    exit 1
fi

if [ ! -d "$DIRECTORY" ]; then
    echo "Creating photos folder at" $DIRECTORY
    mkdir -p $DIRECTORY
fi

if [ ! -d "$DIRECTORY/$TODAY" ]; then
    echo "Creating today's photos sub folder at" $DIRECTORY/$TODAY
    mkdir -p $DIRECTORY/$TODAY
fi

cd $DIRECTORY/$TODAY

while :
do
    CAMERA=$(gphoto2 --auto-detect | awk 'FNR == 3 {print $1, $2, $3}')
    if [ ! -z "$CAMERA" ]; then
    gphoto2 --get-all-files --skip-existing | grep -v "Skip"
    fi
    sleep 1
done
