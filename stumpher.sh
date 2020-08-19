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

TILE_MIN_WIDTH=384

UU=$SRC
#streams_stream_0_coded_widthstreams_stream_0_coded_width

ffprobe -print_format flat=sep_char=_ -show_format -show_streams -loglevel quiet "$UU" > "$NFO"
. $NFO

#LENGTH=$(cat $NFO | grep "^  Duration:" | head -c 1)

FF="echo ffmpeg -loglevel quiet"
FF="ffmpeg -loglevel quiet"


#format.filename="this-is-not-the-file-you-are-looking-for"
#format.nb_streams=3
#format.nb_programs=0
#format.format_name="matroska,webm"
#format.format_long_name="Matroska / WebM"
#format.start_time="0.000000"
#format.duration="5559.054000"
#format.size="10276400944"
#format.bit_rate="14788704"
#format.probe_score=100
#format.tags.encoder="libebml v1.3.0 + libmatroska v1.4.1"
#format.tags.creation_time="2014-04-04 19:54:26"
#streams_stream_0_coded_width

# get 2 fullres images

SEC=${format_duration%\.*}
SECLESS=$(( $SEC  - 1 ))
SEQ1_DIV=4
SEQ1=$(( $SEC / $SEQ1_DIV ))

WIDTH=${streams_stream_0_coded_width}

if [ $SEQ1 -le 0 ];then
  SEQ1=1
fi





# seq $SEQ1 $SEQ1 $SECLESS  | while read a; 
# does some crazy shit with not using the trailing zeroes or numbers in general...
# echoing works, calling ffmpeg doesnt and "-x" shows it beeing called wrong
# looping in shell. This saves an IPC and does something else


besides=$(( $WIDTH / $TILE_MIN_WIDTH ))
S2=$(( 32 / $besides ))
S2=$(( $S2 * $besides ))
S2=$(( $SEC / $S2 ))

SEQ2=$S2
if [ $SEQ2 -le 0 ];then
  SEQ2=1
fi


j=$SEQ1
while [[ $j -le $SECLESS ]]; do
  OFN=$( printf "fullres-%04d.tif" $j )
  OF="${D}/$OFN"
  OUT2=$( printf "$OUT-%04d.jpg" $j )
  ${FF} -noaccurate_seek -ss "${j}" -i "$UU" -frames:v 1 $OF 
  convert "$OF" -resize '1920x>' "$OUT2"
  j=$(( $j + $SEQ1 ))
  echo $OF
done



j=$SEQ2
while [[ $j -lt $SECLESS ]]; do
  OF=$( printf "$D/tn-%04d.tif" $j )
  ${FF} -noaccurate_seek -ss "${j}" -i "$UU" -frames:v 1 \
	-vf scale=iw/$besides:ih/$besides $OF 
  j=$(( $j + $SEQ2 ))
  echo $OF
done

wait


# This is intentionally two loops; one could parallelize the thumbnail generation
# don't do this for non-fs-files (i.e. http(s):// sources; the seeking is terrible
# as it need to download several chunks to figure out the right byteoffset
# and it's doing that for each thumbnail
########################
CVSTRING="convert "

j=$SEQ1
co=0
while [[ $j -le $SECLESS ]]; do
  if [[ $(( $co % 2 )) -eq 0 ]]; then
	  OF=$( printf "$D/fullres-%04d.tif" $j )
  	CVSTRING="${CVSTRING} $OF"
	fi
  co=$(( $co + 1 ))
  j=$(( $j + $SEQ1 ))
done
CVSTRING="${CVSTRING} -append"

co2=0
j=$SEQ2
while [[ $j -lt $SECLESS ]]; do
  if [[ $co2 -eq 0 ]]; then
    CVSTRING="${CVSTRING} ( "
  fi 
  S2=$j
  H=0
  M=0
  S=0
  H=$(( $S2 / 3600 ))
  S2=$(( $S2 - ($H * 3600 ) ))
  M=$(( $S2 / 60 ))
  S2=$(( $S2 - ($M * 60 ) ))
  S=$(( $S2 ))
  LAB=$( printf "%02d:%02d:%02d" $H $M $S )
  OF=$( printf " ( ( -background #00000080 -fill white -font /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf label:%s ) -gravity southeast $D/tn-%04d.tif +swap -composite ) " $LAB $j )
  CVSTRING="${CVSTRING} $OF"
  j=$(( $j + $SEQ2 ))
  co2=$(( $co2 + 1 ))
  if [[ $co2 -ge $besides ]]; then
    CVSTRING="${CVSTRING} +append ) -append"
    co2=0
  fi 
done
if [[ $co2 -gt 0 ]]; then
    CVSTRING="${CVSTRING} +append ) -append"
fi
CVSTRING="$CVSTRING -quality 90 $OUT"

$CVSTRING

rm -vr "$D"
