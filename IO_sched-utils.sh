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

## Input checkers

# Check if the value passed to this function is
# a number.
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

check_if_value_in () {
	local value=$1
	shift

	local in=1 # default we have no match
	for element in "$@"; do
        if [ "$element" == "$value" ]; then
            in=0
            break
        fi
    done

	if [ $in -eq 1 ]; then
		echo "ERROR: no value $value found in \""$@"\". Aborting."
		exit 1
	fi
}
# Check if the test parameters are correct and not empty
check_parameters() {

	local AVAILABLE_TYPE=(read write randread randwrite)

	if [ ${#SCHEDULERS[@]} -eq 0 ]; then
		echo "WARNING: no scheduler found. Aborting test"
		exit 1
	fi
	# Check if the scheduler(s) inserted are available
	for sched in "${SCHEDULERS[@]}"; do
		check_if_value_in "$sched" "${AVAILABLE_SCHED[@]}"
	done

	if [ ${#TEST_TYPE[@]} -eq 0 ]; then
		echo "WARNING: no type found. Aborting test"
		exit 1
	fi

	# Check if the scheduler(s) inserted are available
	for type in "${TEST_TYPE[@]}"; do
		check_if_value_in "$type" "${AVAILABLE_TYPE[@]}"
	done
}

### Fiojobs file creator

# Create the fiojob file
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


### Results saving

# Create the correct header for the output
# depending on the type test executed
HEADER=""
create_header() {
	HEADER="SCHEDULER\t"
	for test_type in ${TEST_TYPE[@]}; do

	        case "$test_type" in
	                read)
	                        test_type="SEQREAD\t"
	                        ;;
	                write)
	                        test_type="SEQWRITE\t"
	                        ;;
	                randread)
	                        test_type="RANDREAD\t"
	                        ;;
	                randwrite)
	                        test_type="RANDWRITE\t"
	                        ;;
	                *)
	                        echo "ERROR"
	                        exit 1
	        esac
	        header=$HEADER$test_type
	done
}

# Save the results
save_results() {
	RESULTS=()
	        file_count=0
	        while IFS='' read -r line || [[ -n "$line" ]]; do
	                RESULTS[$file_count]=$line
	                file_count=$((file_count+1))
	        done < $FILE_LOG

	create_header

	# Show data in a table format and save them in a $OUTPUT_FILE
	if [ ! -d $RESULTS_FOLDER ];then
	        echo "Results folder does not exist. Creating it"
	        mkdir $RESULTS_FOLDER
	fi

	rm $OUTPUT_FILE
	echo
	echo Results
	echo "Unit of measure: KIOPS                    Time: ${TIME}s          Device: $DEV" | tee $OUTPUT_FILE
	echo -n "Number of parallel threads: $N_CPU" | tee -a $OUTPUT_FILE
	echo -e "\tNumber of cpu core(s): $(nproc)\n"| tee -a $OUTPUT_FILE
	{
	printf $header'\n'

	k=0
	index=0
	for (( c=0; c<$N_SCHED; c++ ))
	do
	        local_index=1
	        for t in ${TEST_TYPE[@]};do
	                declare "test_${local_index}_value"=${RESULTS[$index]}
	                index=$((index+1))
	                local_index=$((local_index+1))
	        done

	        printf '%s\t%s\t%s\t%s\t%s\n' "${SCHEDULERS[$c]}" "$test_1_value" "$test_2_value"\
	                "$test_3_value" "$test_4_value"
	        k=$((n_k+1))
	done

	} | column -t -s $'\t'| tee  -a $OUTPUT_FILE

	echo | tee -a $OUTPUT_FILE

	echo "Results written in :" $OUTPUT_FILE
}
