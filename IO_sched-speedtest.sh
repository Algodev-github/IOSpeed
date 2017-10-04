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

DEBUG=1

# Help section
display_help() {
HELP_MESSAGE="$APP_NAME
This script is intended to measure the maximum number of IOPS achievable
with each of the available I/O schedulers. To this purpose, this script uses
fio and null_blk (configured wih zero latency, see below for more details).
Four types of tests are executed, based on I/O types:
SEQREAD - SEQWRITE - RANDREAD - RANDWRITE

USAGE (as root):

$APP_NAME time n_threads

Where:
- time(seconds): how long it takes for every IO type test.
- n_threads: number of threads to spawn for each IO type test
- h|--help: display this help message

EXAMPLE: $APP_NAME 30 4
Launch the test for 30 seconds with the /dev/nullb0 device using 4 threads
for each fio's jobs.

Debug mode:
The debug mode can be enabled by setting the DEBUG variable in the file.
Usage (as root):
$APP_NAME time n_threads \"schedulers\" \"test_type\"

Where:
- schedulers: list of the schedulers to test
- test_type: list of the type of test
	Available types: read, write, randread, randwrite
The others options have the same meaning as the \"no debug\" mode.

EXAMPLE: $APP_NAME 30 4 \"bfq mq-deadline\" \"read write\"
Launch the test for 30 seconds with the /dev/nullb0 device using 4 threads
for each fio's jobs and use only the selecte I/O schedulers and testing
only sequential read and sequential write.

DEFAULT VALUES:
TIME: 60, N° Threads: $N_CPU

CONFIGURATION USED FOR NULL_BLK
The null_blk device created by the test has the following settings:
- queue_mode=1|2
- irqmode=0
- completion_nsec=0
- nr_devices=1

AUTHOR:
Luca Miccio <lucmiccio@gmail.com>" 

echo "$HELP_MESSAGE"
}

if [[ "$1" = '-h'|| "$1" = '--help' ]];
then
	display_help
	exit 0
fi

# Check if the user is root
USER=$(whoami)
if [[ "$USER" != 'root' ]]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

# Remove temporaty files
function clean
{
	rm -f $SCHED_LOG $FILE_LOG test_*.fio
}

# Handle SIGINT - SIGTERM - SIGKILL
trap_func() {
	clean
	echo
	echo "WARNING: Tests interrupted..."
	exit 1
}

trap trap_func SIGINT SIGTERM SIGKILL

# Parameters
APP_NAME="IO_sched-speedtest.sh"
TIME=${1-60} # Seconds: 60 is the minimum value that does not cause
	     # high fluctuations in results

OUTPUT_FILE="max_blk_speed${TIME}s.txt"
DEV="nullb0"
TEST_TYPE=(read write randread randwrite)
N_CPUCALC=$(grep "cpu cores" /proc/cpuinfo | tail -n 1 | sed 's/.*\([0-9]\)/\1/')
N_CPU=${2-$N_CPUCALC}
FILE_LOG=file.log
SCHED_LOG=log
BLK_MQ_SCHED="blk-mq"

# Check inputs
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

is_a_number "$TIME"

if [ "$N_CPU" == '' ]
then 
	N_CPU=1
fi

is_a_number "$N_CPU"


# Create fio's Jobfiles
create_test_file() {
	local RW_TYPE=$1

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
group_reporting=1
"

	echo "$TEST_FILE_CONFIG" > $TEST_FILE

	MASK=1
	for i in `seq 1 $N_CPU`;
		do
	
JOB="
[job $i]
cpumask=$MASK
"       
		if [ $MASK -ne $(nproc) ];then     
			MASK=$((MASK*2))
		fi
		echo "$JOB" >> $TEST_FILE    
	        done  
}

# Debug section
if [ $DEBUG -eq 1 ]; then #debug active
	echo "DEBUG MODE ENABLED"
	TEST_TYPE=($4)
fi

echo "Creating test files..."
for type in "${TEST_TYPE[@]}"
do
	rm -f test_${type}.fio
	create_test_file $type
done

# Check if there is an old null_blk module.
# If it is enabled, replace it with the correct one.
lsmod | grep null_blk > /dev/null

echo "Creating null_blk device..."
if [ $? -eq 0 ];
then 
	modprobe -r null_blk
fi

Q_MODE=1 # Default queue_mode=1 single queue
CUR_DEV=$(basename `mount | grep "on / " | cut -f 1 -d " "` | sed 's/\(...\).*/\1/g')

# Check if blk-mq is enabled
if [ -d /sys/block/$CUR_DEV/mq ];
then 
	Q_MODE=2
	echo "Blk-mq enabled. Switching to multi-queue mode."
fi

# Check available schedulers
echo -n "Using schedulers: "
SCHEDS=$(cat /sys/block/$CUR_DEV/queue/scheduler)

# remove parentheses
SCHEDS=$(echo $SCHEDS | sed 's/\[//')
SCHEDS=$(echo $SCHEDS | sed 's/\]//')
IFS=' ' read -r -a SCHEDULERS <<< "$SCHEDS"

if [ $DEBUG -eq 1 ]; then #debug active
        SCHEDULERS=($3)
	echo "${SCHEDULERS[@]}"
	echo "DEBUG: Overriding scheduler"
	echo "DEBUG: Using schedulers -> ( ${SCHEDULERS[@]} )"
elif
	echo "${SCHEDULERS[@]}"
fi

echo "Test type: ${TEST_TYPE[@]}"

modprobe null_blk queue_mode=$Q_MODE irqmode=0 completion_nsec=0 nr_devices=1

echo
echo Starting tests ...

# Main test loop
N_SCHED=${#SCHEDULERS[@]}
for sched in "${SCHEDULERS[@]}"
do	
	# Change scheduler of the device if needed
	if [ $sched != $BLK_MQ_SCHED ];
	then
		echo $sched > /sys/block/$DEV/queue/scheduler 2> /dev/null 
	fi

	current_rep=1
	for test_type in "${TEST_TYPE[@]}"
	do
		# Invoke test
		echo "Scheduler: $sched - test $current_rep/4 ($test_type) - Number of parallel threads: $N_CPU - Duration ${TIME}s"
		fio test_${test_type}.fio --output=$SCHED_LOG
		OUTPUT=$(less $SCHED_LOG | grep -Eho 'iops=[^[:space:]]*' | cut -d '=' -f 2 | sed 's/.$//')

		# Format output value to KIOPs
		if [ ${OUTPUT: -1} != 'K' ];
		then
			OUTPUT=$(echo "$OUTPUT / 1000"| bc)K
		fi

        echo $OUTPUT >> $FILE_LOG
		current_rep=$((current_rep+1))
		echo
	done
done

# Save results
RESULTS=()
	file_count=0
	while IFS='' read -r line || [[ -n "$line" ]]; do
		RESULTS[$file_count]=$line
		file_count=$((file_count+1))
	done < $FILE_LOG
echo  ${RESULTS[@]}


# Show data in a table format and save them in a $OUTPUT_FILE
rm $OUTPUT_FILE
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

clean
