--------------------------------------------------------------------------------
--
-- File name:   max_write_throughput_benchmark_interactive.sql
--
-- Version:     1.02 (September 2018)
--
--              Tested with client version SQL*Plus 11.2.0.1 and 12.2.0.1
--              Tested with server versions 11.2.0.4, 12.1.0.2, 12.2.0.1 and 18.0.0.0
--
-- Author:      Randolf Geist
--              http://www.oracle-performance.de
--
-- Purpose:     Run concurrent sessions that perform physical direct write multi block I/O mostly, report achieved I/O throughput rate
--              This script asks for parameters to call then "max_write_throughput_benchmark_harness.sql"
--------------------------------------------------------------------------------

set echo off verify off linesize 200 tab off

prompt
prompt This script asks for parameters to call then the actual benchmark script "max_write_throughput_benchmark_harness.sql"
prompt which runs concurrent sessions performing physical direct write multi block I/O mostly to report achieved I/O throughput rate
@@common/interactive_common_prompt_1
prompt
prompt Currently the script supports up to 100.000.000 blocks per object, that is 800 GB at 8 KB block size per table per slave,
prompt so when using 8 slaves that is 6.400 GB.
prompt Probably you want to use more slaves when testing with such a large buffer cache, so can scale up accordingly,
prompt 32 slaves would mean 25 TB already.
prompt Of course this means you need that much space available in the target tablespace and the generation will take a while.
prompt By modifying the script "max_write_throughput_benchmark_slave.sql" you can easily create objects larger than 100.000.000 blocks.
prompt
prompt You'll now be prompted several questions and shown some information about required and available space.
prompt

@@common/interactive_ask_user_drop

@@common/interactive_tablespaces

@@common/interactive_num_slaves

prompt
prompt Enter number of blocks per process table
prompt

accept num_rows default '16000' prompt 'Number of blocks per process table (default 16.000): '

column blocks_req_fm new_value blocks_req_fm noprint
column blocks_req new_value blocks_req noprint

select to_char(&num_rows * &num_slaves, 'FM999G999G999') as blocks_req_fm, &num_rows * &num_slaves as blocks_req from dual;

prompt With &num_slaves slaves and &num_rows blocks per table this means you'll need approx. &blocks_req_fm blocks in the target tablespace.
prompt

@@common/interactive_target_tablespace

@@common/interactive_temporary_tablespace

@@common/interactive_runtime

@@common/interactive_connect_string

prompt
prompt For the CTAS operation this script can make use of Parallel Execution on Enterprise Edition
prompt Default is to use serial execution (degree 1), enter a degree > 1 to make use of Parallel Execution during object creation
prompt

accept px_degree default '1' prompt 'Enter Parallel Degree to use for object creation (default 1): '

@@common/interactive_os_name

@@common/interactive_performance_report

@@common/interactive_common_summary

@@common/interactive_create_user

@@common/interactive_connect_user

@@max_write_throughput_benchmark_harness &num_slaves NA &num_rows "&tablespace_name" &num_seconds "&connect_string" &username "&pwd" "&os_name" &px_degree "&perf_report"
