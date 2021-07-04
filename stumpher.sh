#! /bin/bash

#set -euxo pipefail
#set -euo pipefail
#set -x

SRC=$1
OUT=$2
tmp=$3
LOCAL=${tmp:=0}

if [ $LOCAL != "0" ]; then
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

ffprobe -nostdin - -print_format flat=sep_char=_ -show_format -show_streams -loglevel quiet "$UU" < /dev/null > "$NFO" 
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

DO_FULLRES=1

if [[ $WIDTH -lt $((1920/2)) ]]; then
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

if [ $DO_FULLRES -eq 1 ]; then
	i=$INC
	co=0
	LASTF=""
	while [[ $i -lt $LEN_SECONDS ]]; do
	  OFN=$( printf "fullres-%06d.tif" $i )
	  OF="${D}/$OFN"
	  OUT2=$( printf "$OUT-%06d.webp" $i )
	  ${FF} -noaccurate_seek -ss "${i}" -i "$UU" -frames:v 1 $OF  < /dev/null
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
	CVSTRING="${CVSTRING} -append"
fi


# TILES
# #############################################33

INC=60
INC=$(( ($LEN_SECONDS) / 60 ))
#echo "images if one per 60s $INC"

if [[ $INC -gt 100 ]]; then
       INC=100
fi


# round this up to next multiple of $besides
#echo "rounding up to fit besides $besides ==== $INC + $INC % $besides"
INC=$(( $INC / ($besides *2) ))
INC=$(( $INC + 1 ))
INC=$(( $INC * $besides *2 ))

# cope with webpS 16384 limit.
# we even don't care if it's not webp

FULLS_HEIGHT_HEIGHT=$(($HEIGHT * $NUM_FULLRES * $DO_FULLRES))

this_height=$(( $FULLS_HEIGHT_HEIGHT + ($INC/$besides)*$HEIGHT/$besides_scale ))


# NOTE, bash does not do floating....

if [ $this_height -ge 16384 ]; then
	echo "Image would be $this_height ($INC / $besides * $HEIGHT/$besides_scale) high; chosing to fit in 16k limits (for webp)"
	# desired height
	SPACE_LEFT=$(( 16384 - $FULLS_HEIGHT_HEIGHT ))
	echo "SPAC ELEFT $SPACE_LEFT"
	INC=$(( $SPACE_LEFT / ($HEIGHT*$besides_scale) ))
	echo "$INC images w/ height $HEIGHT possible => $(( $INC * $HEIGHT ))"
	# dunno why -1... maybe line 0 already has 960 height?
	INC=$(( ($INC-1) * $besides ))
fi

NUM=$INC

thumbs=()
j=0


while [[ $j -lt $NUM ]]; do
  #echo -n " $(( 100 * $j / $NUM ))%"

    # if the video is less than say 6 seconds for 6 besides, this needs
    # to overwrite the image
    sec=$(( ($LEN_SECONDS / $NUM) * $j ))
	  OF=$( printf "$D/tn-%06d.tif" $j )
	  ${FF} -noaccurate_seek -ss "${sec}" -i "$UU" -frames:v 1 \
		-vf scale=iw/$besides_scale:ih/$besides_scale $OF < /dev/null
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
