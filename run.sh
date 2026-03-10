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

gphoto2 --set-config capturetarget=1

while :
do
    CAMERA=$(gphoto2 --auto-detect | awk 'FNR == 3 {print $1, $2, $3}')


    if [ ! -z "$CAMERA" ]; then
        paths=$(gphoto2 --list-folders | grep DCIM | tail -n 1 | awk '{print $(NF)}')
        while IFS= read -r p; do
            pc="${p//\'/}"
            pc="${pc%.}"

            echo "Checking path: " $pc

            ncr3p=$(gphoto2 --folder $pc --list-files | awk '{print $2}' | egrep '.CR3')
            if [ "$cr3p" = "$ncr3p" ]; then
                continue
            fi
            cr3p=$ncr3p

            echo "$ncr3p" | tr '\n' '\0' | xargs -0 -I {} gphoto2 --folder $pc --get-file {} --filename "%d-%m-%Y/%f.%C" --skip-existing


        done < <(printf "%s\n" "$paths")
    fi
    sleep 1
done

            # echo "Pulling previous photos"
            # gphoto2 --get-all-files  --skip-existing --filename "%d-%m-%Y/%H-%M-%S-%n.%C" | grep -v "Skip"
            # sleep 3
            # echo "Done!"
            # gphoto2 gphoto2 --capture-tethered --keep --filename "%d-%m-%Y/%H-%M-%S-%n.%C" | grep -v "UNKNOWN"
