-- Store current SQL*Plus environment
-- This requires at least a 10.2 SQL*Plus version to work
store set .xplan_settings replace
set echo off verify off termout off timing off define "&" concat "."
-- If you need to debug, uncomment the following line
-- set echo on verify on termout on
set doc off
doc
-- ----------------------------------------------------------------------------------------------
--
-- Script:       xplan_ash.sql
--
-- Version:      1.0
--               August 2012
--
-- Author:       Randolf Geist
--               oracle-randolf.blogspot.com
--
-- Description:  SQL statement execution analysis using ASH (from 11g on)
--
--               Furthermore A free-standing SQL wrapper over DBMS_XPLAN. Provides access to the
--               DBMS_XPLAN.DISPLAY_CURSOR / DISPLAY_AWR pipelined function for a given SQL_ID and CHILD_NUMBER (PLAN_HASH_VALUE for DISPLAY_AWR)
--
--               This is a tool for an extended analysis of the data provided by the
--               Runtime Profile (aka. Rowsource Statistics enabled via
--               SQL_TRACE = TRUE, STATISTICS_LEVEL = ALL or GATHER_PLAN_STATISTICS hint)
--               and reported via the ALLSTATS/MEMSTATS/IOSTATS formatting option of
--               DBMS_XPLAN.DISPLAY_CURSOR / DISPLAY_AWR
--
--               In addition ASH data can be reported for the following purposes:
--
--               1. Show general information about SQL execution activity
--               2. Provide activity information per SQL plan line id
--               3. Show distribution of work between Parallel Slaves / Query Coordinator / RAC Nodes based on ASH data
--
--               The ASH data options make this a kind of "real time" monitoring tool. Unfortunately the
--               free ASH implementations lack the correlation to the SQL plan line id, hence this is only
--               possible with the original ASH implementation from 11g onwards
--
--               Note that this script supports in principle other ASH sources - everything can be configured below
--
--               A second configuration set is provided that is based on DBA_HIST_ACTIVE_SESS_HISTORY for running analysis on historic ASH data
--               Although the sample frequency of 10 seconds limits the significance of the analysis it might much better than nothing at all
--
--               !! The ASH reporting requires at least Enterprise Edition plus the Diagnostic Pack license !!
--
-- Versions:     This utility will work from version 10.2 and later
--               The ASH based information is only available from 11g on (10g has ASH but no relation to SQL execution instances or SQL plan lines)
--
--               Tested with database versions 10.2.0.4, 10.2.0.5, 11.1.0.7, 11.2.0.1, 11.2.0.2 and 11.2.0.3
--
--               Tested with SQL*Plus / client versions 10.2.0.4, 11.1.0.7, 11.2.0.1 and 11.2.0.2 including InstantClient 11.2.0.1
--
-- Required:     The same access as DBMS_XPLAN.DISPLAY_CURSOR (DISPLAY_AWR) requires. See the documentation
--               of the DBMS_XPLAN package for your Oracle version for more information
--
--               !! The ASH reporting requires at least Enterprise Edition plus the Diagnostic Pack license !!
--
--               In addition the script directly queries
--               1) (G)V$SESSION
--               2) V$SQL_PLAN / V$SQL_PLAN_STATISTICS_ALL (DBA_HIST_SQL_PLAN)
--               3) V$SQL
--               4) GV$SQL_MONITOR
--               5) GV$ACTIVE_SESSION_HISTORY (DBA_HIST_ACTIVE_SESS_HISTORY)
--               6) V$DATABASE
--
-- Note:         This script writes two files during execution, hence it requires write access to the current working directory
--
--               If you see the following error messages during execution:
--
--               SP2-0110: Cannot create save file ".xplan_ash_temp"
--
--               plan_operations as
--                               *
--               ERROR at line 14:
--               ORA-00933: SQL command not properly ended
--
--               then you cannot write to your current working directory
--
-- Credits:      Based on the original XPLAN implementation by Adrian Billington (http://www.oracle-developer.net/utilities.php
--               resp. http://www.oracle-developer.net/content/utilities/xplan.zip)
--               and inspired by Kyle Hailey's TCF query (http://dboptimizer.com/2011/09/20/display_cursor/)
--
-- Features:     In addition to the PID (The PARENT_ID) and ORD (The order of execution, note that this doesn't account for the special cases so it might be wrong)
--               columns added by Adrian's wrapper the following additional columns over ALLSTATS are available (see column configuration where it can be customized which to show):
--
--               A_TIME_SELF        : The time taken by the operation itself - this is the operation's cumulative time minus the direct descendants operation's cumulative time
--               LIO_SELF           : The LIOs done by the operation itself - this is the operation's cumulative LIOs minus the direct descendants operation's cumulative LIOs
--               READS_SELF         : The reads performed the operation itself - this is the operation's cumulative reads minus the direct descendants operation's cumulative reads
--               WRITES_SELF        : The writes performed the operation itself - this is the operation's cumulative writes minus the direct descendants operation's cumulative writes
--               A_TIME_SELF_GRAPH  : A graphical representation of A_TIME_SELF relative to the total A_TIME
--               LIO_SELF_GRAPH     : A graphical representation of LIO_SELF relative to the total LIO
--               READS_SELF_GRAPH   : A graphical representation of READS_SELF relative to the total READS
--               WRITES_SELF_GRAPH  : A graphical representation of WRITES_SELF relative to the total WRITES
--               LIO_RATIO          : Ratio of LIOs per row generated by the row source - the higher this ratio the more likely there could be a more efficient way to generate those rows (be aware of aggregation steps though)
--               TCF_GRAPH          : Each "+"/"-" sign represents one order of magnitude based on ratio between E_ROWS_TIMES_START and A-ROWS. Note that this will be misleading with Parallel Execution (see E_ROWS_TIMES_START)
--               E_ROWS_TIMES_START : The E_ROWS multiplied by STARTS - this is useful for understanding the actual cardinality estimate for related combine child operations getting executed multiple times. Note that this will be misleading with Parallel Execution
--
--               More information including demos can be found online at http://oracle-randolf.blogspot.com/2011/12/extended-displaycursor-with-rowsource.html
--
--               The following information is available based on ASH data. Note that this can be configured in two ways:
--               - The "options" determine what information will be queried / shown in general (see below for more details)
--               - The column configuration can be used to customize exactly which columns to show as part the execution plan output (if available)
--
--               Act                            : Indicates the most recent active plan lines according to ASH (only applicable if the statement is currently executing)
--               Start                          : Show the number of seconds since statement start the plan line was active the first time
--               Dur                            : Show the number of seconds the plan line is/was active
--               Time Active Graph              : Show a graphical representation of the activity timeline of the plan line
--               Parallel Distribution ASH      : Show the Top N processes names along with the number of samples found per SQL plan line id. A trailing "..." indicates that there are more than N processes found
--               Parallel Distribution Graph ASH: Show the distribution of the top processes names either relative to the number of samples per SQL plan line id or to the total number of samples. A trailing "..." indicates more processes than displayed
--               Activity Graph ASH             : Show a graphical representation of the number of samples against that SQL plan line id relative to the total number of samples
--               Top N Activity ASH             : Show the Top N activities (waits or ON CPU) from ASH for that SQL plan line id. A trailing "..." indicates that there are more than N activities found
--
--               The default value for N is 5, but can be changed in the configuration section below, for both "Parallel Distribution ASH" and the "Top N Activity ASH".
--               You can also configure the width of the ASH graphs and the character used for the "Graphs" and "Act" column
--
-- Usage:        @xplan_ash.sql [sql_id|sid=<nnn>[@<inst_id>]] [cursor_child_number (plan_hash_value for the historic ASH)] [DBMS_XPLAN_format_option] [SQL_EXEC_START] [SQL_EXEC_ID] [MONITOR|*ASH*] [[*ASH*][,][DISTRIB|*DISTRIB_REL*|DISTRIB_TOT][,][*TIMELINE*]|[NONE]] [*CURR*|HIST|MIXED] [comma_sep_column_list_to_show/hide]
--
--               If both the SQL_ID and CHILD_NUMBER are omitted the previously executed SQL_ID and CHILD_NUMBER of the session will be used
--
--               If the SQL_ID is specified but the CHILD_NUMBER / PLAN_HASH_VALUE is omitted then
--               - If the ASH options are disabled then CHILD_NUMBER 0 is assumed
--               - If ASH / Real-Time SQL Monitoring should be queried, the corresponding CHILD_NUMBER / PLAN_HASH_VALUE will be looked up based on the remaining option specified
--
--               If instead of a SQL_ID SID=<nnn>[@<inst_id>] is specified as first argument, the current or previous execution of the corresponding SID will be used, if available. Optionally the SID's instance can be specified for RAC
--
--               This version does not support processing multiple child cursors like DISPLAY_CURSOR / AWR is capable of
--               when passing NULL as CHILD_NUMBER / PLAN_HASH_VALUE to DISPLAY_CURSOR / AWR. Hence a CHILD_NUMBER / PLAN_HASH_VALUE is mandatory, either
--               implicitly generated (see above) or explicitly passed
--
-- RAC:          A note to RAC users: If the current instance was *not* involved in executing the SQL, and the execution plan should be displayed from the Shared Pool (CURR option), in best case the execution plan cannot be found
--               In worst case an incorrect plan will be associated from the local instance Shared Pool (You could have the same SQL_ID / CHILD_NUMBER with different plans in different RAC instances).
--               Therefore you need to be careful with cross-instance / remote-instance executions in RAC
--               Why? The tool relies on DBMS_XPLAN.DISPLAY_CURSOR for showing the execution plan from the Shared Pool - but DISPLAY_CURSOR is limited to the local Shared Pool
--
--               Below are already ideas mentioned how this can be addressed in a future version
--
--               The default formatting option for the call to DBMS_XPLAN.DISPLAY_CURSOR / AWR is ADVANCED
--
--               SQL_EXEC_START: This is required to determine the exact instance of statement execution in ASH. It is a date in format "YYYY-MM-DD HH24:MI:SS" (date mask can be changed in the configuration section)
--               SQL_EXEC_ID   : Also required for the same purpose
--
--               If these two are omitted and the SID and previous session execution cases don't apply then the last execution is searched in either V$SQL_MONITOR (MONITOR) or V$ACTIVE_SESSION_HISTORY (the default ASH option)
--               The latter option is required if no Tuning Pack license is available, the former option can be used to make sure that the script finds the same latest execution instance as the Real-Time SQL Monitoring
--
--               This information is used as filter on SQL_EXEC_START and SQL_EXEC_ID in ASH. Together with the SQL_ID it uniquely identifies an execution instance of that SQL
--
--               MONITOR or ASH: Determines where to search for the last execution. By default the script uses ASH
--
--               Note that the scripts queries both GV$SQL_MONITOR and GV$ACTIVE_SESSION_HISTORY to determine the last execution if no SQL_EXEC_START / SQL_EXEC_ID was specified
--
--               !! If you don't have a Tuning Pack license but haven't disabled it in the CONTROL_MANAGEMENT_PACK_ACCESS parameter this query might show up as a Tuning Pack feature usage !!
--
--               The next argument allows specifying if ASH activity, Parallel Distribution and/or Activity Timeline information should be displayed
--
--               ASH        : Show "Act", "Activity Graph ASH" and "Top N Activity ASH" columns per SQL plan line id
--               DISTRIB    : Show Parallel Distribution info based on ASH - the inline plan graph will be relative to the total number of samples per SQL plan line id
--               DISTRIB_REL: Show Parallel Distribution info based on ASH - the inline plan graph will be relative to the maximum number of samples per SQL plan line id (default)
--               DISTRIB_TOT: Show Parallel Distribution info based on ASH - the inline plan graph will be relative to the number of samples per SQL execution
--               TIMELINE   : Show the Start Active, Duration and Time Active Graph columns based on ASH data
--               NONE       : Do nothing of above (for example if you only want the Rowsource Statistics information)
--
--               The next argument specifies if the current ASH from GV$ACTIVE_SESSION_HISTORY should be used (CURR, the default) or the historic information from DBA_HIST_ACTIVE_SESS_HISTORY (HIST)
--               There is also a configuration for taking the plan from AWR (DBMS_XPLAN.DISPLAY_AWR) but taking the sample data from current ASH (GV$ACTIVE_SESSION_HISTORY): MIXED
--
--               The last column defines the column list to show. Use a comma-separated list of columns with no whitespace inbetween.
--               The available list of columns can be found below in the configuration section.
--
--               Alternatively you can also specify which columns *not* to show by using a minus sign in front of the column names
--
-- Note:         You need a veeery wide terminal setting for this if you want to make use of all available columns (e.g. format option ALLSTATS ALL), something like linesize 600 should suffice
--
--               This tool is free but comes with no warranty at all - use at your own risk
--
--               The official blog post to this version of the tool can be found here:
--
--               http://oracle-randolf.blogspot.com/2012/08/parallel-execution-analysis-using-ash.html
--
--               It contains a complete description along with the command line reference, notes and examples
--
-- Ideas:        - Include GV$SESSION_LONGOPS information
--               - Show Parallel Slave overview similar to Real-Time SQL Monitoring
--               - Show MAX PGA / TEMP usage
--
--               - Capture more ASH samples
--
--                 This is how Real-Time SQL Monitoring restricts the samples:
/*
set echo on verify on

column pred1           new_value ash_pred1
column pred2           new_value ash_pred2
column pred3           new_value ash_pred3
column pred1_val       new_value ash_pred1_val
column pred2_val       new_value ash_pred2_val
column pred3_val       new_value ash_pred3_val
column min_sample_time new_value ash_min_sample_time
column max_sample_time new_value ash_max_sample_time

select
        max(pred1)                                                       as pred1
      , max(pred2) keep (dense_rank last order by pred1 nulls first)     as pred2
      , max(pred3) keep (dense_rank last order by pred1 nulls first)     as pred3
      , max(pred1_val) keep (dense_rank last order by pred1 nulls first) as pred1_val
      , max(pred2_val) keep (dense_rank last order by pred1 nulls first) as pred2_val
      , max(pred3_val) keep (dense_rank last order by pred1 nulls first) as pred3_val
      , to_char(min(sql_exec_start), 'YYYY-MM-DD HH24:MI:SS')            as min_sample_time
      , to_char(max(cast(sample_time as date)), 'YYYY-MM-DD HH24:MI:SS') as max_sample_time
from
        (
          select
                  case when qc_instance_id is null then 'inst_id' else 'qc_instance_id' end             as pred1
                , case when qc_instance_id is null then 'session_id' else 'qc_session_id' end           as pred2
                , case when qc_instance_id is null then 'session_serial#' else 'qc_session_serial#' end as pred3
                , case when qc_instance_id is null then inst_id else qc_instance_id end                 as pred1_val
                , case when qc_instance_id is null then session_id else qc_session_id end               as pred2_val
                , case when qc_instance_id is null then session_serial# else qc_session_serial# end     as pred3_val
                , sql_exec_start
                , sample_time
          from
                  gv$active_session_history
          where
                  sql_id = '&si'
          and     sql_exec_start = to_date('&ses', 'YYYY-MM-DD HH24:MI:SS')
          and     sql_exec_id = &sei
        )
;

column pred1           clear
column pred2           clear
column pred3           clear
column pred1_val       clear
column pred2_val       clear
column pred3_val       clear
column min_sample_time clear
column max_sample_time clear


select count(*) from gv$active_session_history
where
        sql_id = '&si'
and     &ash_pred1 = &ash_pred1_val
and     &ash_pred2 = &ash_pred2_val
and     &ash_pred3 = &ash_pred3_val
and     cast(sample_time as date) between to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS') and to_date('&ash_max_sample_time', 'YYYY-MM-DD HH24:MI:SS')
;

select count(*) from gv$active_session_history
where
        sql_id = '&si'
and     sql_exec_start = to_date('&ses', 'YYYY-MM-DD HH24:MI:SS')
and     sql_exec_id = &sei
;

undefine ash_pred1
undefine ash_pred2
undefine ash_pred3
undefine ash_pred1_val
undefine ash_pred2_val
undefine ash_pred3_val
undefine ash_min_sample_time
undefine ash_max_sample_time
*/
--
--
--               - Get formatted DBMS_XPLAN output from remote instances in RAC
--
--                 This is how DBMS_XPLAN can be (mis-)used to get an execution plan from a remote RAC instance:
/*
select * from table(sys.dbms_xplan.display('gv$sql_plan', null, 'ADVANCED', 'inst_id = &inst_id and sql_id = ''&si'' and child_number = &cn'))
*/
#

col plan_table_output format a600
-- col plan_table_count noprint new_value pc
set linesize 600 pagesize 0 tab off

-----------------------------------
-- Configuration, default values --
-----------------------------------

/* The graph character used for the graphs */
define gc = "@"

/* The second graph character used for the graphs */
define gc2 = "*"

/* Threshold for rounding averages */
define rnd_thr = "10"

/* The Top N Processes */
define topnp = "5"

/* The Top N Activities */
define topnw = "5"

/* The Parallel Distribution Graph Size */
define pgs = "32"

/* The Activities Graph Size */
define wgs = "20"

/* The Time Active Graph Size */
define tgs = "20"

/* The number of seconds for the last active plan lines from ASH */
define las = "10"

/* The characters used for the last active plan lines from ASH */
define active_ind = "==>"

/* Number of rows / buckets used in the Average Active Session Graph */
define avg_as_bkts = "100"

/* ADVANCED is assumed as the default formatting option for DBMS_XPLAN.DISPLAY_CURSOR */
define default_fo = "ADVANCED"

/* Get the info about last execution by default from ASH, alternative is Real-Time SQL Monitoring */
define default_source = "ASH"

/* Get the ASH info from current ASH, alternative is historic ASH */
define default_ash = "CURR"

/* Default operation is to show all, Activity, Parallel Distribution and Timeline info based on ASH */
/* Possible values are: [ASH][,][DISTRIB|DISTRIB_REL|DISTRIB_TOT][,][TIMELINE]|[NONE]*/
/* DISTRIB means that the distribution graph will be based on values relative to the number of samples per operation */
/* DISTRIB_REL means that the distribution graph will be based on values relative to the maximum number of samples per operation */
/* DISTRIB_TOT means that the distribution graph will be based on values relative to the total number of samples */
define default_operation = "ASH,DISTRIB_REL,TIMELINE"

/* Date mask */
define dm = "YYYY-MM-DD HH24:MI:SS"

/* List of all available columns */
/* Note that you cannot change the column order (yet), only which columns to show */
/* Keep this list unchanged for reference, change default below */
define all_cols = "pid,ord,act,a_time_self,lio_self,reads_self,writes_self,a_time_self_grf,lio_self_grf,reads_self_grf,writes_self_grf,lio_ratio,tcf_grf,e_rows_times_start,start_active,duration_secs,time_active_grf,procs,procs_grf,activity_grf,activity"

/* Default columns to show */
/* Specify here your custom configuration */
define default_cols = "&all_cols"

/* ASH configuration */

/* Configuration for recent ASH */

/* ASH repository */
define curr_global_ash = "gv$active_session_history"

/* Instance identifier */
define curr_inst_id = "inst_id"

/* Plan tables */
define curr_plan_table = "v$sql_plan"

define curr_plan_table_stats = "v$sql_plan_statistics_all"

/* Plan table second identifier */
define curr_second_id = "child_number"

/* Real-Time SQL Monitor second identifier */
define curr_second_id_monitor = "child_address"

/* Sample frequency of ASH, 1 second for recent */
define curr_sample_freq = "1"

/* Where to get the formatted plan output from */
define curr_plan_function = "dbms_xplan.display_cursor"

/* In 10g we can't use named parameters for function calls */
/* So we need a bit of flexibility here when using different plan functions */
define curr_par_fil = ""

/* Configuration for historical ASH */

/* Global ASH repository */
define hist_global_ash = "(select ash.* from dba_hist_active_sess_history ash, v$database db where db.dbid = ash.dbid)"

/* Instance identifier */
define hist_inst_id = "instance_number"

/* Plan tables */
define hist_plan_table = "(select p.* from dba_hist_sql_plan p, v$database db where p.dbid = db.dbid)"

define hist_plan_table_stats = "(select p.* from dba_hist_sql_plan p, v$database db where p.dbid = db.dbid)"

/* Plan table second identifier */
define hist_second_id = "plan_hash_value"

/* Real-Time SQL Monitor second identifier */
define hist_second_id_monitor = "plan_hash_value"

/* Sample frequency of ASH, 10 seconds for retained history */
define hist_sample_freq = "10"

/* Where to get the formatted plan output from */
define hist_plan_function = "dbms_xplan.display_awr"

/* In 10g we can't use named parameters for function calls */
/* So we need a bit of flexibility here when using different plan functions */
/* DISPLAY_AWR has an additional parameter DB_ID */
define hist_par_fil = "null,"

/* Configuration for mixed execution plan from AWR but data from recent ASH / */

/* ASH repository */
define mixed_global_ash = "gv$active_session_history"

/* Instance identifier */
define mixed_inst_id = "inst_id"

/* Plan tables */
define mixed_plan_table = "(select p.* from dba_hist_sql_plan p, v$database db where p.dbid = db.dbid)"

define mixed_plan_table_stats = "(select p.* from dba_hist_sql_plan p, v$database db where p.dbid = db.dbid)"

/* Plan table second identifier */
define mixed_second_id = "plan_hash_value"

/* Real-Time SQL Monitor second identifier */
define mixed_second_id_monitor = "plan_hash_value"

/* Sample frequency of ASH, 1 second for recent */
define mixed_sample_freq = "1"

/* Where to get the formatted plan output from */
define mixed_plan_function = "dbms_xplan.display_awr"

/* In 10g we can't use named parameters for function calls */
/* So we need a bit of flexibility here when using different plan functions */
define mixed_par_fil = "null,"

-----------------------
-- Preparation steps --
-----------------------

column prev_sql_id         new_value prev_sql_id
column prev_child_number   new_value prev_cn
column prev_sql_exec_start new_value prev_sql_exec_start
column prev_sql_exec_id    new_value prev_sql_exec_id

variable prev_sql_id         varchar2(20)
variable prev_child_number   number
variable prev_sql_exec_start varchar2(50)
variable prev_sql_exec_id    number

/* Get the previous command as default
   if no SQL_ID / CHILD_NUMBER is passed */
/* Can't determine yet the database version
   so need to catch the exception and use a different
   SQL for pre-11g */
declare
  e_invalid_identifier_904 exception;
  pragma exception_init(e_invalid_identifier_904, -904);
begin
  execute immediate '
  select
          prev_sql_id
        , prev_child_number
        , to_char(prev_exec_start, ''&dm'') as prev_sql_exec_start
        , prev_exec_id                      as prev_sql_exec_id
  from
          v$session
  where
          sid = userenv(''sid'')'
  into :prev_sql_id, :prev_child_number, :prev_sql_exec_start, :prev_sql_exec_id;
exception
when e_invalid_identifier_904 then
  execute immediate '
  select
          prev_sql_id
        , prev_child_number
        , to_char(to_date(''01.01.1970'', ''DD.MM.YYYY''), ''&dm'') as prev_sql_exec_start
        , 0                                                         as prev_sql_exec_id
  from
          v$session
  where
          sid = userenv(''sid'')'
  into :prev_sql_id, :prev_child_number, :prev_sql_exec_start, :prev_sql_exec_id;
end;
/

select
        :prev_sql_id                      as prev_sql_id
      , to_char(:prev_child_number, 'TM') as prev_child_number
      , :prev_sql_exec_start              as prev_sql_exec_start
      , to_char(:prev_sql_exec_id, 'TM')  as prev_sql_exec_id
from
         dual
;

-- The following is a hack to use default
-- values for defines
column 1 new_value 1
column 2 new_value 2
column 3 new_value 3
column 4 new_value 4
column 5 new_value 5
column 6 new_value 6
column 7 new_value 7
column 8 new_value 8
column 9 new_value 9

select
        '' as "1"
      , '' as "2"
      , '' as "3"
      , '' as "4"
      , '' as "5"
      , '' as "6"
      , '' as "7"
      , '' as "8"
      , '' as "9"
from
        dual
where
        rownum = 0
;

--set doc off
--doc
/* If you prefer to be prompted for the various options, activate this code block */
/* Anything you pass on the command line will be used as default here, so can simply add the option you like at the prompts */

set termout on

prompt
prompt Anything you pass on the command line will be used as default here
prompt
prompt Command-line parameter value: &1
accept 1 default '&1' prompt 'SQL_ID (or SID=[<inst_id>,]<nnn>): '
prompt Command-line parameter value: &2
accept 2 default '&2' prompt 'CHILD_NUMBER (or PLAN_HASH_VALUE): '
prompt Command-line parameter value: &3
accept 3 default '&3' prompt 'DBMS_XPLAN.DISPLAY* format option (default &default_fo): '
prompt Command-line parameter value: &4
accept 4 default '&4' prompt 'SQL_EXEC_START (format "&dm"): '
prompt Command-line parameter value: &5
accept 5 default '&5' prompt 'SQL_EXEC_ID: '
prompt Command-line parameter value: &6
accept 6 default '&6' prompt 'Source for last exec search (MONITOR/ASH, default &default_source): '
prompt Command-line parameter value: &7
accept 7 default '&7' prompt 'ASH options (default &default_operation): '
prompt Command-line parameter value: &8
accept 8 default '&8' prompt 'ASH source (CURR|HIST|MIXED, default &default_ash): '
prompt Command-line parameter value: &9
accept 9 default '&9' prompt 'Comma separated list of columns to show/hide (default show all configured columns): '

-- If you need to debug, comment the following line
set termout off
--#

-- Some version dependent code switches
col ora11_higher  new_value _IF_ORA11_OR_HIGHER
col ora11_lower   new_value _IF_LOWER_THAN_ORA11
col ora112_higher new_value _IF_ORA112_OR_HIGHER
col ora112_lower  new_value _IF_LOWER_THAN_ORA112

select
        decode(substr(banner, instr(banner, 'Release ') + 8, 2), '11', '',  '--')                                                                         as ora11_higher
      , decode(substr(banner, instr(banner, 'Release ') + 8, 2), '11', '--',  '')                                                                         as ora11_lower
      , case when substr( banner, instr(banner, 'Release ') + 8, instr(substr(banner,instr(banner,'Release ') + 8),' ') ) >= '11.2' then '' else '--' end as ora112_higher
      , case when substr( banner, instr(banner, 'Release ') + 8, instr(substr(banner,instr(banner,'Release ') + 8),' ') ) >= '11.2' then '--' else '' end as ora112_lower
from
        v$version
where
        rownum = 1
;

column fo new_value fo
column so new_value so
column op new_value op
column ah new_value ah
column co new_value co

/* Use passed parameters else use defaults */
select
        upper(nvl('&3', '&default_fo'))                                                                                      as fo
      , upper(nvl(case when upper('&6') in ('MONITOR', 'ASH') then '&6' end, '&default_source'))                             as so
      , upper(nvl('&7', '&default_operation'))                                                                               as op
      , upper(nvl(case when upper('&8') in ('CURR', 'HIST', 'MIXED') then '&8' end, '&default_ash'))                         as ah
      , ',' || upper(trim(both ',' from nvl('&9', '&default_cols'))) || ','                                                  as co
from
        dual
;

/* Determine ASH source */

column global_ash        new_value global_ash
column inst_id           new_value inst_id
column plan_table        new_value plan_table
column plan_table_stats  new_value plan_table_stats
column second_id         new_value second_id
column second_id_monitor new_value second_id_monitor
column sample_freq       new_value sample_freq
column plan_function     new_value plan_function
column par_fil           new_value par_fil

select
        '&curr_global_ash'        as global_ash
      , '&curr_inst_id'           as inst_id
      , '&curr_plan_table'        as plan_table
      , '&curr_plan_table_stats'  as plan_table_stats
      , '&curr_second_id'         as second_id
      , '&curr_second_id_monitor' as second_id_monitor
      , '&curr_sample_freq'       as sample_freq
      , '&curr_plan_function'     as plan_function
      , '&curr_par_fil'           as par_fil
from
        dual
where
        '&ah' = 'CURR'
---------
union all
---------
select
        '&hist_global_ash'        as global_ash
      , '&hist_inst_id'           as inst_id
      , '&hist_plan_table'        as plan_table
      , '&hist_plan_table_stats'  as plan_table_stats
      , '&hist_second_id'         as second_id
      , '&hist_second_id_monitor' as second_id_monitor
      , '&hist_sample_freq'       as sample_freq
      , '&hist_plan_function'     as plan_function
      , '&hist_par_fil'           as par_fil
from
        dual
where
        '&ah' = 'HIST'
---------
union all
---------
select
        '&mixed_global_ash'        as global_ash
      , '&mixed_inst_id'           as inst_id
      , '&mixed_plan_table'        as plan_table
      , '&mixed_plan_table_stats'  as plan_table_stats
      , '&mixed_second_id'         as second_id
      , '&mixed_second_id_monitor' as second_id_monitor
      , '&mixed_sample_freq'       as sample_freq
      , '&mixed_plan_function'     as plan_function
      , '&mixed_par_fil'           as par_fil
from
        dual
where
        '&ah' = 'MIXED'
;

column sid_sql_id         new_value sid_sql_id
column sid_child_no       new_value sid_child_no
column sid_sql_exec_start new_value sid_sql_exec_start
column sid_sql_exec_id    new_value sid_sql_exec_id

/* Get SQL details from GV$SESSION if a SID is specified */
select
&_IF_ORA11_OR_HIGHER          nvl2(sql_exec_start, sql_id, prev_sql_id)                                as sid_sql_id
&_IF_LOWER_THAN_ORA11         nvl2(sql_id, sql_id, prev_sql_id)                                        as sid_sql_id
&_IF_ORA11_OR_HIGHER        , to_char(nvl2(sql_exec_start, sql_child_number, prev_child_number), 'TM') as sid_child_no
&_IF_LOWER_THAN_ORA11       , to_char(nvl2(sql_id, sql_child_number, prev_child_number), 'TM')         as sid_child_no
&_IF_ORA11_OR_HIGHER        , to_char(nvl2(sql_exec_start, sql_exec_start, prev_exec_start), '&dm')    as sid_sql_exec_start
&_IF_LOWER_THAN_ORA11       , ''                                                                       as sid_sql_exec_start
&_IF_ORA11_OR_HIGHER        , to_char(nvl2(sql_exec_start, sql_exec_id, prev_exec_id), 'TM')           as sid_sql_exec_id
&_IF_LOWER_THAN_ORA11       , to_char(null, 'TM')                                                      as sid_sql_exec_id
from
       gv$session
where
       upper(substr('&1', 1, 4)) = 'SID='
/*
and    sid = to_number(substr('&1', case when instr('&1', ',') > 0 then instr('&1', ',') + 1 else 5 end))
and    regexp_like(trim(substr('&1', case when instr('&1', ',') > 0 then instr('&1', ',') + 1 else 5 end)), '^\d+$')
and    inst_id = case when instr('&1', ',') > 0 then to_number(substr('&1', 5, instr('&1', ',') - 5)) else userenv('instance') end
and    (instr('&1', ',') < 1 or regexp_like(trim(substr('&1', 5, instr('&1', ',') - 5)), '^\d+$'))
*/
and    sid = to_number(substr('&1', 5, case when instr('&1', '@') > 0 then instr('&1', '@') - 5 else length('&1') end))
and    regexp_like(trim(substr('&1', 5, case when instr('&1', '@') > 0 then instr('&1', '@') - 5 else length('&1') end)), '^\d+$')
and    inst_id = case when instr('&1', '@') > 0 then to_number(substr('&1', instr('&1', '@') + 1)) else userenv('instance') end
and    (instr('&1', '@') < 1 or regexp_like(trim(substr('&1', instr('&1', '@') + 1)), '^\d+$'))
;

column last_exec_second_id new_value last_exec_second_id

/* Identify the CHILD_NUMBER / PLAN_HASH_VALUE if first parameter identifies a SQL_ID and second parameter is null and ASH / Real-Time SQL Monitoring should be queried */

/* One of the following statements will be short-circuited by the optimizer if the ASH / MONITOR condition is not true */
/* So effectively only one of them will run, the other will not return any data (due to the GROUP BY clause) */

/* This statement is effectively turned into a NOOP in versions below 11g */
select
&_IF_ORA11_OR_HIGHER          cast(max(sql_&second_id_monitor) keep (dense_rank last order by sql_exec_start nulls first) as varchar2(30)) as last_exec_second_id
&_IF_LOWER_THAN_ORA11         '0' as last_exec_second_id
from
&_IF_ORA11_OR_HIGHER          gv$sql_monitor
&_IF_LOWER_THAN_ORA11         dual
&_IF_ORA11_OR_HIGHER  where
&_IF_ORA11_OR_HIGHER          sql_id = '&1'
&_IF_ORA11_OR_HIGHER  and     px_qcsid is null
&_IF_ORA11_OR_HIGHER  and     '&so' = 'MONITOR'
&_IF_ORA11_OR_HIGHER  and     (instr('&op', 'ASH') > 0 or instr('&op', 'DISTRIB') > 0 or instr('&op', 'TIMELINE') > 0)
&_IF_ORA11_OR_HIGHER  and     sql_exec_start = nvl(to_date('&4', '&dm'), sql_exec_start)
&_IF_ORA11_OR_HIGHER  and     sql_exec_id = nvl(trim('&5'), sql_exec_id)
&_IF_ORA11_OR_HIGHER  and     '&1' is not null
&_IF_ORA11_OR_HIGHER  and     upper(substr('&1', 1, 4)) != 'SID='
&_IF_ORA11_OR_HIGHER  and     '&2' is null
group by
        1
---------
union all
---------
select
&_IF_ORA11_OR_HIGHER          to_char(max(sql_&second_id) keep (dense_rank last order by sql_exec_start nulls first), 'TM')                as last_exec_second_id
&_IF_LOWER_THAN_ORA11         '0' as last_exec_second_id
from
&_IF_ORA11_OR_HIGHER          &global_ash
&_IF_LOWER_THAN_ORA11         dual
&_IF_ORA11_OR_HIGHER  where
&_IF_ORA11_OR_HIGHER          sql_id = '&1'
&_IF_ORA11_OR_HIGHER  and     '&so' = 'ASH'
&_IF_ORA11_OR_HIGHER  and     (instr('&op', 'ASH') > 0 or instr('&op', 'DISTRIB') > 0 or instr('&op', 'TIMELINE') > 0)
&_IF_ORA11_OR_HIGHER  and     sql_exec_start = nvl(to_date('&4', '&dm'), sql_exec_start)
&_IF_ORA11_OR_HIGHER  and     sql_exec_id = nvl(trim('&5'), sql_exec_id)
&_IF_ORA11_OR_HIGHER  and     '&1' is not null
&_IF_ORA11_OR_HIGHER  and     upper(substr('&1', 1, 4)) != 'SID='
&_IF_ORA11_OR_HIGHER  and     '&2' is null
group by
        1
;

/* Turn the Real-Time SQL Monitoring CHILD_ADDRESS into a CHILD_NUMBER */

select
        to_char(child_number, 'TM') as last_exec_second_id
from
        v$sql
where
        sql_id = '&1'
and     child_address = hextoraw('&last_exec_second_id')
and     '&so' = 'MONITOR'
and     upper('&second_id_monitor') = 'CHILD_ADDRESS'
and     (instr('&op', 'ASH') > 0 or instr('&op', 'DISTRIB') > 0 or instr('&op', 'TIMELINE') > 0)
and     '&1' is not null
and     upper(substr('&1', 1, 4)) != 'SID='
and     '&2' is null
and     '&_IF_ORA11_OR_HIGHER' is null
;

column si new_value si
column cn new_value cn

/* Use passed parameters else refer to previous SQL_ID / CHILD_NUMBER or SQL details of given SID */
select
        coalesce('&sid_sql_id', '&1', '&prev_sql_id')                                                                        as si
      , coalesce('&sid_child_no', nvl2('&1', coalesce('&2', '&last_exec_second_id', '0'), coalesce('&2', '&prev_cn', '0')))  as cn
from
        dual
;

column c_pid                new_value c_pid
column c_ord                new_value c_ord
column c_act                new_value c_act
column c_a_time_self        new_value c_a_time_self
column c_lio_self           new_value c_lio_self
column c_reads_self         new_value c_reads_self
column c_writes_self        new_value c_writes_self
column c_a_time_self_graph  new_value c_a_time_self_graph
column c_lio_self_graph     new_value c_lio_self_graph
column c_reads_self_graph   new_value c_reads_self_graph
column c_writes_self_graph  new_value c_writes_self_graph
column c_lio_ratio          new_value c_lio_ratio
column c_tcf_graph          new_value c_tcf_graph
column c_e_rows_times_start new_value c_e_rows_times_start
column c_start_active       new_value c_start_active
column c_duration_secs      new_value c_duration_secs
column c_time_active_graph  new_value c_time_active_graph
column c_procs              new_value c_procs
column c_procs_graph        new_value c_procs_graph
column c_activity_graph     new_value c_activity_graph
column c_activity           new_value c_activity

-- Determine which columns to hide
-- if the column string contains a minus
select
        case when instr('&co', ',-PID,') > 0 then null else '1' end                as c_pid
      , case when instr('&co', ',-ORD,') > 0 then null else '1' end                as c_ord
      , case when instr('&co', ',-ACT,') > 0 then null else '1' end                as c_act
      , case when instr('&co', ',-A_TIME_SELF,') > 0 then null else '1' end        as c_a_time_self
      , case when instr('&co', ',-LIO_SELF,') > 0 then null else '1' end           as c_lio_self
      , case when instr('&co', ',-READS_SELF,') > 0 then null else '1' end         as c_reads_self
      , case when instr('&co', ',-WRITES_SELF,') > 0 then null else '1' end        as c_writes_self
      , case when instr('&co', ',-A_TIME_SELF_GRF,') > 0 then null else '1' end    as c_a_time_self_graph
      , case when instr('&co', ',-LIO_SELF_GRF,') > 0 then null else '1' end       as c_lio_self_graph
      , case when instr('&co', ',-READS_SELF_GRF,') > 0 then null else '1' end     as c_reads_self_graph
      , case when instr('&co', ',-WRITES_SELF_GRF,') > 0 then null else '1' end    as c_writes_self_graph
      , case when instr('&co', ',-LIO_RATIO,') > 0 then null else '1' end          as c_lio_ratio
      , case when instr('&co', ',-TCF_GRF,') > 0 then null else '1' end            as c_tcf_graph
      , case when instr('&co', ',-E_ROWS_TIMES_START,') > 0 then null else '1' end as c_e_rows_times_start
      , case when instr('&co', ',-START_ACTIVE,') > 0 then null else '1' end       as c_start_active
      , case when instr('&co', ',-DURATION_SECS,') > 0 then null else '1' end      as c_duration_secs
      , case when instr('&co', ',-TIME_ACTIVE_GRF,') > 0 then null else '1' end    as c_time_active_graph
      , case when instr('&co', ',-PROCS,') > 0 then null else '1' end              as c_procs
      , case when instr('&co', ',-PROCS_GRF,') > 0 then null else '1' end          as c_procs_graph
      , case when instr('&co', ',-ACTIVITY_GRF,') > 0 then null else '1' end       as c_activity_graph
      , case when instr('&co', ',-ACTIVITY,') > 0 then null else '1' end           as c_activity
from
        dual
where
        instr('&co', '-') > 0
---------
union all
---------
-- Determine columns to show
select
        case when instr('&co', ',PID,') > 0 then '1' end                as c_pid
      , case when instr('&co', ',ORD,') > 0 then '1' end                as c_ord
      , case when instr('&co', ',ACT,') > 0 then '1' end                as c_act
      , case when instr('&co', ',A_TIME_SELF,') > 0 then '1' end        as c_a_time_self
      , case when instr('&co', ',LIO_SELF,') > 0 then '1' end           as c_lio_self
      , case when instr('&co', ',READS_SELF,') > 0 then '1' end         as c_reads_self
      , case when instr('&co', ',WRITES_SELF,') > 0 then '1' end        as c_writes_self
      , case when instr('&co', ',A_TIME_SELF_GRF,') > 0 then '1' end    as c_a_time_self_graph
      , case when instr('&co', ',LIO_SELF_GRF,') > 0 then '1' end       as c_lio_self_graph
      , case when instr('&co', ',READS_SELF_GRF,') > 0 then '1' end     as c_reads_self_graph
      , case when instr('&co', ',WRITES_SELF_GRF,') > 0 then '1' end    as c_writes_self_graph
      , case when instr('&co', ',LIO_RATIO,') > 0 then '1' end          as c_lio_ratio
      , case when instr('&co', ',TCF_GRF,') > 0 then '1' end            as c_tcf_graph
      , case when instr('&co', ',E_ROWS_TIMES_START,') > 0 then '1' end as c_e_rows_times_start
      , case when instr('&co', ',START_ACTIVE,') > 0 then '1' end       as c_start_active
      , case when instr('&co', ',DURATION_SECS,') > 0 then '1' end      as c_duration_secs
      , case when instr('&co', ',TIME_ACTIVE_GRF,') > 0 then '1' end    as c_time_active_graph
      , case when instr('&co', ',PROCS,') > 0 then '1' end              as c_procs
      , case when instr('&co', ',PROCS_GRF,') > 0 then '1' end          as c_procs_graph
      , case when instr('&co', ',ACTIVITY_GRF,') > 0 then '1' end       as c_activity_graph
      , case when instr('&co', ',ACTIVITY,') > 0 then '1' end           as c_activity
from
        dual
where
        instr('&co', '-') < 1
;

column last new_value last

/* Last or all execution for Rowsource execution statistics */
select
        case
        when instr('&fo', 'LAST') > 0
        then 'last_'
        end  as last
from
        dual
;

column plan_table_name new_value plan_table_name

/* Get plan info from V$SQL_PLAN_STATISTICS_ALL or V$SQL_PLAN */
select
        case
        when instr('&fo', 'STATS') > 0
        then '&plan_table_stats'
        else '&plan_table'
        end  as plan_table_name
from
        dual
;

column child_ad new_value child_ad

-- Get child address for querying V$SQL_MONITOR
select
        rawtohex(child_address) as child_ad
from
        v$sql
where
        sql_id = '&si'
and     child_number = &cn
and     (instr('&op', 'ASH') > 0 or instr('&op', 'DISTRIB') > 0 or instr('&op', 'TIMELINE') > 0)
and     coalesce('&sid_sql_exec_start', '&4') is null and '&1' is not null
and     upper('&second_id_monitor') = 'CHILD_ADDRESS'
;

column last_exec_start new_value last_exec_start
column last_exec_id new_value last_exec_id

/* Search for the last execution of the statement if no SQL_EXEC_START is specified and no other option provides the information */

/* One of the following statements will be short-circuited by the optimizer if the ASH / MONITOR condition is not true */
/* So effectively only one of them will run, the other will not return any data (due to the GROUP BY clause) */

/* This statement is effectively turned into a NOOP in versions below 11g */
select
&_IF_ORA11_OR_HIGHER          to_char(max(sql_exec_start), '&dm')                                                        as last_exec_start
&_IF_ORA11_OR_HIGHER        , to_char(max(sql_exec_id) keep (dense_rank last order by sql_exec_start nulls first), 'TM') as last_exec_id
&_IF_LOWER_THAN_ORA11         ''   as last_exec_start
&_IF_LOWER_THAN_ORA11       , '0'  as last_exec_id
from
&_IF_ORA11_OR_HIGHER          gv$sql_monitor
&_IF_LOWER_THAN_ORA11         dual
&_IF_ORA11_OR_HIGHER  where
&_IF_ORA11_OR_HIGHER          sql_id = '&si'
&_IF_ORA11_OR_HIGHER  and     sql_&second_id_monitor = case when upper('&second_id_monitor') = 'CHILD_ADDRESS' then '&child_ad' else '&cn' end
&_IF_ORA11_OR_HIGHER  and     px_qcsid is null
&_IF_ORA11_OR_HIGHER  and     '&so' = 'MONITOR'
&_IF_ORA11_OR_HIGHER  and     (instr('&op', 'ASH') > 0 or instr('&op', 'DISTRIB') > 0 or instr('&op', 'TIMELINE') > 0)
&_IF_ORA11_OR_HIGHER  and     coalesce('&sid_sql_exec_start', '&4') is null and '&1' is not null
group by
        1
---------
union all
---------
select
&_IF_ORA11_OR_HIGHER          to_char(max(sql_exec_start), '&dm')                                                        as last_exec_start
&_IF_ORA11_OR_HIGHER        , to_char(max(sql_exec_id) keep (dense_rank last order by sql_exec_start nulls first), 'TM') as last_exec_id
&_IF_LOWER_THAN_ORA11         ''  as last_exec_start
&_IF_LOWER_THAN_ORA11       , '0' as last_exec_id
from
&_IF_ORA11_OR_HIGHER          &global_ash
&_IF_LOWER_THAN_ORA11         dual
&_IF_ORA11_OR_HIGHER  where
&_IF_ORA11_OR_HIGHER          sql_id = '&si'
&_IF_ORA11_OR_HIGHER  and     sql_&second_id = &cn
&_IF_ORA11_OR_HIGHER  and     '&so' = 'ASH'
&_IF_ORA11_OR_HIGHER  and     (instr('&op', 'ASH') > 0 or instr('&op', 'DISTRIB') > 0 or instr('&op', 'TIMELINE') > 0)
&_IF_ORA11_OR_HIGHER  and     coalesce('&sid_sql_exec_start', '&4') is null and '&1' is not null
group by
        1
;

column ls new_value ls
column li new_value li

/* Use passed parameters else refer to last execution found / SQL details of given SID */
select
        coalesce('&sid_sql_exec_start', '&4', case when '&1' is null then '&prev_sql_exec_start' end, '&last_exec_start') as ls
        -- , coalesce('&sid_sql_exec_id', '&5', '&last_exec_id', '-1') as li
      , case
        when '&sid_sql_exec_start' is not null
        then '&sid_sql_exec_id'
        when '&4' is not null
        then nvl(trim('&5'), '-1')
        when '&1' is null
        then '&prev_sql_exec_id'
        else coalesce('&last_exec_id', '-1')
        end                                                                                                               as li
from
        dual
;

/* Check if a plan can be found */
column plan_exists new_value plan_exists

select
        max(sql_id) as plan_exists
from
        &plan_table p
where
        p.sql_id = '&si'
and     p.&second_id = &cn
and     rownum <= 1
;

-------------------------------
-- Actual output starts here --
-------------------------------

set termout on pagesize 999 heading on feedback off newpage 1 numwidth 10 numformat "" null ""

set heading off

column message format a50

/* Just a quick notice if we could not find anything for a given SID */
select
        'No SQL information for &1 found!' as message
from
        dual
where
       upper(substr('&1', 1, 4)) = 'SID='
/*
and    regexp_like(trim(substr('&1', case when instr('&1', ',') > 0 then instr('&1', ',') + 1 else 5 end)), '^\d+$')
and    (instr('&1', ',') < 1 or regexp_like(trim(substr('&1', 5, instr('&1', ',') - 5)), '^\d+$'))
*/
and    regexp_like(trim(substr('&1', 5, case when instr('&1', '@') > 0 then instr('&1', '@') - 5 else length('&1') end)), '^\d+$')
and    (instr('&1', '@') < 1 or regexp_like(trim(substr('&1', instr('&1', '@') + 1)), '^\d+$'))
and    '&sid_sql_id' is null
;

column message clear

set heading on

prompt
prompt
prompt General information
prompt -----------------------------------------------

column sql_id           format a13
column sql_exec_start   format a19
column format_option    format a25
column last_exec_source format a16
column ash_options      format a24
column ash_source       format a10

select
        '&si' as sql_id
      , &cn   as &second_id
&_IF_ORA11_OR_HIGHER        , '&ls' as sql_exec_start
&_IF_ORA11_OR_HIGHER        , &li   as sql_exec_id
      , '&fo' as format_option
&_IF_ORA11_OR_HIGHER        , case
&_IF_ORA11_OR_HIGHER          when '&sid_sql_id' is not null
&_IF_ORA11_OR_HIGHER          then upper('&1')
&_IF_ORA11_OR_HIGHER          when '&1' is null and '&4' is null
&_IF_ORA11_OR_HIGHER          then 'PREV_SQL'
&_IF_ORA11_OR_HIGHER          when '&4' is not null
&_IF_ORA11_OR_HIGHER          then 'N/A'
&_IF_ORA11_OR_HIGHER          else '&so'
&_IF_ORA11_OR_HIGHER          end   as last_exec_source
      , '&op' as ash_options
      , '&ah' as ash_source
from
        dual
;

column sql_id           clear
column sql_exec_start   clear
column format_option    clear
column last_exec_source clear
column ash_options      clear
column ash_source       clear

prompt
prompt

/* Summary information based on ASH */

column instance_count new_value ic
column duration_secs  new_value ds

column first_sample format a19
column last_sample  format a19
column status       format a8

column slave_count new_value slave_count

select
        instance_count
      , first_sample
      , last_sample
      , duration_secs
      , status
      , sample_count
      , cpu_sample_count
      , round(cpu_sample_count / sample_count * 100)                          as percentage_cpu
      , slave_count
      , case when average_as >= &rnd_thr then round(average_as) else average_as end as average_as
from
        (
          select
                  count(distinct &inst_id)                                                                                as instance_count
                , to_char(min(sample_time), '&dm')                                                                        as first_sample
                , to_char(max(sample_time), '&dm')                                                                        as last_sample
&_IF_ORA11_OR_HIGHER                  , round(((max(sample_time) - min(sql_exec_start)) * 86400)) + &sample_freq                                as duration_secs
&_IF_LOWER_THAN_ORA11                 , 0                                                                                                       as duration_secs
                , case when max(sample_time) >= sysdate - 2 * &sample_freq / 86400 then 'ACTIVE' else 'INACTIVE' end      as status
                , count(*)                                                                                                as sample_count
                , sum(is_on_cpu)                                                                                          as cpu_sample_count
                , count(distinct process)                                                                                 as slave_count
&_IF_ORA11_OR_HIGHER                  , round(count(*) / (((max(sample_time) - min(sql_exec_start)) * 86400) + &sample_freq) * &sample_freq, 2) as average_as
&_IF_LOWER_THAN_ORA11                 , 0                                                                                                       as average_as
          from
                  (
                    select
                            &inst_id
                          , cast(sample_time as date)                                                                 as sample_time
                          , sql_id
                          , case
                            -- REGEXP_SUBSTR lacks the subexpr parameter in 10.2
                            -- when regexp_substr(program, '^.*\((P[[:alnum:]]{3})\)$', 1, 1, 'c', 1) is null
                            when regexp_instr(regexp_replace(program, '^.*\((P[[:alnum:]]{3})\)$', '\1', 1, 1, 'c'), '^P[[:alnum:]]{3}$') != 1
                            then null
                            -- REGEXP_SUBSTR lacks the subexpr parameter in 10.2
                            -- else &inst_id || '-' || regexp_substr(program, '^.*\((P[[:alnum:]]{3})\)$', 1, 1, 'c', 1)
                            else &inst_id || '-' || regexp_replace(program, '^.*\((P[[:alnum:]]{3})\)$', '\1', 1, 1, 'c')
                            end                                                                                       as process
                          , case when session_state = 'ON CPU' then 1 else 0 end                                      as is_on_cpu
&_IF_ORA11_OR_HIGHER                            , sql_exec_start
&_IF_ORA11_OR_HIGHER                            , sql_exec_id
                    from
                            &global_ash
                  ) ash
          where
                  ash.sql_id = '&si'
&_IF_ORA11_OR_HIGHER            and     ash.sql_exec_start = to_date('&ls', '&dm')
&_IF_ORA11_OR_HIGHER            and     ash.sql_exec_id = &li
          and     (instr('&op', 'ASH') > 0 or instr('&op', 'DISTRIB') > 0 or instr('&op', 'TIMELINE') > 0)
          and     '&_IF_ORA11_OR_HIGHER' is null
          -- This prevents the aggregate functions to produce a single row
          -- in case of no rows generated to aggregate
          group by
                  1
)
;

column slave_count noprint

select
        case when to_number('&slave_count') = 0 then '' else trim('&slave_count') end as slave_count
from
        dual
;

column slave_count clear

column duration_secs clear

column first_sample clear
column last_sample  clear
column status       clear

column is_cross_instance   new_value _IF_CROSS_INSTANCE    noprint
column is_ora112_or_higher new_value _IF_ORA112_OR_HIGHERP noprint

select
        case when to_number(nvl('&ic', '0')) > 1 then '' else 'no' end  as is_cross_instance
      , case when '&_IF_ORA112_OR_HIGHER' is null then '' else 'no' end as is_ora112_or_higher
from
        dual
;

column is_cross_instance clear
column is_ora112_or_higher clear

/* Summary information per RAC instance based on ASH (for cross-instance SQL execution) */

column first_sample      format a19
column last_sample       format a19
column time_active_graph format a&tgs

select
        instance_id
      , first_sample
      , last_sample
      , start_active
      , duration_secs
      , sample_count
      , process_count
      , case when average_as >= &rnd_thr then round(average_as) else average_as end                                                                     as average_as
      , substr(rpad(' ', round(start_active / to_number('&ds') * &tgs)) || rpad('&gc', round(duration_secs / to_number('&ds') * &tgs), '&gc'), 1, &tgs) as time_active_graph
from
        (
          select
                  &inst_id                                                                                             as instance_id
                , to_char(min(sample_time), '&dm')                                                                     as first_sample
                , to_char(max(sample_time), '&dm')                                                                     as last_sample
&_IF_ORA11_OR_HIGHER                  , round((min(sample_time) - min(sql_exec_start)) * 86400)                                              as start_active
&_IF_LOWER_THAN_ORA11                 , 0                                                                                                    as start_active
                , round(((max(sample_time) - min(sample_time)) * 86400)) + &sample_freq                                as duration_secs
                , count(*)                                                                                             as sample_count
                , count(distinct process)                                                                              as process_count
                , round(count(*) / (((max(sample_time) - min(sample_time)) * 86400) + &sample_freq) * &sample_freq, 2) as average_as
          from
                  (
                    select
                            &inst_id
                          , cast(sample_time as date)                                             as sample_time
                          , regexp_replace(program, '^.*\((P[[:alnum:]]{3})\)$', '\1', 1, 1, 'c') as process
                          , sql_id
&_IF_ORA11_OR_HIGHER                            , sql_exec_start
&_IF_ORA11_OR_HIGHER                            , sql_exec_id
                    from
                            &global_ash
                  ) ash
          where
                  ash.sql_id = '&si'
&_IF_ORA11_OR_HIGHER            and     ash.sql_exec_start = to_date('&ls', '&dm')
&_IF_ORA11_OR_HIGHER            and     ash.sql_exec_id = &li
          and     instr('&op', 'ASH') > 0
          and     '&_IF_ORA11_OR_HIGHER' is null
          and     to_number(nvl('&ic', '0')) > 1
          group by
                  &inst_id
        )
order by
        instance_id
;

column first_sample      clear
column last_sample       clear
column time_active_graph clear

set heading off

column message format a50

select
        'Information on Parallel Degree based on ASH' as message
from
        dual
where
        instr('&op', 'DISTRIB') > 0
and     '&plan_exists' is not null
and     '&_IF_ORA11_OR_HIGHER' is null
---------
union all
---------
select
        '-----------------------------------------------'
from
        dual
where
        instr('&op', 'DISTRIB') > 0
and     '&plan_exists' is not null
and     '&_IF_ORA11_OR_HIGHER' is null
;

column message clear

set heading on

/* Provide summary info on Instance / DFO level if a plan is available */

column dfo               format a6
column time_active_graph format a&tgs
column instance_id &_IF_CROSS_INSTANCE.print

/* This statement is effectively turned into a NOOP in versions below 11g */
with set_count
as
(
  select
          dfo
        , max(set_count) as set_count
  from
          (
            select
                    cast(substr(p.object_node, 2, length(p.object_node) - 4) as varchar2(6))  as dfo
                  , case when p.operation = 'PX RECEIVE' then 2 else 1 end                    as set_count
            from
                    &plan_table p
            where
                    p.sql_id = '&si'
            and     p.&second_id = &cn
            and     p.object_node like ':Q%'
            and     instr('&op', 'DISTRIB') > 0
            and     '&plan_exists' is not null
            and     '&_IF_ORA11_OR_HIGHER' is null
          )
  group by
          dfo
)
select
        instance_id
      , dfo
      , start_active
      , duration_secs
      , sample_count
      , process_count
      , set_count
      , assumed_degree
      , case when average_as >= &rnd_thr then round(average_as) else average_as end                                                                     as average_as
      , substr(rpad(' ', round(start_active / to_number('&ds') * &tgs)) || rpad('&gc', round(duration_secs / to_number('&ds') * &tgs), '&gc'), 1, &tgs) as time_active_graph
from
        (
          select  /*+ cardinality(100) */
                  &inst_id                                                                                                as instance_id
                , pr.dfo
&_IF_ORA11_OR_HIGHER                  , round((min(sample_time) - min(sql_exec_start)) * 86400)                                                 as start_active
&_IF_LOWER_THAN_ORA11                 , 0                                                                                                       as start_active
                , round(((max(sample_time) - min(sample_time)) * 86400)) + &sample_freq                                   as duration_secs
                , count(process)                                                                                          as sample_count
                , count(distinct process)                                                                                 as process_count
                , sc.set_count                                                                                            as set_count
                , ceil(count(distinct process) / sc.set_count)                                                            as assumed_degree
                , round(count(*) / (((max(sample_time) - min(sample_time)) * 86400) + &sample_freq) * &sample_freq, 2)    as average_as
          from    (
                    select
                            ash.&inst_id
                          , regexp_replace(ash.program, '^.*\((P[[:alnum:]]{3})\)$', '\1', 1, 1, 'c') as process
                          , cast(substr(p.object_node, 2, length(p.object_node) - 4) as varchar2(6))  as dfo
                          , cast(ash.sample_time as date)                                             as sample_time
&_IF_ORA11_OR_HIGHER                            , ash.sql_exec_start
&_IF_LOWER_THAN_ORA11                           , to_date('01.01.1970', 'DD.MM.YYYY') as sql_exec_start
                    from
                            &global_ash ash
                          , &plan_table p
                    where
                            ash.sql_id = '&si'
&_IF_ORA11_OR_HIGHER                      and     ash.sql_exec_start = to_date('&ls', '&dm')
&_IF_ORA11_OR_HIGHER                      and     ash.sql_exec_id = &li
                    -- and     regexp_like(ash.program, '^.*\((P[[:alnum:]]{3})\)$')
                    and     p.sql_id = '&si'
                    and     p.&second_id = &cn
&_IF_ORA11_OR_HIGHER                      and     p.id = ash.sql_plan_line_id
                    and     p.object_node is not null
                    and     instr('&op', 'DISTRIB') > 0
                    and     '&plan_exists' is not null
                    and     '&_IF_ORA11_OR_HIGHER' is null
                  ) pr
                , set_count sc
          where
                  sc.dfo = pr.dfo
          group by
                  &inst_id
                , pr.dfo
                , sc.set_count
        )
order by
        instance_id
      , dfo
;

column dfo               clear
column time_active_graph clear
column instance_id       clear

set doc off
doc
/* This is no longer used */
/* Provide summary info on Instance only if a plan is not available */

column time_active_graph format a&tgs
column instance_id &_IF_CROSS_INSTANCE.print

/* This statement is effectively turned into a NOOP in versions below 11g */
select
        instance_id
      , start_active
      , duration_secs
      , sample_count
      , process_count
      , substr(rpad(' ', round(start_active / to_number('&ds') * &tgs)) || rpad('&gc', round(duration_secs / to_number('&ds') * &tgs), '&gc'), 1, &tgs) as time_active_graph
from
        (
          select
                  &inst_id                                                              as instance_id
&_IF_ORA11_OR_HIGHER                  , round((min(sample_time) - min(sql_exec_start)) * 86400)               as start_active
&_IF_LOWER_THAN_ORA11                 , 0                                                                     as start_active
                , round(((max(sample_time) - min(sample_time)) * 86400)) + &sample_freq as duration_secs
                , count(process)                                                        as sample_count
                , count(distinct process)                                               as process_count
          from    (
                    select
                            ash.&inst_id
                          , regexp_replace(ash.program, '^.*\((P[[:alnum:]]{3})\)$', '\1', 1, 1, 'c') as process
                          , cast(ash.sample_time as date)                                             as sample_time
&_IF_ORA11_OR_HIGHER                            , ash.sql_exec_start
&_IF_LOWER_THAN_ORA11                           , to_date('01.01.1970', 'DD.MM.YYYY')                                       as sql_exec_start
                    from
                            &global_ash ash
                    where
                            ash.sql_id = '&si'
&_IF_ORA11_OR_HIGHER                      and     ash.sql_exec_start = to_date('&ls', '&dm')
&_IF_ORA11_OR_HIGHER                      and     ash.sql_exec_id = &li
                    -- and     regexp_like(ash.program, '^.*\((P[[:alnum:]]{3})\)$')
                    and     instr('&op', 'DISTRIB') > 0
                    and     '&plan_exists' is null
                    and     '&_IF_ORA11_OR_HIGHER' is null
                  ) pr
          group by
                  &inst_id
        )
order by
        instance_id
;

column time_active_graph clear
column instance_id       clear
#

set heading off

/* If DISTRIB option was used and Parallel Execution was expected
   show a message here that no Parallel Execution activity could be found in ASH */

column message format a50

select
        'No Parallel Slave activity found in ASH!' as message
from
        dual
where
        '&slave_count' is null and instr('&op', 'DISTRIB') > 0
and     '&plan_exists' is not null
and     '&_IF_ORA11_OR_HIGHER' is null;

set heading off

select
        'Average Active Session Overview based on ASH' as message
from
        dual
where
        '&slave_count' is not null and instr('&op', 'DISTRIB') > 0
and     '&_IF_ORA11_OR_HIGHER' is null
---------
union all
---------
select
        '-----------------------------------------------'
from
        dual
where
        '&slave_count' is not null and instr('&op', 'DISTRIB') > 0
and     '&_IF_ORA11_OR_HIGHER' is null
;

column message clear

set heading on

/* Average Active Session overview graph for Parallel Execution */

column average_as_graph format a256
column instance_id &_IF_CROSS_INSTANCE.print

set doc off
doc
/* Old Average Active Session Graph code */
/* This statement is effectively turned into a NOOP in versions below 11g */
select
        max(duration_secs)                                                                                            as duration_secs
      , case when avg(cnt_cpu) >= &rnd_thr then round(avg(cnt_cpu)) else round(avg(cnt_cpu), 2) end                   as cpu
      , case when avg(cnt_other) >= &rnd_thr then round(avg(cnt_other)) else round(avg(cnt_other), 2) end             as other
      , case when avg(cnt) >= &rnd_thr then round(avg(cnt)) else round(avg(cnt), 2) end                               as average_as
      , cast(rpad('&gc', round(avg(cnt_cpu)), '&gc') || rpad('&gc2', round(avg(cnt_other)), '&gc2') as varchar2(256)) as average_as_graph
from    (
          select
                  duration_secs
                , cnt
                , cnt_cpu
                , cnt_other
                , ntile(&avg_as_bkts) over (order by duration_secs) as bkt
          from    (
                    select
&_IF_ORA11_OR_HIGHER                              round((cast(sample_time as date) - sql_exec_start) * 86400) + 1 as duration_secs
&_IF_LOWER_THAN_ORA11                             0                                                               as duration_secs
                          , count(*)                                                        as cnt
                          , count(case when session_state = 'ON CPU' then 1 end)            as cnt_cpu
                          , count(case when session_state != 'ON CPU' then 1 end)           as cnt_other
                    from
                            &global_ash
                    where
                            sql_id = '&si'
&_IF_ORA11_OR_HIGHER                      and     sql_exec_start = to_date('&ls', '&dm')
&_IF_ORA11_OR_HIGHER                      and     sql_exec_id = &li
                    and     '&slave_count' is not null and instr('&op', 'DISTRIB') > 0
                    and     '&_IF_ORA11_OR_HIGHER' is null
                    group by
&_IF_ORA11_OR_HIGHER                              cast(sample_time as date) - sql_exec_start
&_IF_LOWER_THAN_ORA11                             cast(sample_time as date) - to_date('01.01.1970', 'DD.MM.YYYY')
                  )
        )
group by
        bkt
order by
        bkt
;
#

column pga  format a6 &_IF_ORA112_OR_HIGHERP.print
column temp format a6 &_IF_ORA112_OR_HIGHERP.print
break on duration_secs

with
/* Base ASH data */
ash_base as
(
  select  /*+ materialize */
          &inst_id                  as instance_id
&_IF_ORA11_OR_HIGHER          , sql_exec_start
&_IF_LOWER_THAN_ORA11         , to_date('01.01.1970', 'DD.MM.YYYY') as sql_exec_start
        , cast(sample_time as date) as sample_time
        , session_state
&_IF_ORA112_OR_HIGHER         , nullif(pga_allocated, 0) as pga_allocated
&_IF_LOWER_THAN_ORA112        , to_number(null) as pga_allocated
&_IF_ORA112_OR_HIGHER         , nullif(temp_space_allocated, 0) as temp_space_allocated
&_IF_LOWER_THAN_ORA112        , to_number(null) as temp_space_allocated
  from
          &global_ash
  where
          sql_id = '&si'
&_IF_ORA11_OR_HIGHER    and     sql_exec_start = to_date('&ls', '&dm')
&_IF_ORA11_OR_HIGHER    and     sql_exec_id = &li
  and     '&slave_count' is not null
  and     instr('&op', 'DISTRIB') > 0
  and     '&_IF_ORA11_OR_HIGHER' is null
),
/* Three different points in time: The actual start, the first and last ASH sample */
dates as
(
  select
          min(sql_exec_start) as sql_exec_start
        , min(sample_time)    as min_sample_time
        , max(sample_time)    as max_sample_time
  from
          ash_base
),
/* Calculate a virtual timeline that should correspond to the samples */
/* Just in case we had no activity at all at a specific sample time */
/* Together with the instances this will be our driving rowsource for the activity calculation */
timeline as
(
  /* Calculate backwards from first sample to actual start of execution */
  select
          min_sample_time - rownum * &sample_freq / 86400 as timeline
        , sql_exec_start
  from
          dates
  start with
          min_sample_time - rownum * &sample_freq / 86400 >= sql_exec_start
  connect by
          min_sample_time - rownum * &sample_freq / 86400 >= sql_exec_start
  ---------
  union all
  ---------
  /* Calculate forward from first sample to last sample */
  select
          min_sample_time + (rownum - 1) * &sample_freq / 86400
        , sql_exec_start
  from
          dates
  start with
          min_sample_time + (rownum - 1) * &sample_freq / 86400 < max_sample_time + &sample_freq / 86400
  connect by
          min_sample_time + (rownum - 1) * &sample_freq / 86400 < max_sample_time + &sample_freq / 86400
  -- order by
  --        timeline
),
/* Instances found in ASH sample data */
instance_data
as
(
  select
          distinct
          instance_id
  from
          ash_base
),
/* Simply the cartesian product of timeline and instances */
/* Our driving rowsource */
timeline_inst
as
(
  select
          t.timeline    as sample_time
        , i.instance_id as instance_id
        , t.sql_exec_start
  from
          timeline t
        , instance_data i
),
/* Outer join the ASH samples to the timeline / instance rowsource */
ash_data as
(
  select
          t.sample_time
        , t.instance_id
        , ash.session_state
        , t.sql_exec_start
        , ash.pga_allocated
        , ash.temp_space_allocated
  from
          timeline_inst t
        , ash_base ash
  where
  /* Samples might deviate from the virtual timeline */
  /* In particular historic ASH rows from multiple RAC instances */
  /* Hence we join on a range */
          &sample_freq > 1 and
          ash.sample_time (+) >= t.sample_time - &sample_freq  / 2 / 86400
  and     ash.sample_time (+) <  t.sample_time + &sample_freq  / 2 / 86400
  and     ash.instance_id (+) = t.instance_id
  ---------
  union all
  ---------
  /* The one second interval is a special case since DATEs cannot calculate sub-seconds */
  /* Hence we can simply do an equi join */
  select
          t.sample_time
        , t.instance_id
        , ash.session_state
        , t.sql_exec_start
        , ash.pga_allocated
        , ash.temp_space_allocated
  from
          timeline_inst t
        , ash_base ash
  where
          &sample_freq = 1 and
          ash.sample_time (+) = t.sample_time
  and     ash.instance_id (+) = t.instance_id
--  order by
--          sample_time
--        , instance_id
),
/* Group the ASH data by sample_time */
ash_distrib as
(
  select
          instance_id
        , duration_secs
        , cnt
        , cnt_cpu
        , cnt_other
        , pga_mem
        , temp_space_alloc
        , ntile(&avg_as_bkts) over (partition by instance_id order by duration_secs) as bkt
  from    (
            select
                    round((sample_time  - sql_exec_start) * 86400) + 1    as duration_secs
                  , count(session_state)                                  as cnt
                  , count(case when session_state = 'ON CPU' then 1 end)  as cnt_cpu
                  , count(case when session_state != 'ON CPU' then 1 end) as cnt_other
                  , sum(pga_allocated)                                    as pga_mem
                  , sum(temp_space_allocated)                             as temp_space_alloc
                  , instance_id
            from
                    ash_data
            group by
                    sample_time - sql_exec_start
                  , instance_id
          )
),
/* and compress into the target number of buckets */
ash_distrib_bkts as
(
  /* BKT could be kept for sorting, but DURATION_SECS is assumed to be increasing, too */
  select
          instance_id
        , max(duration_secs)                                                                                            as duration_secs
        , round(avg(pga_mem))                                                                                           as pga_mem
        , round(avg(temp_space_alloc))                                                                                  as temp_space
        , round(avg(cnt_cpu), 2)                                                                                        as cpu
        , round(avg(cnt_other), 2)                                                                                      as other
        , round(avg(cnt), 2)                                                                                            as average_as
        , cast(rpad('&gc', round(avg(cnt_cpu)), '&gc') || rpad('&gc2', round(avg(cnt_other)), '&gc2') as varchar2(256)) as average_as_graph
  from
          ash_distrib
  group by
          bkt
        , instance_id
  -- order by
  --         bkt
  --       , instance_id
),
/* We need some log based data for formatting the PGA / TEMP figures */
ash_distrib_bkts_prefmt as
(
  select
          instance_id
        , duration_secs
        , pga_mem
        , trunc(log(10, abs(case pga_mem when 0 then 1 else pga_mem end)))               as power_10_pga_mem
        , trunc(mod(log(10, abs(case pga_mem when 0 then 1 else pga_mem end)) ,3))       as power_10_pga_mem_mod_3
        , temp_space
        , trunc(log(10, abs(case temp_space when 0 then 1 else temp_space end)))         as power_10_temp_space
        , trunc(mod(log(10, abs(case temp_space when 0 then 1 else temp_space end)), 3)) as power_10_temp_space_mod_3
        , case when cpu >= &rnd_thr then round(cpu) else cpu end                         as cpu
        , case when other >= &rnd_thr then round(other) else other end                   as other
        , case when average_as >= &rnd_thr then round(average_as) else average_as end    as average_as
        , average_as_graph
  from
          ash_distrib_bkts
),
/* Format the PGA / TEMP figures */
ash_distrib_bkts_fmt as
(
  select
          instance_id
        , duration_secs
        , to_char(round(pga_mem / power(10, power_10_pga_mem - case when power_10_pga_mem > 0 and power_10_pga_mem_mod_3 = 0 then 3 else power_10_pga_mem_mod_3 end)), 'FM99999') ||
          case power_10_pga_mem - case when power_10_pga_mem > 0 and power_10_pga_mem_mod_3 = 0 then 3 else power_10_pga_mem_mod_3 end
          when 0            then ' '
          when 1            then ' '
          when 3*1          then 'K'
          when 3*2          then 'M'
          when 3*3          then 'G'
          when 3*4          then 'T'
          when 3*5          then 'P'
          when 3*6          then 'E'
          else case
               when pga_mem is null
               then null
               else '*10^'||to_char(power_10_pga_mem - case when power_10_pga_mem > 0 and power_10_pga_mem_mod_3 = 0 then 3 else power_10_pga_mem_mod_3 end)
               end
          end      as pga_mem_format
        , to_char(round(temp_space / power(10, power_10_temp_space - case when power_10_temp_space > 0 and power_10_temp_space_mod_3 = 0 then 3 else power_10_temp_space_mod_3 end)), 'FM99999') ||
          case power_10_temp_space - case when power_10_temp_space > 0 and power_10_temp_space_mod_3 = 0 then 3 else power_10_temp_space_mod_3 end
          when 0            then ' '
          when 1            then ' '
          when 3*1          then 'K'
          when 3*2          then 'M'
          when 3*3          then 'G'
          when 3*4          then 'T'
          when 3*5          then 'P'
          when 3*6          then 'E'
          else case
               when temp_space is null
               then null
               else '*10^'||to_char(power_10_temp_space - case when power_10_temp_space > 0 and power_10_temp_space_mod_3 = 0 then 3 else power_10_temp_space_mod_3 end)
               end
          end      as temp_space_format
        , cpu
        , other
        , average_as
        , average_as_graph
  from
          ash_distrib_bkts_prefmt
)
select
        instance_id
      , duration_secs
      , lpad(pga_mem_format, 6)    as pga
      , lpad(temp_space_format, 6) as temp
      , cpu
      , other
      , average_as
      , average_as_graph
from
        ash_distrib_bkts_fmt
order by
        duration_secs
      , instance_id
;

column pga  clear
column temp clear

column average_as_graph clear
column instance_id      clear

clear breaks

prompt
prompt

set pagesize 0 feedback on

/* The following code snippet represents the core ASH based information for the plan line related ASH info */
/* It will be re-used if no execution plan could be found */
/* Therefore it will be saved to a file and re-loaded into the SQL buffer after execution of this statement */

/* Activity details on execution plan line level */

/* No read consistency on V$ views, therefore we materialize here the ASH content required */
with
ash_base as
(
  select  /*+ materialize */
          &inst_id
&_IF_ORA11_OR_HIGHER          , nvl(sql_plan_line_id, 0)                                                                      as sql_plan_line_id
&_IF_LOWER_THAN_ORA11         , 0  as sql_plan_line_id
&_IF_ORA11_OR_HIGHER          , sql_plan_operation || ' ' || sql_plan_options                                                 as plan_operation
&_IF_LOWER_THAN_ORA11         , '' as plan_operation
        , case
          when session_state = 'WAITING' then nvl(event, '<Wait Event Is Null>') else session_state end as event
        , program
        , sql_plan_hash_value
        , sample_time
&_IF_ORA11_OR_HIGHER          , sql_exec_start
&_IF_LOWER_THAN_ORA11         , to_date('01.01.1970', 'DD.MM.YYYY')                                                           as sql_exec_start
  from
          &global_ash
  where
          sql_id = '&si'
&_IF_ORA11_OR_HIGHER  and     sql_exec_start = to_date('&ls', '&dm')
&_IF_ORA11_OR_HIGHER  and     sql_exec_id = &li
  and     '&_IF_ORA11_OR_HIGHER' is null
  and     (instr('&op', 'ASH') > 0 or instr('&op', 'DISTRIB') > 0 or instr('&op', 'TIMELINE') > 0)
),
/* Distribution of Parallel Slaves (including QC) based on ASH */
/* This statement is effectively turned into a NOOP in versions below 11g */
/* Use LISTAGG() from 11.2 on, in 11.1 use XMLAGG() instead for string aggregation */
parallel_procs as
(
  select
          plan_line
        , procs
        , case when length(procs_graph) > &pgs then substr(procs_graph, 1, &pgs) || '...' else procs_graph end as procs_graph
  from    (
            select
                    plan_line
&_IF_ORA112_OR_HIGHER                   , listagg(case when rn > &topnp + 1 then null when rn = &topnp + 1 then '...' else process || '(' || cnt || ')' end, ',') within group (order by rn)                                                                                                                                                                          as procs
&_IF_LOWER_THAN_ORA112                  , ltrim(extract(xmlagg(xmlelement("V", case when rn > &topnp + 1 then null when rn = &topnp + 1 then ',' || '...' else ',' || process || '(' || cnt || ')' end) order by rn), '/V/text()'), ',')                                                                                                                                                                 as procs
&_IF_ORA112_OR_HIGHER                   , listagg(rpad(case when mod(rn - 1, 16) > 9 then chr(65 + mod(rn - 1, 16) - 10) else chr(48 + mod(rn - 1, 16)) end, case when round(ratio * &pgs) < 1 then 1 else round(ratio * &pgs) end, case when mod(rn - 1, 16) > 9 then chr(65 + mod(rn - 1, 16) - 10) else chr(48 + mod(rn - 1, 16)) end)) within group (order by rn) as procs_graph
&_IF_LOWER_THAN_ORA112                  , ltrim(extract(xmlagg(xmlelement("V", rpad(case when mod(rn - 1, 16) > 9 then chr(65 + mod(rn - 1, 16) - 10) else chr(48 + mod(rn - 1, 16)) end, case when round(ratio * &pgs) < 1 then 1 else round(ratio * &pgs) end, case when mod(rn - 1, 16) > 9 then chr(65 + mod(rn - 1, 16) - 10) else chr(48 + mod(rn - 1, 16)) end)) order by rn), '/V/text()'), ',') as procs_graph
            from    (
                      select
                              plan_line
                            , process
                            , cnt
                            , cnt / case when instr('&op', 'DISTRIB_TOT') > 0 then total_cnt when instr('&op', 'DISTRIB_REL') > 0 then max(total_cnt_plan_line) over () else total_cnt_plan_line end as ratio
                            , row_number() over (partition by plan_line order by cnt desc, process) as rn
                      from    (
                                select
                                        distinct
                                        sql_plan_line_id                                                                                                                           as plan_line
                                      , case when to_number(nvl('&ic', '0')) > 1 then &inst_id || '-' end || regexp_replace(program, '^.*\((P[[:alnum:]]{3})\)$', '\1', 1, 1, 'c') as process
                                      , count(*) over (partition by sql_plan_line_id, &inst_id || '-' || regexp_replace(program, '^.*\((P[[:alnum:]]{3})\)$', '\1', 1, 1, 'c'))    as cnt
                                      , count(*) over (partition by sql_plan_line_id)                                                                                              as total_cnt_plan_line
                                      , count(*) over ()                                                                                                                           as total_cnt
                                from
                                        ash_base
                                where   '&_IF_ORA11_OR_HIGHER' is null
                                and     instr('&op', 'DISTRIB') > 0
                              )
                    )
            where
                    rn <= &pgs + 1
            group by
                    plan_line
          )
),
/* Activity from ASH */
ash as
(
  select
          plan_line
&_IF_ORA112_OR_HIGHER          , listagg(case when rn > &topnw + 1 then null when rn = &topnw + 1 then '...' else event || '(' || cnt || ')' end, ',') within group (order by rn) as activity
&_IF_LOWER_THAN_ORA112         , ltrim(extract(xmlagg(xmlelement("V", case when rn > &topnw + 1 then null when rn = &topnw + 1 then ',' || '...' else ',' || event || '(' || cnt || ')' end) order by rn), '/V/text()'), ',') as activity
        , rpad(' ', nvl(round(sum_cnt / nullif(total_cnt, 0) * &wgs), 0) + 1, '&gc')                                                                       as activity_graph
  from    (
            select
                    plan_line
                  , event
                  , cnt
                  , total_cnt
                  , row_number() over (partition by plan_line order by cnt desc, event) as rn
                  , sum(cnt) over (partition by plan_line)                              as sum_cnt
            from    (
                      select
                              distinct
                              sql_plan_line_id                                                     as plan_line
                            , event
                            , count(*) over (partition by sql_plan_line_id, event)                 as cnt
                            , count(*) over ()                                                     as total_cnt
                      from
                              ash_base
                      where   '&_IF_ORA11_OR_HIGHER' is null
                      and     instr('&op', 'ASH') > 0
                    )
          )
  where
          rn <= &topnw + 1
  group by
          plan_line
        , total_cnt
        , sum_cnt
),
/* The last active plan lines from ASH, if SQL is currently executing */
active_plan_lines as
(
  select
          distinct
          sql_plan_line_id as plan_line
  from
          ash_base
  where   sample_time >= sysdate - &las / 86400
  and     '&_IF_ORA11_OR_HIGHER' is null
  and     instr('&op', 'ASH') > 0
),
/* Activity time line per SQL plan line */
plan_line_timelines as
(
  select
          '+' || to_char(start_active, 'TM')                                                                                                              as start_active
        , to_char(duration_secs, 'TM')                                                                                                                    as duration_secs
        , plan_line
        , substr(rpad(' ', round(start_active / to_number('&ds') * &tgs)) || rpad('&gc', round(duration_secs / to_number('&ds') * &tgs), '&gc'), 1, &tgs) as time_active_graph
  from
          (
            select
                    round((min(sample_time) - min(sql_exec_start)) * 86400)    as start_active
                  , round(((max(sample_time) - min(sample_time)) * 86400)) + 1 as duration_secs
                  , sql_plan_line_id                                           as plan_line
            from
                    (
                      select
                              cast(sample_time as date) as sample_time
                            , sql_exec_start
                            , sql_plan_line_id
                      from
                              ash_base
                      where   '&_IF_ORA11_OR_HIGHER' is null
                      and     instr('&op', 'TIMELINE') > 0
                    )
            group by
                    sql_plan_line_id
          )
),
.

-- If you need to debug, comment the following line
-- set termout off

save .xplan_ash_temp replace

-- set termout on

i
-- The next three queries are based on the original XPLAN wrapper by Adrian Billington
-- to determine the PID and ORD information, only slightly modified to deal with
-- the 10g special case that V$SQL_PLAN_STATISTICS_ALL doesn't include the ID = 0 operation
-- and starts with 1 instead for Rowsource Statistics
sql_plan_data as
(
  select
          id
        , parent_id
  from
          &plan_table_name
  where
          sql_id = '&si'
  and     &second_id = &cn
),
hierarchy_data as
(
  select
          id
        , parent_id
  from
          sql_plan_data
  start with
          id in
          (
            select
                    id
            from
                    sql_plan_data p1
            where
                    not exists
                    (
                      select
                              null
                      from
                              sql_plan_data p2
                      where
                              p2.id = p1.parent_id
                    )
          )
  connect by
          prior id = parent_id
  order siblings by
          id desc
),
ordered_hierarchy_data as
(
  select
          id
        , parent_id                                as pid
        , row_number() over (order by rownum desc) as oid
        , max(id) over ()                          as maxid
        , min(id) over ()                          as minid
  from
          hierarchy_data
),
-- The following query uses the MAX values
-- rather than taking the values of PLAN OPERATION_ID = 0 (or 1 for 10g V$SQL_PLAN_STATISTICS_ALL)
-- for determining the grand totals
--
-- This is because queries that get cancelled do not
-- necessarily have yet sensible values in the root plan operation
--
-- Furthermore with Parallel Execution the elapsed time accumulated
-- with the ALLSTATS option for operations performed in parallel
-- will be greater than the wallclock elapsed time shown for the Query Coordinator
--
-- Note that if you use GATHER_PLAN_STATISTICS with the default
-- row sampling frequency the (LAST_)ELAPSED_TIME will be very likely
-- wrong and hence the time-based graphs and self-statistics will be misleading
--
-- Similar things might happen when cancelling queries
--
-- For queries running with STATISTICS_LEVEL = ALL (or sample frequency set to 1)
-- the A-TIME is pretty reliable
totals as
(
  select
          max(&last.cu_buffer_gets + &last.cr_buffer_gets) as total_lio
        , max(&last.elapsed_time)                          as total_elapsed
        , max(&last.disk_reads)                            as total_reads
        , max(&last.disk_writes)                           as total_writes
  from
          v$sql_plan_statistics_all
  where
          sql_id = '&si'
  and     child_number = &cn
  and     instr('&fo', 'STATS') > 0
  group by
          1
),
-- The totals for the direct descendants of an operation
-- These are required for calculating the work performed
-- by a (parent) operation itself
-- Basically this is the SUM grouped by PARENT_ID
direct_desc_totals as
(
  select
          sum(&last.cu_buffer_gets + &last.cr_buffer_gets) as lio
        , sum(&last.elapsed_time)                          as elapsed
        , sum(&last.disk_reads)                            as reads
        , sum(&last.disk_writes)                           as writes
        , parent_id
  from
          v$sql_plan_statistics_all
  where
          sql_id = '&si'
  and     child_number = &cn
  and     instr('&fo', 'STATS') > 0
  group by
          parent_id
),
-- Putting the three together
-- The statistics, direct descendant totals plus totals
extended_stats as
(
  select
          stats.id
        , stats.parent_id
        , stats.&last.elapsed_time                                  as elapsed
        , (stats.&last.cu_buffer_gets + stats.&last.cr_buffer_gets) as lio
        , stats.&last.starts                                        as starts
        , stats.&last.output_rows                                   as a_rows
        , stats.cardinality                                         as e_rows
        , stats.&last.disk_reads                                    as reads
        , stats.&last.disk_writes                                   as writes
        , ddt.elapsed                                               as ddt_elapsed
        , ddt.lio                                                   as ddt_lio
        , ddt.reads                                                 as ddt_reads
        , ddt.writes                                                as ddt_writes
        , t.total_elapsed
        , t.total_lio
        , t.total_reads
        , t.total_writes
  from
          v$sql_plan_statistics_all stats
        , direct_desc_totals ddt
        , totals t
  where
          stats.sql_id='&si'
  and     stats.child_number = &cn
  and     ddt.parent_id (+) = stats.id
  and     instr('&fo', 'STATS') > 0
),
-- Further information derived from above
derived_stats as
(
  select
          id
        , greatest(elapsed - nvl(ddt_elapsed , 0), 0)                              as elapsed_self
        , greatest(lio - nvl(ddt_lio, 0), 0)                                       as lio_self
        , trunc((greatest(lio - nvl(ddt_lio, 0), 0)) / nullif(a_rows, 0))          as lio_ratio
        , greatest(reads - nvl(ddt_reads, 0), 0)                                   as reads_self
        , greatest(writes - nvl(ddt_writes,0) ,0)                                  as writes_self
        , total_elapsed
        , total_lio
        , total_reads
        , total_writes
        , trunc(log(10, nullif(starts * e_rows / nullif(a_rows, 0), 0)))           as tcf_ratio
        , starts * e_rows                                                          as e_rows_times_start
  from
          extended_stats
),
/* Format the data as required */
formatted_data1 as
(
  select
          id
        , lio_ratio
        , total_elapsed
        , total_lio
        , total_reads
        , total_writes
        , to_char(numtodsinterval(round(elapsed_self / 10000) * 10000 / 1000000, 'SECOND'))                         as e_time_interval
          /* Imitate the DBMS_XPLAN number formatting */
        , case
          when lio_self >= 18000000000000000000 then to_char(18000000000000000000/1000000000000000000, 'FM99999') || 'E'
          when lio_self >= 10000000000000000000 then to_char(lio_self/1000000000000000000, 'FM99999') || 'E'
          when lio_self >= 10000000000000000 then to_char(lio_self/1000000000000000, 'FM99999') || 'P'
          when lio_self >= 10000000000000 then to_char(lio_self/1000000000000, 'FM99999') || 'T'
          when lio_self >= 10000000000 then to_char(lio_self/1000000000, 'FM99999') || 'G'
          when lio_self >= 10000000 then to_char(lio_self/1000000, 'FM99999') || 'M'
          when lio_self >= 100000 then to_char(lio_self/1000, 'FM99999') || 'K'
          else to_char(lio_self, 'FM99999') || ' '
          end                                                                                                       as lio_self_format
        , case
          when reads_self >= 18000000000000000000 then to_char(18000000000000000000/1000000000000000000, 'FM99999') || 'E'
          when reads_self >= 10000000000000000000 then to_char(reads_self/1000000000000000000, 'FM99999') || 'E'
          when reads_self >= 10000000000000000 then to_char(reads_self/1000000000000000, 'FM99999') || 'P'
          when reads_self >= 10000000000000 then to_char(reads_self/1000000000000, 'FM99999') || 'T'
          when reads_self >= 10000000000 then to_char(reads_self/1000000000, 'FM99999') || 'G'
          when reads_self >= 10000000 then to_char(reads_self/1000000, 'FM99999') || 'M'
          when reads_self >= 100000 then to_char(reads_self/1000, 'FM99999') || 'K'
          else to_char(reads_self, 'FM99999') || ' '
          end                                                                                                       as reads_self_format
        , case
          when writes_self >= 18000000000000000000 then to_char(18000000000000000000/1000000000000000000, 'FM99999') || 'E'
          when writes_self >= 10000000000000000000 then to_char(writes_self/1000000000000000000, 'FM99999') || 'E'
          when writes_self >= 10000000000000000 then to_char(writes_self/1000000000000000, 'FM99999') || 'P'
          when writes_self >= 10000000000000 then to_char(writes_self/1000000000000, 'FM99999') || 'T'
          when writes_self >= 10000000000 then to_char(writes_self/1000000000, 'FM99999') || 'G'
          when writes_self >= 10000000 then to_char(writes_self/1000000, 'FM99999') || 'M'
          when writes_self >= 100000 then to_char(writes_self/1000, 'FM99999') || 'K'
          else to_char(writes_self, 'FM99999') || ' '
          end                                                                                                       as writes_self_format
        , case
          when e_rows_times_start >= 18000000000000000000 then to_char(18000000000000000000/1000000000000000000, 'FM99999') || 'E'
          when e_rows_times_start >= 10000000000000000000 then to_char(e_rows_times_start/1000000000000000000, 'FM99999') || 'E'
          when e_rows_times_start >= 10000000000000000 then to_char(e_rows_times_start/1000000000000000, 'FM99999') || 'P'
          when e_rows_times_start >= 10000000000000 then to_char(e_rows_times_start/1000000000000, 'FM99999') || 'T'
          when e_rows_times_start >= 10000000000 then to_char(e_rows_times_start/1000000000, 'FM99999') || 'G'
          when e_rows_times_start >= 10000000 then to_char(e_rows_times_start/1000000, 'FM99999') || 'M'
          when e_rows_times_start >= 100000 then to_char(e_rows_times_start/1000, 'FM99999') || 'K'
          else to_char(e_rows_times_start, 'FM99999') || ' '
          end                                                                                                       as e_rows_times_start_format
        , rpad(' ', nvl(round(elapsed_self / nullif(total_elapsed, 0) * 12), 0) + 1, '&gc')                         as elapsed_self_graph
        , rpad(' ', nvl(round(lio_self / nullif(total_lio, 0) * 12), 0) + 1, '&gc')                                 as lio_self_graph
        , rpad(' ', nvl(round(reads_self / nullif(total_reads, 0) * 12), 0) + 1, '&gc')                             as reads_self_graph
        , rpad(' ', nvl(round(writes_self / nullif(total_writes, 0) * 12), 0) + 1, '&gc')                           as writes_self_graph
        , ' ' ||
          case
          when tcf_ratio > 0
          then rpad('-', tcf_ratio, '-')
          else rpad('+', tcf_ratio * -1, '+')
          end                                                                                                       as tcf_graph
  from
          derived_stats
),
/* The final formatted data */
formatted_data as
(
  select
          /*+ Convert the INTERVAL representation to the A-TIME representation used by DBMS_XPLAN
              by turning the days into hours */
          to_char(to_number(substr(e_time_interval, 2, 9)) * 24 + to_number(substr(e_time_interval, 12, 2)), 'FM900') ||
          substr(e_time_interval, 14, 9)
          as a_time_self
        , a.*
  from
          formatted_data1 a
),
/* Combine the information with the original DBMS_XPLAN output */
xplan_data as (
  select
          x.plan_table_output
        , o.id
        , o.pid
        , o.oid
        , o.maxid
        , o.minid
        , a.a_time_self
        , a.lio_self_format
        , a.reads_self_format
        , a.writes_self_format
        , cast(a.elapsed_self_graph as varchar2(20))               as elapsed_self_graph
        , cast(a.lio_self_graph as varchar2(20))                   as lio_self_graph
        , cast(a.reads_self_graph as varchar2(20))                 as reads_self_graph
        , cast(a.writes_self_graph as varchar2(20))                as writes_self_graph
        , a.lio_ratio
        , cast(a.tcf_graph as varchar2(20))                        as tcf_graph
        , a.total_elapsed
        , a.total_lio
        , a.total_reads
        , a.total_writes
        , a.e_rows_times_start_format
        , cast(p.procs as varchar2(200))                           as procs
        , cast(p.procs_graph as varchar2(100))                     as procs_graph
        , cast(w.activity as varchar2(200))                        as activity
        , cast(w.activity_graph as varchar2(50))                   as activity_graph
        , case when l.plan_line is not null then '&active_ind' end as line_active
        , t.start_active
        , t.duration_secs
        , t.time_active_graph
        , x.rn
  from
          (
            select  /* Take advantage of 11g table function dynamic sampling */
                    /*+ dynamic_sampling(dc, 2) */
                    /* This ROWNUM determines the order of the output/processing */
                    rownum as rn
                  , plan_table_output
            from
                    table(&plan_function('&si',&cn, &par_fil.'&fo')) dc
          ) x
        , ordered_hierarchy_data o
        , formatted_data a
        , parallel_procs p
        , ash w
        , active_plan_lines l
        , plan_line_timelines t
  where
          o.id (+) = case
                     when regexp_like(x.plan_table_output, '^\|[\* 0-9]+\|')
                     then to_number(regexp_substr(x.plan_table_output, '[0-9]+'))
                     end
  and     a.id (+) = case
                     when regexp_like(x.plan_table_output, '^\|[\* 0-9]+\|')
                     then to_number(regexp_substr(x.plan_table_output, '[0-9]+'))
                     end
  and     p.plan_line (+) = case
                            when regexp_like(x.plan_table_output, '^\|[\* 0-9]+\|')
                            then to_number(regexp_substr(x.plan_table_output, '[0-9]+'))
                            end
  and     w.plan_line (+) = case
                            when regexp_like(x.plan_table_output, '^\|[\* 0-9]+\|')
                            then to_number(regexp_substr(x.plan_table_output, '[0-9]+'))
                            end
  and     l.plan_line (+) = case
                            when regexp_like(x.plan_table_output, '^\|[\* 0-9]+\|')
                            then to_number(regexp_substr(x.plan_table_output, '[0-9]+'))
                            end
  and     t.plan_line (+) = case
                            when regexp_like(x.plan_table_output, '^\|[\* 0-9]+\|')
                            then to_number(regexp_substr(x.plan_table_output, '[0-9]+'))
                            end
)
/* Inject the additional data into the original DBMS_XPLAN output
   by using the MODEL clause */
select
        plan_table_output
      -- , plan_table_count
from
        xplan_data
model
        dimension by (rn as r)
        measures
        (
          cast(plan_table_output as varchar2(1000))                                                                      as plan_table_output
        , id
        , maxid
        , minid
        , pid
        , oid
        , a_time_self
        , lio_self_format
        , reads_self_format
        , writes_self_format
        , e_rows_times_start_format
        , elapsed_self_graph
        , lio_self_graph
        , reads_self_graph
        , writes_self_graph
        , lio_ratio
        , tcf_graph
        , total_elapsed
        , total_lio
        , total_reads
        , total_writes
        , greatest(max(length(maxid)) over () + 3, 6)                                                                    as csize
        , cast(null as varchar2(200))                                                                                    as inject
        , cast(null as varchar2(400))                                                                                    as inject2
        , cast(null as varchar2(400))                                                                                    as inject3
        , greatest(max(length(procs)) over () + 3, 28)                                                                   as procs_size
        , greatest(max(length(procs_graph)) over () + 3, 34)                                                             as procs_graph_size
        , greatest(max(length(activity)) over () + 3, 22)                                                                as activity_size
        , greatest(max(length(activity_graph)) over () + 3, 22)                                                          as activity_graph_size
        , greatest(max(length(line_active)) over () + 3, 6)                                                              as line_active_size
        , greatest(max(length(start_active)) over () + 3, 8)                                                             as start_active_size
        , greatest(max(length(duration_secs)) over () + 3, 6)                                                            as duration_secs_size
        , greatest(max(length(time_active_graph)) over () + 3, 20)                                                       as time_active_graph_size
        , case when instr('&op', 'DISTRIB') > 0 and '&slave_count' is not null then max(length(procs)) over () end       as procs_is_not_null
        , case when instr('&op', 'DISTRIB') > 0 and '&slave_count' is not null then max(length(procs_graph)) over () end as procs_graph_is_not_null
        , case when instr('&op', 'ASH') > 0 then max(length(activity)) over () end                                       as activity_is_not_null
        , case when instr('&op', 'ASH') > 0 then max(length(activity_graph)) over () end                                 as activity_graph_is_not_null
        , case when instr('&op', 'ASH') > 0 then max(length(line_active)) over () end                                    as line_active_is_not_null
        , case when instr('&op', 'TIMELINE') > 0 then max(length(start_active)) over () end                              as start_active_is_not_null
        , case when instr('&op', 'TIMELINE') > 0 then max(length(duration_secs)) over () end                             as duration_secs_is_not_null
        , case when instr('&op', 'TIMELINE') > 0 then max(length(time_active_graph)) over () end                         as time_active_graph_is_not_null
        , procs
        , procs_graph
        , activity
        , activity_graph
        , line_active
        , start_active
        , duration_secs
        , time_active_graph
        -- , count(*) over () as plan_table_count
        )
        rules sequential order
        (
          /* Prepare the injection of the OID / PID / ACT info */
          inject[r]  = case
                               /* MINID/MAXID are the same for all rows
                                  so it doesn't really matter
                                  which offset we refer to */
                       when    id[cv(r)+1] = minid[cv(r)+1]
                            or id[cv(r)+3] = minid[cv(r)+3]
                            or id[cv(r)-1] = maxid[cv(r)-1]
                       then rpad('-', case when '&c_pid' is not null then csize[cv()] else 0 end + case when '&c_ord' is not null then csize[cv()] else 0 end + case when line_active_is_not_null[cv()] is not null and '&c_act' is not null then line_active_size[cv()] else 0 end, '-')
                       when id[cv(r)+2] = minid[cv(r)+2]
                       then '|' || case when '&c_pid' is not null then lpad('Pid |', csize[cv()]) end || case when '&c_ord' is not null then lpad('Ord |', csize[cv()]) end || case when line_active_is_not_null[cv()] is not null and '&c_act' is not null then lpad('Act |', line_active_size[cv()]) end
                       when id[cv()] is not null
                       then '|' || case when '&c_pid' is not null then lpad(pid[cv()] || ' |', csize[cv()]) end || case when '&c_ord' is not null then lpad(oid[cv()] || ' |', csize[cv()]) end || case when line_active_is_not_null[cv()] is not null and '&c_act' is not null then lpad(line_active[cv()] || ' |', line_active_size[cv()]) end
                       end
          /* Prepare the injection of the remaining info */
        , inject2[r] = case
                       when    id[cv(r)+1] = minid[cv(r)+1]
                            or id[cv(r)+3] = minid[cv(r)+3]
                            or id[cv(r)-1] = maxid[cv(r)-1]
                       -- Determine the line width for the three rows where we have horizontal lines
                       then rpad('-',
                            case when coalesce(total_elapsed[cv(r)+1], total_elapsed[cv(r)+3], total_elapsed[cv(r)-1]) > 0 and '&c_a_time_self' is not null then
                            14 else 0 end /* A_TIME_SELF */       +
                            case when coalesce(total_lio[cv(r)+1], total_lio[cv(r)+3], total_lio[cv(r)-1]) > 0 and '&c_lio_self' is not null then
                            11 else 0 end /* LIO_SELF */          +
                            case when coalesce(total_reads[cv(r)+1], total_reads[cv(r)+3], total_reads[cv(r)-1]) > 0 and '&c_reads_self' is not null then
                            11 else 0 end /* READS_SELF */        +
                            case when coalesce(total_writes[cv(r)+1], total_writes[cv(r)+3], total_writes[cv(r)-1]) > 0 and '&c_writes_self' is not null then
                            11 else 0 end /* WRITES_SELF */       +
                            case when coalesce(total_elapsed[cv(r)+1], total_elapsed[cv(r)+3], total_elapsed[cv(r)-1]) > 0 and '&c_a_time_self_graph' is not null then
                            14 else 0 end /* A_TIME_SELF_GRAPH */ +
                            case when coalesce(total_lio[cv(r)+1], total_lio[cv(r)+3], total_lio[cv(r)-1]) > 0 and '&c_lio_self_graph' is not null then
                            14 else 0 end /* LIO_SELF_GRAPH */    +
                            case when coalesce(total_reads[cv(r)+1], total_reads[cv(r)+3], total_reads[cv(r)-1]) > 0 and '&c_reads_self_graph' is not null then
                            14 else 0 end /* READS_SELF_GRAPH */  +
                            case when coalesce(total_writes[cv(r)+1], total_writes[cv(r)+3], total_writes[cv(r)-1]) > 0 and '&c_writes_self_graph' is not null then
                            14 else 0 end /* WRITES_SELF_GRAPH */ +
                            case when coalesce(total_lio[cv(r)+1], total_lio[cv(r)+3], total_lio[cv(r)-1]) > 0 and '&c_lio_ratio' is not null then
                            11 else 0 end /* LIO_RATIO */         +
                            case when coalesce(total_elapsed[cv(r)+1], total_elapsed[cv(r)+3], total_elapsed[cv(r)-1]) > 0 and '&c_tcf_graph' is not null then
                            11 else 0 end /* TCF_GRAPH */         +
                            case when coalesce(total_elapsed[cv(r)+1], total_elapsed[cv(r)+3], total_elapsed[cv(r)-1]) > 0 and '&c_e_rows_times_start' is not null then
                            11 else 0 end /* E_ROWS_TIMES_START */
                            , '-')
                       -- The additional headings
                       when id[cv(r)+2] = minid[cv(r)+2]
                       then
                            case when total_elapsed[cv(r)+2] > 0 and '&c_a_time_self' is not null then
                            lpad('A-Time Self |' , 14) end ||
                            case when total_lio[cv(r)+2] > 0 and '&c_lio_self' is not null then
                            lpad('Bufs Self |'   , 11) end ||
                            case when total_reads[cv(r)+2] > 0 and '&c_reads_self' is not null then
                            lpad('Reads Self|'   , 11) end ||
                            case when total_writes[cv(r)+2] > 0 and '&c_writes_self' is not null then
                            lpad('Write Self|'   , 11) end ||
                            case when total_elapsed[cv(r)+2] > 0 and '&c_a_time_self_graph' is not null then
                            lpad('A-Ti S-Graph |', 14) end ||
                            case when total_lio[cv(r)+2] > 0 and '&c_lio_self_graph' is not null then
                            lpad('Bufs S-Graph |', 14) end ||
                            case when total_reads[cv(r)+2] > 0 and '&c_reads_self_graph' is not null then
                            lpad('Reads S-Graph|', 14) end ||
                            case when total_writes[cv(r)+2] > 0 and '&c_writes_self_graph' is not null then
                            lpad('Write S-Graph|', 14) end ||
                            case when total_lio[cv(r)+2] > 0 and '&c_lio_ratio' is not null then
                            lpad('LIO Ratio |'   , 11) end ||
                            case when total_elapsed[cv(r)+2] > 0 and '&c_tcf_graph' is not null then
                            lpad('TCF Graph |'   , 11) end ||
                            case when total_elapsed[cv(r)+2] > 0 and '&c_e_rows_times_start' is not null then
                            lpad('E-Rows*Sta|'   , 11) end
                       -- The actual data
                       when id[cv()] is not null
                       then
                            case when total_elapsed[cv()] > 0 and '&c_a_time_self' is not null then
                            lpad(a_time_self[cv()]               || ' |', 14) end ||
                            case when total_lio[cv()] > 0 and '&c_lio_self' is not null then
                            lpad(lio_self_format[cv()]           ||  '|', 11) end ||
                            case when total_reads[cv()] > 0 and '&c_reads_self' is not null then
                            lpad(reads_self_format[cv()]         ||  '|', 11) end ||
                            case when total_writes[cv()] > 0 and '&c_writes_self' is not null then
                            lpad(writes_self_format[cv()]        ||  '|', 11) end ||
                            case when total_elapsed[cv()] > 0 and '&c_a_time_self_graph' is not null then
                            rpad(elapsed_self_graph[cv()], 13)   ||  '|'      end ||
                            case when total_lio[cv()] > 0 and '&c_lio_self_graph' is not null then
                            rpad(lio_self_graph[cv()], 13)       ||  '|'      end ||
                            case when total_reads[cv()] > 0 and '&c_reads_self_graph' is not null then
                            rpad(reads_self_graph[cv()], 13)     ||  '|'      end ||
                            case when total_writes[cv()] > 0 and '&c_writes_self_graph' is not null then
                            rpad(writes_self_graph[cv()], 13)    ||  '|'      end ||
                            case when total_lio[cv()] > 0 and '&c_lio_ratio' is not null then
                            lpad(lio_ratio[cv()]                 || ' |', 11) end ||
                            case when total_elapsed[cv()] > 0 and '&c_tcf_graph' is not null then
                            rpad(tcf_graph[cv()], 9)             || ' |'      end ||
                            case when total_elapsed[cv()] > 0 and '&c_e_rows_times_start' is not null then
                            lpad(e_rows_times_start_format[cv()] ||  '|', 11) end
                       end
        /* The additional ASH based info (except Active which is part of inject) */
        , inject3[r] = case
                       when    id[cv(r)+1] = minid[cv(r)+1]
                            or id[cv(r)+3] = minid[cv(r)+3]
                            or id[cv(r)-1] = maxid[cv(r)-1]
                       -- Determine the line width for the three rows where we have horizontal lines
                       then rpad('-',
                            case when coalesce(start_active_is_not_null[cv(r)+1], start_active_is_not_null[cv(r)+3], start_active_is_not_null[cv(r)-1]) is not null and '&c_start_active' is not null then
                            start_active_size[cv(r)+1] else 0 end       /* START_ACTIVE */       +
                            case when coalesce(duration_secs_is_not_null[cv(r)+1], duration_secs_is_not_null[cv(r)+3], duration_secs_is_not_null[cv(r)-1]) is not null and '&c_duration_secs' is not null then
                            duration_secs_size[cv(r)+1] else 0 end      /* DURATION_SECS */      +
                            case when coalesce(time_active_graph_is_not_null[cv(r)+1], time_active_graph_is_not_null[cv(r)+3], time_active_graph_is_not_null[cv(r)-1]) is not null and '&c_time_active_graph' is not null then
                            time_active_graph_size[cv(r)+1] else 0 end  /* TIME_ACTIVE_GRAPH */  +
                            case when coalesce(procs_is_not_null[cv(r)+1], procs_is_not_null[cv(r)+3], procs_is_not_null[cv(r)-1]) is not null and '&c_procs' is not null then
                            procs_size[cv(r)+1] else 0 end              /* PROCS */              +
                            case when coalesce(procs_graph_is_not_null[cv(r)+1], procs_graph_is_not_null[cv(r)+3], procs_graph_is_not_null[cv(r)-1]) is not null and '&c_procs_graph' is not null then
                            procs_graph_size[cv(r)+1] else 0 end        /* PROCS_GRAPH */        +
                            case when coalesce(activity_graph_is_not_null[cv(r)+1], activity_graph_is_not_null[cv(r)+3], activity_graph_is_not_null[cv(r)-1]) is not null and '&c_activity_graph' is not null then
                            activity_graph_size[cv(r)+1] else 0 end     /* ACTIVITY_GRAPH */     +
                            case when coalesce(activity_is_not_null[cv(r)+1], activity_is_not_null[cv(r)+3], activity_is_not_null[cv(r)-1]) is not null and '&c_activity' is not null then
                            activity_size[cv(r)+1] else 0 end           /* ACTIVITY */
                            , '-')
                       -- The additional headings
                       when id[cv(r)+2] = minid[cv(r)+2]
                       then
                            case when start_active_is_not_null[cv(r)+2] is not null and '&c_start_active' is not null then
                            rpad(' Start', start_active_size[cv(r)+2] - 1)                             || '|' end ||
                            case when duration_secs_is_not_null[cv(r)+2] is not null and '&c_duration_secs' is not null then
                            rpad(' Dur', duration_secs_size[cv(r)+2] - 1)                              || '|' end ||
                            case when time_active_graph_is_not_null[cv(r)+2] is not null and '&c_time_active_graph' is not null then
                            rpad(' Time Active Graph', time_active_graph_size[cv(r)+2] - 1)            || '|' end ||
                            case when procs_is_not_null[cv(r)+2] is not null and '&c_procs' is not null then
                            rpad(' Parallel Distribution ASH', procs_size[cv(r)+2] - 1)                || '|' end ||
                            case when procs_graph_is_not_null[cv(r)+2] is not null and '&c_procs_graph' is not null then
                            rpad(' Parallel Distribution Graph ASH', procs_graph_size[cv(r)+2] - 1)    || '|' end ||
                            case when activity_graph_is_not_null[cv(r)+2] is not null and '&c_activity_graph' is not null then
                            rpad(' Activity Graph ASH', activity_graph_size[cv(r)+2] - 1)              || '|' end ||
                            case when activity_is_not_null[cv(r)+2] is not null and '&c_activity' is not null then
                            rpad(' Top &topnw Activity ASH', activity_size[cv(r)+2] - 1)               || '|' end
                       -- The actual data
                       when id[cv()] is not null
                       then
                            case when start_active_is_not_null[cv()] is not null and '&c_start_active' is not null then
                            lpad(start_active[cv()]           ||  ' |', start_active_size[cv()])               end ||
                            case when duration_secs_is_not_null[cv()] is not null and '&c_duration_secs' is not null then
                            lpad(duration_secs[cv()]           ||  ' |', duration_secs_size[cv()])             end ||
                            case when time_active_graph_is_not_null[cv()] is not null and '&c_time_active_graph' is not null then
                            rpad(' ' || time_active_graph[cv()], time_active_graph_size[cv()] - 1)      || '|' end ||
                            case when procs_is_not_null[cv()] is not null and '&c_procs' is not null then
                            rpad(' ' || procs[cv()], procs_size[cv()] - 1)                              || '|' end ||
                            case when procs_graph_is_not_null[cv()] is not null and '&c_procs_graph' is not null then
                            rpad(' ' || procs_graph[cv()], procs_graph_size[cv()] - 1)                  || '|' end ||
                            case when activity_graph_is_not_null[cv()] is not null and '&c_activity_graph' is not null then
                            rpad(' ' || substr(activity_graph[cv()], 2), activity_graph_size[cv()] - 1) || '|' end ||
                            case when activity_is_not_null[cv()] is not null and '&c_activity' is not null then
                            rpad(' ' || activity[cv()], activity_size[cv()] - 1)                        || '|' end
                       end
          /* Putting it all together */
        , plan_table_output[r] = case
                                 when inject[cv()] like '---%'
                                 then inject[cv()] || plan_table_output[cv()] || inject2[cv()] || inject3[cv()]
                                 when inject[cv()] is present
                                 then regexp_replace(plan_table_output[cv()], '\|', inject[cv()], 1, 2) || inject2[cv()] || inject3[cv()]
                                 else plan_table_output[cv()]
                                 end
        )
order by
        r
;

/* Determine which columns to show in the output following */

set heading on pagesize 999 feedback off

column show_line_active       new_value _SHOW_LINE_ACTIVE       noprint
column show_procs             new_value _SHOW_PROCS             noprint
column show_procs_graph       new_value _SHOW_PROCS_GRAPH       noprint
column show_activity          new_value _SHOW_ACTIVITY          noprint
column show_activity_graph    new_value _SHOW_ACTIVITY_GRAPH    noprint
column show_start_active      new_value _SHOW_START_ACTIVE      noprint
column show_duration_secs     new_value _SHOW_DURATION_SECS     noprint
column show_time_active_graph new_value _SHOW_TIME_ACTIVE_GRAPH noprint

select
        case when '&c_act' is not null and instr('&op', 'ASH') > 0 then '' else 'no' end                    as show_line_active
      , case when '&c_procs' is not null and instr('&op', 'DISTRIB') > 0 then '' else 'no' end              as show_procs
      , case when '&c_procs_graph' is not null and instr('&op', 'DISTRIB') > 0 then '' else 'no' end        as show_procs_graph
      , case when '&c_activity' is not null and instr('&op', 'ASH') > 0 then '' else 'no' end               as show_activity
      , case when '&c_activity_graph' is not null and instr('&op', 'ASH') > 0 then '' else 'no' end         as show_activity_graph
      , case when '&c_start_active' is not null and instr('&op', 'TIMELINE') > 0 then '' else 'no' end      as show_start_active
      , case when '&c_duration_secs' is not null and instr('&op', 'TIMELINE') > 0 then '' else 'no' end     as show_duration_secs
      , case when '&c_time_active_graph' is not null and instr('&op', 'TIMELINE') > 0 then '' else 'no' end as show_time_active_graph
from
        dual
;

column show_line_active       clear
column show_procs             clear
column show_procs_graph       clear
column show_activity          clear
column show_activity_graph    clear
column show_start_active      clear
column show_duration_secs     clear
column show_time_active_graph clear

column plan_operation    format a30
column line_active       format a5  heading "Act"                              &_SHOW_LINE_ACTIVE.print
column procs             format a55 heading "Parallel Distribution ASH"        &_SHOW_PROCS.print
column procs_graph       format a40 heading "Parallel Distribution Graph ASH"  &_SHOW_PROCS_GRAPH.print
column activity          format a80 heading "Activity Graph ASH"               &_SHOW_ACTIVITY.print
column activity_graph    format a25 heading "Top &topnw Activity ASH"          &_SHOW_ACTIVITY_GRAPH.print
column start_active      format a15 heading "Start"                            &_SHOW_START_ACTIVE.print
column duration_secs     format a15 heading "Dur"                              &_SHOW_DURATION_SECS.print
column time_active_graph format a25 heading "Time Active Graph"                &_SHOW_TIME_ACTIVE_GRAPH.print

/* If no plan could be found, provide mininum information based on ASH about plan line activity */

/* Get the previously saved buffer contents */

-- If you need to debug, comment the following line
set termout off

get .xplan_ash_temp

set termout on

i
/* Info about the plan operation from ASH */
plan_operations as
(
  select
          distinct
          sql_plan_line_id    as plan_line
        , sql_plan_hash_value as plan_hash_value
        , plan_operation
  from
          ash_base
  where
          '&_IF_ORA11_OR_HIGHER' is null
  and     (instr('&op', 'ASH') > 0 or instr('&op', 'DISTRIB') > 0 or instr('&op', 'TIMELINE') > 0)
)
select
        o.plan_hash_value
      , o.plan_line
      , o.plan_operation
      , case when l.plan_line is not null then '&active_ind' end as line_active
      , t.start_active
      , t.duration_secs
      , t.time_active_graph
      , p.procs
      , p.procs_graph
      , a.activity_graph
      , a.activity
from
        plan_operations o
      , parallel_procs p
      , ash a
      , plan_line_timelines t
      , active_plan_lines l
where
        o.plan_line = p.plan_line (+)
and     o.plan_line = a.plan_line (+)
and     o.plan_line = t.plan_line (+)
and     o.plan_line = l.plan_line (+)
and     '&_IF_ORA11_OR_HIGHER' is null
and     (instr('&op', 'ASH') > 0 or instr('&op', 'DISTRIB') > 0  or instr('&op', 'TIMELINE') > 0)
and     '&plan_exists' is null
order by
        plan_line
;

column plan_operation clear
column line_active clear
column procs clear
column procs_graph clear
column activity clear
column activity_graph clear
column start_active clear
column duration_secs clear
column time_active_graph clear

-----------------------------------
-- Clean up SQL*Plus environment --
-----------------------------------

undefine default_fo
undefine default_source
undefine default_operation
undefine default_ash
undefine prev_sql_id
undefine prev_cn
undefine prev_sql_exec_start
undefine prev_sql_exec_id
undefine last_exec_start
undefine last_exec_id
undefine last_exec_second_id
undefine last
undefine child_ad
undefine slave_count
undefine topnp
undefine topnw
undefine pgs
undefine wgs
undefine si
undefine cn
undefine fo
undefine so
undefine ls
undefine li
undefine op
undefine ah
undefine co
undefine gc
undefine gc2
undefine 1
undefine 2
undefine 3
undefine 4
undefine 5
undefine 6
undefine 7
undefine 8
undefine 9
undefine sid_sql_id
undefine sid_child_no
undefine sid_sql_exec_start
undefine sid_sql_exec_id
undefine _IF_ORA11_OR_HIGHER
undefine _IF_LOWER_THAN_ORA11
undefine _IF_ORA112_OR_HIGHER
undefine _IF_LOWER_THAN_ORA112
undefine _IF_ORA112_OR_HIGHERP
undefine _IF_CROSS_INSTANCE
undefine plan_table_name
undefine las
undefine active_ind
undefine ic
undefine dm
undefine all_cols
undefine default_cols
undefine curr_global_ash
undefine curr_inst_id
undefine curr_plan_table
undefine curr_plan_table_stats
undefine curr_second_id
undefine curr_second_id_monitor
undefine curr_sample_freq
undefine curr_plan_function
undefine curr_par_fil
undefine hist_global_ash
undefine hist_inst_id
undefine hist_plan_table
undefine hist_plan_table_stats
undefine hist_second_id
undefine hist_second_id_monitor
undefine hist_sample_freq
undefine hist_plan_function
undefine hist_par_fil
undefine mixed_global_ash
undefine mixed_inst_id
undefine mixed_plan_table
undefine mixed_plan_table_stats
undefine mixed_second_id
undefine mixed_second_id_monitor
undefine mixed_sample_freq
undefine mixed_plan_function
undefine mixed_par_fil
undefine global_ash
undefine inst_id
undefine plan_table
undefine plan_table_stats
undefine second_id
undefine second_id_monitor
undefine sample_freq
undefine plan_function
undefine par_fil
undefine c_pid
undefine c_ord
undefine c_act
undefine c_a_time_self
undefine c_lio_self
undefine c_reads_self
undefine c_writes_self
undefine c_a_time_self_graph
undefine c_lio_self_graph
undefine c_reads_self_graph
undefine c_writes_self_graph
undefine c_lio_ratio
undefine c_tcf_graph
undefine c_e_rows_times_start
undefine c_start_active
undefine c_duration_secs
undefine c_time_active_graph
undefine c_procs
undefine c_procs_graph
undefine c_activity_graph
undefine c_activity
undefine ds
undefine tgs
undefine avg_as_bkts
undefine rnd_thr
-- undefine pc
undefine plan_exists
undefine _SHOW_LINE_ACTIVE
undefine _SHOW_PROCS
undefine _SHOW_PROCS_GRAPH
undefine _SHOW_ACTIVITY
undefine _SHOW_ACTIVITY_GRAPH
undefine _SHOW_START_ACTIVE
undefine _SHOW_DURATION_SECS
undefine _SHOW_TIME_ACTIVE_GRAPH

col plan_table_output clear
col prev_sql_id clear
col prev_child_number clear
col prev_sql_exec_start clear
col prev_sql_exec_id clear
col last_exec_start clear
col last_exec_id clear
col last_exec_second_id clear
col si clear
col cn clear
col fo clear
col so clear
col op clear
col ah clear
col co clear
col last clear
col li clear
col ls clear
col child_ad clear
col 1 clear
col 2 clear
col 3 clear
col 4 clear
col 5 clear
col 6 clear
col 7 clear
col 8 clear
col 9 clear
col sid_sql_id         clear
col sid_child_no       clear
col sid_sql_exec_start clear
col sid_sql_exec_id    clear
col ora11_higher  clear
col ora11_lower   clear
col ora112_higher clear
col ora112_lower  clear
col global_ash clear
col inst_id clear
col plan_table clear
col plan_table_stats clear
col second_id clear
col second_id_monitor clear
col sample_freq clear
col plan_function clear
col par_fil clear
col plan_table_name clear
col instance_count clear
col c_pid clear
col c_ord clear
col c_act clear
col c_a_time_self clear
col c_lio_self clear
col c_reads_self clear
col c_writes_self clear
col c_a_time_self_graph clear
col c_lio_self_graph clear
col c_reads_self_graph clear
col c_writes_self_graph clear
col c_lio_ratio clear
col c_tcf_graph clear
col c_e_rows_times_start clear
col c_start_active clear
col c_duration_secs clear
col c_time_active_graph clear
col c_procs clear
col c_procs_graph clear
col c_activity_graph clear
col c_activity clear
-- col plan_table_count clear
col plan_exists clear

-- Restore previous SQL*Plus environment
@.xplan_settings