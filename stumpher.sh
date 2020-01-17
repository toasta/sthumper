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

UU=$SRC

ffprobe -print_format flat=sep_char=_ -show_format -loglevel quiet "$UU" > "$NFO"
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

# get 2 fullres images

SEC=${format_duration%\.*}
SECLESS=$(( $SEC - 1 ))
SEQ1=$(( $SEC / 3 ))
SEQ2=$(( $SEC / 32 ))
if [ $SEQ1 -le 0 ];then
  SEQ1=1
fi

if [ $SEQ2 -le 0 ];then
  SEQ2=1
fi

# seq $SEQ1 $SEQ1 $SECLESS  | while read a; 
# does some crazy shit with not using the trailing zeroes or numbers in general...
# echoing works, calling ffmpeg doesnt and "-x" shows it beeing called wrong
# looping in shell. This saves an IPC and does something else

j=$SEQ1
while [[ $j -lt $SECLESS ]]; do
  OF=$( printf "$D/fullres-%04d.tif" $j )
  ${FF} -ss "${j}" -i "$UU" -frames:v 1 $OF 
  j=$(( $j + $SEQ1 ))
  echo $OF
done

j=$SEQ2
while [[ $j -lt $SECLESS ]]; do
  OF=$( printf "$D/tn-%04d.tif" $j )
  ${FF} -ss "${j}" -i "$UU" -frames:v 1 -vf scale=iw/4:ih/4 $OF 
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
while [[ $j -lt $SECLESS ]]; do
  OF=$( printf "$D/fullres-%04d.tif" $j )
  j=$(( $j + $SEQ1 ))
  CVSTRING="${CVSTRING} $OF"
done
CVSTRING="${CVSTRING} -append"

co2=0
j=$SEQ2
while [[ $j -lt $SECLESS ]]; do
  if [[ $co2 -eq 0 ]]; then
    CVSTRING="${CVSTRING} ( "
  fi 
  OF=$( printf "$D/tn-%04d.tif" $j )
  CVSTRING="${CVSTRING} $OF"
  j=$(( $j + $SEQ2 ))
  co2=$(( $co2 + 1 ))
  if [[ $co2 -eq 4 ]]; then
    CVSTRING="${CVSTRING} +append ) -append"
    co2=0
  fi 
done
if [[ $co2 -gt 0 ]]; then
    CVSTRING="${CVSTRING} +append ) -append"
fi
CVSTRING="$CVSTRING $OUT"

$CVSTRING

rm -vr "$D"
