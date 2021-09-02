#! /bin/bash

#set -euxo pipefail
#set -euo pipefail
#set -x

SRC=$1
OUT=$2
tmp=$3
LOCAL=${tmp:=0}

START=$(date +%s )

#if [ $LOCAL != "0" ]; then
#	DDD=/dev/shm/sthumph/
#	mkdir -p $DDD
#	D=$(mktemp -d -p $DDD)
#else
  D=$(mktemp -d)
#fi
##D=.
#
NFO="$D/ffprobe-output"
#
if [ -s $OUT ]; then
  echo "refusing to clobber '$OUT'"
  exit 1
fi

TILE_MIN_WIDTH=300

UU=$SRC

ffprobe -print_format flat=sep_char=_ -show_format -show_streams -loglevel quiet "$UU" < /dev/null > "$NFO" 
. $NFO

if [ "${format_duration}" = "N/A" -o "X${format_duration}" = "X" ]; then
  echo "returned length is (${format_duration}); re(encoding) file to get correct length"
  UU2="$UU-recode.${UU##*.}"
  ffmpeg -nostdin -i "${UU}" -acodec copy -vcodec copy -map_metadata -1  "${UU2}" < /dev/null
  # just get the duration and leave other metadata intact.
  # we seem to have  to strip the old metadata completely
  # https://superuser.com/questions/650291/how-to-get-video-duration-in-seconds

  ffprobe -print_format flat=sep_char=_ -show_format -show_streams -loglevel quiet "$UU2" | grep "^format_duration" > "${NFO}_"
  . "${NFO}_"
	if [ "${format_duration}" = "N/A" -o "X${format_duration}" = "X" ]; then
		echo "even after recoding/reparsing no length found. bailing out"
		exit;
	fi
  # if the file was so broken, maybe it's better to use the reparsed file?
  if [ 1 -eq 1 ]; then
    mv "$UU2" "$UU"
  else
    rm -f "$UU2"
  fi

  #runtime on original file:
  # THIS IS JUST ONE TEST....
  # real	1m31.677s
  # user	1m41.204s
  # sys	0m33.258s

  #runtime on reparsed file
  # real	0m44.595s
  # user	1m18.498s
  # sys	0m11.370s

  rm -f "${NFO}_"
  echo "returned length is now (${format_duration})"
fi


FF="echo ffmpeg -loglevel quiet"
FF="ffmpeg -loglevel quiet -nostdin"
#FF="ffmpeg -nostdin"
#FF="ffmpeg "


LEN_SECONDS=$(( ${format_duration%\.*} - 0 ))
NUM_FULLRES=6


# use first video stream as *the* stream and use that's (:) width
NUM_STREAMS=${format_nb_streams}
i=0
WIDTH="unknown"
HEIGHT="unknown"
while [ $i -le $NUM_STREAMS ]; do
  tmp="streams_stream_${i}_codec_type"
  tv=${!tmp}
  if [ "$tv" = "video" ]; then
    #    streams_stream_3   _coded_width=1280
    # ?? coded vs. codec?
    tmp="streams_stream_${i}_width"
    tv=${!tmp}
    if [[ "X$tv" != "X" && "$tv" -gt 0 ]]; then
      WIDTH=$tv
    	tmp="streams_stream_${i}_height"
	HEIGHT=${!tmp}
      break
    fi
  fi
  i=$(( $i + 1 ))

done


if [ "${WIDTH}" = "unknown" ]; then
  echo "no useable video stream with a width set found; skipping this file"
  exit
fi

# 4k looks to small to see, double it up
if [[ $WIDTH -gt 1920 ]]; then
  TILE_MIN_WIDTH=$(( $TILE_MIN_WIDTH * 2 ))
fi

# this is int() => floor()
besides=$(( $WIDTH / $TILE_MIN_WIDTH ))
besides_scale=$besides

TILE_SIZE=$(( $WIDTH / $besides ))
TILE_HEIGHT=$(( $HEIGHT / $besides ))

DO_FULLRES=1

if [[ $WIDTH -lt $((1920/2)) ]]; then
	DO_FULLRES=0
	TILE_SIZE=$WIDTH
	besides=$(((1920-0)/$WIDTH))
	besides_scale=1
  TILE_HEIGHT=$(( $HEIGHT / $besides ))
fi


printf "width(%4d), length(%4d), tilesize(%3d), filename(%s)\n" $WIDTH $LEN_SECONDS $TILE_SIZE $SRC

LINES=$(( $LEN_SECONDS / (90) / $besides ))

if [ $LINES -le 1 ]; then
  LINES=1
fi

if [ $LINES -gt 16 ]; then
  LINES=16
fi

height=$(( ($DO_FULLRES * 2 * $HEIGHT) + $LINES * $TILE_HEIGHT ))

while [ $height -ge 16384 ]; do
  LINES=$(( $LINES - 1 ))
  height=$(( ($DO_FULLRES * 2 * $HEIGHT) + $LINES * $TILE_HEIGHT ))
done

REAL_NUMBER_OF_IMAGES=$(( $LINES * $besides ))
NUMIMAGES=$(( $REAL_NUMBER_OF_IMAGES * 150 / 100))
if [ $NUMIMAGES -le 1 ]; then
NUMIMAGES=1
fi

INC=$(( $LEN_SECONDS / $NUMIMAGES ))
#echo "*** $LINES lines w/ $besides image besides *** for $LEN_SECONDS => one pic each $INC seconds"

if [ $INC -le 1 ]; then
INC=1
fi

#assume 25% for final convert
pvcount=$(( $NUMIMAGES * 125 / 100 ))
# fifo w/ mkfifo sucks
FIFO="$D/pvprogress"
cat /dev/null > $FIFO
tail -f $FIFO | pv -s $pvcount -p -t -e --pidfile $D/pv.pid  > /dev/null &

if [ 1 -eq 1 ]; then
  j=$INC
  while [[ $j -le $LEN_SECONDS ]]; do
      OF=$( printf "$D/tn-%06d.jpg" $j )
      ${FF} -noaccurate_seek -ss "$j" -i "$UU" -frames:v 1 \
      $OF < /dev/null
      j=$(( $j + $INC ))
      echo >> $FIFO
  done
fi

#howmany=$(( (100/$besides) * $besides ))
# one line every 5 minutes?


FLIST="$D/flist.txt"
find $D -type f -iname "tn-*.jpg" -printf "%s %p\n" | \
  sort -n -k 1,1 | tail -n $REAL_NUMBER_OF_IMAGES | cut -d" " -f 2- | sort \
  > $FLIST

export CVSTRING=""
if [ $DO_FULLRES -eq 1 ]; then
  FULLRES1=$(( $REAL_NUMBER_OF_IMAGES * 1/4 ))
  FULLRES2=$(( $REAL_NUMBER_OF_IMAGES * 3/4 ))
  # no while read a, it's a subshell
  # but maybe it does with export?
  CVSTRING="$CVSTRING $(cat $FLIST | head -n $FULLRES1 | tail -n 1)"
  CVSTRING="$CVSTRING $(cat $FLIST | head -n $FULLRES2 | tail -n 1)"
  CVSTRING="$CVSTRING -append"
fi



j=0
export CV=" "
export TMP=""
for a in $(< $FLIST); do
  #echo "**** $a"
  # begins a line?
	if [ $j -gt 0 -a $(($j % $besides)) -eq 0 ]; then
    CV="$CV ( $TMP ) -append"
    TMP=""
	fi
  S2=$( echo "$a" | perl -pe 's/.*?0*(\d+)\..*/$1/' )
  M=0
  S=0
  H=$(( $S2 / 3600 ))
  S2=$(( $S2 - ($H * 3600 ) ))
  M=$(( $S2 / 60 ))
  S2=$(( $S2 - ($M * 60 ) ))
  S=$(( $S2 ))
  LAB=$( printf "%02d:%02d:%02d" $H $M $S )
  #OF="( ( -background #00000080 -fill white -font /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf label:$LAB ) -gravity southeast $a +swap -composite ) +append"
  OF="( ( $a -resize ${TILE_SIZE}x ) ( -background #00000080 -fill white -font /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf label:$LAB ) -gravity southeast  -composite ) +append"
  export TMP="$TMP $OF"
  j=$(( $j + 1 ))
done
if [ "X$TMP" != "X" ]; then
  CV="$CV ( $TMP ) -append"
fi


#set -x
convert $CVSTRING $CV  $OUT
#set +x

#$CVSTRING "$OUT"


END=$(date +%s )
#echo "took $(( $END - $START )) seconds"
kill $(< $D/pv.pid)
#echo "TMPDIR is $D"
rm -fr "$D"
echo
