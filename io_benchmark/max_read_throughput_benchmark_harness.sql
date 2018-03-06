--------------------------------------------------------------------------------
--
-- File name:   max_read_throughput_benchmark_harness.sql
--
-- Version:     1.0 (January 2018)
--
--              Tested with client version SQL*Plus 11.2.0.1 and 12.2.0.1
--              Tested with server versions 11.2.0.4, 12.1.0.2 and 12.2.0.1
--
-- Author:      Randolf Geist
--              http://www.oracle-performance.de
--
-- Purpose:     Run concurrent sessions that perform physical read multi block I/O mostly, report achieved I/O throughput rate
--
--              The script is supposed (!) to cope with all configurations: Windows / Unix / Linux, Single Instance / RAC, Standard / Enterprise Edition, PDB / Non-PDB, Non-Exadata / Exadata
--              But since this is 1.0 version it obviously wasn't tested in all possible combinations / configurations, so expect some glitches
--              Feedback and ideas how to improve are welcome
--
-- Parameters:  Optionally pass number of slaves as first parameter, default 8
--              Optionally pass the testtype, default "ASYNC" which means asynchronous (bypassing buffer cache) I/O ("direct path read" / "cell smart table/index scan" on Exadata), other valid options: "SYNC" which means synchronous I/O ("db file scattered read" / "cell multiblock physical read" on Exadats)
--              Optionally pass sizing of the tables, default 1.000.000 rows / blocks per table created per slave. So with 8 slaves this is 8 M blocks, which is 64 GB at 8 KB block size
--
--              For synchronous / buffered I/O the buffer cache used (see below) should be much smaller, otherwise more logical than physical I/O will be performed
--
--              Optionally pass the tablespace name for the tables, default is no tablespace specification. If required add a storage specification here to put the objects into some none default buffer cache, like keep or recycle pool
--              This could look like "xyz storage (buffer_pool recycle)" which will then be prepended with "TABLESPACE" by the script. Note that you need to put the parameter in double qoutes since it contains blanks otherwise it won't be recognized as a single parameter.
--
--              Optionally pass the time to wait before taking another snapshot and killing the sessions, default 600 seconds / 10 minutes
--
--              If you want the final query on Sys Metrics to show anything useful you need to use a minimum runtime of 120 seconds to ensure that there is at least a single 60 seconds snapshot period completed for SysMetric history
--
--              Optionally pass the connect string to use (no leading @ sign please), default is nothing, so whatever is configured as local connection gets used
--              Optionally pass the user, default is current_user. Don't use SYS resp. SYSDBA for this, but a dedicated user / schema
--              Optionally pass the password of the (current) user, default is lower(user)
--              Optionally pass the OS of this client ("Windows" or anything else), default is derived from V$VERSION (but this is then the database OS, not necessarily the client OS and assumes SQL*Plus runs on database server)
--              Optionally pass the parallel degree to use when creating the objects, can be helpful on Enterprise Edition when creating very large objects, default is degree 1 (serial)
--              Optionally pass the type of performance report to generate, either "AWR" or "STATSPACK" or "NONE" for no report at all. Default is derived from V$VERSION, "Enterprise Edition" defaults to "AWR", otherwise "STATSPACK"
--
-- Example:     @max_read_throughput_benchmark_harness 4 SYNC 10000 "test_8k storage (buffer_pool recycle)" 120
--
--              This means: Start four slaves, use the synchronous I/O mode, table size will be 10.000 rows / blocks each for the four tables created, use tablespace test_8k and put objects in recycle buffer cache, run the slaves for 120 seconds
--
-- Prereq:      User needs execute privilege on DBMS_LOCK
--              User needs execute privilege on DBMS_WORKLOAD_REPOSITORY for automatic AWR report generation - assumes a Diagnostic Pack license is available
--              User needs execute privilege on PERFSTAT.STATSPACK for automatic STATSPACK report generation
--              User should have either execute privilege on DBMS_SYSTEM to cancel or alternatively ALTER SYSTEM KILL SESSION privilege to be able to kill the sessions launched
--              Otherwise you have to wait for them to gracefully shutdown (depending on the execution time of a single query execution this might take longer than the time specified)
--
--              For synchronous I/O the tablespace used should be assigned to a small buffer cache (e.g. use non-default block size like 16K or use a non-default buffer cache like keep or recycle (see above how to specify a "storage" definition) and assign smallest possible cache size)
--              otherwise mixture of logical and physical I/O might happen, not maximising physical I/O
--
--              If you want to test with large buffer cache and/or suspect caching effects on lower storage layers (or even O/S file system layer) you can create large objects, and use "px_degree" > 1 to speed up object creation
--              The script currently supports up to 100 M rows / blocks table / index per slave, which is 800 GB per object using 8 KB block size
--              You can easily go larger by adjusting the object generator1/2 queries below, note the "px_degree" option to speed up object creation using Parallel Execution on Enterprise Edition
--
--              SELECT privileges on
--              GV$EVENT_HISTOGRAM_MICRO
--              V$SESSION
--              GV$SESSION
--              V$INSTANCE
--              GV$INSTANCE
--              V$DATABASE
--              AWR_PDB_SNAPSHOT (12.2 PDB)
--              DBA_HIST_SNAPSHOT
--              GV$CON_SYSMETRIC_HISTORY (12.2 PDB)
--              GV$SYSMETRIC_HISTORY
--
-- Notes:       The script can make use of AWR views and calls to DBMS_WORKLOAD_REPOSITORY when using the AWR report option. Please ensure that you have either a Diagnostic Pack license or don't use AWR / switched off AWR functionality via the CONTROL_MANAGEMENT_PACK_ACCESS parameter
--              The script ia aware of RAC and generates a GLOBAL AWR report for RAC runs, also shows IOPS per instance and total at the end in such a case
--
--              On Unix/Linux the script makes use of the "xdg-open" utility to open the generated HTML AWR / STATSPACK TXT report ("start" command gets used on Windows)
--              This requires the "xdg-utils" package to be installed on the system
--
--              In addition to the tables created and dropped for running the benchmark, from 12.1 on the script will create two snapshots of GV$EVENT_HISTOGRAM_MICRO
--              called EVENT_HISTOGRAM_MICRO1 and EVENT_HISTOGRAM_MICRO2. These tables will remain after the run and can be used to get a nice and more granular histogram
--              of multi block read synchronous latencies using a query similar to the following:
                /*
                select
                        inst_id
                      , event
                      , wait_time
                      , count
                      , round(ratio_to_report(count) over (partition by inst_id, event) * 100, 1) as percent
                      , rpad('#', round(ratio_to_report(count) over (partition by inst_id, event) * 24, 1), '#') as percent_graph
                from (
                select '<= ' || a.wait_time_format as wait_time, b.wait_count - a.wait_count as count, a.wait_time_micro, a.event, a.inst_id
                from event_histogram_micro1 a, event_histogram_micro2 b
                where a.wait_time_micro = b.wait_time_micro
                and a.event = b.event
                and b.wait_count - a.wait_count > 0
                and a.inst_id = b.inst_id
                )
                order by inst_id, event, wait_time_micro;
                */
--------------------------------------------------------------------------------

set echo on timing on verify on time on

define default_testtype = "ASYNC"
define default_tab_size = "1000000"

@@common/evaluate_parameters

@@common/create_multi_block_benchmark_objects

define slave_name = "max_read_throughput_benchmark"

@@common/create_launch_slave_script

define ehm_instance = 1

@@common/create_event_histogram_micro_multi_block_snapshot

@@common/launch_slaves_generate_snapshots

define ehm_instance = 2

@@common/create_event_histogram_micro_multi_block_snapshot

define action = "SQLPMB"

@@common/cancel_kill_slave_sessions

@@common/cleanup_multi_block_benchmark_objects

@@common/generate_performance_report

@@common/launch_performance_report

column metric_name format a40
column max_mb_val format 999g999g999
column min_mb_val format 999g999g999
column avg_mb_val format 999g999g999
column med_mb_val format 999g999g999

-- Display Throughput information from Sys Metrics
with base as
(
select * from &metric_view
where
begin_time >= timestamp '&start_time' and end_time <= timestamp '&end_time'
and metric_name in ('Physical Read Bytes Per Sec', 'Physical Read Total Bytes Per Sec')
),
step1 as
(
select * from base where metric_name = 'Physical Read Bytes Per Sec'
union all
select * from base where metric_name = 'Physical Read Total Bytes Per Sec'
and not exists (select null from base where metric_name = 'Physical Read Bytes Per Sec')
)
select
&group_by_instance       coalesce(to_char(inst_id, 'TM'), 'TOTAL') as inst_id,
       metric_name
     , count(*) as cnt
     , round(max(value)/1024/1024) as max_mb_val
     , round(min(value)/1024/1024) as min_mb_val
     , round(avg(value)/1024/1024) as avg_mb_val
     , round(median(value)/1024/1024) as med_mb_val
from
       step1
group by
       metric_name
&group_by_instance     , grouping sets((), inst_id)
;
