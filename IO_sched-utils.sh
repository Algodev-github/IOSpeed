#!/bin/bash
#   Copyright (C) 2016 Luca Miccio <lucmiccio@gmail.com>

#   This program is free software: you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.

#   You should have received a copy of the GNU General Public License
#   along with this program.  If not, see <http://www.gnu.org/licenses/>.

# This file contains all the utility functions used by the IO_sched-speedtest.sh

# Input checkers
is_a_number() {
	local number=$1
	if [[ $number != '' &&  $number =~ ^-?[0-9]+$ ]];
	then
		: # No errors
	else
		echo "$number input not correct..."
		exit 1;
	fi
}


# Fiojobs file creator
create_test_file() {
	local RW_TYPE=$1
    local TIME=$2
    local DEV=$3
    local TEST_FILE=$4

	TEST_FILE=test_$RW_TYPE.fio

TEST_FILE_CONFIG="
[global]
bs=4k
ioengine=psync
iodepth=4
runtime=$TIME
direct=1
filename=/dev/$DEV
rw=$RW_TYPE
group_reporting=1"

	echo "$TEST_FILE_CONFIG" > $TEST_FILE

	MASK=1
	for i in `seq 1 $(nproc)`;
		do

JOB="
[job $i]
cpumask=$MASK
"
			 MASK=$((MASK*2))

		           echo "$JOB" >> $TEST_FILE
	   done
}

# Results saving

save_results(){
    RESULTS=()
    	file_count=0
    	while IFS='' read -r line || [[ -n "$line" ]]; do
    		RESULTS[$file_count]=$line
    		file_count=$((file_count+1))
    	done < $FILE_LOG
    echo  ${RESULTS[@]}

    # Create the results folder if it does not exist
    if [ ! -d $RESULTS_FOLDER ];then
            echo "Results folder does not exist. Creating it"
            mkdir $RESULTS_FOLDER
    fi

    # Show data in a table format and save them in a $OUTPUT_FILE
    rm $OUTPUT_FILE 2> /dev/null_blk
    echo
    echo Results
    echo "Unit of measure: KIOPS			Time: ${TIME}s		Device: $DEV" | tee $OUTPUT_FILE
    echo "Number of parallel threads: $N_CPU" | tee -a $OUTPUT_FILE
    {
    printf 'SCHEDULER\tSEQREAD\tSEQWRITE\tRANDREAD\tRANDWRITE\n'

    k=0
    for (( c=0; c<$N_SCHED; c++ ))
    do
    	read=$((k))
    	write=$((k+1))
    	randread=$((k+2))
    	randwrite=$((k+3))
    	printf '%s\t%s\t%s\t%s\t%s\n' "${SCHEDULERS[$c]}" "${RESULTS[$read]}" "${RESULTS[$write]}"\
    		"${RESULTS[$randread]}" "${RESULTS[$randwrite]}"
    	k=$((randwrite+1))
    done

    } | column -t -s $'\t'| tee  -a $OUTPUT_FILE

    echo | tee -a $OUTPUT_FILE

    echo "Results written in :" $OUTPUT_FILE
}
