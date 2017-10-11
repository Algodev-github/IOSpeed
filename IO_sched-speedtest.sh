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

# Set this value to 1 to enable debug mode(more on help section), 0 otherwise
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
TIME: 60, N° Threads: $(nproc)

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

# Source the utils
. ./IO_sched-utils.sh

# Check if the user is root
USER=$(whoami)
if [[ "$USER" != 'root' ]]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

# Remove temporary files and disable null_blk module
function clean
{
	echo "Removing garbage..."
    rm -f $SCHED_LOG $FILE_LOG test_*.fio 2> /dev/null
    echo "Removing null block module..."
    modprobe -r null_blk 2> /dev/null
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
RESULTS_FOLDER="results/"
OUTPUT_FILE="${RESULTS_FOLDER}io_speed_results-${TIME}s-${N_CPU}t.txt"

# Check inputs
is_a_number "$TIME"

if [ "$N_CPU" == '' ]; then
	N_CPU=1
fi

is_a_number "$N_CPU"


# Debug section
if [ $DEBUG -eq 1 ]; then #debug active
	echo "DEBUG MODE ENABLED"
	TEST_TYPE=($4)
fi

echo "Creating test files..."
for type in "${TEST_TYPE[@]}"
do
	rm -f test_${type}.fio
	create_test_file $type $TIME $DEV $TEST_FILE
done

# Check if there is an old null_blk module.
# If it is enabled, replace it with the correct one.
lsmod | grep null_blk > /dev/null

echo "Creating null_blk device..."
if [ $? -eq 0 ];
then
	modprobe -r null_blk 2> /dev/null
	if [ $? -eq 0 ]; # null_blk is not a module but built-in
		echo "ERROR: problem with the null_blk module"
		echo "CHECK: Null block is probably built in. Not supported yet. Aborting"
		exit 1
	fi
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
SCHEDS=$(cat /sys/block/$CUR_DEV/queue/scheduler)

# remove parentheses
SCHEDS=$(echo $SCHEDS | sed 's/\[//')
SCHEDS=$(echo $SCHEDS | sed 's/\]//')
IFS=' ' read -r -a SCHEDULERS <<< "$SCHEDS"
IFS=' ' read -r -a AVAILABLE_SCHED <<< "$SCHEDS"


if [ $DEBUG -eq 1 ]; then # Debug active
        SCHEDULERS=($3)
	echo "DEBUG: Overriding scheduler"
	echo "DEBUG: Using schedulers -> ( ${SCHEDULERS[@]} )"

fi

# Check Parameters before test
check_parameters

setup_cpu_governor "performance"

echo "Using schedulers: ${SCHEDULERS[@]}"

echo "Test type: ${TEST_TYPE[@]}"

modprobe null_blk queue_mode=$Q_MODE irqmode=0 completion_nsec=0 nr_devices=1

echo
echo Starting tests ...

touch $FILE_LOG
# Main test loop
N_SCHED=${#SCHEDULERS[@]}
for sched in "${SCHEDULERS[@]}"
do
	# Change scheduler of the device if needed
	echo $sched > /sys/block/$DEV/queue/scheduler 2> /dev/null

	# If we are using the BFQ I/O scheduler set the low_latency and
	# the slice_idle parameters to 0 so that we can achieve the
	# maximum throughput with BFQ.
	# N.B: For a complete and deeper analysis these values would be
	# set to their defaults.
	if [ "$sched" == "bfq" ]; then
                echo "BFQ detected: Disabling low_latency and slice idle"
                echo 0 > /sys/block/$DEV/queue/iosched/low_latency
                echo 0 > /sys/block/$DEV/queue/iosched/slice_idle
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

# Save results, clean all files and exit
save_results
clean
exit 0
