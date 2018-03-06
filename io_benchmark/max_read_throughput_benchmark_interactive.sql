--------------------------------------------------------------------------------
--
-- File name:   max_read_throughput_benchmark_interactive.sql
--
-- Version:     1.0 (March 2018)
--
--              Tested with client version SQL*Plus 11.2.0.1 and 12.2.0.1
--              Tested with server versions 11.2.0.4, 12.1.0.2 and 12.2.0.1
--
-- Author:      Randolf Geist
--              http://www.oracle-performance.de
--
-- Purpose:     Run concurrent sessions that perform physical read multi block I/O mostly, report achieved I/O throughput rate
--              This script asks for parameters to call then "max_read_throughput_benchmark_harness.sql"
--------------------------------------------------------------------------------

set echo off verify off linesize 200 tab off

prompt
prompt This script asks for parameters to call then the actual benchmark script "max_read_throughput_benchmark_harness.sql"
prompt which runs concurrent sessions performing physical read multi block I/O mostly to report achieved I/O throughput rate
@@common/interactive_common_prompt_1
prompt
prompt The script supports two modes: Synchronous I/O ("db file scattered read" / "cell multiblock physical read" on Exadata) and asynchronous (bypassing buffer cache) I/O ("direct path read" / "cell smart table/index scan" on Exadata)
prompt For synchronous I/O please note that in order to max out the I/O using too small objects / a too large buffer cache will lead to logical instead of physicsl I/O.
prompt The objects created should be significantly larger than the buffer cache used for the tablespace assigned.
prompt Since the asynchronous I/O "direct path read" bypasses the buffer cache by definition, it doesn't suffer from this problem.
prompt
prompt Ideally, if you don't suspect caching effects on lower layers (or deliberately want to see their effects) you can use a very small buffer cache
prompt e.g. a minimum sized KEEP or RECYCLE buffer cache (one granule) using the block size that you want to test (usually the default block size)
prompt By default the script creates a table of 1.000.000 blocks per slave => 8 GB at 8 KB block size
prompt At the default number of slaves = 8 this means approx. 64 GB of space required. The buffer cache should be much smaller, as already mentioned, which it usually is at one granule (less than 64 MB typically).
@@common/interactive_common_prompt_2
prompt Currently the script supports up to 100.000.000 blocks per object, that is 800 GB at 8 KB block size per table per slave, so when using 8 slaves that is 6.400 GB.
prompt Probably you want to use more slaves when testing with such a large buffer cache, so can scale up accordingly, 32 slaves would mean 25 TB already.
prompt Of course this means you need that much space available in the target tablespace and the generation will take a while.
prompt By modifying the script "create_multi_block_benchmark_objects.sql" you can easily create objects larger than 100.000.000 blocks, see the script header for comments in that regard.
prompt
prompt You'll now be prompted several questions and shown some information about required and available space as well as current cache sizes.
prompt

@@common/interactive_ask_user_drop

@@common/interactive_buffer_cache_sizing

@@common/interactive_tablespaces

@@common/interactive_num_slaves

@@common/interactive_multi_block_object_size

@@common/interactive_target_tablespace
prompt Check this size against the buffer cache you want to use - it should be significantly larger than the buffer cache used when using synchronous I/O for maximum physical I/O.
prompt

@@common/interactive_storage_clause

@@common/interactive_temporary_tablespace

@@common/interactive_runtime

prompt
prompt Enter the mode to use for the benchmark. This can be either ASYNC (if supported by O/S / file system configuration) or SYNC I/O
prompt Asynchronous multi block I/O is mainly "direct path read" (or "cell smart table/index scan" on Exadata)
prompt Synchronous multi block I/O is mainly "db file scattered read" (or "cell multiblock physical read" on Exadata)
prompt
prompt Typically you can max out I/O with far fewer clients when using ASYNC I/O (if supported)
prompt Default is ASYNC - which will bypass the buffer cache
prompt

accept sync_or_async default 'ASYNC' prompt 'Enter ASYNC or SYNC mode to use for benchmark (default ASYNC): '

@@common/interactive_connect_string

@@common/interactive_px_degree

@@common/interactive_os_name

@@common/interactive_performance_report

@@common/interactive_common_summary
prompt Storage clause:                  &storage_clause
prompt I/O mode:                        &sync_or_async

@@common/interactive_create_user

@@common/interactive_connect_user

@@max_read_throughput_benchmark_harness &num_slaves &sync_or_async &num_rows "&tablespace_name &storage_clause" &num_seconds "&connect_string" &username "&pwd" "&os_name" &px_degree "&perf_report"
