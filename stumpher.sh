#! /bin/bash

#set -euxo pipefail
#set -euo pipefail
#set -x

SRC=$1
OUT=$2
tmp=$3
LOCAL=${tmp:=0}

if [ $LOCAL != "0"]; then
	DDD=/dev/shm/sthumph/
	mkdir -p $DDD
	D=$(mktemp -d -p $DDD)
else
D=$(mktemp -d)
fi

NFO="$D/ffprobe-output"

if [ -s $OUT ]; then
  echo "refusing to clobber '$OUT'"
  exit 1
fi

TILE_MIN_WIDTH=300

UU=$SRC

ffprobe -print_format flat=sep_char=_ -show_format -show_streams -loglevel quiet "$UU" > "$NFO"
. $NFO

FF="echo ffmpeg -loglevel quiet"
FF="ffmpeg -loglevel quiet"
#FF="ffmpeg "


LEN_SECONDS=$(( ${format_duration%\.*} - 0 ))
NUM_FULLRES=6

WIDTH=${streams_stream_0_coded_width:=0}

if [[ $WIDTH -eq 0 ]]; then
	WIDTH=${streams_stream_1_coded_width}
fi

# 4k looks to small to see, double it up
if [[ $WIDTH -gt 1920 ]]; then
  TILE_MIN_WIDTH=$(( $TILE_MIN_WIDTH * 2 ))
fi

# this is int() => floor()
besides=$(( $WIDTH / $TILE_MIN_WIDTH ))
besides_scale=$besides

TILE_SIZE=$(( $WIDTH / $besides ))

DO_FULLRES=1

if [[ $WIDTH -lt $((1920/1)) ]]; then
	DO_FULLRES=0
	TILE_SIZE=$WIDTH
	besides=$(((1920-0)/$WIDTH))
	besides_scale=1
fi


printf "width(%4d), length(%4d), tilesize(%3d), filename(%s)\n" $WIDTH $LEN_SECONDS $TILE_SIZE $SRC

CVSTRING="convert "


INC=$(( $LEN_SECONDS / $NUM_FULLRES ))
if [[ $INC -le 0 ]]; then
	INC=1
fi


# FULLRES
# #############################################33

i=$INC
co=0
LASTF=""
while [[ $i -lt $LEN_SECONDS ]]; do
  OFN=$( printf "fullres-%06d.tif" $i )
  OF="${D}/$OFN"
  OUT2=$( printf "$OUT-%06d.webp" $i )
  ${FF} -noaccurate_seek -ss "${i}" -i "$UU" -frames:v 1 $OF 
  if [ ! -s $OF ]; then
    cp $LASTF $OF
  fi
	if [ $LOCAL = "0" ]; then
  		convert "$OF" "$OUT2"
	fi
  i=$(( $i + $INC ))
  if [[ $co -eq $(( $NUM_FULLRES * 1/4))  || $co -eq $(( $NUM_FULLRES * 3/4 ))  ]]; then
	  if [[ $DO_FULLRES -eq 1 ]]; then
	  CVSTRING="${CVSTRING} $OF"
	  fi
  fi
	co=$(( $co + 1 ))
  LASTF=$OUT2
done
if [[ $DO_FULLRES -eq 1 ]]; then
	CVSTRING="${CVSTRING} -append"
fi


# TILES
# #############################################33

INC=60

# how many images if one per minute?
INC=$(( ($LEN_SECONDS) / 60 ))
#echo "images if one per 60s $INC"

while [[ $INC -gt 100 ]]; do
       INC=100
done
#INC=30

#INC=1


# round this up to next multiple of $besides

#echo "rounding up to fit besides $besides ==== $INC + $INC % $besides"
#echo "wanna do $INC frames"
INC=$(( $INC / ($besides *2) ))
INC=$(( $INC + 1 ))

INC=$(( $INC * $besides *2 ))
#echo "rounding to next higher multiple of $besides => $INC"

NUM=$INC

#exit

thumbs=()
j=0

while [[ $j -lt $NUM ]]; do
  #echo -n " $(( 100 * $j / $NUM ))%"

    # if the video is less than say 6 seconds for 6 besides, this needs
    # to overwrite the image
    sec=$(( ($LEN_SECONDS / $NUM) * $j ))
	  OF=$( printf "$D/tn-%06d.tif" $j )
	  ${FF} -noaccurate_seek -ss "${sec}" -i "$UU" -frames:v 1 \
		-vf scale=iw/$besides_scale:ih/$besides_scale $OF 
    # maybe corrupt somewhere in the middle, use last image.
    # FIXME - what at image 0?
    if [ ! -s $OF ]; then
      cp $( printf "$D/tn-%06d.tif" $(( $j - 1 )) ) "$OF"
    fi
	  S2=$sec
	  H=0
	  M=0
	  S=0
	  H=$(( $S2 / 3600 ))
	  S2=$(( $S2 - ($H * 3600 ) ))
	  M=$(( $S2 / 60 ))
	  S2=$(( $S2 - ($M * 60 ) ))
	  S=$(( $S2 ))
	  LAB=$( printf "%02d:%02d:%02d" $H $M $S )
	  OF=$( printf "\n\t( ( -background #00000080 -fill white -font /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf label:%s ) -gravity southeast %s +swap -composite )\n" $LAB $OF )
      thumbs+=("$OF")
      j=$(( $j + 1 ))

done


# TILES
##############################################33
j=0
for i in "${thumbs[@]}"
do
    #echo "\n\n****j($j) besides($besides) i($i)****\n"
	if [ $(($j % $besides)) -eq 0 ]; then
		CVSTRING="${CVSTRING} ("$'\n'
	fi

    CVSTRING="${CVSTRING} $i"$'\n'


    #check if this image concludes a line
    # this is the same as $j % $besides == (besides - 1)
    j=$(( $j + 1 ))
	  #if [[ $(( ($j+1) % $besides)) -eq 0 ]]; then
	  if [[ $(( ($j) % $besides)) -eq 0 ]]; then
		  CVSTRING="${CVSTRING} +append ) -append"$'\n'
	  fi
done

#echo $CVSTRING

$CVSTRING "$OUT"

rm -r "$D"
