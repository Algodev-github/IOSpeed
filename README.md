# IO Speedtest
This test script is designed to measure the performance of I/O
schedulers and it supports both blk and blk-mq. The script automatically
checks whether blk or blk-mq is in use, and measures performance
with all available schedulers.

More information about the test and its goals are in IO_sched-speedtest.txt file.
#Usage
1. Go into the IOSpeed folder using the terminal
2. Run the IO_sched-speedtest.sh script under root permissions

Execute **./IO_sched-speedtest.sh -h** for more options.

N.B: The debug options is enabled by default. For more information
about this option see the help section or the variable comments in
the IO_sched-speedtest file.

##  Info
For more information about Algodev group and its projects visit out [site](http://algo.ing.unimo.it/algodev/projects.php)
## License
This program is under [GNU General Public License](https://www.gnu.org/licenses/gpl-3.0-standalone.html)
