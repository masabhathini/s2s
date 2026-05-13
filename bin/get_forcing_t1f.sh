#!/bin/bash
# shellcheck disable=SC2154,SC2086,SC1091,SC2034
set -e

source "$(dirname "$0")/koi"
koiname="$0"
koidescription="Extract a single ensemble member from the ECMWF S2S data"

__koimain() {
  __addarg "-h" "--help" "help" "optional" "" "$koidescription" ""
  __addarg "-i" "--input" "storevalue" "required" "" "Input grib data" ""
  __addarg "-m" "--member" "storevalue" "required" "" "Ensemble member" ""
  __addarg "-o" "--output" "storevalue" "optional" "" "Output grib data" ""
  __addarg "-n" "--nday" "storevalue" "optional" "46" "Forecast length in days" ""
  __addarg "" "--year" "storevalue" "optional" "" "Forecast year (used to extract reforecast)" ""
  __addarg "" "--lsminput" "storevalue" "optional" "" "Input grib data for land-sea mask (because LSM not available in Reforecast)" ""

  __parseargs "$@"

  set -ux

  inv=${input}.inv

  if [[ ! -e $inv ]]; then
    inv=inventory
    wgrib -s "$input" >"$inv"
  fi

  if [[ "$member" -eq 0 ]]; then
    search_string="Control forecast 0:"
    dataType="cf"
  else
    search_string="Perturbed forecast $member:"
    dataType="pf"
  fi

  # Extract the year if needed
  year_search_string="d=${year: -2}"

  tmpfile=data.mem${member}
  soilfile=soildata.mem${member}
  lsmfile=lsmdata.mem${member}

  # Get land-sea mask
  if [ -n "$lsminput" ]; then
    wgrib "$lsminput" | grep LSM | wgrib -s -grib -i "${lsminput}" -o "${lsmfile}.0000"
  else
    grep LSM <"$inv" | wgrib -s -grib -i "${input}" -o "${lsmfile}.0000"
  fi

  grep "$search_string" <"$inv" | grep "$year_search_string" | wgrib -i "$input" -s dataType="$dataType" -grib -o "$tmpfile" >/dev/null

  #mkdir -p sorted
  wgrib -s $tmpfile >inv
  grep -E 'STL|SWVL' <inv | grep ':anl:'| grep "$search_string" | wgrib -i "$tmpfile" -s -grib -o "${soilfile}.0000"

  # Sort in time for ungrib compatibility
  grep ':anl:' <inv | wgrib -i $tmpfile -s -grib -o "${tmpfile}.0000" >/dev/null
  #grib_set -s dataType="cf" "tmp.${soilfile}.0000" "${soilfile}.0000"
  cat ${soilfile}.0000 ${tmpfile}.0000 >> tmp.${lsmfile}.0000
  for ((k = 1; k <= 21; k++)); do
    j=$((k * 12))
    jj=$(printf "%04d\n" $j)
    grib_set -s indicatorOfUnitOfTimeRange=1,P1=${j},stepRange=${j} ${soilfile}.0000 ${soilfile}.${jj}
    grib_set -s indicatorOfUnitOfTimeRange=1,P1=${j},stepRange=${j} ${lsmfile}.0000 ${lsmfile}.${jj}
    grep ":${j}hr fcst:" <inv | wgrib -i "$tmpfile" -s -grib -o "${tmpfile}.${jj}" >/dev/null
    cat ${soilfile}.${jj} ${tmpfile}.${jj} >> tmp.${lsmfile}.${jj}
  done
  for ((k=22; k<=92; k++)); do
    l=$(( (k-22)/22 + 1 ))
    j=$(( ((k-1)%22) * 12 ))
    jj=$((k * 12))
    jjj=$(printf "%04d\n" $jj)
    grib_set -s timeRangeIndicator=10,indicatorOfUnitOfTimeRange=${l},P1=${j},P2=0,stepRange=${jj} ${soilfile}.0000 ${soilfile}.${jjj}
    grib_set -s timeRangeIndicator=10,indicatorOfUnitOfTimeRange=${l},P1=${j},P2=0,stepRange=${jj} ${lsmfile}.0000 ${lsmfile}.${jjj}
    grep ":${jj}hr fcst:" <inv | wgrib -i "$tmpfile" -s -grib -o "${tmpfile}.${jjj}" >/dev/null
    cat ${soilfile}.${jjj} ${tmpfile}.${jjj} >> tmp.${lsmfile}.${jjj}
  done
  
  cat "tmp.${lsmfile}".* >"${output}"
  #rm inv "${tmpfile}".* ${soilfile}* ${lsmfile}* tmp.${lsmfile}.*

}

__koirun "$@"
