#! /bin/bash

set -euxo pipefail

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


SECONDS=$(( ${format_duration%\.*} - 10 ))
NUM_FULLRES=4

WIDTH=${streams_stream_0_coded_width:=0}

if [[ $WIDTH -eq 0 ]]; then
	WIDTH=${streams_stream_1_coded_width}
fi

# this is int() => floor()
besides=$(( $WIDTH / $TILE_MIN_WIDTH ))
TILE_SIZE=$(( $WIDTH / $besides ))

CVSTRING="convert "


INC=$(( $SECONDS / $NUM_FULLRES ))
if [[ $INC -le 0 ]]; then
	INC=1
fi

i=$INC
co=0
while [[ $i -le $SECONDS ]]; do
  OFN=$( printf "fullres-%04d.tif" $i )
  OF="${D}/$OFN"
  OUT2=$( printf "$OUT-%04d.jpg" $i )
  ${FF} -noaccurate_seek -ss "${i}" -i "$UU" -frames:v 1 $OF 
  convert "$OF" -quality 50% "$OUT2"
  i=$(( $i + $INC ))
  if [[ $(( ($co % 2) )) -eq 0 ]]; then
	  CVSTRING="${CVSTRING} $OF"
  fi
	co=$(( $co + 1 ))
done
CVSTRING="${CVSTRING} -append"



i=10
INC=60

# how many images if one per minute?
INC=$(( ($SECONDS-$i) / 60 ))
# round this up to next multiple of $besides
INC=$(( $INC + ($INC % $besides) ))

INC=$(( $SECONDS / $INC ))


co=0
while [[ $i -lt $SECONDS ]]; do

if [[ $co -eq 0 ]]; then
	echo
	CVSTRING="${CVSTRING} ("
fi
  co=$(( $co + 1 ))
  OF=$( printf "$D/tn-%04d.tif" $i )
  ${FF} -noaccurate_seek -ss "${i}" -i "$UU" -frames:v 1 \
	-vf scale=iw/$besides:ih/$besides $OF 
  S2=$i
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
  i=$(( $i + $INC ))
  if [[ $co -ge $besides ]]; then
  	CVSTRING="${CVSTRING} +append ) -append"
	co=0
  fi
done
if [[ $co -gt 0 ]]; then
	CVSTRING="${CVSTRING} +append ) -append"
	co=0
fi

#if [[ $co -gt 0 ]]; then
	#CVSTRING="$CVSTRING +append ) -append"

#fi


CVSTRING="$CVSTRING -quality 50% $OUT"

$CVSTRING

rm -vr "$D"
