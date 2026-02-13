#!/usr/bin/env sh

shopt -s extglob
DIRECTORY=/rafael_mounts/photos_from_rpi
STYLES=("astia")

cd $DIRECTORY

for folder in *; do
    cd ${folder} 
    for style in $STYLES; do
        mkdir -p ${style} ;
        raws=$(ls *.@(CR3|cr3) | sed -e 's/\.CR3$//' | sed -e 's/\.cr3$//' | sort)
        jpgs=$(ls ${style} | sed -e 's/\.jpg$//' | sort)
        dff=$(diff <(echo "$raws") <(echo "$jpgs") | grep "^<" | sed 's/^< //')
        for photo in $dff; do
            echo ${folder} ${style} ${photo} ;
            darktable-cli ${photo}.CR3 ${style}/${photo}.jpg --style ${style} --style-overwrite ;
        done
    done
    cd ..
done
