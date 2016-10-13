#IO Speedtest
This test is designed to measure the performance of I/O schedulers,
especially of [BFQ] (http://algo.ing.unimo.it/people/paolo/disk_sched/),
in the prospect of a possible integration in
blk-mq. The test exercises only blk, as existing I/O schedulers are
currently available only in blk.
It is possibile to run the test also if blk-mq is enabled on the system.

More information about the test and its goals are in IO_sched-speedtest.txt file.
#Usage
1. Go into the IOSpeed folder using the terminal
2. Run the IO_sched-speedtest.sh script under root permissions

Execute **./IO_sched-speedtest.sh -h** for more information about options.

#Info
For more information about Algodev group and its projects visit out [site](http://algo.ing.unimo.it/algodev/projects.php)
#License
This program is under [GNU General Public License](https://www.gnu.org/licenses/gpl-3.0-standalone.html)
