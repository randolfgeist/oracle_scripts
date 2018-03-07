--------------------------------------------------------------------------------
--
-- File name:   max_write_throughput_benchmark_harness.sql
--
-- Version:     1.0 (January 2018)
--
--              Tested with client version SQL*Plus 11.2.0.1 and 12.2.0.1
--              Tested with server versions 11.2.0.4, 12.1.0.2 and 12.2.0.1
--
--              This tool is free but comes with no warranty at all - use at your own risk
--
-- Author:      Randolf Geist
--              http://www.oracle-performance.de
--
-- Links:       You can find more information about this tool on my blog:
--
--              http://oracle-randolf.blogspot.com/search/label/io_benchmark
--
--              There is also a brief tutorial on my Youtube channel how to use:
--
--              https://www.youtube.com/c/RandolfGeist
--
-- Purpose:     Run concurrent sessions that perform physical direct write I/O mostly, report achieved throughput write rate
--
--              The script is supposed (!) to cope with all configurations: Windows / Unix / Linux, Single Instance / RAC, Standard / Enterprise Edition, PDB / Non-PDB, Non-Exadata / Exadata
--              But since this is 1.0 version it obviously wasn't tested in all possible combinations / configurations, so expect some glitches
--              Feedback and ideas how to improve are welcome
--
-- Parameters:  Optionally pass number of slaves as first parameter, default 8
--              Optionally pass the testtype, currently unused
--              Optionally pass sizing of the tables, default 16.000 rows resp. blocks per table per slave
--
--              This means 16.000 blocks per slave, so for 8 slaves the objects require approx. 128.000 blocks, which is approx. 1 GB at 8 KB block size
--
--              Optionally pass the tablespace name for the tables, default is no tablespace specification.
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
-- Example:     @max_write_throughput_benchmark_harness 4 NA 8000 "test_8k storage (buffer_pool recycle)" 120
--
--              This means: Start four slaves, table size will be 8.000 rows / blocks, use tablespace test_8k and put objects in recycle buffer cache, run the slaves for 120 seconds
--
-- Prereq:      User needs execute privilege on DBMS_LOCK
--              User needs execute privilege on DBMS_WORKLOAD_REPOSITORY for automatic AWR report generation - assumes a Diagnostic Pack license is available
--              User needs execute privilege on PERFSTAT.STATSPACK for automatic STATSPACK report generation
--              User should have either execute privilege on DBMS_SYSTEM to cancel or alternatively ALTER SYSTEM KILL SESSION privilege to be able to kill the sessions launched
--              Otherwise you have to wait for them to gracefully shutdown (depending on the execution time of a single query execution this might take longer than the time specified)
--
--              The script currently supports up to 10 M rows / blocks per table per slave, which is 8 GB per object using 8 KB block size
--              You can easily go larger by adjusting the object generator1/2 queries in the slave script called, note the "px_degree" option to using Parallel Execution on Enterprise Edition, not required / much tested though
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
--              The script ia aware of RAC and generates a GLOBAL AWR report for RAC runs, also shows throughput per instance and total at the end in such a case
--
--              On Unix/Linux the script makes use of the "xdg-open" utility to open the generated HTML AWR / STATSPACK TXT report ("start" command gets used on Windows)
--              This requires the "xdg-utils" package to be installed on the system
--
--------------------------------------------------------------------------------

set echo on timing on verify on time on

define default_testtype = "NA"
define default_tab_size = "16000"

@@common/evaluate_parameters

define slave_name = "max_write_throughput_benchmark"

@@common/create_write_throughput_launch_slave_script

@@common/launch_slaves_generate_snapshots

define action = "SQLPWMB"

@@common/cancel_kill_slave_sessions

@@common/cleanup_multi_block_benchmark_objects

@@common/generate_performance_report

@@common/launch_performance_report

column metric_name format a40
column max_val format 999g999g999
column min_val format 999g999g999
column avg_val format 999g999g999
column med_val format 999g999g999

-- Display Throughput information from Sys Metrics
with base as
(
select * from &metric_view
where
begin_time >= timestamp '&start_time' and end_time <= timestamp '&end_time'
and metric_name in ('Physical Write Bytes Per Sec', 'Physical Write Total Bytes Per Sec')
),
step1 as
(
select * from base where metric_name = 'Physical Write Bytes Per Sec'
union all
select * from base where metric_name = 'Physical Write Total Bytes Per Sec'
and not exists (select null from base where metric_name = 'Physical Write Bytes Per Sec')
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
