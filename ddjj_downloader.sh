#!/bin/bash

# dependencies : wget gnumeric zenity

DATE=$(date +"%Y-%m-%d_%H-%M-%S")
OUTPUT_DIR=output_${DATE}/
OUTPUT_FILE=output.csv
HEADER='Empresa,"Nombre corto",Año,Mes,Cuenca,Provincia,Área,Yacimiento,"ID Pozo",Sigla,Form.Prod.,Cód.Propio,Nom.Propio,Prod.Men.Pet.(m3),Prod.Men.Gas(Mm3),Prod.Men.Agua(m3),Prod.Acum.Pet.(m3),Prod.Acum.Gas(Mm3),Prod.Acum.Agua(m3),Iny.Agua(m3),Iny.Gas(Mm3),Iny.CO2(Mm3),Iny.Otros(m3),RGP,"% de Agua",TEF,"Vida Útil",Sist.Extrac.,Est.Pozo,"Tipo Pozo",Clasificación,"Sub clasificación","Tipo de Recurso","Sub tipo de Recurso",Observaciones,Latitud,Longitud,Cota,Profundidad'

rm -rf $OUTPUT_DIR
mkdir $OUTPUT_DIR
cd $OUTPUT_DIR

# Company parameters
url="https://www.se.gob.ar/datosupstream/consulta_avanzada/listado.php"
wget "$url" --output-document="list.php"

cat list.php | \
	sed -n '/<select class="grande" name="idempresa">/,/<\/select>/p' | \
	head -n -1 | \
	tail -n +3 | \
	sed 's/^[ \t]*//' | \
	iconv -f latin1 -t utf-8 > \
	short_list.php

read_company_name() {
	short_names=$(cat short_list.php | sed -e 's/<option.*>\(.*\)<\/option>/FALSE\n\1/' | tr "\n" "|")
	IFS='|' read -ra NAMES <<< "$short_names"

	zenity --height=750 --width=500 \
		--list --checklist \
		--title "Selección de empresas" \
		--text "Seleccione items en la siguiente lista" \
		--column "" --column "Nombre de empresa" \
		"${NAMES[@]}"
}

if params=`read_company_name`; then
	IFS='|' read -ra LONG_NAMES <<< "$params"
else
	exit
fi

get_short_name() {
	long_name=$1
	grep "$long_name" short_list.php | \
		sed -e 's/.*value="\(.*\)".*/\1/'
}

idempresa_list=""
for ((i = 0; i < ${#LONG_NAMES[@]}; i++)) do
	new_id=$(get_short_name "${LONG_NAMES[$i]}")
    idempresa_list="$idempresa_list|$new_id"
done

idempresa_list=$(echo $idempresa_list | tail -c +2)
IFS='|' read -ra ID_EMPRESA <<< "$idempresa_list"

# Date parameters
read_params() {
	zenity \
		--forms \
		--title="Selección de fechas" \
		--text="Ingrese los siguientes parámetros" \
		--add-entry "Año desde" \
		--add-entry "Mes desde"  \
		--add-entry "Año hasta" \
		--add-entry "Mes hasta"
}

if params=`read_params`; then
	IFS='|' read -ra PARAMS <<< "$params"
else
	exit
fi

year_from=${PARAMS[0]}
month_from=${PARAMS[1]}
year_to=${PARAMS[2]}
month_to=${PARAMS[3]}

error() {
	zenity --error --text="$1"
	exit
}

if [ "$year_from" -gt "$year_to" ]; then error "Rango incorrecto"; fi
if [ "$month_from" -lt "1" ] || [ "$month_from" -gt "12" ]; then error "Rango incorrecto"; fi
if [ "$month_to" -lt "1" ] || [ "$month_to" -gt "12" ]; then error "Rango incorrecto"; fi
if [ "$year_from" -eq "$year_to" ]; then
	if [ "$month_from" -gt "$month_to" ]; then error "Rango incorrecto"; fi
fi

# Lets do some real work!
download() {
	idempresa=$1
	idanio=$2
	idmes=$3

	url="http://wvw.se.gob.ar/datosupstream/consulta_avanzada/ddjj.xls.php?idempresa=$idempresa&idmes=$idmes&idanio=$idanio"
	file="$idempresa-$idanio-$idmes"
	(wget "$url" --output-document="$file.xls" && ssconvert "$file.xls" "$file.csv")
}

merge() {
	idempresa=$1
	long_name_empresa=$2
	idanio=$3
	idmes=$4

	file="$idempresa-$idanio-$idmes"
	prefix="$long_name_empresa,$idempresa,$idanio,$idmes,"

	#if [ -z ${init_flag} ]; then
		#head -n 1 "$file.csv" | sed -e "s/^/Empresa,Año,Mes,/" >> "$output"
		#init_flag="ON"
	#fi

	tail -n +2 "$file.csv" | sed -e "s/^/$prefix/" >> "$OUTPUT_FILE"
}

progress() {
	zenity --progress \
	  --auto-close \
	  title="Generando archivo" \
	  text="Aguarde mientras su archivo está siendo generado..." \
	  percentage=0
}

echo "${HEADER}" > "$OUTPUT_FILE"

work() {
	for ((i = 0; i < ${#ID_EMPRESA[@]}; i++)) do

		percent=$(awk "BEGIN { pc=100*${i}/${#ID_EMPRESA[@]}; i=int(pc); print (pc-i<0.5)?i:i+1 }")
		echo "$percent"

		idempresa="${ID_EMPRESA[$i]}"
		if [ -z "${idempresa}" ]; then
			continue
		fi
		long_name_empresa="${LONG_NAMES[$i]}"

		# Download
		for idanio in `seq $year_from $year_to`; do
			if [ "$idanio" -eq "$year_from" ]; then
				if [ "$idanio" -eq "$year_to" ]; then
					for idmes in `seq $month_from $month_to`; do
						download "$idempresa" "$idanio" "$idmes"
					done
				else
					for idmes in `seq $month_from 12`; do
						download "$idempresa" "$idanio" "$idmes"
					done
				fi
			elif [ "$idanio" -eq "$year_to" ]; then
				for idmes in `seq 1 $month_to`; do
					download "$idempresa" "$idanio" "$idmes"
				done
			else
				for idmes in `seq 1 12`; do
					download "$idempresa" "$idanio" "$idmes"
				done
			fi
		done

		# Merge
		for idanio in `seq $year_from $year_to`; do
			if [ "$idanio" -eq "$year_from" ]; then
				if [ "$idanio" -eq "$year_to" ]; then
					for idmes in `seq $month_from $month_to`; do
						merge "$idempresa" "$long_name_empresa" "$idanio" "$idmes"
					done
				else
					for idmes in `seq $month_from 12`; do
						merge "$idempresa" "$long_name_empresa" "$idanio" "$idmes"
					done
				fi
			elif [ "$idanio" -eq "$year_to" ]; then
				for idmes in `seq 1 $month_to`; do
					merge "$idempresa" "$long_name_empresa" "$idanio" "$idmes"
				done
			else
				for idmes in `seq 1 12`; do
					merge "$idempresa" "$long_name_empresa" "$idanio" "$idmes"
				done
			fi
		done

	done #\idempresa
}

work | progress

cp $OUTPUT_FILE ../output_${DATE}.csv

zenity --info --text="Exito! Su archivo se ha generado en output_${DATE}.csv"
