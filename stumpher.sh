#! /bin/bash

#set -euxo pipefail
#set -euo pipefail
#set -x

D=$(mktemp -d)
SRC=$1
OUT=$2
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
NUM_FULLRES=4

WIDTH=${streams_stream_0_coded_width:=0}

if [[ $WIDTH -eq 0 ]]; then
	WIDTH=${streams_stream_1_coded_width}
fi

# this is int() => floor()
besides=$(( $WIDTH / $TILE_MIN_WIDTH ))
TILE_SIZE=$(( $WIDTH / $besides ))

CVSTRING="convert "


INC=$(( $LEN_SECONDS / $NUM_FULLRES ))
if [[ $INC -le 0 ]]; then
	INC=1
fi

i=$INC
co=0
while [[ $i -le $LEN_SECONDS ]]; do
  OFN=$( printf "fullres-%06d.tif" $i )
  OF="${D}/$OFN"
  OUT2=$( printf "$OUT-%06d.jpg" $i )
  ${FF} -noaccurate_seek -ss "${i}" -i "$UU" -frames:v 1 $OF 
  convert "$OF" "$OUT2"
  i=$(( $i + $INC ))
  if [[ $(( ($co % 2) )) -eq 0 ]]; then
	  CVSTRING="${CVSTRING} $OF"
  fi
	co=$(( $co + 1 ))
done
CVSTRING="${CVSTRING} -append"



INC=60

# how many images if one per minute?
INC=$(( ($LEN_SECONDS) / 60 ))
echo "images if one per 60s $INC"

while [[ $INC -ge 100 ]]; do
       INC=$(( $INC / 2 ))
done


# round this up to next multiple of $besides

#echo "rounding up to fit besides $besides ==== $INC + $INC % $besides"
echo "rounding up to besides $besides $INC"
INC=$(( $INC / $besides ))

INC=$(( $INC + 1 ))

INC=$(( $INC * $besides ))
echo "rounding to besides $besides $INC"

NUM=$INC

#exit

co=0
j=0

while [[ $j -lt $NUM ]]; do
  echo -n " $(( 100 * $j / $NUM ))%"

	if [ $(($j % $besides)) -eq 0 ]; then
		CVSTRING="${CVSTRING} ("
	fi
    # if the video is less than say 6 seconds for 6 besides, this needs
    # to overwrite the image
    sec=$(( ($LEN_SECONDS / $NUM) * $j ))
	  co=$(( $co + 1 ))
	  OF=$( printf "$D/tn-%06d.tif" $sec )
	  ${FF} -noaccurate_seek -n -ss "${sec}" -i "$UU" -frames:v 1 \
		-vf scale=iw/$besides:ih/$besides $OF 
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
	  OF=$( printf " ( ( -background #00000080 -fill white -font /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf label:%s ) -gravity southeast %s +swap -composite ) " $LAB $OF )
	  CVSTRING="${CVSTRING} $OF"
	  j=$(( $j + 1 ))
	  if [[ $(($j % $besides)) -eq 0 ]]; then
		CVSTRING="${CVSTRING} +append ) -append"
	  fi
done
#CVSTRING="${CVSTRING} +append ) -append"
#CVSTRING="${CVSTRING} +append ) -append"
# if [[ $co -gt 0 ]]; then
# 	CVSTRING="${CVSTRING} +append ) -append"
# 	co=0
# fi

#if [[ $co -gt 0 ]]; then
	#CVSTRING="$CVSTRING +append ) -append"

#fi


CVSTRING="$CVSTRING $OUT"

$CVSTRING

rm -r "$D"
