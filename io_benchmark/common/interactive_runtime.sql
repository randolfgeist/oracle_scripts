prompt
prompt Specify runtime of the benchmark in seconds, default is 600 seconds / 10 minutes.
prompt You need at least 120 seconds runtime to have the final query that displays information about the benchmark result show something meaningful.
prompt You can use shorter runtimes but then you'll have to resort to the AWR/STATSPACK report generated for information about the I/O figures.
prompt

accept num_seconds default '600' prompt 'Enter number of seconds to run (default 600): '
