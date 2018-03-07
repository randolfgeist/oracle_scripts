--------------------------------------------------------------------------------
--
-- File name:   max_write_iops_benchmark_interactive.sql
--
-- Version:     1.0 (March 2018)
--
--              Tested with client version SQL*Plus 11.2.0.1 and 12.2.0.1
--              Tested with server versions 11.2.0.4, 12.1.0.2 and 12.2.0.1
--
-- Author:      Randolf Geist
--              http://www.oracle-performance.de
--
-- Purpose:     Run concurrent sessions that perform physical read and write I/O mostly, report achieved IOPS read and write rate
--              This script asks for parameters to call then "max_write_iops_benchmark_harness.sql"
--------------------------------------------------------------------------------

set echo off verify off linesize 200 tab off

prompt
prompt This script asks for parameters to call then the actual benchmark script "max_write_iops_benchmark_harness.sql"
prompt which runs concurrent sessions performing physical read and write I/O mostly, report achieved IOPS read and write rate
@@common/interactive_common_prompt_1
prompt
prompt If you want a mixture of single block read and write I/O use a buffer cache that is smaller than the objects created.
prompt If the objects fit into the buffer cache then you should see after warming up the cache write I/O mostly.
prompt This write I/O will only happen if the DB writer is required to do so, so if your redo logs are large you'll have
prompt to run the benchmark long enough to cycle through all groups which should force to write dirty blocks from cache to disk.
prompt
prompt If you want to maximize the single block reads:
prompt Ideally, if you don't suspect caching effects on lower layers (or deliberately want to see their effects)
prompt you can use a very small buffer cache e.g. a minimum sized KEEP or RECYCLE buffer cache (one granule) using the block size
prompt that you want to test (usually the default block size)
prompt Then you don't need to create larger objects, the default of approx. 16.000 blocks per slave (two times 8.000 blocks
prompt for table and index) should be sufficient => 128 MB at 8 KB block size
prompt At the default number of slaves = 8 this means approx. 1 GB of space required. The buffer cache should be much smaller,
prompt as already mentioned, which it usually is at one granule (less than 64 MB typically).
@@common/interactive_common_prompt_2
prompt Currently the script supports up to 100.000.000 blocks per object, that is 1.600 GB at 8 KB block size per table + index
prompt combination per slave, so when using 8 slaves that is 12.800 GB.
prompt Probably you want to use more slaves when testing with such a large buffer cache, so can scale up accordingly,
prompt 32 slaves would mean 50 TB already.
prompt Of course this means you need that much space available in the target tablespace and the generation will take a while.
prompt By modifying the script "create_single_block_benchmark_objects.sql" you can easily create objects larger than
prompt 100.000.000 blocks, see the script header for comments in that regard.
prompt
prompt You'll now be prompted several questions and shown some information about
prompt required and available space as well as current cache sizes.
prompt

@@common/interactive_ask_user_drop

@@common/interactive_buffer_cache_sizing

@@common/interactive_tablespaces

@@common/interactive_num_slaves

@@common/interactive_single_block_object_size

@@common/interactive_target_tablespace
prompt Check this size against the buffer cache you want to use - it should be significantly larger than the buffer cache used for maximum physical read I/O.
prompt

@@common/interactive_storage_clause

@@common/interactive_temporary_tablespace

@@common/interactive_runtime

@@common/interactive_connect_string

@@common/interactive_px_degree

@@common/interactive_os_name

@@common/interactive_performance_report

@@common/interactive_common_summary
prompt Storage clause:                  &storage_clause

@@common/interactive_create_user

@@common/interactive_connect_user

@@max_write_iops_benchmark_harness &num_slaves NA &num_rows "&tablespace_name &storage_clause" &num_seconds "&connect_string" &username "&pwd" "&os_name" &px_degree "&perf_report"
