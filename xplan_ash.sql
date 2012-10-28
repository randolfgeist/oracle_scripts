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
-- Version:      2.01
--               October 2012
--
-- Author:       Randolf Geist
--               oracle-randolf.blogspot.com
--
-- Description:  SQL statement execution analysis using ASH (from 10.2 on)
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
--               2. Provide activity information per SQL plan line id (11g+)
--               3. Show distribution of work between Parallel Slaves / Query Coordinator / RAC Nodes based on ASH data
--
--               The ASH data options make this a kind of "real time" monitoring tool. Unfortunately the
--               free ASH implementations (and 10g versions) lack the correlation to the SQL plan line id, hence this is only
--               possible with the original ASH implementation from 11g onwards
--
--               Note that this script supports in principle other ASH sources - everything can be configured below
--
--               A second configuration set is provided that is based on DBA_HIST_ACTIVE_SESS_HISTORY for running analysis on historic ASH data
--               Although the sample frequency of 10 seconds limits the significance of the analysis it might be much better than nothing at all
--
--               !! The ASH reporting requires at least Enterprise Edition plus the Diagnostic Pack license !!
--
-- Versions:     This utility will work from version 10.2 and later
--               The ASH based information on plan line level is only available from 11g on (10g has ASH but no relation to SQL execution instances or SQL plan lines)
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
--               2) GV$SQL_PLAN / GV$SQL_PLAN_STATISTICS_ALL (DBA_HIST_SQL_PLAN)
--               3) GV$SQL
--               4) GV$SQL_MONITOR
--               5) GV$ACTIVE_SESSION_HISTORY (DBA_HIST_ACTIVE_SESS_HISTORY)
--               6) V$DATABASE
--
-- Note:         This script writes two files during execution (.xplan_ash_temp and .xplan_ash_settings), hence it requires write access to the current working directory
--
--               If you see some of the following error messages during execution:
--
--               SP2-0103: Nothing in SQL buffer to run.
--
--               SP2-0110: Cannot create save file ".xplan_ash_temp"
--
--               plan_operations as
--                               *
--               ERROR at line 14:
--               ORA-00933: SQL command not properly ended
--
--               plan_operations as
--                               *
--               ERROR at line 2:
--               ORA-00900: invalid SQL statement
--
--               then you cannot write to your current working directory
--
-- Credits:      Based on the original XPLAN implementation by Adrian Billington (http://www.oracle-developer.net/utilities.php
--               resp. http://www.oracle-developer.net/content/utilities/xplan.zip)
--               and inspired by Kyle Hailey's TCF query (http://dboptimizer.com/2011/09/20/display_cursor/)
--
-- Features:     In addition to the PID (The PARENT_ID) and ORD (The order of execution, note that this doesn't account for the special cases so it might be wrong)
--               columns added by Adrian's wrapper the following additional execution plan columns over ALLSTATS are available (see column configuration where it can be customized which to show):
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
--               The following information is available based on ASH data (from 11g on). Note that this can be configured in two ways:
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
-- Usage:        @xplan_ash.sql [sql_id|sid=<nnn>[@<inst_id>]] [cursor_child_number (plan_hash_value for the historic ASH)] [DBMS_XPLAN_format_option] [SQL_EXEC_START] [SQL_EXEC_ID (SQL_EXEC_END for pre-11g)] [MONITOR|*ASH*] [[*ASH*][,][DISTRIB|*DISTRIB_REL*|DISTRIB_TOT][,][*TIMELINE*]|[NONE]] [*CURR*|HIST|MIXED] [comma_sep_column_list_to_show/hide]
--
--               If both the SQL_ID and CHILD_NUMBER are omitted the previously executed SQL_ID and CHILD_NUMBER of the session will be used
--
--               If the SQL_ID is specified but the CHILD_NUMBER / PLAN_HASH_VALUE is omitted then
--               - If the ASH options are disabled then CHILD_NUMBER 0 is assumed
--               - If ASH / Real-Time SQL Monitoring should be queried, the corresponding CHILD_NUMBER / PLAN_HASH_VALUE will be looked up based on the remaining options specified
--
--               If instead of a SQL_ID SID=<nnn>[@<inst_id>] is specified as first argument, the current or previous execution of the corresponding SID will be used, if available. Optionally the SID's instance can be specified for RAC
--
--               This version does not support processing multiple child cursors like DISPLAY_CURSOR / AWR is capable of
--               when passing NULL as CHILD_NUMBER / PLAN_HASH_VALUE to DISPLAY_CURSOR / AWR. Hence a CHILD_NUMBER / PLAN_HASH_VALUE is mandatory, either
--               implicitly generated (see above) or explicitly passed
--
-- RAC:          A note to RAC users below 11.2.0.2: If the current instance was *not* involved in executing the SQL, and the execution plan should be displayed from the Shared Pool (CURR option), in best case the execution plan cannot be found
--               In worst case an incorrect plan will be associated from the local instance Shared Pool (You could have the same SQL_ID / CHILD_NUMBER with different plans in different RAC instances).
--               Therefore you need to be careful with cross-instance / remote-instance executions in RAC
--               Why? The tool relies on DBMS_XPLAN.DISPLAY_CURSOR for showing the execution plan from the Shared Pool - but DISPLAY_CURSOR is limited to the local Shared Pool
--
--               From 11.2.0.2 a workaround is implemented that can "remotely" execute DBMS_XPLAN.DISPLAY_CURSOR on the RAC instance where the correct plan should be in the Library Cache
--
--               The default formatting option for the call to DBMS_XPLAN.DISPLAY_CURSOR / AWR is ADVANCED
--
--               For 11g+:
--               SQL_EXEC_START: This is required to determine the exact instance of statement execution in ASH. It is a date in format "YYYY-MM-DD HH24:MI:SS" (date mask can be changed in the configuration section)
--               SQL_EXEC_ID   : Also required for the same purpose
--
--               If these two are omitted and the SID and previous session execution cases don't apply then the last execution is searched in either GV$SQL_MONITOR (MONITOR) or GV$ACTIVE_SESSION_HISTORY (the default ASH option)
--               The latter option is required if no Tuning Pack license is available, the former option can be used to make sure that the script finds the same latest execution instance as the Real-Time SQL Monitoring
--
--               This information is used as filter on SQL_EXEC_START and SQL_EXEC_ID in ASH. Together with the SQL_ID it uniquely identifies an execution instance of that SQL
--
--               For 10.2:
--               SQL_EXEC_START: This is always mandatory and determines the start samples in ASH. It is a date in format "YYYY-MM-DD HH24:MI:SS" (date mask can be changed in the configuration section)
--               SQL_EXEC_END  : This is always mandatory and determines the end samples in ASH. It is a date in format "YYYY-MM-DD HH24:MI:SS" (date mask can be changed in the configuration section)
--
--               For 10.2 these two are mandatory since an exact SQL execution instance cannot be identified in pre-11g ASH data
--
--               For 11g+:
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
--               The official blog post for version 1.0 of the tool can be found here:
--
--               http://oracle-randolf.blogspot.com/2012/08/parallel-execution-analysis-using-ash.html
--
--               It contains a complete description along with the command line reference, notes and examples
--
--               The official blog post for version 2.0 of the tool can be found here:
--
--               http://oracle-randolf.blogspot.com/2012/10/new-version-of-xplanash-utility.html
--
--               It explains all the new sections and features of 2.0
--
--               You can find all related posts following this link:
--               http://oracle-randolf.blogspot.com/search/label/XPLAN_ASH
--
--               The latest version can be downloaded here:
--               https://github.com/randolfgeist/oracle_scripts/raw/master/xplan_ash.sql
--
-- Experimental: There is a global switch _EXPERIMENTAL at the beginning of the configuration section below.
--               By default this is disabled because the stuff shown could be called "unreliable" and potentially "misleading" information.
--
--               If you enable it by setting the configuration switch to an empty string, the I/O figures from the ASH data (only from 11.2+ on)
--               will be shown at various places of the report. Note that this data is unreliable and usually falls short of
--               the actual activity (I've never seen it reporting more than the actual activities). Since sometimes unreliable
--               figures can be much better than nothing at all you can enable it that in cases where you want for example get an
--               idea if the I/O was in the range of MBs or GBs - this is something you should be able to tell from the ASH data
--
--               Likewise the average and median wait times from ASH will be shown at different places of the report if experimental is turned on.
--               It is important to understand what these wait times are: These are waits that were "in-flight", not completed when the sampling took place.
--               Doing statistical analysis based on such sampled, in-flight wait times is sometimes called "Bad ASH math", but again, if you know what you are doing
--               and keep telling yourself what you're looking at, there might be cases where this information could be useful, for example, if you see that
--               hundreds or thousands of those "in-flight" waits were sampled with a typical wait time of 0.5 secs where you expect a typical wait time of 0.005 secs.
--               This might be an indicator that something was broken or went wrong and could be worth further investigation.
--
-- Change Log:
--
--               2.01: October 2012
--                    - The NONE option did not populate a substitution variable properly that is required from 11.2.0.2 on
--                      for running the DBMS_XPLAN function on the right node via the GV$() function
--
--               2.0: October 2012
--                    - Access check
--                    - Conditional compilation for different database versions
--                    - Additional activity summary (when enabling "experimenal" including average and median wait times)
--                    - Concurrent activity information (what is going on at the same time as this SQL statement executes)
--                    - Experimental stuff: Additional I/O summary
--                    - More pretty printing
--                    - Experimental stuff: I/O added to Average Active Session Graph (renamed to Activity Timeline)
--                    - Top Execution Plan Lines and Top Activities added to Activity Timeline
--                    - Activity Timeline is now also shown for serial execution when TIMELINE option is specified
--                    - From 11.2.0.2 on: We get the ACTUAL DOP from the undocumented PX_FLAGS column added to ASH
--                    - All relevant XPLAN_ASH queries are now decorated so it should be easy to identify them in the Library Cache
--                    - More samples are now covered and a kind of "read consistency" across queries on ASH is introduced
--                    - From 11.2.0.2 on: Executions plans are now pulled from the remote RAC instance Library Cache if necessary
--                    - Separate Parallel Slave activity overview
--                    - Limited support for Oracle 10.2 ASH
--
--               1.0: August 2012
--                    Initial release
--
-- Ideas:        - Include GV$SESSION_LONGOPS information
--               - Show information about the session identified
--               - Show MAX PGA / TEMP usage for Activity Timeline
--
*/
#

col plan_table_output format a600
-- col plan_table_count noprint new_value pc
set linesize 600 pagesize 0 tab off

-----------------------------------
-- Configuration, default values --
-----------------------------------

/* Configure EXPERIMENTAL stuff (currently I/O summary and figures added to Activity Timeline as well as average / median wait times for Activity Summaries) */
/* Set this to "" for enabling experimental stuff */
/* Set this to "--" for disabling experimental stuff */
define _EXPERIMENTAL = "--"

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

/* The Top N Plan lines in the Activity Timeline */
define topnl = "3"

/* The Top N Activities in the Activity Timeline */
define topna = "3"

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
define curr_plan_table = "gv$sql_plan"

define curr_plan_table_stats = "gv$sql_plan_statistics_all"

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

/* For current ASH we need the instance_id in addition for remote instance executions */
define curr_third_id = "''''p.inst_id = '''' || :inst_id"

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

/* For historic ASH we don't need the instance_id in addition for remote instance executions */
define hist_third_id = "''''1 = 1 --'''' || :inst_id"

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

/* For mixed ASH we don't need the instance_id in addition for remote instance executions */
define mixed_third_id = "''''1 = 1 --'''' || :inst_id"

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
begin
  $IF DBMS_DB_VERSION.VERSION < 11 $THEN
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
  $ELSE
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
  $END
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

/* Perform an access check on all objects that might be used and cause a failure */
variable access_check varchar2(4000)

declare
  type t_check_list is table of varchar2(30);
  $IF DBMS_DB_VERSION.VERSION < 11 $THEN
  a_check_list t_check_list := t_check_list('DUAL', 'V$SESSION', 'GV$SESSION', 'V$DATABASE', 'GV$ACTIVE_SESSION_HISTORY', 'GV$SQL_PLAN', 'GV$SQL_PLAN_STATISTICS_ALL', 'V$VERSION', 'GV$SQL', 'DBA_HIST_ACTIVE_SESS_HISTORY', 'DBA_HIST_SQL_PLAN');
  $ELSE
  a_check_list t_check_list := t_check_list('DUAL', 'V$SESSION', 'GV$SESSION', 'V$DATABASE', 'GV$ACTIVE_SESSION_HISTORY', 'GV$SQL_PLAN', 'GV$SQL_PLAN_STATISTICS_ALL', 'V$VERSION', 'GV$SQL_MONITOR', 'GV$SQL', 'DBA_HIST_ACTIVE_SESS_HISTORY', 'DBA_HIST_SQL_PLAN');
  $END
  s_dummy varchar2(1);
  s_result varchar2(4000);
begin
  for i in a_check_list.first..a_check_list.last loop
    begin
      execute immediate 'select to_char(null) as dummy from ' || a_check_list(i) || ' where 1 = 2' into s_dummy;
    exception
    when NO_DATA_FOUND then
      null;
    when others then
      s_result := s_result || chr(10) || 'Error ORA' || to_char(SQLCODE, '00000') || ' when accessing ' || a_check_list(i);
    end;
  end loop;
  s_result := ltrim(s_result, chr(10));
  :access_check := s_result;
end;
/

set termout on

set heading off feedback off

column message format a100

select
        '----------------------------------------------------------------------------------------------' as message
from
        dual
where
        :access_check is not null
---------
union all
---------
select
        '!!Access Check failed!!'
from
        dual
where
        :access_check is not null
---------
union all
---------
select
        '----------------------------------------------------------------------------------------------'
from
        dual
where
        :access_check is not null
---------
union all
---------
select
        :access_check
from
        dual
where
        :access_check is not null
;

column message clear

set heading on feedback on

set termout off

-- Default some defines that cause the script appear to "hang" in case of missing privileges
-- This is just to avoid the "hang" (waiting for input with termout off) -
-- these will be populated when operating with proper privileges
define last_exec_second_id = ""
define last_exec_start = ""
define sid_sql_id = ""
define sid_child_no = ""
define sid_sql_exec_start = ""
define child_ad = ""
define sid_sql_exec_id = ""
define last_exec_id = ""
define slave_count = ""
define ic = ""
define ds = ""
define plan_exists = ""
define plan_inst_id = ""
define ash_pred1 = "1 = "
define ash_pred2 = "2"
define ash_ln_pred1 = "1 = "
define ash_ln_pred2 = "2"
define ash_min_sample_time = ""
define ash_max_sample_time = ""
define ca_sc = ""

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

-- Some version dependent code switches
col ora11_higher    new_value _IF_ORA11_OR_HIGHER
col ora11_lower     new_value _IF_LOWER_THAN_ORA11
col ora112_higher   new_value _IF_ORA112_OR_HIGHER
col ora112_lower    new_value _IF_LOWER_THAN_ORA112
col ora11202_higher new_value _IF_ORA11202_OR_HIGHER
col ora11202_lower  new_value _IF_LOWER_THAN_ORA11202

select
        decode(substr(banner, instr(banner, 'Release ') + 8, 2), '11', '',  '--')                                                                             as ora11_higher
      , decode(substr(banner, instr(banner, 'Release ') + 8, 2), '11', '--',  '')                                                                             as ora11_lower
      , case when substr( banner, instr(banner, 'Release ') + 8, instr(substr(banner,instr(banner,'Release ') + 8),' ') ) >= '11.2' then '' else '--'     end as ora112_higher
      , case when substr( banner, instr(banner, 'Release ') + 8, instr(substr(banner,instr(banner,'Release ') + 8),' ') ) >= '11.2' then '--' else ''     end as ora112_lower
      , case when substr( banner, instr(banner, 'Release ') + 8, instr(substr(banner,instr(banner,'Release ') + 8),' ') ) >= '11.2.0.2' then '' else '--' end as ora11202_higher
      , case when substr( banner, instr(banner, 'Release ') + 8, instr(substr(banner,instr(banner,'Release ') + 8),' ') ) >= '11.2.0.2' then '--' else '' end as ora11202_lower
from
        v$version
where
        rownum = 1
;

/* For versions prior to 11g there is no concept of SQL_EXEC_START / SQL_EXEC_ID */
/* Hence we require the user to enter simply a start and end date for the ASH samples to use */
column sql_exec2 new_value _SQL_EXEC2

select
&_IF_LOWER_THAN_ORA11         'SQL_EXEC_END (format "&dm")' as sql_exec2
&_IF_ORA11_OR_HIGHER          'SQL_EXEC_ID'                 as sql_exec2
from
        dual;

column sql_exec2 clear

--set doc off
--doc
/* If you prefer to be prompted for the various options, activate this code block */
/* Anything you pass on the command line will be used as default here, so you can simply add/amend/overwrite the option you like at the prompts */

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
accept 5 default '&5' prompt '&_SQL_EXEC2: '
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

set termout on

prompt
prompt
prompt XPLAN_ASH V2.01 (C) 2012 Randolf Geist
prompt http://oracle-randolf.blogspot.com
prompt
prompt Initializing...
prompt ------------------------------------------------

-- If you need to debug, comment the following line
set termout off

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
column third_id          new_value third_id

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
      , '&curr_third_id'          as third_id
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
      , '&hist_third_id'          as third_id
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
      , '&mixed_third_id'          as third_id
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
select /* XPLAN_ASH GET_SESSION_DETAILS */
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
column instance_id         new_value plan_inst_id

/* Identify the CHILD_NUMBER / PLAN_HASH_VALUE if first parameter identifies a SQL_ID and second parameter is null and ASH / Real-Time SQL Monitoring should be queried */

/* One of the following statements will be short-circuited by the optimizer if the ASH / MONITOR condition is not true */
/* So effectively only one of them will run, the other will not return any data (due to the GROUP BY clause) */

select /* XPLAN_ASH IDENTIFY_SECOND_ID */
&_IF_ORA11_OR_HIGHER          cast(max(sql_&second_id_monitor) keep (dense_rank last order by sql_exec_start nulls first) as varchar2(30)) as last_exec_second_id
&_IF_LOWER_THAN_ORA11         '0' as last_exec_second_id
&_IF_ORA11_OR_HIGHER        , to_char(cast(max(inst_id) keep (dense_rank last order by sql_exec_start nulls first) as varchar2(30)), 'TM') as instance_id
&_IF_LOWER_THAN_ORA11       , '0' as instance_id
from
&_IF_ORA11_OR_HIGHER          gv$sql_monitor
&_IF_LOWER_THAN_ORA11         dual
where
&_IF_LOWER_THAN_ORA11         1 = 2
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
&_IF_LOWER_THAN_ORA11         to_char(max(sql_&second_id) keep (dense_rank first order by sample_time - to_timestamp('&4 ', '&dm') nulls last), 'TM')  as last_exec_second_id
&_IF_ORA11_OR_HIGHER        , to_char(cast(max(case when qc_instance_id is not null then qc_instance_id else &inst_id end) keep (dense_rank last order by sql_exec_start nulls first) as varchar2(30)), 'TM') as instance_id
&_IF_LOWER_THAN_ORA11       , to_char(cast(max(case when qc_instance_id is not null then qc_instance_id else &inst_id end) keep (dense_rank first order by sample_time - to_timestamp('&4 ', '&dm') nulls last) as varchar2(30)), 'TM') as instance_id
from
        &global_ash
where
        sql_id = '&1'
and     '&so' = 'ASH'
and     (instr('&op', 'ASH') > 0 or instr('&op', 'DISTRIB') > 0 or instr('&op', 'TIMELINE') > 0)
&_IF_ORA11_OR_HIGHER  and     sql_exec_start = nvl(to_date('&4', '&dm'), sql_exec_start)
&_IF_ORA11_OR_HIGHER  and     sql_exec_id = nvl(trim('&5'), sql_exec_id)
&_IF_LOWER_THAN_ORA11 and     sample_time between to_timestamp('&4', '&dm') and to_timestamp('&5', '&dm') + interval '1' second
and     '&1' is not null
and     upper(substr('&1', 1, 4)) != 'SID='
and     '&2' is null
group by
        1
;

select
        nvl('&plan_inst_id', sys_context('USERENV', 'INSTANCE')) as instance_id
from
        dual;

column instance_id     clear

/* Turn the Real-Time SQL Monitoring CHILD_ADDRESS into a CHILD_NUMBER */

select  /* XPLAN_ASH CHILD_ADDRESS_TO_CHILD_NUMBER */
        to_char(child_number, 'TM') as last_exec_second_id
from
        gv$sql
where
        sql_id = '&1'
and     child_address = hextoraw('&last_exec_second_id')
and     inst_id = &plan_inst_id
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

/* Get plan info from GV$SQL_PLAN_STATISTICS_ALL or GV$SQL_PLAN */
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

-- Get child address for querying GV$SQL_MONITOR
select  /* XPLAN_ASH CHILD_NUMBER_TO_CHILD_ADDRESS */
        rawtohex(child_address) as child_ad
from
        gv$sql
where
        sql_id = '&si'
and     child_number = &cn
and     inst_id = &plan_inst_id
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
select /* XPLAN_ASH SEARCH_LAST_EXECUTION */
&_IF_ORA11_OR_HIGHER          to_char(max(sql_exec_start), '&dm')                                                        as last_exec_start
&_IF_ORA11_OR_HIGHER        , to_char(max(sql_exec_id) keep (dense_rank last order by sql_exec_start nulls first), 'TM') as last_exec_id
&_IF_LOWER_THAN_ORA11         ''   as last_exec_start
&_IF_LOWER_THAN_ORA11       , '0'  as last_exec_id
from
&_IF_ORA11_OR_HIGHER          gv$sql_monitor
&_IF_LOWER_THAN_ORA11         dual
where
&_IF_LOWER_THAN_ORA11         1 = 2
&_IF_ORA11_OR_HIGHER          sql_id = '&si'
&_IF_ORA11_OR_HIGHER  and     sql_&second_id_monitor = case when upper('&second_id_monitor') = 'CHILD_ADDRESS' then '&child_ad' else '&cn' end
&_IF_ORA11_OR_HIGHER  and     px_qcsid is null
&_IF_ORA11_OR_HIGHER  and     '&so' = 'MONITOR'
&_IF_ORA11_OR_HIGHER  and     (instr('&op', 'ASH') > 0 or instr('&op', 'DISTRIB') > 0 or instr('&op', 'TIMELINE') > 0)
&_IF_ORA11_OR_HIGHER  and     coalesce('&sid_sql_exec_start', '&4') is null and '&1' is not null
and     '&_IF_ORA11_OR_HIGHER' is null
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
&_IF_ORA11_OR_HIGHER          &global_ash ash
&_IF_LOWER_THAN_ORA11         dual
where
&_IF_LOWER_THAN_ORA11         1 = 2
&_IF_ORA11_OR_HIGHER          sql_id = '&si'
&_IF_ORA11_OR_HIGHER  and     sql_&second_id = &cn
&_IF_ORA11_OR_HIGHER  and     '&so' = 'ASH'
&_IF_ORA11_OR_HIGHER  and     (instr('&op', 'ASH') > 0 or instr('&op', 'DISTRIB') > 0 or instr('&op', 'TIMELINE') > 0)
&_IF_ORA11_OR_HIGHER  and     coalesce('&sid_sql_exec_start', '&4') is null and '&1' is not null
and     '&_IF_ORA11_OR_HIGHER' is null
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

/* Define the actual query on ASH for samples */
/* Not all samples for a SQL execution are marked with SQL_EXEC_START / SQL_EXEC_ID */
/* So in order to include those samples a little bit of logic is required */
/* This logic here is inspired by Real-Time SQL Monitoring */
/* In order to support other ASH sources this query needs to be adjusted along with
   the parameters that define the valid ASH samples */
/* This query here restricts the ASH data to the session information identified */
/* The actual ASH queries will use the clauses determined here along with the SQL_ID plus start / end sample time */
column pred1           new_value ash_pred1
column pred2           new_value ash_pred2
column ln_pred1        new_value ash_ln_pred1
column ln_pred2        new_value ash_ln_pred2
column instance_id     new_value plan_inst_id
column min_sample_time new_value ash_min_sample_time
column max_sample_time new_value ash_max_sample_time

select  /* XPLAN_ASH DEFINE_ASH_SAMPLES */
        pred1
      , pred2
      , ln_pred1
      , ln_pred2
      , instance_id
      , to_char(sql_exec_start, 'YYYY-MM-DD HH24:MI:SS')  as min_sample_time
      , to_char(max_sample_time, 'YYYY-MM-DD HH24:MI:SS') as max_sample_time
from
        (
          select
                  max_sample_time
                  /* For versions that support the GV$() special table function we can actually refer to the instance where the execution was started */
                  /* For prior versions this is deliberately limited to the current instance to get at least a consistent behaviour */
                  /* Although this might mean either getting no plan at all or in worst case getting a wrong plan from the local Library Cache */
&_IF_ORA11202_OR_HIGHER                 , to_char(case when qc_instance_id is not null then qc_instance_id else instance_id end, 'TM')                                                                       as instance_id
&_IF_LOWER_THAN_ORA11202                , sys_context('USERENV', 'INSTANCE')                                                                                                                                 as instance_id
                , '((ash.&inst_id = '           || to_char(nvl(case when qc_instance_id is not null then qc_instance_id else instance_id end, 0), 'TM') ||
                  ' and ash.session_id = '      || to_char(nvl(case when qc_instance_id is not null then qc_session_id else session_id end, -1), 'TM') ||
                  ' and ash.session_serial# = ' || to_char(nvl(case when qc_instance_id is not null then coalesce(qc_session_serial#, session_serial#, -1) else session_serial# end, -1), 'TM') || ')'       as pred1
                , case when qc_instance_id is not null then
                  'or (ash.qc_instance_id = ' || to_char(qc_instance_id, 'TM') ||
                  ' and ash.qc_session_id = ' || to_char(qc_session_id, 'TM') ||
&_IF_ORA11_OR_HIGHER                    ' and ash.qc_session_serial# = ' || to_char(qc_session_serial#, 'TM') ||
                  '))'
                  else
                  ')'
                  end                                                                                                                                            as pred2
                , '((lnnvl(ash.&inst_id = '          || to_char(nvl(case when qc_instance_id is not null then qc_instance_id else instance_id end, 0), 'TM') || ')' ||
                  ' or lnnvl(ash.session_id = '      || to_char(nvl(case when qc_instance_id is not null then qc_session_id else session_id end, -1), 'TM') || ')' ||
                  ' or lnnvl(ash.session_serial# = ' || to_char(nvl(case when qc_instance_id is not null then coalesce(qc_session_serial#, session_serial#, -1) else session_serial# end, -1), 'TM') || '))' as ln_pred1
                , case when qc_instance_id is not null then
                  'and (lnnvl(ash.qc_instance_id = ' || to_char(qc_instance_id, 'TM') || ')' ||
                  ' or lnnvl(ash.qc_session_id = ' || to_char(qc_session_id, 'TM') || ')' ||
&_IF_ORA11_OR_HIGHER                    ' or lnnvl(ash.qc_session_serial# = ' || to_char(qc_session_serial#, 'TM') || ')' ||
                  '))'
                  else
                  ')'
                  end                                                                                                                                                                                        as ln_pred2
                , sql_exec_start
          from
                  (
                    select
                            min(sql_exec_start)                                                                     as sql_exec_start
                          , max(cast(sample_time as date))                                                          as max_sample_time
&_IF_ORA11_OR_HIGHER                            , max(instance_id) keep (dense_rank last order by cnt, sample_time nulls first)           as instance_id
&_IF_LOWER_THAN_ORA11                           , max(instance_id) keep (dense_rank first order by sample_time - to_timestamp('&ls ', '&dm') nulls last)         as instance_id
&_IF_ORA11_OR_HIGHER                            , max(session_id) keep (dense_rank last order by cnt, sample_time nulls first)         as session_id
&_IF_LOWER_THAN_ORA11                           , max(session_id) keep (dense_rank first order by sample_time - to_timestamp('&ls ', '&dm') nulls last)       as session_id
&_IF_ORA11_OR_HIGHER                            , max(session_serial#) keep (dense_rank last order by cnt, sample_time nulls first)    as session_serial#
&_IF_LOWER_THAN_ORA11                           , max(session_serial#) keep (dense_rank first order by sample_time - to_timestamp('&ls ', '&dm') nulls last)  as session_serial#
&_IF_ORA11_OR_HIGHER                            , max(qc_instance_id) keep (dense_rank last order by cnt, sample_time nulls first)     as qc_instance_id
&_IF_LOWER_THAN_ORA11                           , max(qc_instance_id) keep (dense_rank first order by sample_time - to_timestamp('&ls ', '&dm') nulls last)   as qc_instance_id
&_IF_ORA11_OR_HIGHER                            , max(qc_session_id) keep (dense_rank last order by cnt, sample_time nulls first)      as qc_session_id
&_IF_LOWER_THAN_ORA11                           , max(qc_session_id) keep (dense_rank first order by sample_time - to_timestamp('&ls ', '&dm') nulls last)    as qc_session_id
&_IF_ORA11_OR_HIGHER                            , max(qc_session_serial#) keep (dense_rank last order by cnt, sample_time nulls first) as qc_session_serial#
&_IF_LOWER_THAN_ORA11                           , null                                                                                 as qc_session_serial#
                    from
                            (
                              select
&_IF_ORA11_OR_HIGHER                                        sql_exec_start
&_IF_LOWER_THAN_ORA11                                       to_date('&ls', '&dm')   as sql_exec_start
                                    , sample_time
                                    , &inst_id                as instance_id
                                    , session_id
                                    , session_serial#
                                    , qc_instance_id
                                    , qc_session_id
&_IF_ORA11_OR_HIGHER                                      , qc_session_serial#
                                    , count(*) over (partition by
                                                     case when qc_instance_id is not null
                                                     then qc_instance_id || ',' || qc_session_id
&_IF_ORA11_OR_HIGHER                                                       || ',' || qc_session_serial#
                                                     else &inst_id || ',' || session_id || ',' || session_serial# end)         as cnt
                              from
                                      &global_ash ash
                              where
                                      sql_id = '&si'
&_IF_ORA11_OR_HIGHER                               and     sql_exec_start = to_date('&ls', '&dm')
&_IF_ORA11_OR_HIGHER                               and     sql_exec_id = &li
&_IF_LOWER_THAN_ORA11                              and     sample_time >= to_timestamp('&ls', '&dm') and sample_time < to_timestamp('&li', '&dm') + interval '1' second
                            )
                  )
        )
;

select
        nvl('&plan_inst_id', sys_context('USERENV', 'INSTANCE')) as instance_id
from
        dual;

column pred1           clear
column pred2           clear
column ln_pred1        clear
column ln_pred2        clear
column instance_id     clear
column min_sample_time clear
column max_sample_time clear

/* Determine any additional filters on the plan tables for remote RAC executions */
variable out_third_id varchar2(100)

exec execute immediate 'select &third_id as add_filter from dual' into :out_third_id using '&plan_inst_id'

column third_id new_value third_id

select
        :out_third_id as third_id
from
        dual;

column third_id clear

/* Check if a plan can be found */
column plan_exists new_value plan_exists

select
        max(sql_id) as plan_exists
from
        &plan_table p
where
        p.sql_id = '&si'
and     p.&second_id = &cn
and     &third_id
and     rownum <= 1
;

-------------------------------
-- Actual output starts here --
-------------------------------

set termout on pagesize 999 heading on feedback off newpage 1 numwidth 10 numformat "" null "" colsep "|" headsep "|"

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
prompt ------------------------------------------------

column sql_id           format a13
column sql_exec_start   format a19
column sql_exec_end     format a19
column format_option    format a25
column last_exec_source format a16
column ash_options      format a24
column ash_source       format a10

select
        '&si' as sql_id
      , &cn   as &second_id
      , '&ls' as sql_exec_start
&_IF_ORA11_OR_HIGHER        , &li   as sql_exec_id
&_IF_LOWER_THAN_ORA11       , '&li'   as sql_exec_end
      , '&fo' as format_option
      , case
        when '&sid_sql_id' is not null
        then upper('&1')
&_IF_ORA11_OR_HIGHER          when '&1' is null and '&4' is null
&_IF_LOWER_THAN_ORA11         when '&1' is null
        then 'PREV_SQL'
        when '&4' is not null
        then 'N/A'
        else '&so'
        end   as last_exec_source
      , '&op' as ash_options
      , '&ah' as ash_source
from
        dual
;

column sql_id           clear
column sql_exec_start   clear
column sql_exec_end     clear
column format_option    clear
column last_exec_source clear
column ash_options      clear
column ash_source       clear

set heading off

column message format a50

select
        chr(10) || chr(10) as message
from
        dual
where
        (instr('&op', 'ASH') > 0 or instr('&op', 'DISTRIB') > 0 or instr('&op', 'TIMELINE') > 0)
---------
union all
---------
select
        'Global ASH Summary' as message
from
        dual
where
        (instr('&op', 'ASH') > 0 or instr('&op', 'DISTRIB') > 0 or instr('&op', 'TIMELINE') > 0)
---------
union all
---------
select
        '-----------------------------------------------'
from
        dual
where
        (instr('&op', 'ASH') > 0 or instr('&op', 'DISTRIB') > 0 or instr('&op', 'TIMELINE') > 0)
;

column message clear

set heading on

/* Summary information based on ASH */

column inst_count new_value ic noprint
column duration_secs  new_value ds

column first_sample format a19
column last_sample  format a19
column status       format a8

column slave_count new_value slave_count

select  /* XPLAN_ASH GLOBAL_ASH_SUMMARY */
        instance_count
      , inst_count
      , first_sample
      , last_sample
      , duration_secs
      , status
      , sample_count
      , cpu_sample_count
      , round(cpu_sample_count / sample_count * 100)                          as percentage_cpu
      , slave_count
      , case when average_as >= &rnd_thr then round(average_as) else average_as end as average_as
      , module
      , action
from
        (
          select
                  to_char(count(distinct &inst_id), 'TM')                                                                 as inst_count
                , count(distinct &inst_id)                                                                                as instance_count
                , to_char(min(sample_time), '&dm')                                                                        as first_sample
                , to_char(max(sample_time), '&dm')                                                                        as last_sample
                , round(((max(sample_time) - min(sql_exec_start)) * 86400)) + &sample_freq                                as duration_secs
                , case when max(sample_time) >= sysdate - 2 * &sample_freq / 86400 then 'ACTIVE' else 'INACTIVE' end      as status
                , count(*)                                                                                                as sample_count
                , sum(is_on_cpu)                                                                                          as cpu_sample_count
                , count(distinct process)                                                                                 as slave_count
                , nvl(max(module), '<NULL>')                                                                              as module
                , nvl(max(action), '<NULL>')                                                                              as action
                , round(count(*) / (((max(sample_time) - min(sql_exec_start)) * 86400) + &sample_freq) * &sample_freq, 2) as average_as
          from
                  (
                    select
                            &inst_id
                          , cast(sample_time as date)                                                                 as sample_time
                          , sql_id
                          , case
                            -- REGEXP_SUBSTR lacks the subexpr parameter in 10.2
                            -- when regexp_substr(program, '^.*\((P[[:alnum:]][[:digit:]][[:digit:]])\)$', 1, 1, 'c', 1) is null
                            when regexp_instr(regexp_replace(program, '^.*\((P[[:alnum:]][[:digit:]][[:digit:]])\)$', '\1', 1, 1, 'c'), '^P[[:alnum:]][[:digit:]][[:digit:]]$') != 1
                            then null
                            -- REGEXP_SUBSTR lacks the subexpr parameter in 10.2
                            -- else &inst_id || '-' || regexp_substr(program, '^.*\((P[[:alnum:]][[:digit:]][[:digit:]])\)$', 1, 1, 'c', 1)
                            else &inst_id || '-' || regexp_replace(program, '^.*\((P[[:alnum:]][[:digit:]][[:digit:]])\)$', '\1', 1, 1, 'c')
                            end                                                                                       as process
                          , case when session_state = 'ON CPU' then 1 else 0 end                                      as is_on_cpu
                          , module
                          , action
&_IF_ORA11_OR_HIGHER                            , sql_exec_start
&_IF_LOWER_THAN_ORA11                           , to_date('&ls', '&dm') as sql_exec_start
&_IF_ORA11_OR_HIGHER                            , sql_exec_id
                    from
                            &global_ash ash
                    where
                            sql_id = '&si'
                    and     &ash_pred1 &ash_pred2
                    and     cast(sample_time as date) between to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS') and to_date('&ash_max_sample_time', 'YYYY-MM-DD HH24:MI:SS')
                  ) ash
          where
                  (instr('&op', 'ASH') > 0 or instr('&op', 'DISTRIB') > 0 or instr('&op', 'TIMELINE') > 0)
          -- This prevents the aggregate functions to produce a single row
          -- in case of no rows generated to aggregate
          group by
                  1
)
;

-- If you need to debug, comment the following line
set termout off

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
column is_ora11_or_higher  new_value _IF_ORA11_OR_HIGHERP  noprint

select
        case when to_number(nvl('&ic', '0')) > 1 then '' else 'no' end  as is_cross_instance
      , case when '&_IF_ORA112_OR_HIGHER' is null then '' else 'no' end as is_ora112_or_higher
      , case when '&_IF_ORA11_OR_HIGHER'  is null then '' else 'no' end as is_ora11_or_higher
from
        dual
;

column is_cross_instance clear
column is_ora112_or_higher clear
column is_ora11_or_higher clear

set termout on

set heading off

column message format a50

select
        chr(10) || chr(10) as message
from
        dual
where
        (instr('&op', 'ASH') > 0 or instr('&op', 'DISTRIB') > 0 or instr('&op', 'TIMELINE') > 0)
and     to_number(nvl('&ic', '0')) > 1
---------
union all
---------
select
        'Global ASH Summary per Instance' as message
from
        dual
where
        (instr('&op', 'ASH') > 0 or instr('&op', 'DISTRIB') > 0 or instr('&op', 'TIMELINE') > 0)
and     to_number(nvl('&ic', '0')) > 1
---------
union all
---------
select
        '-----------------------------------------------'
from
        dual
where
        (instr('&op', 'ASH') > 0 or instr('&op', 'DISTRIB') > 0 or instr('&op', 'TIMELINE') > 0)
and     to_number(nvl('&ic', '0')) > 1
;

column message clear

set heading on

/* Summary information per RAC instance based on ASH (for cross-instance SQL execution) */

column first_sample      format a19
column last_sample       format a19
column time_active_graph format a&tgs

select  /* XPLAN_ASH GLOBAL_ASH_SUMMARY_CROSS_INSTANCE */
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
                , round((min(sample_time) - min(sql_exec_start)) * 86400)                                              as start_active
                , round(((max(sample_time) - min(sample_time)) * 86400)) + &sample_freq                                as duration_secs
                , count(*)                                                                                             as sample_count
                , count(distinct process)                                                                              as process_count
                , round(count(*) / (((max(sample_time) - min(sample_time)) * 86400) + &sample_freq) * &sample_freq, 2) as average_as
          from
                  (
                    select
                            &inst_id
                          , cast(sample_time as date)                                                                as sample_time
                          , regexp_replace(program, '^.*\((P[[:alnum:]][[:digit:]][[:digit:]])\)$', '\1', 1, 1, 'c') as process
                          , sql_id
&_IF_ORA11_OR_HIGHER                            , sql_exec_start
&_IF_LOWER_THAN_ORA11                           , to_date('&ls', '&dm') as sql_exec_start
&_IF_ORA11_OR_HIGHER                            , sql_exec_id
                    from
                            &global_ash ash
                    where
                            sql_id = '&si'
                    and     &ash_pred1 &ash_pred2
                    and     cast(sample_time as date) between to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS') and to_date('&ash_max_sample_time', 'YYYY-MM-DD HH24:MI:SS')
                  ) ash
          where
                  (instr('&op', 'ASH') > 0 or instr('&op', 'DISTRIB') > 0 or instr('&op', 'TIMELINE') > 0)
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
        chr(10) || chr(10) as message
from
        dual
where
        instr('&op', 'ASH') > 0
---------
union all
---------
select
        'Global ASH Summary for concurrent activity' as message
from
        dual
where
        instr('&op', 'ASH') > 0
---------
union all
---------
select
        '-----------------------------------------------'
from
        dual
where
        instr('&op', 'ASH') > 0
;

column message clear

set heading on

/* Summary information for concurrent activity based on ASH */

column instance_id &_IF_CROSS_INSTANCE.print
column sample_count new_value ca_sc

select  /* XPLAN_ASH GLOBAL_ASH_SUMMARY_CONCURRENT_EXECUTION */
        instance_id
      , sample_count
      , cpu_sample_count
      , round(cpu_sample_count / sample_count * 100)                                as percentage_cpu
      , case when average_as >= &rnd_thr then round(average_as) else average_as end as average_as
      , foreground_count
      , background_count
      , slave_count
&_IF_ORA112_OR_HIGHER       , client_count
      , process_count
      , transact_count
      , sql_id_count
&_IF_ORA11_OR_HIGHER        , sql_execution_count
      , module_count
      , action_count
from
        (
          select
                  instance_id
                , count(*)                                             as sample_count
                , round(count(*) / to_number('&ds') * &sample_freq, 2) as average_as
                , sum(is_on_cpu)                                       as cpu_sample_count
                , count(distinct process)                              as slave_count
                , count(is_foreground)                                 as foreground_count
                , count(is_background)                                 as background_count
&_IF_ORA112_OR_HIGHER                 , count(distinct machine)                              as client_count
                , count(distinct program)                              as process_count
                , count(distinct xid)                                  as transact_count
                , count(distinct sql_id)                               as sql_id_count
&_IF_ORA11_OR_HIGHER                  , count(distinct sql_exec_unique)                      as sql_execution_count
                , count(distinct module)                               as module_count
                , count(distinct action)                               as action_count
          from
                  (
                    select
                            &inst_id as instance_id
                          , cast(sample_time as date)                                                                 as sample_time
                          , sql_id
                          , case
                            -- REGEXP_SUBSTR lacks the subexpr parameter in 10.2
                            -- when regexp_substr(program, '^.*\((P[[:alnum:]][[:digit:]][[:digit:]])\)$', 1, 1, 'c', 1) is null
                            when regexp_instr(regexp_replace(program, '^.*\((P[[:alnum:]][[:digit:]][[:digit:]])\)$', '\1', 1, 1, 'c'), '^P[[:alnum:]][[:digit:]][[:digit:]]$') != 1 or session_type != 'FOREGROUND' or program is null
                            then null
                            -- REGEXP_SUBSTR lacks the subexpr parameter in 10.2
                            -- else &inst_id || '-' || regexp_substr(program, '^.*\((P[[:alnum:]][[:digit:]][[:digit:]])\)$', 1, 1, 'c', 1)
                            else &inst_id || '-' || regexp_replace(program, '^.*\((P[[:alnum:]][[:digit:]][[:digit:]])\)$', '\1', 1, 1, 'c')
                            end                                                                                       as process
                          , case when session_state = 'ON CPU' then 1 else 0 end                                      as is_on_cpu
                          , case when session_type = 'FOREGROUND' then 1 else null end                                as is_foreground
                          , case when session_type = 'BACKGROUND' then 1 else null end                                as is_background
&_IF_ORA112_OR_HIGHER                           , machine
                          , program
                          , xid
&_IF_ORA11_OR_HIGHER                            , sql_id || '|' || to_char(sql_exec_start, 'DD.MM.YYYY HH24:MI:SS') || '|' || to_char(sql_exec_id, 'TM') as sql_exec_unique
                          , module
                          , action
&_IF_ORA11_OR_HIGHER                            , sql_exec_start
&_IF_ORA11_OR_HIGHER                            , sql_exec_id
                    from
                            &global_ash ash
                    where
                            (lnnvl(sql_id = '&si') or &ash_ln_pred1 &ash_ln_pred2)
                    and     cast(sample_time as date) between to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS') and to_date('&ash_max_sample_time', 'YYYY-MM-DD HH24:MI:SS')
                    and     &inst_id in
                            (
                              select
                                      distinct
                                      &inst_id
                              from
                                      &global_ash ash
                              where
                                      sql_id = '&si'
                              and     &ash_pred1 &ash_pred2
                              and     cast(sample_time as date) between to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS') and to_date('&ash_max_sample_time', 'YYYY-MM-DD HH24:MI:SS')
                            )
                  ) ash
          where
                  instr('&op', 'ASH') > 0
          -- This prevents the aggregate functions to produce a single row
          -- in case of no rows generated to aggregate
          group by
                  instance_id
        )
order by
        instance_id
;

column instance_id clear
column sample_count clear

set heading off

column message format a50

select
        chr(10) || chr(10) as message
from
        dual
where
        instr('&op', 'ASH') > 0
and     '&ca_sc' is null
---------
union all
---------
select
        'No concurrent activity detected' as message
from
        dual
where
        instr('&op', 'ASH') > 0
and     '&ca_sc' is null
;

column message clear

set heading on

set heading off

column message format a50

select
        chr(10) || chr(10) as message
from
        dual
where
        instr('&op', 'ASH') > 0
---------
union all
---------
select
        'Concurrent Activity Summary (not this execution)' as message
from
        dual
where
        instr('&op', 'ASH') > 0
---------
union all
---------
select
        '-----------------------------------------------'
from
        dual
where
        instr('&op', 'ASH') > 0
;

column message clear

set heading on

-- If you need to debug, comment the following line
set termout off

/* Determine if wait times should be shown or not (Bad ASH math, so don't show that by default) */

column show_wait_times new_value _SHOW_WAIT_TIMES noprint

select
        case when '&_EXPERIMENTAL' is null then '' else 'no' end as show_wait_times
from
        dual
;

column show_wait_times clear

set termout on
column instance_id &_IF_CROSS_INSTANCE.print
column activity format a50
column activity_class format a20
column activity_graph format a&wgs
column avg_tim_wait_ms &_SHOW_WAIT_TIMES.print
column med_tim_wait_ms &_SHOW_WAIT_TIMES.print
break on instance_id

select  /* XPLAN_ASH CONCURRENT_ACTIVITY_CONCURRENT_EXECUTION */
        instance_id
      , activity
      , activity_class
      , round(avg(time_waited) / 1000, 1)                                         as avg_tim_wait_ms
      , round(median(time_waited) / 1000, 1)                                      as med_tim_wait_ms
      , count(*)                                                                  as sample_count
      , round(count(*) / total_cnt * 100)                                         as percentage
      , rpad('&gc', nvl(round(count(*) / nullif(total_cnt, 0) * &wgs), 0), '&gc') as activity_graph
from
        (
                    select
                            &inst_id as instance_id
                          , case when session_state = 'WAITING' then nvl(wait_class, '<Wait Class Is Null>') else session_state end as activity_class
                          , case when session_state = 'WAITING' then nvl(event, '<Wait Event Is Null>') else session_state end      as activity
                          , case when session_state = 'WAITING' then nullif(time_waited, 0) else null end                           as time_waited
                          , count(*) over ()                                                                                        as total_cnt
                    from
                            &global_ash ash
                    where
                            (lnnvl(sql_id = '&si') or &ash_ln_pred1 &ash_ln_pred2)
                    and     cast(sample_time as date) between to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS') and to_date('&ash_max_sample_time', 'YYYY-MM-DD HH24:MI:SS')
                    and     &inst_id in
                            (
                              select
                                      distinct
                                      &inst_id
                              from
                                      &global_ash ash
                              where
                                      sql_id = '&si'
                              and     &ash_pred1 &ash_pred2
                              and     cast(sample_time as date) between to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS') and to_date('&ash_max_sample_time', 'YYYY-MM-DD HH24:MI:SS')
                            )
                    and     instr('&op', 'ASH') > 0
        )
group by
        instance_id
      , activity
      , activity_class
      , total_cnt
order by
        instance_id
      , sample_count desc
;

column instance_id clear
column activity clear
column activity_class clear
column activity_graph clear
column avg_tim_wait_ms clear
column med_tim_wait_ms clear

clear breaks

set heading off

column message format a50

select
        chr(10) || chr(10) as message
from
        dual
where
        instr('&op', 'ASH') > 0
and     '&ca_sc' is null
---------
union all
---------
select
        'No concurrent activity detected' as message
from
        dual
where
        instr('&op', 'ASH') > 0
and     '&ca_sc' is null
;

column message clear

set heading on

/* I/O Summary information based on ASH */

/* The following query will be used multiple times with different parameters and therefore written to a temporary file */

select  /* XPLAN_ASH IO_SUMMARY */
        instance_id
      , duration_secs
      , lpad(to_char(round(total_read_io_req / power(10, power_10_total_read_io_req - case when power_10_total_read_io_req > 0 and power_10_total_read_io_req_3 = 0 then 3 else power_10_total_read_io_req_3 end)), 'FM99999'), 5) ||
        case power_10_total_read_io_req - case when power_10_total_read_io_req > 0 and power_10_total_read_io_req_3 = 0 then 3 else power_10_total_read_io_req_3 end
        when 0            then ' '
        when 1            then ' '
        when 3*1          then 'K'
        when 3*2          then 'M'
        when 3*3          then 'G'
        when 3*4          then 'T'
        when 3*5          then 'P'
        when 3*6          then 'E'
        else case
             when total_read_io_req is null
             then null
             else '*10^'||to_char(power_10_total_read_io_req - case when power_10_total_read_io_req > 0 and power_10_total_read_io_req_3 = 0 then 3 else power_10_total_read_io_req_3 end)
             end
        end      as total_read_io_req
      , lpad(to_char(round(total_write_io_req / power(10, power_10_total_write_io_req - case when power_10_total_write_io_req > 0 and power_10_total_write_io_req_3 = 0 then 3 else power_10_total_write_io_req_3 end)), 'FM99999'), 5) ||
        case power_10_total_write_io_req - case when power_10_total_write_io_req > 0 and power_10_total_write_io_req_3 = 0 then 3 else power_10_total_write_io_req_3 end
        when 0            then ' '
        when 1            then ' '
        when 3*1          then 'K'
        when 3*2          then 'M'
        when 3*3          then 'G'
        when 3*4          then 'T'
        when 3*5          then 'P'
        when 3*6          then 'E'
        else case
             when total_write_io_req is null
             then null
             else '*10^'||to_char(power_10_total_write_io_req - case when power_10_total_write_io_req > 0 and power_10_total_write_io_req_3 = 0 then 3 else power_10_total_write_io_req_3 end)
             end
        end      as total_write_io_req
      , lpad(to_char(round(read_io_req_per_sec / power(10, power_10_read_io_req_per_sec - case when power_10_read_io_req_per_sec > 0 and power_10_read_io_req_per_sec_3 = 0 then 3 else power_10_read_io_req_per_sec_3 end)), 'FM99999'), 5) ||
        case power_10_read_io_req_per_sec - case when power_10_read_io_req_per_sec > 0 and power_10_read_io_req_per_sec_3 = 0 then 3 else power_10_read_io_req_per_sec_3 end
        when 0            then ' '
        when 1            then ' '
        when 3*1          then 'K'
        when 3*2          then 'M'
        when 3*3          then 'G'
        when 3*4          then 'T'
        when 3*5          then 'P'
        when 3*6          then 'E'
        else case
             when read_io_req_per_sec is null
             then null
             else '*10^'||to_char(power_10_read_io_req_per_sec - case when power_10_read_io_req_per_sec > 0 and power_10_read_io_req_per_sec_3 = 0 then 3 else power_10_read_io_req_per_sec_3 end)
             end
        end      as read_io_req_per_sec
      , lpad(to_char(round(write_io_req_per_sec / power(10, power_10_write_io_req_per_sec - case when power_10_write_io_req_per_sec > 0 and power_10_write_io_req_persec_3 = 0 then 3 else power_10_write_io_req_persec_3 end)), 'FM99999'), 5) ||
        case power_10_write_io_req_per_sec - case when power_10_write_io_req_per_sec > 0 and power_10_write_io_req_persec_3 = 0 then 3 else power_10_write_io_req_persec_3 end
        when 0            then ' '
        when 1            then ' '
        when 3*1          then 'K'
        when 3*2          then 'M'
        when 3*3          then 'G'
        when 3*4          then 'T'
        when 3*5          then 'P'
        when 3*6          then 'E'
        else case
             when write_io_req_per_sec is null
             then null
             else '*10^'||to_char(power_10_write_io_req_per_sec - case when power_10_write_io_req_per_sec > 0 and power_10_write_io_req_persec_3 = 0 then 3 else power_10_write_io_req_persec_3 end)
             end
        end      as write_io_req_per_sec
      , lpad(to_char(round(total_read_io_bytes / power(10, power_10_t_read_io_bytes - case when power_10_t_read_io_bytes > 0 and power_10_t_read_io_bytes_3 = 0 then 3 else power_10_t_read_io_bytes_3 end)), 'FM99999'), 5) ||
        case power_10_t_read_io_bytes - case when power_10_t_read_io_bytes > 0 and power_10_t_read_io_bytes_3 = 0 then 3 else power_10_t_read_io_bytes_3 end
        when 0            then ' '
        when 1            then ' '
        when 3*1          then 'K'
        when 3*2          then 'M'
        when 3*3          then 'G'
        when 3*4          then 'T'
        when 3*5          then 'P'
        when 3*6          then 'E'
        else case
             when total_read_io_bytes is null
             then null
             else '*10^'||to_char(power_10_t_read_io_bytes - case when power_10_t_read_io_bytes > 0 and power_10_t_read_io_bytes_3 = 0 then 3 else power_10_t_read_io_bytes_3 end)
             end
        end      as total_read_io_bytes
      , lpad(to_char(round(total_write_io_bytes / power(10, power_10_t_write_io_bytes - case when power_10_t_write_io_bytes > 0 and power_10_t_write_io_bytes_3 = 0 then 3 else power_10_t_write_io_bytes_3 end)), 'FM99999'), 5) ||
        case power_10_t_write_io_bytes - case when power_10_t_write_io_bytes > 0 and power_10_t_write_io_bytes_3 = 0 then 3 else power_10_t_write_io_bytes_3 end
        when 0            then ' '
        when 1            then ' '
        when 3*1          then 'K'
        when 3*2          then 'M'
        when 3*3          then 'G'
        when 3*4          then 'T'
        when 3*5          then 'P'
        when 3*6          then 'E'
        else case
             when total_write_io_bytes is null
             then null
             else '*10^'||to_char(power_10_t_write_io_bytes - case when power_10_t_write_io_bytes > 0 and power_10_t_write_io_bytes_3 = 0 then 3 else power_10_t_write_io_bytes_3 end)
             end
        end      as total_write_io_bytes
      , lpad(to_char(round(total_intercon_io_bytes / power(10, power_10_t_intcon_io_bytes - case when power_10_t_intcon_io_bytes > 0 and power_10_t_intcon_io_bytes_3 = 0 then 3 else power_10_t_intcon_io_bytes_3 end)), 'FM99999'), 5) ||
        case power_10_t_intcon_io_bytes - case when power_10_t_intcon_io_bytes > 0 and power_10_t_intcon_io_bytes_3 = 0 then 3 else power_10_t_intcon_io_bytes_3 end
        when 0            then ' '
        when 1            then ' '
        when 3*1          then 'K'
        when 3*2          then 'M'
        when 3*3          then 'G'
        when 3*4          then 'T'
        when 3*5          then 'P'
        when 3*6          then 'E'
        else case
             when total_intercon_io_bytes is null
             then null
             else '*10^'||to_char(power_10_t_intcon_io_bytes - case when power_10_t_intcon_io_bytes > 0 and power_10_t_intcon_io_bytes_3 = 0 then 3 else power_10_t_intcon_io_bytes_3 end)
             end
        end      as total_intercon_io_bytes
      , lpad(to_char(round(read_io_bytes_per_sec / power(10, power_10_read_io_bytes_ps - case when power_10_read_io_bytes_ps > 0 and power_10_read_io_bytes_ps_3 = 0 then 3 else power_10_read_io_bytes_ps_3 end)), 'FM99999'), 5) ||
        case power_10_read_io_bytes_ps - case when power_10_read_io_bytes_ps > 0 and power_10_read_io_bytes_ps_3 = 0 then 3 else power_10_read_io_bytes_ps_3 end
        when 0            then ' '
        when 1            then ' '
        when 3*1          then 'K'
        when 3*2          then 'M'
        when 3*3          then 'G'
        when 3*4          then 'T'
        when 3*5          then 'P'
        when 3*6          then 'E'
        else case
             when read_io_bytes_per_sec is null
             then null
             else '*10^'||to_char(power_10_read_io_bytes_ps - case when power_10_read_io_bytes_ps > 0 and power_10_read_io_bytes_ps_3 = 0 then 3 else power_10_read_io_bytes_ps_3 end)
             end
        end      as read_io_bytes_per_sec
      , lpad(to_char(round(write_io_bytes_per_sec / power(10, power_10_write_io_bytes_ps - case when power_10_write_io_bytes_ps > 0 and power_10_write_io_bytes_ps_3 = 0 then 3 else power_10_write_io_bytes_ps_3 end)), 'FM99999'), 5) ||
        case power_10_write_io_bytes_ps - case when power_10_write_io_bytes_ps > 0 and power_10_write_io_bytes_ps_3 = 0 then 3 else power_10_write_io_bytes_ps_3 end
        when 0            then ' '
        when 1            then ' '
        when 3*1          then 'K'
        when 3*2          then 'M'
        when 3*3          then 'G'
        when 3*4          then 'T'
        when 3*5          then 'P'
        when 3*6          then 'E'
        else case
             when write_io_bytes_per_sec is null
             then null
             else '*10^'||to_char(power_10_write_io_bytes_ps - case when power_10_write_io_bytes_ps > 0 and power_10_write_io_bytes_ps_3 = 0 then 3 else power_10_write_io_bytes_ps_3 end)
             end
        end      as write_io_bytes_per_sec
      , lpad(to_char(round(intercon_io_bytes_per_sec / power(10, power_10_intercon_io_bytes_ps - case when power_10_intercon_io_bytes_ps > 0 and power_10_intercon_io_byte_ps_3 = 0 then 3 else power_10_intercon_io_byte_ps_3 end)), 'FM99999'), 5) ||
        case power_10_intercon_io_bytes_ps - case when power_10_intercon_io_bytes_ps > 0 and power_10_intercon_io_byte_ps_3 = 0 then 3 else power_10_intercon_io_byte_ps_3 end
        when 0            then ' '
        when 1            then ' '
        when 3*1          then 'K'
        when 3*2          then 'M'
        when 3*3          then 'G'
        when 3*4          then 'T'
        when 3*5          then 'P'
        when 3*6          then 'E'
        else case
             when intercon_io_bytes_per_sec is null
             then null
             else '*10^'||to_char(power_10_intercon_io_bytes_ps - case when power_10_intercon_io_bytes_ps > 0 and power_10_intercon_io_byte_ps_3 = 0 then 3 else power_10_intercon_io_byte_ps_3 end)
             end
        end      as intercon_io_bytes_per_sec
      , lpad(to_char(round(avg_read_req_size / power(10, power_10_avg_read_req_size - case when power_10_avg_read_req_size > 0 and power_10_avg_read_req_size_3 = 0 then 3 else power_10_avg_read_req_size_3 end)), 'FM99999'), 5) ||
        case power_10_avg_read_req_size - case when power_10_avg_read_req_size > 0 and power_10_avg_read_req_size_3 = 0 then 3 else power_10_avg_read_req_size_3 end
        when 0            then ' '
        when 1            then ' '
        when 3*1          then 'K'
        when 3*2          then 'M'
        when 3*3          then 'G'
        when 3*4          then 'T'
        when 3*5          then 'P'
        when 3*6          then 'E'
        else case
             when avg_read_req_size is null
             then null
             else '*10^'||to_char(power_10_avg_read_req_size - case when power_10_avg_read_req_size > 0 and power_10_avg_read_req_size_3 = 0 then 3 else power_10_avg_read_req_size_3 end)
             end
        end      as avg_read_req_size
      , lpad(to_char(round(med_read_req_size / power(10, power_10_med_read_req_size - case when power_10_med_read_req_size > 0 and power_10_med_read_req_size_3 = 0 then 3 else power_10_med_read_req_size_3 end)), 'FM99999'), 5) ||
        case power_10_med_read_req_size - case when power_10_med_read_req_size > 0 and power_10_med_read_req_size_3 = 0 then 3 else power_10_med_read_req_size_3 end
        when 0            then ' '
        when 1            then ' '
        when 3*1          then 'K'
        when 3*2          then 'M'
        when 3*3          then 'G'
        when 3*4          then 'T'
        when 3*5          then 'P'
        when 3*6          then 'E'
        else case
             when med_read_req_size is null
             then null
             else '*10^'||to_char(power_10_med_read_req_size - case when power_10_med_read_req_size > 0 and power_10_med_read_req_size_3 = 0 then 3 else power_10_med_read_req_size_3 end)
             end
        end      as med_read_req_size
      , lpad(to_char(round(avg_write_req_size / power(10, power_10_avg_write_req_size - case when power_10_avg_write_req_size > 0 and power_10_avg_write_req_size_3 = 0 then 3 else power_10_avg_write_req_size_3 end)), 'FM99999'), 5) ||
        case power_10_avg_write_req_size - case when power_10_avg_write_req_size > 0 and power_10_avg_write_req_size_3 = 0 then 3 else power_10_avg_write_req_size_3 end
        when 0            then ' '
        when 1            then ' '
        when 3*1          then 'K'
        when 3*2          then 'M'
        when 3*3          then 'G'
        when 3*4          then 'T'
        when 3*5          then 'P'
        when 3*6          then 'E'
        else case
             when avg_write_req_size is null
             then null
             else '*10^'||to_char(power_10_avg_write_req_size - case when power_10_avg_write_req_size > 0 and power_10_avg_write_req_size_3 = 0 then 3 else power_10_avg_write_req_size_3 end)
             end
        end      as avg_write_req_size
      , lpad(to_char(round(med_write_req_size / power(10, power_10_med_write_req_size - case when power_10_med_write_req_size > 0 and power_10_med_write_req_size_3 = 0 then 3 else power_10_med_write_req_size_3 end)), 'FM99999'), 5) ||
        case power_10_med_write_req_size - case when power_10_med_write_req_size > 0 and power_10_med_write_req_size_3 = 0 then 3 else power_10_med_write_req_size_3 end
        when 0            then ' '
        when 1            then ' '
        when 3*1          then 'K'
        when 3*2          then 'M'
        when 3*3          then 'G'
        when 3*4          then 'T'
        when 3*5          then 'P'
        when 3*6          then 'E'
        else case
             when med_write_req_size is null
             then null
             else '*10^'||to_char(power_10_med_write_req_size - case when power_10_med_write_req_size > 0 and power_10_med_write_req_size_3 = 0 then 3 else power_10_med_write_req_size_3 end)
             end
        end      as med_write_req_size
      , to_char(nvl(cell_offload_efficiency, 0), '999') || '%' as cell_offload_efficiency
from
        (
          select
                  instance_id
                , duration_secs
                , total_read_io_req
                , total_write_io_req
                , read_io_req_per_sec
                , write_io_req_per_sec
                , total_read_io_bytes
                , total_write_io_bytes
                , total_intercon_io_bytes
                , avg_read_req_size
                , med_read_req_size
                , avg_write_req_size
                , med_write_req_size
                , 100 - round(total_intercon_io_bytes / nullif((total_read_io_bytes + total_write_io_bytes), 0) * 100) as cell_offload_efficiency
                , read_io_bytes_per_sec
                , write_io_bytes_per_sec
                , intercon_io_bytes_per_sec
                , trunc(log(10, abs(case total_read_io_bytes when 0 then 1 else total_read_io_bytes end)))                     as power_10_t_read_io_bytes
                , trunc(mod(log(10, abs(case total_read_io_bytes when 0 then 1 else total_read_io_bytes end)), 3))             as power_10_t_read_io_bytes_3
                , trunc(log(10, abs(case total_write_io_bytes when 0 then 1 else total_write_io_bytes end)))                   as power_10_t_write_io_bytes
                , trunc(mod(log(10, abs(case total_write_io_bytes when 0 then 1 else total_write_io_bytes end)), 3))           as power_10_t_write_io_bytes_3
                , trunc(log(10, abs(case total_read_io_req when 0 then 1 else total_read_io_req end)))                         as power_10_total_read_io_req
                , trunc(mod(log(10, abs(case total_read_io_req when 0 then 1 else total_read_io_req end)), 3))                 as power_10_total_read_io_req_3
                , trunc(log(10, abs(case total_write_io_req when 0 then 1 else total_write_io_req end)))                       as power_10_total_write_io_req
                , trunc(mod(log(10, abs(case total_write_io_req when 0 then 1 else total_write_io_req end)), 3))               as power_10_total_write_io_req_3
                , trunc(log(10, abs(case read_io_req_per_sec when 0 then 1 else read_io_req_per_sec end)))                     as power_10_read_io_req_per_sec
                , trunc(mod(log(10, abs(case read_io_req_per_sec when 0 then 1 else read_io_req_per_sec end)), 3))             as power_10_read_io_req_per_sec_3
                , trunc(log(10, abs(case write_io_req_per_sec when 0 then 1 else write_io_req_per_sec end)))                   as power_10_write_io_req_per_sec
                , trunc(mod(log(10, abs(case write_io_req_per_sec when 0 then 1 else write_io_req_per_sec end)), 3))           as power_10_write_io_req_persec_3
                , trunc(log(10, abs(case total_intercon_io_bytes when 0 then 1 else total_intercon_io_bytes end)))             as power_10_t_intcon_io_bytes
                , trunc(mod(log(10, abs(case total_intercon_io_bytes when 0 then 1 else total_intercon_io_bytes end)), 3))     as power_10_t_intcon_io_bytes_3
                , trunc(log(10, abs(case read_io_bytes_per_sec when 0 then 1 else read_io_bytes_per_sec end)))                 as power_10_read_io_bytes_ps
                , trunc(mod(log(10, abs(case read_io_bytes_per_sec when 0 then 1 else read_io_bytes_per_sec end)), 3))         as power_10_read_io_bytes_ps_3
                , trunc(log(10, abs(case write_io_bytes_per_sec when 0 then 1 else write_io_bytes_per_sec end)))               as power_10_write_io_bytes_ps
                , trunc(mod(log(10, abs(case write_io_bytes_per_sec when 0 then 1 else write_io_bytes_per_sec end)), 3))       as power_10_write_io_bytes_ps_3
                , trunc(log(10, abs(case intercon_io_bytes_per_sec when 0 then 1 else intercon_io_bytes_per_sec end)))         as power_10_intercon_io_bytes_ps
                , trunc(mod(log(10, abs(case intercon_io_bytes_per_sec when 0 then 1 else intercon_io_bytes_per_sec end)), 3)) as power_10_intercon_io_byte_ps_3
                , trunc(log(10, abs(case avg_read_req_size when 0 then 1 else avg_read_req_size end)))                         as power_10_avg_read_req_size
                , trunc(mod(log(10, abs(case avg_read_req_size when 0 then 1 else avg_read_req_size end)), 3))                 as power_10_avg_read_req_size_3
                , trunc(log(10, abs(case med_read_req_size when 0 then 1 else med_read_req_size end)))                         as power_10_med_read_req_size
                , trunc(mod(log(10, abs(case med_read_req_size when 0 then 1 else med_read_req_size end)), 3))                 as power_10_med_read_req_size_3
                , trunc(log(10, abs(case avg_write_req_size when 0 then 1 else avg_write_req_size end)))                       as power_10_avg_write_req_size
                , trunc(mod(log(10, abs(case avg_write_req_size when 0 then 1 else avg_write_req_size end)), 3))               as power_10_avg_write_req_size_3
                , trunc(log(10, abs(case med_write_req_size when 0 then 1 else med_write_req_size end)))                       as power_10_med_write_req_size
                , trunc(mod(log(10, abs(case med_write_req_size when 0 then 1 else med_write_req_size end)), 3))               as power_10_med_write_req_size_3
          from
                  (
                    select
                            instance_id
                          , duration_secs
                          , sum_delta_read_io_req                                               as total_read_io_req
                          , sum_delta_write_io_req                                              as total_write_io_req
                          , sum_delta_read_io_bytes                                             as total_read_io_bytes
                          , sum_delta_write_io_bytes                                            as total_write_io_bytes
                          , sum_delta_interc_io_bytes                                           as total_intercon_io_bytes
                          , round(avg_delta_read_req_size)                                      as avg_read_req_size
                          , round(med_delta_read_req_size)                                      as med_read_req_size
                          , round(avg_delta_write_req_size)                                     as avg_write_req_size
                          , round(med_delta_write_req_size)                                     as med_write_req_size
                          , round(sum_delta_read_io_req / duration_secs)                        as read_io_req_per_sec
                          , round(sum_delta_write_io_req / duration_secs)                       as write_io_req_per_sec
                          , round(sum_delta_read_io_bytes / duration_secs)                      as read_io_bytes_per_sec
                          , round(sum_delta_write_io_bytes / duration_secs)                     as write_io_bytes_per_sec
                          , round(sum_delta_interc_io_bytes / duration_secs)                    as intercon_io_bytes_per_sec
                    from
                            (
                              select
                                     &GROUP_CROSS_INSTANCE                                                     as instance_id
                                   , round(((max(sample_time) - min(sql_exec_start)) * 86400)) + &sample_freq  as duration_secs
                                   , sum(delta_read_io_requests)                                               as sum_delta_read_io_req
                                   , sum(delta_write_io_requests)                                              as sum_delta_write_io_req
                                   , sum(delta_read_io_bytes)                                                  as sum_delta_read_io_bytes
                                   , sum(delta_write_io_bytes)                                                 as sum_delta_write_io_bytes
                                   , sum(delta_interconnect_io_bytes)                                          as sum_delta_interc_io_bytes
                                   , avg(delta_read_request_size)                                              as avg_delta_read_req_size
                                   , median(delta_read_request_size)                                           as med_delta_read_req_size
                                   , avg(delta_write_request_size)                                             as avg_delta_write_req_size
                                   , median(delta_write_request_size)                                          as med_delta_write_req_size
                              from
                                      (
                                        select
                                                &inst_id                  as instance_id
                                              , sql_id
                                              , cast(sample_time as date) as sample_time
&_IF_ORA112_OR_HIGHER                                               , delta_time
&_IF_LOWER_THAN_ORA112                                              , 0 as delta_time
&_IF_ORA112_OR_HIGHER                                               , delta_read_io_requests
&_IF_LOWER_THAN_ORA112                                              , 0 as delta_read_io_requests
&_IF_ORA112_OR_HIGHER                                               , delta_write_io_requests
&_IF_LOWER_THAN_ORA112                                              , 0 as delta_write_io_requests
&_IF_ORA112_OR_HIGHER                                               , delta_read_io_bytes
&_IF_LOWER_THAN_ORA112                                              , 0 as delta_read_io_bytes
&_IF_ORA112_OR_HIGHER                                               , delta_write_io_bytes
&_IF_LOWER_THAN_ORA112                                              , 0 as delta_write_io_bytes
&_IF_ORA112_OR_HIGHER                                               , delta_read_io_bytes / nullif(delta_read_io_requests, 0) as delta_read_request_size
&_IF_LOWER_THAN_ORA112                                              , 0 as delta_read_request_size
&_IF_ORA112_OR_HIGHER                                               , delta_write_io_bytes / nullif(delta_write_io_requests, 0) as delta_write_request_size
&_IF_LOWER_THAN_ORA112                                              , 0 as delta_write_request_size
&_IF_ORA112_OR_HIGHER                                               , delta_interconnect_io_bytes
&_IF_LOWER_THAN_ORA112                                              , 0 as delta_interconnect_io_bytes
&_IF_ORA11_OR_HIGHER                                                , sql_exec_start
&_IF_LOWER_THAN_ORA11                                               , to_date('01.01.1970', 'DD.MM.YYYY') as sql_exec_start
&_IF_ORA11_OR_HIGHER                                                , sql_exec_id
                                        from
                                                &global_ash ash
                                        where
                                                sql_id = '&si'
                                        and     &ash_pred1 &ash_pred2
                                        and     cast(sample_time as date) between to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS') and to_date('&ash_max_sample_time', 'YYYY-MM-DD HH24:MI:SS')
                                      ) ash
                              where
                              -- only include samples that cover a time period within the execution time period of the SQL statement
&_IF_ORA112_OR_HIGHER                                       ash.sample_time - round(ash.delta_time / 1000000) / 86400 >= ash.sql_exec_start - &sample_freq / 86400
&_IF_LOWER_THAN_ORA112                                      1 = 1
                              and     instr('&op', 'ASH') > 0
                              and     '&_IF_ORA112_OR_HIGHER' is null
                              and     '&_EXPERIMENTAL' is null
                              and     to_number(nvl('&ic', '0')) > &INSTANCE_THRESHOLD
                              -- This prevents the aggregate functions to produce a single row
                              -- in case of no rows generated to aggregate
                              group by
                                      &GROUP_CROSS_INSTANCE
                            )
                  )
        )
order by
        instance_id
.

-- If you need to debug, comment the following line
set termout off

save .xplan_ash_temp replace

set termout on

set heading off

column message format a50

select
        chr(10) || chr(10) as message
from
        dual
where
        instr('&op', 'ASH') > 0
and     '&_IF_ORA112_OR_HIGHER' is null
and     '&_EXPERIMENTAL' is null
---------
union all
---------
select
        'Global I/O Summary based on ASH' as message
from
        dual
where
        instr('&op', 'ASH') > 0
and     '&_IF_ORA112_OR_HIGHER' is null
and     '&_EXPERIMENTAL' is null
---------
union all
---------
select
        '-----------------------------------------------'
from
        dual
where
        instr('&op', 'ASH') > 0
and     '&_IF_ORA112_OR_HIGHER' is null
and     '&_EXPERIMENTAL' is null
;

column message clear

set heading on

-- If you need to debug, comment the following line
set termout off

get .xplan_ash_temp

set termout on

column instance_id noprint

column duration_secs                       heading 'DURATION|SECS'          justify left
column total_read_io_req         format a6 heading 'TOTAL|READ|IO|REQS'     justify left
column total_write_io_req        format a6 heading 'TOTAL|WRITE|IO|REQS'    justify left
column read_io_req_per_sec       format a6 heading 'READ|IO|REQS|PERSEC'    justify left
column write_io_req_per_sec      format a6 heading 'WRITE|IO|REQS|PERSEC'   justify left
column total_read_io_bytes       format a6 heading 'TOTAL|READ|IO|BYTES'    justify left
column total_write_io_bytes      format a6 heading 'TOTAL|WRITE|IO|BYTES'   justify left
column avg_read_req_size         format a6 heading 'AVG|READ|REQ|SIZE'      justify left
column med_read_req_size         format a6 heading 'MEDIAN|READ|REQ|SIZE'   justify left
column avg_write_req_size        format a6 heading 'AVG|WRITE|REQ|SIZE'     justify left
column med_write_req_size        format a6 heading 'MEDIAN|WRITE|REQ|SIZE'  justify left
column total_intercon_io_bytes   format a6 heading 'TOTAL|IO|LAYER|BYTES'   justify left
column cell_offload_efficiency   format a5 heading 'CELL|OFFL|EFF'          justify left
column read_io_bytes_per_sec     format a6 heading 'READ|IO|BYTES|PERSEC'   justify left
column write_io_bytes_per_sec    format a6 heading 'WRITE|IO|BYTES|PERSEC'  justify left
column intercon_io_bytes_per_sec format a6 heading 'IO|LAYER|BYTES|PERSEC'  justify left

define INSTANCE_THRESHOLD = "0"
define GROUP_CROSS_INSTANCE = "1"

/

set heading off

column message format a50

select
        chr(10) || chr(10) as message
from
        dual
where
        instr('&op', 'ASH') > 0
and     '&_IF_ORA112_OR_HIGHER' is null
and     '&_EXPERIMENTAL' is null
and     to_number(nvl('&ic', '0')) > 1
---------
union all
---------
select
        'Global I/O Summary per Instance based on ASH' as message
from
        dual
where
        instr('&op', 'ASH') > 0
and     '&_IF_ORA112_OR_HIGHER' is null
and     '&_EXPERIMENTAL' is null
and     to_number(nvl('&ic', '0')) > 1
---------
union all
---------
select
        '-----------------------------------------------'
from
        dual
where
        instr('&op', 'ASH') > 0
and     '&_IF_ORA112_OR_HIGHER' is null
and     '&_EXPERIMENTAL' is null
and     to_number(nvl('&ic', '0')) > 1
;

column message clear

set heading on

set termout off

get .xplan_ash_temp

set termout on

column instance_id print

define INSTANCE_THRESHOLD = "1"
define GROUP_CROSS_INSTANCE = "instance_id"

/

undefine INSTANCE_THRESHOLD
undefine GROUP_CROSS_INSTANCE

column duration_secs             clear
column total_read_io_req         clear
column total_write_io_req        clear
column read_io_req_per_sec       clear
column write_io_req_per_sec      clear
column total_read_io_bytes       clear
column total_write_io_bytes      clear
column avg_read_req_size         clear
column med_read_req_size         clear
column avg_write_req_size        clear
column med_write_req_size        clear
column total_intercon_io_bytes   clear
column cell_offload_efficiency   clear
column read_io_bytes_per_sec     clear
column write_io_bytes_per_sec    clear
column intercon_io_bytes_per_sec clear

set heading off

column message format a50

select
        chr(10) || chr(10) as message
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
with /* XPLAN_ASH PARALLEL_DEGREE_INFO */
set_count
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
            and     &third_id
            and     p.object_node like ':Q%'
            and     instr('&op', 'DISTRIB') > 0
            and     '&plan_exists' is not null
            and     '&_IF_ORA11_OR_HIGHER' is null
          )
  group by
          dfo
)
select  /* XPLAN_ASH PARALLEL_DEGREE_INFO */
        instance_id
      , dfo
      , start_active
      , duration_secs
      , sample_count
      , process_count
      , set_count
      , assumed_degree
&_IF_ORA11202_OR_HIGHER      , actual_degree / to_number('&ic') as actual_degree
      , case when average_as >= &rnd_thr then round(average_as) else average_as end                                                                     as average_as
      , substr(rpad(' ', round(start_active / to_number('&ds') * &tgs)) || rpad('&gc', round(duration_secs / to_number('&ds') * &tgs), '&gc'), 1, &tgs) as time_active_graph
from
        (
          select  /*+ cardinality(100) */
                  &inst_id                                                                                                as instance_id
                , sc.dfo
&_IF_ORA11_OR_HIGHER                  , round((min(sample_time) - min(sql_exec_start)) * 86400)                                                 as start_active
&_IF_LOWER_THAN_ORA11                 , 0                                                                                                       as start_active
                , round(((max(sample_time) - min(sample_time)) * 86400)) + &sample_freq                                   as duration_secs
                , count(process)                                                                                          as sample_count
                , count(distinct process)                                                                                 as process_count
                , sc.set_count                                                                                            as set_count
                , ceil(count(distinct process) / sc.set_count)                                                            as assumed_degree
&_IF_ORA11202_OR_HIGHER               , max(trunc(px_flags / 2097152))                                                                          as actual_degree
                , round(count(*) / (((max(sample_time) - min(sample_time)) * 86400) + &sample_freq) * &sample_freq, 2)    as average_as
          from    (
                    select  /*+ cardinality(ash 100) use_hash(ash p) no_merge(p) */
                            ash.&inst_id
                          , regexp_replace(ash.program, '^.*\((P[[:alnum:]][[:digit:]][[:digit:]])\)$', '\1', 1, 1, 'c') as process
                          , cast(substr(p.object_node, 2, length(p.object_node) - 4) as varchar2(6))                     as dfo
                          , cast(ash.sample_time as date)                                                                as sample_time
&_IF_ORA11202_OR_HIGHER                         , px_flags
&_IF_ORA11_OR_HIGHER                            , ash.sql_exec_start
&_IF_LOWER_THAN_ORA11                           , to_date('01.01.1970', 'DD.MM.YYYY') as sql_exec_start
                    from
                            &global_ash ash
                          , &plan_table p
                    where
                            ash.sql_id = '&si'
                    and     &ash_pred1 &ash_pred2
                    and     cast(ash.sample_time as date) between to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS') and to_date('&ash_max_sample_time', 'YYYY-MM-DD HH24:MI:SS')
                    -- and     regexp_like(ash.program, '^.*\((P[[:alnum:]][[:digit:]][[:digit:]])\)$')
                    and     p.sql_id = '&si'
                    and     p.&second_id = &cn
                    and     &third_id
&_IF_ORA11_OR_HIGHER                      and     p.id = ash.sql_plan_line_id
                    and     p.object_node is not null
                    and     instr('&op', 'DISTRIB') > 0
                    and     '&plan_exists' is not null
                    and     '&_IF_ORA11_OR_HIGHER' is null
                  ) pr
                , set_count sc
          where
                  sc.dfo = pr.dfo (+)
          group by
                  &inst_id
                , sc.dfo
                , sc.set_count
        )
order by
        instance_id
      , dfo
;

column dfo               clear
column time_active_graph clear
column instance_id       clear

/* If DISTRIB option was used and Parallel Execution was expected
   show a message here that no Parallel Execution activity could be found in ASH */

set heading off

column message format a50

select
        chr(10) || chr(10) as message
from
        dual
where
        '&slave_count' is null and instr('&op', 'DISTRIB') > 0
and     '&plan_exists' is not null
and     '&_IF_ORA11_OR_HIGHER' is null
---------
union all
---------
select
        'No Parallel Slave activity found in ASH!' as message
from
        dual
where
        '&slave_count' is null and instr('&op', 'DISTRIB') > 0
and     '&plan_exists' is not null
and     '&_IF_ORA11_OR_HIGHER' is null;

column message clear

set heading on

set heading off

column message format a50

select
        chr(10) || chr(10) as message
from
        dual
where
        '&slave_count' is not null and instr('&op', 'DISTRIB') > 0
---------
union all
---------
select
        'Parallel Slave activity overview based on ASH' as message
from
        dual
where
        '&slave_count' is not null and instr('&op', 'DISTRIB') > 0
---------
union all
---------
select
        '-----------------------------------------------'
from
        dual
where
        '&slave_count' is not null and instr('&op', 'DISTRIB') > 0
;

column message clear

set heading on

-- If you need to debug, comment the following line
set termout off

/* Determine if I/O figures should be shown or not */

column show_io_cols new_value _SHOW_IO_COLS noprint

select
        case when '&_EXPERIMENTAL' is null and '&_IF_ORA112_OR_HIGHER' is null then '' else 'no' end as show_io_cols
from
        dual
;

column show_io_cols clear

set termout on

column instance_id &_IF_CROSS_INSTANCE.print
break on instance_id

column process format a64
column cnt heading 'SAMPLE|COUNT'
column cnt_cpu heading 'SAMPLE|COUNT|CPU'
column cnt_other heading 'SAMPLE|COUNT|OTHER'
column percentage_cpu heading 'PERCENT|CPU'
column pga  format a6 heading 'MAX|PGA'  &_IF_ORA112_OR_HIGHERP.print
column temp format a6 heading 'MAX|TEMP' &_IF_ORA112_OR_HIGHERP.print
column rd_req format a6 heading 'READ|REQS'           &_SHOW_IO_COLS.print
column wr_req format a6 heading 'WRITE|REQS'          &_SHOW_IO_COLS.print
column rd_byt format a6 heading 'READ|BYTES'          &_SHOW_IO_COLS.print
column wr_byt format a6 heading 'WRITE|BYTES'         &_SHOW_IO_COLS.print
column io_byt format a6 heading 'IO|LAYER|BYTES'      &_SHOW_IO_COLS.print
column rd_r_s format a6 heading 'READ|REQ|PERSEC'     &_SHOW_IO_COLS.print
column wr_r_s format a6 heading 'WRITE|REQ|PERSEC'    &_SHOW_IO_COLS.print
column rd_b_s format a6 heading 'READ|BYTES|PERSEC'   &_SHOW_IO_COLS.print
column wr_b_s format a6 heading 'WRITE|BYTES|PERSEC'  &_SHOW_IO_COLS.print
column io_b_s format a6 heading 'IO_LAY|BYTES|PERSEC' &_SHOW_IO_COLS.print
column a_rr_s format a6 heading 'AVG|RE_REQ|SIZE'     &_SHOW_IO_COLS.print
column m_rr_s format a6 heading 'MEDIAN|RE_REQ|SIZE'  &_SHOW_IO_COLS.print
column a_wr_s format a6 heading 'AVG|WR_REQ|SIZE'     &_SHOW_IO_COLS.print
column m_wr_s format a6 heading 'MEDIAN|WR_REQ|SIZE'  &_SHOW_IO_COLS.print
column plan_lines format a40 heading 'TOP|ACTIVE|PLAN LINES' &_IF_ORA11_OR_HIGHERP.print
column activities format a70 heading 'TOP|ACTIVITIES'
column activity_graph format a&wgs

with /* XPLAN_ASH PARALLEL_SLAVE_ACTIVITY */
/* Base ASH data */
ash_base as
(
  select  /*+ materialize */
          &inst_id                                                                                                                                                      as instance_id
&_IF_ORA11_OR_HIGHER          , sql_exec_start
&_IF_LOWER_THAN_ORA11         , to_date('&ls', '&dm')                                                                                                                                         as sql_exec_start
&_IF_ORA11_OR_HIGHER          , sql_plan_line_id
&_IF_LOWER_THAN_ORA11         , 0 as sql_plan_line_id
        , cast(sample_time as date)                                                                                                                                     as sample_time
        , session_state
        , case when session_state = 'WAITING' then nvl(event, '<Wait Event Is Null>') else session_state end                                                            as activity
        , case when to_number(nvl('&ic', '0')) > 1 then &inst_id || '-' end || regexp_replace(program, '^.*\((P[[:alnum:]][[:digit:]][[:digit:]])\)$', '\1', 1, 1, 'c') as process
        , count(*) over ()                                                                                                                                              as total_cnt
&_IF_ORA112_OR_HIGHER         , nullif(pga_allocated, 0) as pga_allocated
&_IF_LOWER_THAN_ORA112        , to_number(null) as pga_allocated
&_IF_ORA112_OR_HIGHER         , nullif(temp_space_allocated, 0) as temp_space_allocated
&_IF_LOWER_THAN_ORA112        , to_number(null) as temp_space_allocated
&_IF_ORA112_OR_HIGHER         , case when cast(sample_time as date) - round(delta_time / 1000000) / 86400 >= sql_exec_start - &sample_freq / 86400 then delta_read_io_requests else null end                                    as delta_read_io_requests
&_IF_LOWER_THAN_ORA112        , to_number(null) as delta_read_io_requests
&_IF_ORA112_OR_HIGHER         , case when cast(sample_time as date) - round(delta_time / 1000000) / 86400 >= sql_exec_start - &sample_freq / 86400 then delta_write_io_requests else null end                                   as delta_write_io_requests
&_IF_LOWER_THAN_ORA112        , to_number(null) as delta_write_io_requests
&_IF_ORA112_OR_HIGHER         , case when cast(sample_time as date) - round(delta_time / 1000000) / 86400 >= sql_exec_start - &sample_freq / 86400 then delta_read_io_bytes else null end                                       as delta_read_io_bytes
&_IF_LOWER_THAN_ORA112        , to_number(null) as delta_read_io_bytes
&_IF_ORA112_OR_HIGHER         , case when cast(sample_time as date) - round(delta_time / 1000000) / 86400 >= sql_exec_start - &sample_freq / 86400 then delta_write_io_bytes else null end                                      as delta_write_io_bytes
&_IF_LOWER_THAN_ORA112        , to_number(null) as delta_write_io_bytes
&_IF_ORA112_OR_HIGHER         , case when cast(sample_time as date) - round(delta_time / 1000000) / 86400 >= sql_exec_start - &sample_freq / 86400 then delta_read_io_bytes / nullif(delta_read_io_requests, 0) else null end   as delta_read_request_size
&_IF_LOWER_THAN_ORA112        , to_number(null) as delta_read_request_size
&_IF_ORA112_OR_HIGHER         , case when cast(sample_time as date) - round(delta_time / 1000000) / 86400 >= sql_exec_start - &sample_freq / 86400 then delta_write_io_bytes / nullif(delta_write_io_requests, 0) else null end as delta_write_request_size
&_IF_LOWER_THAN_ORA112        , to_number(null) as delta_write_request_size
&_IF_ORA112_OR_HIGHER         , case when cast(sample_time as date) - round(delta_time / 1000000) / 86400 >= sql_exec_start - &sample_freq / 86400 then delta_interconnect_io_bytes else null end                               as delta_interconnect_io_bytes
&_IF_LOWER_THAN_ORA112        , to_number(null) as delta_interconnect_io_bytes
  from
          &global_ash ash
  where
          sql_id = '&si'
  and     &ash_pred1 &ash_pred2
  and     cast(sample_time as date) between to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS') and to_date('&ash_max_sample_time', 'YYYY-MM-DD HH24:MI:SS')
  and     '&slave_count' is not null and instr('&op', 'DISTRIB') > 0
),
/* The most active plan lines */
/* Count occurrence per sample_time and execution plan line */
ash_plan_lines as
(
  select
          cnt
        , instance_id
        , process
        , sql_plan_line_id
  from
          (
            select
                    count(*) as cnt
                  , instance_id
                  , process
                  , sql_plan_line_id
            from
                    ash_base
            group by
                    process
                  , instance_id
                  , sql_plan_line_id
          )
),
/* The Top N execution plan lines */
ash_plan_lines_rn as
(
  select
          cnt
        , sql_plan_line_id
        , instance_id
        , process
        , row_number() over (partition by process, instance_id order by cnt desc, sql_plan_line_id) as rn
  from
          ash_plan_lines
),
/* Aggregate the Top N execution plan lines */
/* This will be joined later to the remaining data */
ash_plan_lines_agg as
(
  select
          instance_id
        , process
&_IF_ORA112_OR_HIGHER           , listagg(case when rn > &topnl + 1 then null when rn = &topnl + 1 then '...' else case when sql_plan_line_id is null then null else sql_plan_line_id || '(' || cnt || ')' end end, ',') within group (order by rn) as plan_lines
&_IF_LOWER_THAN_ORA112          , ltrim(extract(xmlagg(xmlelement("V", case when rn > &topnl + 1 then null when rn = &topnl + 1 then ',' || '...' else case when sql_plan_line_id is null then null else ',' || sql_plan_line_id || '(' || cnt || ')' end end) order by rn), '/V/text()'), ',') as plan_lines
  from
          ash_plan_lines_rn
  group by
          instance_id
        , process
),
/* Count occurrence per sample_time and ASH activity */
ash_activity as
(
  select
          cnt
        , activity
        , instance_id
        , process
  from
          (
            select
                    process
                  , count(*) as cnt
                  , activity
                  , instance_id
            from
                    ash_base
            group by
                    process
                  , instance_id
                  , activity
          )
),
/* The Top N activities per bucket */
ash_activity_rn as
(
  select
          cnt
        , activity
        , instance_id
        , process
        , row_number() over (partition by process, instance_id order by cnt desc, activity) as rn
  from
          ash_activity
),
/* Aggregate the Top N activity */
/* This will be joined later to the remaining data */
ash_activity_agg as
(
  select
          instance_id
        , process
&_IF_ORA112_OR_HIGHER           , listagg(case when rn > &topna + 1 then null when rn = &topna + 1 then '...' else case when activity is null then null else activity || '(' || cnt || ')' end end, ',') within group (order by rn) as activities
&_IF_LOWER_THAN_ORA112          , ltrim(extract(xmlagg(xmlelement("V", case when rn > &topna + 1 then null when rn = &topna + 1 then ',' || '...' else case when activity is null then null else ',' || activity || '(' || cnt || ')' end end) order by rn), '/V/text()'), ',') as activities
  from
          ash_activity_rn
  group by
          instance_id
        , process
),
/* Group the ASH data by process */
ash_process as
(
  select
          instance_id
        , process
        , total_cnt
        , cnt
        , cnt_cpu
        , cnt_other
        , pga_mem
        , temp_space
        , read_req
        , write_req
        , read_bytes
        , write_bytes
        , total_io_bytes
        , read_req_per_sec
        , write_req_per_sec
        , read_bytes_per_sec
        , write_bytes_per_sec
        , tot_io_bytes_per_sec
        , avg_read_req_size
        , med_read_req_size
        , avg_write_req_size
        , med_write_req_size
  from    (
            select
                    process
                  , count(session_state)                                                          as cnt
                  , count(case when session_state = 'ON CPU' then 1 end)                          as cnt_cpu
                  , count(case when session_state != 'ON CPU' then 1 end)                         as cnt_other
                  , max(pga_allocated)                                                            as pga_mem
                  , max(temp_space_allocated)                                                     as temp_space
                  , sum(delta_read_io_requests)                                                   as read_req
                  , sum(delta_write_io_requests)                                                  as write_req
                  , sum(delta_read_io_bytes)                                                      as read_bytes
                  , sum(delta_write_io_bytes)                                                     as write_bytes
                  , sum(delta_interconnect_io_bytes)                                              as total_io_bytes
                  , round(sum(delta_read_io_requests) / &sample_freq  / count(session_state))     as read_req_per_sec
                  , round(sum(delta_write_io_requests) / &sample_freq / count(session_state))     as write_req_per_sec
                  , round(sum(delta_read_io_bytes) / &sample_freq / count(session_state))         as read_bytes_per_sec
                  , round(sum(delta_write_io_bytes) / &sample_freq / count(session_state))        as write_bytes_per_sec
                  , round(sum(delta_interconnect_io_bytes) / &sample_freq / count(session_state)) as tot_io_bytes_per_sec
                  , round(avg(delta_read_request_size))                                           as avg_read_req_size
                  , round(median(delta_read_request_size))                                        as med_read_req_size
                  , round(avg(delta_write_request_size))                                          as avg_write_req_size
                  , round(median(delta_write_request_size))                                       as med_write_req_size
                  , instance_id
                  , total_cnt
            from
                    ash_base
            group by
                    process
                  , instance_id
                  , total_cnt
          )
),
/* We need some log based data for formatting the figures */
ash_process_prefmt as
(
  select
          instance_id
        , process
        , pga_mem
        , trunc(log(10, abs(case pga_mem when 0 then 1 else pga_mem end)))                                    as power_10_pga_mem
        , trunc(mod(log(10, abs(case pga_mem when 0 then 1 else pga_mem end)) ,3))                            as power_10_pga_mem_mod_3
        , temp_space
        , trunc(log(10, abs(case temp_space when 0 then 1 else temp_space end)))                              as power_10_temp_space
        , trunc(mod(log(10, abs(case temp_space when 0 then 1 else temp_space end)), 3))                      as power_10_temp_space_mod_3
        , read_req
        , trunc(log(10, abs(case read_req when 0 then 1 else read_req end)))                                  as power_10_read_req
        , trunc(mod(log(10, abs(case read_req when 0 then 1 else read_req end)), 3))                          as power_10_read_req_mod_3
        , write_req
        , trunc(log(10, abs(case write_req when 0 then 1 else write_req end)))                                as power_10_write_req
        , trunc(mod(log(10, abs(case write_req when 0 then 1 else write_req end)), 3))                        as power_10_write_req_mod_3
        , avg_read_req_size
        , trunc(log(10, abs(case avg_read_req_size when 0 then 1 else avg_read_req_size end)))                as power_10_avg_read_req_size
        , trunc(mod(log(10, abs(case avg_read_req_size when 0 then 1 else avg_read_req_size end)), 3))        as power_10_avg_read_req_size_3
        , med_read_req_size
        , trunc(log(10, abs(case med_read_req_size when 0 then 1 else med_read_req_size end)))                as power_10_med_read_req_size
        , trunc(mod(log(10, abs(case med_read_req_size when 0 then 1 else med_read_req_size end)), 3))        as power_10_med_read_req_size_3
        , avg_write_req_size
        , trunc(log(10, abs(case avg_write_req_size when 0 then 1 else avg_write_req_size end)))              as power_10_avg_write_req_size
        , trunc(mod(log(10, abs(case avg_write_req_size when 0 then 1 else avg_write_req_size end)), 3))      as power_10_avg_write_req_size_3
        , med_write_req_size
        , trunc(log(10, abs(case med_write_req_size when 0 then 1 else med_write_req_size end)))              as power_10_med_write_req_size
        , trunc(mod(log(10, abs(case med_write_req_size when 0 then 1 else med_write_req_size end)), 3))      as power_10_med_write_req_size_3
        , read_bytes
        , trunc(log(10, abs(case read_bytes when 0 then 1 else read_bytes end)))                              as power_10_read_bytes
        , trunc(mod(log(10, abs(case read_bytes when 0 then 1 else read_bytes end)), 3))                      as power_10_read_bytes_mod_3
        , write_bytes
        , trunc(log(10, abs(case write_bytes when 0 then 1 else write_bytes end)))                            as power_10_write_bytes
        , trunc(mod(log(10, abs(case write_bytes when 0 then 1 else write_bytes end)), 3))                    as power_10_write_bytes_mod_3
        , total_io_bytes
        , trunc(log(10, abs(case total_io_bytes when 0 then 1 else total_io_bytes end)))                      as power_10_total_io_bytes
        , trunc(mod(log(10, abs(case total_io_bytes when 0 then 1 else total_io_bytes end)), 3))              as power_10_total_io_bytes_mod_3
        , read_req_per_sec
        , trunc(log(10, abs(case read_req_per_sec when 0 then 1 else read_req_per_sec end)))                  as power_10_read_req_per_sec
        , trunc(mod(log(10, abs(case read_req_per_sec when 0 then 1 else read_req_per_sec end)), 3))          as power_10_read_req_ps_mod_3
        , write_req_per_sec
        , trunc(log(10, abs(case write_req_per_sec when 0 then 1 else write_req_per_sec end)))                as power_10_write_req_per_sec
        , trunc(mod(log(10, abs(case write_req_per_sec when 0 then 1 else write_req_per_sec end)), 3))        as power_10_write_req_ps_mod_3
        , read_bytes_per_sec
        , trunc(log(10, abs(case read_bytes_per_sec when 0 then 1 else read_bytes_per_sec end)))              as power_10_read_bytes_per_sec
        , trunc(mod(log(10, abs(case read_bytes_per_sec when 0 then 1 else read_bytes_per_sec end)), 3))      as power_10_read_bytes_ps_mod_3
        , write_bytes_per_sec
        , trunc(log(10, abs(case write_bytes_per_sec when 0 then 1 else write_bytes_per_sec end)))            as power_10_write_bytes_per_sec
        , trunc(mod(log(10, abs(case write_bytes_per_sec when 0 then 1 else write_bytes_per_sec end)), 3))    as power_10_write_bytes_ps_mod_3
        , tot_io_bytes_per_sec
        , trunc(log(10, abs(case tot_io_bytes_per_sec when 0 then 1 else tot_io_bytes_per_sec end)))          as power_10_tot_io_bytes_per_sec
        , trunc(mod(log(10, abs(case tot_io_bytes_per_sec when 0 then 1 else tot_io_bytes_per_sec end)), 3))  as power_10_tot_io_bytes_ps_mod_3
        , cnt
        , cnt_cpu
        , cnt_other
        , total_cnt
        , round(cnt_cpu / cnt * 100)                                                                          as percentage_cpu
  from
          ash_process
),
/* Format the figures */
ash_process_fmt as
(
  select
          instance_id
        , process
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
        , to_char(round(read_req / power(10, power_10_read_req - case when power_10_read_req > 0 and power_10_read_req_mod_3 = 0 then 3 else power_10_read_req_mod_3 end)), 'FM99999') ||
          case power_10_read_req - case when power_10_read_req > 0 and power_10_read_req_mod_3 = 0 then 3 else power_10_read_req_mod_3 end
          when 0            then ' '
          when 1            then ' '
          when 3*1          then 'K'
          when 3*2          then 'M'
          when 3*3          then 'G'
          when 3*4          then 'T'
          when 3*5          then 'P'
          when 3*6          then 'E'
          else case
               when read_req is null
               then null
               else '*10^'||to_char(power_10_read_req - case when power_10_read_req > 0 and power_10_read_req_mod_3 = 0 then 3 else power_10_read_req_mod_3 end)
               end
          end      as read_req
        , to_char(round(avg_read_req_size / power(10, power_10_avg_read_req_size - case when power_10_avg_read_req_size > 0 and power_10_avg_read_req_size_3 = 0 then 3 else power_10_avg_read_req_size_3 end)), 'FM99999') ||
          case power_10_avg_read_req_size - case when power_10_avg_read_req_size > 0 and power_10_avg_read_req_size_3 = 0 then 3 else power_10_avg_read_req_size_3 end
          when 0            then ' '
          when 1            then ' '
          when 3*1          then 'K'
          when 3*2          then 'M'
          when 3*3          then 'G'
          when 3*4          then 'T'
          when 3*5          then 'P'
          when 3*6          then 'E'
          else case
               when avg_read_req_size is null
               then null
               else '*10^'||to_char(power_10_avg_read_req_size - case when power_10_avg_read_req_size > 0 and power_10_avg_read_req_size_3 = 0 then 3 else power_10_avg_read_req_size_3 end)
               end
          end      as avg_read_req_size
        , to_char(round(med_read_req_size / power(10, power_10_med_read_req_size - case when power_10_med_read_req_size > 0 and power_10_med_read_req_size_3 = 0 then 3 else power_10_med_read_req_size_3 end)), 'FM99999') ||
          case power_10_med_read_req_size - case when power_10_med_read_req_size > 0 and power_10_med_read_req_size_3 = 0 then 3 else power_10_med_read_req_size_3 end
          when 0            then ' '
          when 1            then ' '
          when 3*1          then 'K'
          when 3*2          then 'M'
          when 3*3          then 'G'
          when 3*4          then 'T'
          when 3*5          then 'P'
          when 3*6          then 'E'
          else case
               when med_read_req_size is null
               then null
               else '*10^'||to_char(power_10_med_read_req_size - case when power_10_med_read_req_size > 0 and power_10_med_read_req_size_3 = 0 then 3 else power_10_med_read_req_size_3 end)
               end
          end      as med_read_req_size
        , to_char(round(avg_write_req_size / power(10, power_10_avg_write_req_size - case when power_10_avg_write_req_size > 0 and power_10_avg_write_req_size_3 = 0 then 3 else power_10_avg_write_req_size_3 end)), 'FM99999') ||
          case power_10_avg_write_req_size - case when power_10_avg_write_req_size > 0 and power_10_avg_write_req_size_3 = 0 then 3 else power_10_avg_write_req_size_3 end
          when 0            then ' '
          when 1            then ' '
          when 3*1          then 'K'
          when 3*2          then 'M'
          when 3*3          then 'G'
          when 3*4          then 'T'
          when 3*5          then 'P'
          when 3*6          then 'E'
          else case
               when avg_write_req_size is null
               then null
               else '*10^'||to_char(power_10_avg_write_req_size - case when power_10_avg_write_req_size > 0 and power_10_avg_write_req_size_3 = 0 then 3 else power_10_avg_write_req_size_3 end)
               end
          end      as avg_write_req_size
        , to_char(round(med_write_req_size / power(10, power_10_med_write_req_size - case when power_10_med_write_req_size > 0 and power_10_med_write_req_size_3 = 0 then 3 else power_10_med_write_req_size_3 end)), 'FM99999') ||
          case power_10_med_write_req_size - case when power_10_med_write_req_size > 0 and power_10_med_write_req_size_3 = 0 then 3 else power_10_med_write_req_size_3 end
          when 0            then ' '
          when 1            then ' '
          when 3*1          then 'K'
          when 3*2          then 'M'
          when 3*3          then 'G'
          when 3*4          then 'T'
          when 3*5          then 'P'
          when 3*6          then 'E'
          else case
               when med_write_req_size is null
               then null
               else '*10^'||to_char(power_10_med_write_req_size - case when power_10_med_write_req_size > 0 and power_10_med_write_req_size_3 = 0 then 3 else power_10_med_write_req_size_3 end)
               end
          end      as med_write_req_size
        , to_char(round(write_req / power(10, power_10_write_req - case when power_10_write_req > 0 and power_10_write_req_mod_3 = 0 then 3 else power_10_write_req_mod_3 end)), 'FM99999') ||
          case power_10_write_req - case when power_10_write_req > 0 and power_10_write_req_mod_3 = 0 then 3 else power_10_write_req_mod_3 end
          when 0            then ' '
          when 1            then ' '
          when 3*1          then 'K'
          when 3*2          then 'M'
          when 3*3          then 'G'
          when 3*4          then 'T'
          when 3*5          then 'P'
          when 3*6          then 'E'
          else case
               when write_req is null
               then null
               else '*10^'||to_char(power_10_write_req - case when power_10_write_req > 0 and power_10_write_req_mod_3 = 0 then 3 else power_10_write_req_mod_3 end)
               end
          end      as write_req
        , to_char(round(read_bytes / power(10, power_10_read_bytes - case when power_10_read_bytes > 0 and power_10_read_bytes_mod_3 = 0 then 3 else power_10_read_bytes_mod_3 end)), 'FM99999') ||
          case power_10_read_bytes - case when power_10_read_bytes > 0 and power_10_read_bytes_mod_3 = 0 then 3 else power_10_read_bytes_mod_3 end
          when 0            then ' '
          when 1            then ' '
          when 3*1          then 'K'
          when 3*2          then 'M'
          when 3*3          then 'G'
          when 3*4          then 'T'
          when 3*5          then 'P'
          when 3*6          then 'E'
          else case
               when read_bytes is null
               then null
               else '*10^'||to_char(power_10_read_bytes - case when power_10_read_bytes > 0 and power_10_read_bytes_mod_3 = 0 then 3 else power_10_read_bytes_mod_3 end)
               end
          end      as read_bytes
        , to_char(round(write_bytes / power(10, power_10_write_bytes - case when power_10_write_bytes > 0 and power_10_write_bytes_mod_3 = 0 then 3 else power_10_write_bytes_mod_3 end)), 'FM99999') ||
          case power_10_write_bytes - case when power_10_write_bytes > 0 and power_10_write_bytes_mod_3 = 0 then 3 else power_10_write_bytes_mod_3 end
          when 0            then ' '
          when 1            then ' '
          when 3*1          then 'K'
          when 3*2          then 'M'
          when 3*3          then 'G'
          when 3*4          then 'T'
          when 3*5          then 'P'
          when 3*6          then 'E'
          else case
               when write_bytes is null
               then null
               else '*10^'||to_char(power_10_write_bytes - case when power_10_write_bytes > 0 and power_10_write_bytes_mod_3 = 0 then 3 else power_10_write_bytes_mod_3 end)
               end
          end      as write_bytes
        , to_char(round(total_io_bytes / power(10, power_10_total_io_bytes - case when power_10_total_io_bytes > 0 and power_10_total_io_bytes_mod_3 = 0 then 3 else power_10_total_io_bytes_mod_3 end)), 'FM99999') ||
          case power_10_total_io_bytes - case when power_10_total_io_bytes > 0 and power_10_total_io_bytes_mod_3 = 0 then 3 else power_10_total_io_bytes_mod_3 end
          when 0            then ' '
          when 1            then ' '
          when 3*1          then 'K'
          when 3*2          then 'M'
          when 3*3          then 'G'
          when 3*4          then 'T'
          when 3*5          then 'P'
          when 3*6          then 'E'
          else case
               when total_io_bytes is null
               then null
               else '*10^'||to_char(power_10_total_io_bytes - case when power_10_total_io_bytes > 0 and power_10_total_io_bytes_mod_3 = 0 then 3 else power_10_total_io_bytes_mod_3 end)
               end
          end      as total_io_bytes
        , to_char(round(read_req_per_sec / power(10, power_10_read_req_per_sec - case when power_10_read_req_per_sec > 0 and power_10_read_req_ps_mod_3 = 0 then 3 else power_10_read_req_ps_mod_3 end)), 'FM99999') ||
          case power_10_read_req_per_sec - case when power_10_read_req_per_sec > 0 and power_10_read_req_ps_mod_3 = 0 then 3 else power_10_read_req_ps_mod_3 end
          when 0            then ' '
          when 1            then ' '
          when 3*1          then 'K'
          when 3*2          then 'M'
          when 3*3          then 'G'
          when 3*4          then 'T'
          when 3*5          then 'P'
          when 3*6          then 'E'
          else case
               when read_req_per_sec is null
               then null
               else '*10^'||to_char(power_10_read_req_per_sec - case when power_10_read_req_per_sec > 0 and power_10_read_req_ps_mod_3 = 0 then 3 else power_10_read_req_ps_mod_3 end)
               end
          end      as read_req_per_sec
        , to_char(round(write_req_per_sec / power(10, power_10_write_req_per_sec - case when power_10_write_req_per_sec > 0 and power_10_write_req_ps_mod_3 = 0 then 3 else power_10_write_req_ps_mod_3 end)), 'FM99999') ||
          case power_10_write_req_per_sec - case when power_10_write_req_per_sec > 0 and power_10_write_req_ps_mod_3 = 0 then 3 else power_10_write_req_ps_mod_3 end
          when 0            then ' '
          when 1            then ' '
          when 3*1          then 'K'
          when 3*2          then 'M'
          when 3*3          then 'G'
          when 3*4          then 'T'
          when 3*5          then 'P'
          when 3*6          then 'E'
          else case
               when write_req_per_sec is null
               then null
               else '*10^'||to_char(power_10_write_req_per_sec - case when power_10_write_req_per_sec > 0 and power_10_write_req_ps_mod_3 = 0 then 3 else power_10_write_req_ps_mod_3 end)
               end
          end      as write_req_per_sec
        , to_char(round(read_bytes_per_sec / power(10, power_10_read_bytes_per_sec - case when power_10_read_bytes_per_sec > 0 and power_10_read_bytes_ps_mod_3 = 0 then 3 else power_10_read_bytes_ps_mod_3 end)), 'FM99999') ||
          case power_10_read_bytes_per_sec - case when power_10_read_bytes_per_sec > 0 and power_10_read_bytes_ps_mod_3 = 0 then 3 else power_10_read_bytes_ps_mod_3 end
          when 0            then ' '
          when 1            then ' '
          when 3*1          then 'K'
          when 3*2          then 'M'
          when 3*3          then 'G'
          when 3*4          then 'T'
          when 3*5          then 'P'
          when 3*6          then 'E'
          else case
               when read_bytes_per_sec is null
               then null
               else '*10^'||to_char(power_10_read_bytes_per_sec - case when power_10_read_bytes_per_sec > 0 and power_10_read_bytes_ps_mod_3 = 0 then 3 else power_10_read_bytes_ps_mod_3 end)
               end
          end      as read_bytes_per_sec
        , to_char(round(write_bytes_per_sec / power(10, power_10_write_bytes_per_sec - case when power_10_write_bytes_per_sec > 0 and power_10_write_bytes_ps_mod_3 = 0 then 3 else power_10_write_bytes_ps_mod_3 end)), 'FM99999') ||
          case power_10_write_bytes_per_sec - case when power_10_write_bytes_per_sec > 0 and power_10_write_bytes_ps_mod_3 = 0 then 3 else power_10_write_bytes_ps_mod_3 end
          when 0            then ' '
          when 1            then ' '
          when 3*1          then 'K'
          when 3*2          then 'M'
          when 3*3          then 'G'
          when 3*4          then 'T'
          when 3*5          then 'P'
          when 3*6          then 'E'
          else case
               when write_bytes_per_sec is null
               then null
               else '*10^'||to_char(power_10_write_bytes_per_sec - case when power_10_write_bytes_per_sec > 0 and power_10_write_bytes_ps_mod_3 = 0 then 3 else power_10_write_bytes_ps_mod_3 end)
               end
          end      as write_bytes_per_sec
        , to_char(round(tot_io_bytes_per_sec / power(10, power_10_tot_io_bytes_per_sec - case when power_10_tot_io_bytes_per_sec > 0 and power_10_tot_io_bytes_ps_mod_3 = 0 then 3 else power_10_tot_io_bytes_ps_mod_3 end)), 'FM99999') ||
          case power_10_tot_io_bytes_per_sec - case when power_10_tot_io_bytes_per_sec > 0 and power_10_tot_io_bytes_ps_mod_3 = 0 then 3 else power_10_tot_io_bytes_ps_mod_3 end
          when 0            then ' '
          when 1            then ' '
          when 3*1          then 'K'
          when 3*2          then 'M'
          when 3*3          then 'G'
          when 3*4          then 'T'
          when 3*5          then 'P'
          when 3*6          then 'E'
          else case
               when tot_io_bytes_per_sec is null
               then null
               else '*10^'||to_char(power_10_tot_io_bytes_per_sec - case when power_10_tot_io_bytes_per_sec > 0 and power_10_tot_io_bytes_ps_mod_3 = 0 then 3 else power_10_tot_io_bytes_ps_mod_3 end)
               end
          end      as tot_io_bytes_per_sec
        , cnt
        , cnt_cpu
        , cnt_other
        , percentage_cpu
        , rpad('&gc', nvl(round(cnt / nullif(total_cnt, 0) * &wgs), 0), '&gc') as activity_graph
  from
          ash_process_prefmt
)
/* The final set including the Top N plan lines and Top N activities */
select  /* XPLAN_ASH PARALLEL_SLAVE_ACTIVITY */
        a.instance_id
      , a.process
      , cnt
      , activity_graph
      , cnt_cpu
      , cnt_other
      , percentage_cpu
      , lpad(pga_mem_format, 6)      as pga
      , lpad(temp_space_format, 6)   as temp
      , lpad(read_req, 6)            as rd_req
      , lpad(write_req, 6)           as wr_req
      , lpad(read_req_per_sec, 6)    as rd_r_s
      , lpad(write_req_per_sec, 6)   as wr_r_s
      , lpad(read_bytes, 6)          as rd_byt
      , lpad(write_bytes, 6)         as wr_byt
      , lpad(total_io_bytes, 6)      as io_byt
      , lpad(read_bytes_per_sec, 6)  as rd_b_s
      , lpad(write_bytes_per_sec, 6) as wr_b_s
      , lpad(tot_io_bytes_per_sec, 6) as io_b_s
      , lpad(avg_read_req_size, 6)   as a_rr_s
      , lpad(med_read_req_size, 6)   as m_rr_s
      , lpad(avg_write_req_size, 6)  as a_wr_s
      , lpad(med_write_req_size, 6)  as m_wr_s
      , b.plan_lines
      , c.activities
from
        ash_process_fmt a
      , ash_plan_lines_agg b
      , ash_activity_agg c
where
        a.instance_id = b.instance_id (+)
and     a.process = b.process (+)
and     a.instance_id = c.instance_id (+)
and     a.process = c.process (+)
order by
        instance_id
      , process
;

column process clear
column cnt clear
column cnt_cpu clear
column cnt_other clear
column percentage_cpu clear
column pga  clear
column temp clear
column rd_req clear
column wr_req clear
column rd_byt clear
column wr_byt clear
column io_byt clear
column rd_r_s clear
column wr_r_s clear
column rd_b_s clear
column wr_b_s clear
column io_b_s clear
column a_rr_s clear
column m_rr_s clear
column a_wr_s clear
column m_wr_s clear
column plan_lines clear
column activities clear
column instance_id    clear
column activity_graph clear

clear breaks

undefine _SHOW_IO_COLS

set heading on

/* Various activity summaries */

/* The following query will be used multiple times with different parameters and therefore written to a temporary file */

select  /* XPLAN_ASH ACTIVITY_SUMMARY */
        &GROUP_CROSS_INSTANCE as instance_id
&INCLUDE_ACTIVITY      , activity
      , activity_class
      , round(avg(time_waited) / 1000, 1)                                         as avg_tim_wait_ms
      , round(median(time_waited) / 1000, 1)                                      as med_tim_wait_ms
      , count(*)                                                                  as sample_count
      , round(count(*) / total_cnt * 100)                                         as percentage
      , rpad('&gc', nvl(round(count(*) / nullif(total_cnt, 0) * &wgs), 0), '&gc') as activity_graph
from
        (
                    select
                            &inst_id as instance_id
                          , case when session_state = 'WAITING' then nvl(wait_class, '<Wait Class Is Null>') else session_state end as activity_class
                          , case when session_state = 'WAITING' then nvl(event, '<Wait Event Is Null>') else session_state end      as activity
                          , case when session_state = 'WAITING' then nullif(time_waited, 0) else null end                           as time_waited
                          , count(*) over ()                                                                                        as total_cnt
                    from
                            &global_ash ash
                    where
                            sql_id = '&si'
                    and     &ash_pred1 &ash_pred2
                    and     cast(sample_time as date) between to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS') and to_date('&ash_max_sample_time', 'YYYY-MM-DD HH24:MI:SS')
                    and     instr('&op', 'ASH') > 0
                    and     to_number(nvl('&ic', '0')) > &INSTANCE_THRESHOLD
        )
group by
        &GROUP_CROSS_INSTANCE
&INCLUDE_ACTIVITY      , activity
      , activity_class
      , total_cnt
order by
        &GROUP_CROSS_INSTANCE
      , sample_count desc
.

-- If you need to debug, comment the following line
set termout off

save .xplan_ash_temp replace

set termout on

set heading off

column message format a50

select
        chr(10) || chr(10) as message
from
        dual
where
        instr('&op', 'ASH') > 0
---------
union all
---------
select
        'Activity Class Summary' as message
from
        dual
where
        instr('&op', 'ASH') > 0
---------
union all
---------
select
        '-----------------------------------------------'
from
        dual
where
        instr('&op', 'ASH') > 0
;

column message clear

set heading on

column activity_class format a20
column activity_graph format a&wgs
column instance_id noprint
column avg_tim_wait_ms &_SHOW_WAIT_TIMES.print
column med_tim_wait_ms &_SHOW_WAIT_TIMES.print

-- If you need to debug, comment the following line
set termout off

get .xplan_ash_temp

set termout on

define INSTANCE_THRESHOLD = "0"
define GROUP_CROSS_INSTANCE = "1"
define INCLUDE_ACTIVITY = "--"

/

column activity_class clear
column activity_graph clear
column instance_id clear
column avg_tim_wait_ms clear
column med_tim_wait_ms clear

set heading off

column message format a50

select
        chr(10) || chr(10) as message
from
        dual
where
        instr('&op', 'ASH') > 0
and     to_number(nvl('&ic', '0')) > 1
---------
union all
---------
select
        'Activity Class Summary per Instance' as message
from
        dual
where
        instr('&op', 'ASH') > 0
and     to_number(nvl('&ic', '0')) > 1
---------
union all
---------
select
        '-----------------------------------------------'
from
        dual
where
        instr('&op', 'ASH') > 0
and     to_number(nvl('&ic', '0')) > 1
;

column message clear

set heading on

column activity_class format a20
column activity_graph format a&wgs
column avg_tim_wait_ms &_SHOW_WAIT_TIMES.print
column med_tim_wait_ms &_SHOW_WAIT_TIMES.print
break on instance_id

-- If you need to debug, comment the following line
set termout off

get .xplan_ash_temp

set termout on

define INSTANCE_THRESHOLD = "1"
define GROUP_CROSS_INSTANCE = "instance_id"
define INCLUDE_ACTIVITY = "--"

/

column activity_class clear
column activity_graph clear
column avg_tim_wait_ms clear
column med_tim_wait_ms clear

clear breaks

set heading off

column message format a50

select
        chr(10) || chr(10) as message
from
        dual
where
        instr('&op', 'ASH') > 0
---------
union all
---------
select
        'Activity Summary' as message
from
        dual
where
        instr('&op', 'ASH') > 0
---------
union all
---------
select
        '-----------------------------------------------'
from
        dual
where
        instr('&op', 'ASH') > 0
;

column message clear

set heading on

column activity format a50
column activity_class format a20
column activity_graph format a&wgs
column avg_tim_wait_ms &_SHOW_WAIT_TIMES.print
column med_tim_wait_ms &_SHOW_WAIT_TIMES.print
column instance_id noprint

-- If you need to debug, comment the following line
set termout off

get .xplan_ash_temp

set termout on

define INSTANCE_THRESHOLD = "0"
define GROUP_CROSS_INSTANCE = "1"
define INCLUDE_ACTIVITY = ""

/

column activity clear
column activity_class clear
column activity_graph clear
column instance_id clear
column avg_tim_wait_ms clear
column med_tim_wait_ms clear

set heading off

column message format a50

select
        chr(10) || chr(10) as message
from
        dual
where
        instr('&op', 'ASH') > 0
and     to_number(nvl('&ic', '0')) > 1
---------
union all
---------
select
        'Activity Summary per Instance' as message
from
        dual
where
        instr('&op', 'ASH') > 0
and     to_number(nvl('&ic', '0')) > 1
---------
union all
---------
select
        '-----------------------------------------------'
from
        dual
where
        instr('&op', 'ASH') > 0
and     to_number(nvl('&ic', '0')) > 1
;

column message clear

set heading on

column activity format a50
column activity_class format a20
column activity_graph format a&wgs
column avg_tim_wait_ms &_SHOW_WAIT_TIMES.print
column med_tim_wait_ms &_SHOW_WAIT_TIMES.print
break on instance_id

-- If you need to debug, comment the following line
set termout off

get .xplan_ash_temp

set termout on

define INSTANCE_THRESHOLD = "1"
define GROUP_CROSS_INSTANCE = "instance_id"
define INCLUDE_ACTIVITY = ""

/

column activity clear
column activity_class clear
column activity_graph clear
column avg_tim_wait_ms clear
column med_tim_wait_ms clear

clear breaks

undefine INSTANCE_THRESHOLD
undefine GROUP_CROSS_INSTANCE
undefine INCLUDE_ACTIVITY
undefine _SHOW_WAIT_TIMES

set heading off

column message format a50

select
        chr(10) || chr(10) as message
from
        dual
where
        (('&slave_count' is not null and instr('&op', 'DISTRIB') > 0) or instr('&op', 'TIMELINE') > 0)
---------
union all
---------
select
        'Activity Timeline based on ASH' as message
from
        dual
where
        (('&slave_count' is not null and instr('&op', 'DISTRIB') > 0) or instr('&op', 'TIMELINE') > 0)
---------
union all
---------
select
        '-----------------------------------------------'
from
        dual
where
        (('&slave_count' is not null and instr('&op', 'DISTRIB') > 0) or instr('&op', 'TIMELINE') > 0)
;

column message clear

set heading on

/* Activity Timeline */

-- If you need to debug, comment the following line
set termout off

/* Determine if I/O figures should be shown or not */

column show_io_cols new_value _SHOW_IO_COLS noprint

select
        case when '&_EXPERIMENTAL' is null and '&_IF_ORA112_OR_HIGHER' is null then '' else 'no' end as show_io_cols
from
        dual
;

column show_io_cols clear

set termout on

column average_as_graph format a250 heading 'AVERAGE|ACTIVE SESSIONS|GRAPH'
column instance_id &_IF_CROSS_INSTANCE.print

column pga  format a6 &_IF_ORA112_OR_HIGHERP.print
column temp format a6 &_IF_ORA112_OR_HIGHERP.print
column rd_req format a6 heading 'READ|REQS'           &_SHOW_IO_COLS.print
column wr_req format a6 heading 'WRITE|REQS'          &_SHOW_IO_COLS.print
column rd_byt format a6 heading 'READ|BYTES'          &_SHOW_IO_COLS.print
column wr_byt format a6 heading 'WRITE|BYTES'         &_SHOW_IO_COLS.print
column io_byt format a6 heading 'IO|LAYER|BYTES'      &_SHOW_IO_COLS.print
column rd_r_s format a6 heading 'READ|REQ|PERSEC'     &_SHOW_IO_COLS.print
column wr_r_s format a6 heading 'WRITE|REQ|PERSEC'    &_SHOW_IO_COLS.print
column rd_b_s format a6 heading 'READ|BYTES|PERSEC'   &_SHOW_IO_COLS.print
column wr_b_s format a6 heading 'WRITE|BYTES|PERSEC'  &_SHOW_IO_COLS.print
column io_b_s format a6 heading 'IO_LAY|BYTES|PERSEC' &_SHOW_IO_COLS.print
column a_rr_s format a6 heading 'AVG|RE_REQ|SIZE'     &_SHOW_IO_COLS.print
column m_rr_s format a6 heading 'MEDIAN|RE_REQ|SIZE'  &_SHOW_IO_COLS.print
column a_wr_s format a6 heading 'AVG|WR_REQ|SIZE'     &_SHOW_IO_COLS.print
column m_wr_s format a6 heading 'MEDIAN|WR_REQ|SIZE'  &_SHOW_IO_COLS.print
column plan_lines format a40 heading 'TOP|ACTIVE|PLAN LINES' &_IF_ORA11_OR_HIGHERP.print
column activities format a70 heading 'TOP|ACTIVITIES'
column processes  format a60 heading 'TOP|PROCESSES'
column average_as heading 'AVERAGE|ACTIVE|SESSIONS'
break on duration_secs

with /* XPLAN_ASH ACTIVITY_TIMELINE */
/* Base ASH data */
ash_base as
(
  select  /*+ materialize */
          &inst_id                  as instance_id
&_IF_ORA11_OR_HIGHER          , sql_exec_start
&_IF_LOWER_THAN_ORA11         , to_date('&ls', '&dm') as sql_exec_start
&_IF_ORA11_OR_HIGHER          , sql_plan_line_id
&_IF_LOWER_THAN_ORA11         , 0 as sql_plan_line_id
        , cast(sample_time as date) as sample_time
        , session_state
        , case when session_state = 'WAITING' then nvl(event, '<Wait Event Is Null>') else session_state end as activity
        , case when to_number(nvl('&ic', '0')) > 1 then &inst_id || '-' end || regexp_replace(program, '^.*\((P[[:alnum:]][[:digit:]][[:digit:]])\)$', '\1', 1, 1, 'c') as process
&_IF_ORA112_OR_HIGHER         , nullif(pga_allocated, 0) as pga_allocated
&_IF_LOWER_THAN_ORA112        , to_number(null) as pga_allocated
&_IF_ORA112_OR_HIGHER         , nullif(temp_space_allocated, 0) as temp_space_allocated
&_IF_LOWER_THAN_ORA112        , to_number(null) as temp_space_allocated
&_IF_ORA112_OR_HIGHER         , case when cast(sample_time as date) - round(delta_time / 1000000) / 86400 >= sql_exec_start - &sample_freq / 86400 then delta_read_io_requests else null end                                    as delta_read_io_requests
&_IF_LOWER_THAN_ORA112        , to_number(null) as delta_read_io_requests
&_IF_ORA112_OR_HIGHER         , case when cast(sample_time as date) - round(delta_time / 1000000) / 86400 >= sql_exec_start - &sample_freq / 86400 then delta_write_io_requests else null end                                   as delta_write_io_requests
&_IF_LOWER_THAN_ORA112        , to_number(null) as delta_write_io_requests
&_IF_ORA112_OR_HIGHER         , case when cast(sample_time as date) - round(delta_time / 1000000) / 86400 >= sql_exec_start - &sample_freq / 86400 then delta_read_io_bytes else null end                                       as delta_read_io_bytes
&_IF_LOWER_THAN_ORA112        , to_number(null) as delta_read_io_bytes
&_IF_ORA112_OR_HIGHER         , case when cast(sample_time as date) - round(delta_time / 1000000) / 86400 >= sql_exec_start - &sample_freq / 86400 then delta_write_io_bytes else null end                                      as delta_write_io_bytes
&_IF_LOWER_THAN_ORA112        , to_number(null) as delta_write_io_bytes
&_IF_ORA112_OR_HIGHER         , case when cast(sample_time as date) - round(delta_time / 1000000) / 86400 >= sql_exec_start - &sample_freq / 86400 then delta_read_io_bytes / nullif(delta_read_io_requests, 0) else null end   as delta_read_request_size
&_IF_LOWER_THAN_ORA112        , to_number(null) as delta_read_request_size
&_IF_ORA112_OR_HIGHER         , case when cast(sample_time as date) - round(delta_time / 1000000) / 86400 >= sql_exec_start - &sample_freq / 86400 then delta_write_io_bytes / nullif(delta_write_io_requests, 0) else null end as delta_write_request_size
&_IF_LOWER_THAN_ORA112        , to_number(null) as delta_write_request_size
&_IF_ORA112_OR_HIGHER         , case when cast(sample_time as date) - round(delta_time / 1000000) / 86400 >= sql_exec_start - &sample_freq / 86400 then delta_interconnect_io_bytes else null end                               as delta_interconnect_io_bytes
&_IF_LOWER_THAN_ORA112        , to_number(null) as delta_interconnect_io_bytes
  from
          &global_ash ash
  where
          sql_id = '&si'
  and     &ash_pred1 &ash_pred2
  and     cast(sample_time as date) between to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS') and to_date('&ash_max_sample_time', 'YYYY-MM-DD HH24:MI:SS')
  and     (('&slave_count' is not null and instr('&op', 'DISTRIB') > 0) or instr('&op', 'TIMELINE') > 0)
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
          min_sample_time + (rownum - 1) * &sample_freq / 86400 < max_sample_time + 1 / 86400
  connect by
          min_sample_time + (rownum - 1) * &sample_freq / 86400 < max_sample_time + 1 / 86400
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
        , ash.activity
        , ash.process
        , round((t.sample_time - t.sql_exec_start) * 86400) + 1 as duration_secs
        , t.sql_exec_start
        , ash.sql_plan_line_id
        , ash.pga_allocated
        , ash.temp_space_allocated
        , ash.delta_read_io_requests
        , ash.delta_write_io_requests
        , ash.delta_read_io_bytes
        , ash.delta_write_io_bytes
        , ash.delta_read_request_size
        , ash.delta_write_request_size
        , ash.delta_interconnect_io_bytes
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
        , ash.activity
        , ash.process
        , round((t.sample_time  - t.sql_exec_start) * 86400) + &sample_freq as duration_secs
        , t.sql_exec_start
        , ash.sql_plan_line_id
        , ash.pga_allocated
        , ash.temp_space_allocated
        , ash.delta_read_io_requests
        , ash.delta_write_io_requests
        , ash.delta_read_io_bytes
        , ash.delta_write_io_bytes
        , ash.delta_read_request_size
        , ash.delta_write_request_size
        , ash.delta_interconnect_io_bytes
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
/* The most active plan lines */
/* Define the target buckets */
ash_bkts as
(
  select
          instance_id
        , duration_secs
        , ntile(&avg_as_bkts) over (partition by instance_id order by duration_secs) as bkt
  from
          (
            select
                    distinct
                    instance_id
                  , duration_secs
            from
                    ash_data
          )
),
/* Count occurrence per sample_time and execution plan line */
ash_plan_lines as
(
  select
          cnt
        , sql_plan_line_id
        , instance_id
        , duration_secs
  from
          (
            select
                    duration_secs
                  , count(*) as cnt
                  , case when session_state is null then null else nvl(to_char(sql_plan_line_id, 'TM'), '<NULL>') end as sql_plan_line_id
                  , instance_id
            from
                    ash_data
            group by
                    duration_secs
                  , instance_id
                  , case when session_state is null then null else nvl(to_char(sql_plan_line_id, 'TM'), '<NULL>') end
          )
),
/* Group by bucket and execution plan line */
ash_plan_lines_bkts as
(
  select
          sum(a.cnt) as cnt
        , max(a.duration_secs) as duration_secs
        , a.sql_plan_line_id
        , a.instance_id
        , b.bkt
  from
          ash_plan_lines a
        , ash_bkts b
  where
          a.instance_id = b.instance_id
  and     a.duration_secs = b.duration_secs
  group by
          a.sql_plan_line_id
        , a.instance_id
        , b.bkt
),
/* The Top N execution plan lines per bucket */
ash_plan_lines_bkts_rn as
(
  select
          cnt
        , sql_plan_line_id
        , instance_id
        , bkt
        , duration_secs
        , row_number() over (partition by bkt, instance_id order by cnt desc, sql_plan_line_id) as rn
  from
          ash_plan_lines_bkts
),
/* Aggregate per bucket the Top N execution plan lines */
/* This will be joined later to the remaining bucket data */
ash_plan_lines_bkts_agg as
(
  select
          instance_id
        , max(duration_secs) as duration_secs
&_IF_ORA112_OR_HIGHER           , listagg(case when rn > &topnl + 1 then null when rn = &topnl + 1 then '...' else case when sql_plan_line_id is null then null else sql_plan_line_id || '(' || cnt || ')' end end, ',') within group (order by rn) as plan_lines
&_IF_LOWER_THAN_ORA112          , ltrim(extract(xmlagg(xmlelement("V", case when rn > &topnl + 1 then null when rn = &topnl + 1 then ',' || '...' else case when sql_plan_line_id is null then null else ',' || sql_plan_line_id || '(' || cnt || ')' end end) order by rn), '/V/text()'), ',') as plan_lines
  from
          ash_plan_lines_bkts_rn
  group by
          instance_id
        , bkt
),
/* Count occurrence per sample_time and ASH activity */
ash_activity as
(
  select
          cnt
        , activity
        , instance_id
        , duration_secs
  from
          (
            select
                    duration_secs
                  , count(*) as cnt
                  , case when session_state is null then null else activity end as activity
                  , instance_id
            from
                    ash_data
            group by
                    duration_secs
                  , instance_id
                  , case when session_state is null then null else activity end
          )
),
/* Group by bucket and activity */
ash_activity_bkts as
(
  select
          sum(a.cnt) as cnt
        , max(a.duration_secs) as duration_secs
        , a.activity
        , a.instance_id
        , b.bkt
  from
          ash_activity a
        , ash_bkts b
  where
          a.instance_id = b.instance_id
  and     a.duration_secs = b.duration_secs
  group by
          a.activity
        , a.instance_id
        , b.bkt
),
/* The Top N activities per bucket */
ash_activity_bkts_rn as
(
  select
          cnt
        , activity
        , instance_id
        , bkt
        , duration_secs
        , row_number() over (partition by bkt, instance_id order by cnt desc, activity) as rn
  from
          ash_activity_bkts
),
/* Aggregate per bucket the Top N activity */
/* This will be joined later to the remaining bucket data */
ash_activity_bkts_agg as
(
  select
          instance_id
        , max(duration_secs) as duration_secs
&_IF_ORA112_OR_HIGHER           , listagg(case when rn > &topna + 1 then null when rn = &topna + 1 then '...' else case when activity is null then null else activity || '(' || cnt || ')' end end, ',') within group (order by rn) as activities
&_IF_LOWER_THAN_ORA112          , ltrim(extract(xmlagg(xmlelement("V", case when rn > &topna + 1 then null when rn = &topna + 1 then ',' || '...' else case when activity is null then null else ',' || activity || '(' || cnt || ')' end end) order by rn), '/V/text()'), ',') as activities
  from
          ash_activity_bkts_rn
  group by
          instance_id
        , bkt
),
/* Count occurrence per sample_time and ASH process */
ash_process as
(
  select
          cnt
        , process
        , instance_id
        , duration_secs
  from
          (
            select
                    duration_secs
                  , count(*) as cnt
                  , case when session_state is null then null else process end as process
                  , instance_id
            from
                    ash_data
            group by
                    duration_secs
                  , instance_id
                  , case when session_state is null then null else process end
          )
),
/* Group by bucket and process */
ash_process_bkts as
(
  select
          sum(a.cnt) as cnt
        , max(a.duration_secs) as duration_secs
        , a.process
        , a.instance_id
        , b.bkt
  from
          ash_process a
        , ash_bkts b
  where
          a.instance_id = b.instance_id
  and     a.duration_secs = b.duration_secs
  group by
          a.process
        , a.instance_id
        , b.bkt
),
/* The Top N processes per bucket */
ash_process_bkts_rn as
(
  select
          cnt
        , process
        , instance_id
        , bkt
        , duration_secs
        , row_number() over (partition by bkt, instance_id order by cnt desc, process) as rn
  from
          ash_process_bkts
),
/* Aggregate per bucket the Top N processes */
/* This will be joined later to the remaining bucket data */
ash_process_bkts_agg as
(
  select
          instance_id
        , max(duration_secs) as duration_secs
&_IF_ORA112_OR_HIGHER           , listagg(case when rn > &topnp + 1 then null when rn = &topnp + 1 then '...' else case when process is null then null else process || '(' || cnt || ')' end end, ',') within group (order by rn) as processes
&_IF_LOWER_THAN_ORA112          , ltrim(extract(xmlagg(xmlelement("V", case when rn > &topnp + 1 then null when rn = &topnp + 1 then ',' || '...' else case when process is null then null else ',' || process || '(' || cnt || ')' end end) order by rn), '/V/text()'), ',') as processes
  from
          ash_process_bkts_rn
  group by
          instance_id
        , bkt
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
        , read_req
        , write_req
        , read_bytes
        , write_bytes
        , total_io_bytes
        , read_req_per_sec
        , write_req_per_sec
        , read_bytes_per_sec
        , write_bytes_per_sec
        , tot_io_bytes_per_sec
/*
        , avg_read_request_size
        , med_read_request_size
        , avg_write_request_size
        , med_write_request_size
*/
        , ntile(&avg_as_bkts) over (partition by instance_id order by duration_secs) as bkt
  from    (
            select
                    duration_secs
                  , count(session_state)                                          as cnt
                  , count(case when session_state = 'ON CPU' then 1 end)          as cnt_cpu
                  , count(case when session_state != 'ON CPU' then 1 end)         as cnt_other
                  , sum(pga_allocated)                                            as pga_mem
                  , sum(temp_space_allocated)                                     as temp_space_alloc
                  , sum(delta_read_io_requests)                                   as read_req
                  , sum(delta_write_io_requests)                                  as write_req
                  , sum(delta_read_io_bytes)                                      as read_bytes
                  , sum(delta_write_io_bytes)                                     as write_bytes
                  , sum(delta_interconnect_io_bytes)                              as total_io_bytes
                  , sum(delta_read_io_requests) / &sample_freq                    as read_req_per_sec
                  , sum(delta_write_io_requests) / &sample_freq                   as write_req_per_sec
                  , sum(delta_read_io_bytes) / &sample_freq                       as read_bytes_per_sec
                  , sum(delta_write_io_bytes) / &sample_freq                      as write_bytes_per_sec
                  , sum(delta_interconnect_io_bytes) / &sample_freq               as tot_io_bytes_per_sec
/*
                  , avg(delta_read_request_size)                                  as avg_read_req_size
                  , median(delta_read_request_size)                               as med_read_req_size
                  , avg(delta_write_request_size)                                 as avg_write_req_size
                  , median(delta_write_request_size)                              as med_write_req_size
*/
                  , instance_id
            from
                    ash_data
            group by
                    duration_secs
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
        , round(sum(read_req))                                                                                          as read_req
        , round(sum(write_req))                                                                                         as write_req
        , round(sum(read_bytes))                                                                                        as read_bytes
        , round(sum(write_bytes))                                                                                       as write_bytes
        , round(sum(total_io_bytes))                                                                                    as total_io_bytes
        , round(avg(read_req_per_sec))                                                                                  as read_req_per_sec
        , round(avg(write_req_per_sec))                                                                                 as write_req_per_sec
        , round(avg(read_bytes_per_sec))                                                                                as read_bytes_per_sec
        , round(avg(write_bytes_per_sec))                                                                               as write_bytes_per_sec
        , round(avg(tot_io_bytes_per_sec))                                                                              as tot_io_bytes_per_sec
/*
        , round(avg(avg_read_req_size))                                                                                 as avg_read_req_size
        , round(median(avg_read_req_size))                                                                              as med_read_req_size
        , round(avg(avg_write_req_size))                                                                                as avg_write_req_size
        , round(median(avg_write_req_size))                                                                             as med_write_req_size
*/
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
/* Some data can be directly averaged on the buckets for higher precision results */
ash_distrib_per_bkt as
(
  select
          a.instance_id
        , b.bkt
        , max(a.duration_secs)                                          as duration_secs
        , round(avg(delta_read_request_size))                           as avg_read_req_size
        , round(median(delta_read_request_size))                        as med_read_req_size
        , round(avg(delta_write_request_size))                          as avg_write_req_size
        , round(median(delta_write_request_size))                       as med_write_req_size
  from
          ash_data a
        , ash_bkts b
  where
          a.instance_id = b.instance_id
  and     a.duration_secs = b.duration_secs
  group by
          a.instance_id
        , b.bkt
),
/* We need some log based data for formatting the figures */
ash_distrib_bkts_prefmt as
(
  select
          a.instance_id
        , a.duration_secs
        , pga_mem
        , trunc(log(10, abs(case pga_mem when 0 then 1 else pga_mem end)))                                    as power_10_pga_mem
        , trunc(mod(log(10, abs(case pga_mem when 0 then 1 else pga_mem end)) ,3))                            as power_10_pga_mem_mod_3
        , temp_space
        , trunc(log(10, abs(case temp_space when 0 then 1 else temp_space end)))                              as power_10_temp_space
        , trunc(mod(log(10, abs(case temp_space when 0 then 1 else temp_space end)), 3))                      as power_10_temp_space_mod_3
        , read_req
        , trunc(log(10, abs(case read_req when 0 then 1 else read_req end)))                                  as power_10_read_req
        , trunc(mod(log(10, abs(case read_req when 0 then 1 else read_req end)), 3))                          as power_10_read_req_mod_3
        , write_req
        , trunc(log(10, abs(case write_req when 0 then 1 else write_req end)))                                as power_10_write_req
        , trunc(mod(log(10, abs(case write_req when 0 then 1 else write_req end)), 3))                        as power_10_write_req_mod_3
        , avg_read_req_size
        , trunc(log(10, abs(case avg_read_req_size when 0 then 1 else avg_read_req_size end)))                as power_10_avg_read_req_size
        , trunc(mod(log(10, abs(case avg_read_req_size when 0 then 1 else avg_read_req_size end)), 3))        as power_10_avg_read_req_size_3
        , med_read_req_size
        , trunc(log(10, abs(case med_read_req_size when 0 then 1 else med_read_req_size end)))                as power_10_med_read_req_size
        , trunc(mod(log(10, abs(case med_read_req_size when 0 then 1 else med_read_req_size end)), 3))        as power_10_med_read_req_size_3
        , avg_write_req_size
        , trunc(log(10, abs(case avg_write_req_size when 0 then 1 else avg_write_req_size end)))              as power_10_avg_write_req_size
        , trunc(mod(log(10, abs(case avg_write_req_size when 0 then 1 else avg_write_req_size end)), 3))      as power_10_avg_write_req_size_3
        , med_write_req_size
        , trunc(log(10, abs(case med_write_req_size when 0 then 1 else med_write_req_size end)))              as power_10_med_write_req_size
        , trunc(mod(log(10, abs(case med_write_req_size when 0 then 1 else med_write_req_size end)), 3))      as power_10_med_write_req_size_3
        , read_bytes
        , trunc(log(10, abs(case read_bytes when 0 then 1 else read_bytes end)))                              as power_10_read_bytes
        , trunc(mod(log(10, abs(case read_bytes when 0 then 1 else read_bytes end)), 3))                      as power_10_read_bytes_mod_3
        , write_bytes
        , trunc(log(10, abs(case write_bytes when 0 then 1 else write_bytes end)))                            as power_10_write_bytes
        , trunc(mod(log(10, abs(case write_bytes when 0 then 1 else write_bytes end)), 3))                    as power_10_write_bytes_mod_3
        , total_io_bytes
        , trunc(log(10, abs(case total_io_bytes when 0 then 1 else total_io_bytes end)))                      as power_10_total_io_bytes
        , trunc(mod(log(10, abs(case total_io_bytes when 0 then 1 else total_io_bytes end)), 3))              as power_10_total_io_bytes_mod_3
        , read_req_per_sec
        , trunc(log(10, abs(case read_req_per_sec when 0 then 1 else read_req_per_sec end)))                  as power_10_read_req_per_sec
        , trunc(mod(log(10, abs(case read_req_per_sec when 0 then 1 else read_req_per_sec end)), 3))          as power_10_read_req_ps_mod_3
        , write_req_per_sec
        , trunc(log(10, abs(case write_req_per_sec when 0 then 1 else write_req_per_sec end)))                as power_10_write_req_per_sec
        , trunc(mod(log(10, abs(case write_req_per_sec when 0 then 1 else write_req_per_sec end)), 3))        as power_10_write_req_ps_mod_3
        , read_bytes_per_sec
        , trunc(log(10, abs(case read_bytes_per_sec when 0 then 1 else read_bytes_per_sec end)))              as power_10_read_bytes_per_sec
        , trunc(mod(log(10, abs(case read_bytes_per_sec when 0 then 1 else read_bytes_per_sec end)), 3))      as power_10_read_bytes_ps_mod_3
        , write_bytes_per_sec
        , trunc(log(10, abs(case write_bytes_per_sec when 0 then 1 else write_bytes_per_sec end)))            as power_10_write_bytes_per_sec
        , trunc(mod(log(10, abs(case write_bytes_per_sec when 0 then 1 else write_bytes_per_sec end)), 3))    as power_10_write_bytes_ps_mod_3
        , tot_io_bytes_per_sec
        , trunc(log(10, abs(case tot_io_bytes_per_sec when 0 then 1 else tot_io_bytes_per_sec end)))          as power_10_tot_io_bytes_per_sec
        , trunc(mod(log(10, abs(case tot_io_bytes_per_sec when 0 then 1 else tot_io_bytes_per_sec end)), 3))  as power_10_tot_io_bytes_ps_mod_3
        , case when cpu >= &rnd_thr then round(cpu) else cpu end                                              as cpu
        , case when other >= &rnd_thr then round(other) else other end                                        as other
        , case when average_as >= &rnd_thr then round(average_as) else average_as end                         as average_as
        , average_as_graph
  from
          ash_distrib_bkts a
        , ash_distrib_per_bkt b
  where
          a.instance_id = b.instance_id
  and     a.duration_secs = b.duration_secs
),
/* Format the figures */
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
        , to_char(round(read_req / power(10, power_10_read_req - case when power_10_read_req > 0 and power_10_read_req_mod_3 = 0 then 3 else power_10_read_req_mod_3 end)), 'FM99999') ||
          case power_10_read_req - case when power_10_read_req > 0 and power_10_read_req_mod_3 = 0 then 3 else power_10_read_req_mod_3 end
          when 0            then ' '
          when 1            then ' '
          when 3*1          then 'K'
          when 3*2          then 'M'
          when 3*3          then 'G'
          when 3*4          then 'T'
          when 3*5          then 'P'
          when 3*6          then 'E'
          else case
               when read_req is null
               then null
               else '*10^'||to_char(power_10_read_req - case when power_10_read_req > 0 and power_10_read_req_mod_3 = 0 then 3 else power_10_read_req_mod_3 end)
               end
          end      as read_req
        , to_char(round(avg_read_req_size / power(10, power_10_avg_read_req_size - case when power_10_avg_read_req_size > 0 and power_10_avg_read_req_size_3 = 0 then 3 else power_10_avg_read_req_size_3 end)), 'FM99999') ||
          case power_10_avg_read_req_size - case when power_10_avg_read_req_size > 0 and power_10_avg_read_req_size_3 = 0 then 3 else power_10_avg_read_req_size_3 end
          when 0            then ' '
          when 1            then ' '
          when 3*1          then 'K'
          when 3*2          then 'M'
          when 3*3          then 'G'
          when 3*4          then 'T'
          when 3*5          then 'P'
          when 3*6          then 'E'
          else case
               when avg_read_req_size is null
               then null
               else '*10^'||to_char(power_10_avg_read_req_size - case when power_10_avg_read_req_size > 0 and power_10_avg_read_req_size_3 = 0 then 3 else power_10_avg_read_req_size_3 end)
               end
          end      as avg_read_req_size
        , to_char(round(med_read_req_size / power(10, power_10_med_read_req_size - case when power_10_med_read_req_size > 0 and power_10_med_read_req_size_3 = 0 then 3 else power_10_med_read_req_size_3 end)), 'FM99999') ||
          case power_10_med_read_req_size - case when power_10_med_read_req_size > 0 and power_10_med_read_req_size_3 = 0 then 3 else power_10_med_read_req_size_3 end
          when 0            then ' '
          when 1            then ' '
          when 3*1          then 'K'
          when 3*2          then 'M'
          when 3*3          then 'G'
          when 3*4          then 'T'
          when 3*5          then 'P'
          when 3*6          then 'E'
          else case
               when med_read_req_size is null
               then null
               else '*10^'||to_char(power_10_med_read_req_size - case when power_10_med_read_req_size > 0 and power_10_med_read_req_size_3 = 0 then 3 else power_10_med_read_req_size_3 end)
               end
          end      as med_read_req_size
        , to_char(round(avg_write_req_size / power(10, power_10_avg_write_req_size - case when power_10_avg_write_req_size > 0 and power_10_avg_write_req_size_3 = 0 then 3 else power_10_avg_write_req_size_3 end)), 'FM99999') ||
          case power_10_avg_write_req_size - case when power_10_avg_write_req_size > 0 and power_10_avg_write_req_size_3 = 0 then 3 else power_10_avg_write_req_size_3 end
          when 0            then ' '
          when 1            then ' '
          when 3*1          then 'K'
          when 3*2          then 'M'
          when 3*3          then 'G'
          when 3*4          then 'T'
          when 3*5          then 'P'
          when 3*6          then 'E'
          else case
               when avg_write_req_size is null
               then null
               else '*10^'||to_char(power_10_avg_write_req_size - case when power_10_avg_write_req_size > 0 and power_10_avg_write_req_size_3 = 0 then 3 else power_10_avg_write_req_size_3 end)
               end
          end      as avg_write_req_size
        , to_char(round(med_write_req_size / power(10, power_10_med_write_req_size - case when power_10_med_write_req_size > 0 and power_10_med_write_req_size_3 = 0 then 3 else power_10_med_write_req_size_3 end)), 'FM99999') ||
          case power_10_med_write_req_size - case when power_10_med_write_req_size > 0 and power_10_med_write_req_size_3 = 0 then 3 else power_10_med_write_req_size_3 end
          when 0            then ' '
          when 1            then ' '
          when 3*1          then 'K'
          when 3*2          then 'M'
          when 3*3          then 'G'
          when 3*4          then 'T'
          when 3*5          then 'P'
          when 3*6          then 'E'
          else case
               when med_write_req_size is null
               then null
               else '*10^'||to_char(power_10_med_write_req_size - case when power_10_med_write_req_size > 0 and power_10_med_write_req_size_3 = 0 then 3 else power_10_med_write_req_size_3 end)
               end
          end      as med_write_req_size
        , to_char(round(write_req / power(10, power_10_write_req - case when power_10_write_req > 0 and power_10_write_req_mod_3 = 0 then 3 else power_10_write_req_mod_3 end)), 'FM99999') ||
          case power_10_write_req - case when power_10_write_req > 0 and power_10_write_req_mod_3 = 0 then 3 else power_10_write_req_mod_3 end
          when 0            then ' '
          when 1            then ' '
          when 3*1          then 'K'
          when 3*2          then 'M'
          when 3*3          then 'G'
          when 3*4          then 'T'
          when 3*5          then 'P'
          when 3*6          then 'E'
          else case
               when write_req is null
               then null
               else '*10^'||to_char(power_10_write_req - case when power_10_write_req > 0 and power_10_write_req_mod_3 = 0 then 3 else power_10_write_req_mod_3 end)
               end
          end      as write_req
        , to_char(round(read_bytes / power(10, power_10_read_bytes - case when power_10_read_bytes > 0 and power_10_read_bytes_mod_3 = 0 then 3 else power_10_read_bytes_mod_3 end)), 'FM99999') ||
          case power_10_read_bytes - case when power_10_read_bytes > 0 and power_10_read_bytes_mod_3 = 0 then 3 else power_10_read_bytes_mod_3 end
          when 0            then ' '
          when 1            then ' '
          when 3*1          then 'K'
          when 3*2          then 'M'
          when 3*3          then 'G'
          when 3*4          then 'T'
          when 3*5          then 'P'
          when 3*6          then 'E'
          else case
               when read_bytes is null
               then null
               else '*10^'||to_char(power_10_read_bytes - case when power_10_read_bytes > 0 and power_10_read_bytes_mod_3 = 0 then 3 else power_10_read_bytes_mod_3 end)
               end
          end      as read_bytes
        , to_char(round(write_bytes / power(10, power_10_write_bytes - case when power_10_write_bytes > 0 and power_10_write_bytes_mod_3 = 0 then 3 else power_10_write_bytes_mod_3 end)), 'FM99999') ||
          case power_10_write_bytes - case when power_10_write_bytes > 0 and power_10_write_bytes_mod_3 = 0 then 3 else power_10_write_bytes_mod_3 end
          when 0            then ' '
          when 1            then ' '
          when 3*1          then 'K'
          when 3*2          then 'M'
          when 3*3          then 'G'
          when 3*4          then 'T'
          when 3*5          then 'P'
          when 3*6          then 'E'
          else case
               when write_bytes is null
               then null
               else '*10^'||to_char(power_10_write_bytes - case when power_10_write_bytes > 0 and power_10_write_bytes_mod_3 = 0 then 3 else power_10_write_bytes_mod_3 end)
               end
          end      as write_bytes
        , to_char(round(total_io_bytes / power(10, power_10_total_io_bytes - case when power_10_total_io_bytes > 0 and power_10_total_io_bytes_mod_3 = 0 then 3 else power_10_total_io_bytes_mod_3 end)), 'FM99999') ||
          case power_10_total_io_bytes - case when power_10_total_io_bytes > 0 and power_10_total_io_bytes_mod_3 = 0 then 3 else power_10_total_io_bytes_mod_3 end
          when 0            then ' '
          when 1            then ' '
          when 3*1          then 'K'
          when 3*2          then 'M'
          when 3*3          then 'G'
          when 3*4          then 'T'
          when 3*5          then 'P'
          when 3*6          then 'E'
          else case
               when total_io_bytes is null
               then null
               else '*10^'||to_char(power_10_total_io_bytes - case when power_10_total_io_bytes > 0 and power_10_total_io_bytes_mod_3 = 0 then 3 else power_10_total_io_bytes_mod_3 end)
               end
          end      as total_io_bytes
        , to_char(round(read_req_per_sec / power(10, power_10_read_req_per_sec - case when power_10_read_req_per_sec > 0 and power_10_read_req_ps_mod_3 = 0 then 3 else power_10_read_req_ps_mod_3 end)), 'FM99999') ||
          case power_10_read_req_per_sec - case when power_10_read_req_per_sec > 0 and power_10_read_req_ps_mod_3 = 0 then 3 else power_10_read_req_ps_mod_3 end
          when 0            then ' '
          when 1            then ' '
          when 3*1          then 'K'
          when 3*2          then 'M'
          when 3*3          then 'G'
          when 3*4          then 'T'
          when 3*5          then 'P'
          when 3*6          then 'E'
          else case
               when read_req_per_sec is null
               then null
               else '*10^'||to_char(power_10_read_req_per_sec - case when power_10_read_req_per_sec > 0 and power_10_read_req_ps_mod_3 = 0 then 3 else power_10_read_req_ps_mod_3 end)
               end
          end      as read_req_per_sec
        , to_char(round(write_req_per_sec / power(10, power_10_write_req_per_sec - case when power_10_write_req_per_sec > 0 and power_10_write_req_ps_mod_3 = 0 then 3 else power_10_write_req_ps_mod_3 end)), 'FM99999') ||
          case power_10_write_req_per_sec - case when power_10_write_req_per_sec > 0 and power_10_write_req_ps_mod_3 = 0 then 3 else power_10_write_req_ps_mod_3 end
          when 0            then ' '
          when 1            then ' '
          when 3*1          then 'K'
          when 3*2          then 'M'
          when 3*3          then 'G'
          when 3*4          then 'T'
          when 3*5          then 'P'
          when 3*6          then 'E'
          else case
               when write_req_per_sec is null
               then null
               else '*10^'||to_char(power_10_write_req_per_sec - case when power_10_write_req_per_sec > 0 and power_10_write_req_ps_mod_3 = 0 then 3 else power_10_write_req_ps_mod_3 end)
               end
          end      as write_req_per_sec
        , to_char(round(read_bytes_per_sec / power(10, power_10_read_bytes_per_sec - case when power_10_read_bytes_per_sec > 0 and power_10_read_bytes_ps_mod_3 = 0 then 3 else power_10_read_bytes_ps_mod_3 end)), 'FM99999') ||
          case power_10_read_bytes_per_sec - case when power_10_read_bytes_per_sec > 0 and power_10_read_bytes_ps_mod_3 = 0 then 3 else power_10_read_bytes_ps_mod_3 end
          when 0            then ' '
          when 1            then ' '
          when 3*1          then 'K'
          when 3*2          then 'M'
          when 3*3          then 'G'
          when 3*4          then 'T'
          when 3*5          then 'P'
          when 3*6          then 'E'
          else case
               when read_bytes_per_sec is null
               then null
               else '*10^'||to_char(power_10_read_bytes_per_sec - case when power_10_read_bytes_per_sec > 0 and power_10_read_bytes_ps_mod_3 = 0 then 3 else power_10_read_bytes_ps_mod_3 end)
               end
          end      as read_bytes_per_sec
        , to_char(round(write_bytes_per_sec / power(10, power_10_write_bytes_per_sec - case when power_10_write_bytes_per_sec > 0 and power_10_write_bytes_ps_mod_3 = 0 then 3 else power_10_write_bytes_ps_mod_3 end)), 'FM99999') ||
          case power_10_write_bytes_per_sec - case when power_10_write_bytes_per_sec > 0 and power_10_write_bytes_ps_mod_3 = 0 then 3 else power_10_write_bytes_ps_mod_3 end
          when 0            then ' '
          when 1            then ' '
          when 3*1          then 'K'
          when 3*2          then 'M'
          when 3*3          then 'G'
          when 3*4          then 'T'
          when 3*5          then 'P'
          when 3*6          then 'E'
          else case
               when write_bytes_per_sec is null
               then null
               else '*10^'||to_char(power_10_write_bytes_per_sec - case when power_10_write_bytes_per_sec > 0 and power_10_write_bytes_ps_mod_3 = 0 then 3 else power_10_write_bytes_ps_mod_3 end)
               end
          end      as write_bytes_per_sec
        , to_char(round(tot_io_bytes_per_sec / power(10, power_10_tot_io_bytes_per_sec - case when power_10_tot_io_bytes_per_sec > 0 and power_10_tot_io_bytes_ps_mod_3 = 0 then 3 else power_10_tot_io_bytes_ps_mod_3 end)), 'FM99999') ||
          case power_10_tot_io_bytes_per_sec - case when power_10_tot_io_bytes_per_sec > 0 and power_10_tot_io_bytes_ps_mod_3 = 0 then 3 else power_10_tot_io_bytes_ps_mod_3 end
          when 0            then ' '
          when 1            then ' '
          when 3*1          then 'K'
          when 3*2          then 'M'
          when 3*3          then 'G'
          when 3*4          then 'T'
          when 3*5          then 'P'
          when 3*6          then 'E'
          else case
               when tot_io_bytes_per_sec is null
               then null
               else '*10^'||to_char(power_10_tot_io_bytes_per_sec - case when power_10_tot_io_bytes_per_sec > 0 and power_10_tot_io_bytes_ps_mod_3 = 0 then 3 else power_10_tot_io_bytes_ps_mod_3 end)
               end
          end      as tot_io_bytes_per_sec
        , cpu
        , other
        , average_as
        , average_as_graph
  from
          ash_distrib_bkts_prefmt
)
/* The final set including the Top N plan lines and Top N activities */
select  /* XPLAN_ASH ACTIVITY_TIMELINE */
        a.instance_id
      , a.duration_secs
      , lpad(pga_mem_format, 6)      as pga
      , lpad(temp_space_format, 6)   as temp
      , lpad(read_req, 6)            as rd_req
      , lpad(write_req, 6)           as wr_req
      , lpad(read_req_per_sec, 6)    as rd_r_s
      , lpad(write_req_per_sec, 6)   as wr_r_s
      , lpad(read_bytes, 6)          as rd_byt
      , lpad(write_bytes, 6)         as wr_byt
      , lpad(total_io_bytes, 6)      as io_byt
      , lpad(read_bytes_per_sec, 6)  as rd_b_s
      , lpad(write_bytes_per_sec, 6) as wr_b_s
      , lpad(tot_io_bytes_per_sec, 6) as io_b_s
      , lpad(avg_read_req_size, 6)   as a_rr_s
      , lpad(med_read_req_size, 6)   as m_rr_s
      , lpad(avg_write_req_size, 6)  as a_wr_s
      , lpad(med_write_req_size, 6)  as m_wr_s
      , cpu
      , other
      , average_as
      , b.plan_lines
      , c.activities
      , d.processes
      , average_as_graph
from
        ash_distrib_bkts_fmt a
      , ash_plan_lines_bkts_agg b
      , ash_activity_bkts_agg c
      , ash_process_bkts_agg d
where
        a.instance_id = b.instance_id (+)
and     a.duration_secs = b.duration_secs (+)
and     a.instance_id = c.instance_id (+)
and     a.duration_secs = c.duration_secs (+)
and     a.instance_id = d.instance_id (+)
and     a.duration_secs = d.duration_secs (+)
order by
        duration_secs
      , instance_id
;

column pga  clear
column temp clear
column rd_req clear
column wr_req clear
column rd_byt clear
column wr_byt clear
column io_byt clear
column rd_r_s clear
column wr_r_s clear
column rd_b_s clear
column wr_b_s clear
column io_b_s clear
column a_rr_s clear
column m_rr_s clear
column a_wr_s clear
column m_wr_s clear
column plan_lines clear
column activities clear
column processes clear
column average_as clear
column average_as_graph clear
column instance_id      clear

clear breaks

undefine _SHOW_IO_COLS

set heading off

column message format a50

select
        chr(10) || chr(10) as message
from
        dual
where
        (instr('&op', 'ASH') > 0 or instr('&op', 'DISTRIB') > 0 or instr('&op', 'TIMELINE') > 0)
---------
union all
---------
select
        'Activity on execution plan line level' as message
from
        dual
where
        (instr('&op', 'ASH') > 0 or instr('&op', 'DISTRIB') > 0 or instr('&op', 'TIMELINE') > 0)
and     '&_IF_ORA11_OR_HIGHER' is null
---------
union all
---------
select
        'Execution plan details' as message
from
        dual
where
        (instr('&op', 'ASH') > 0 or instr('&op', 'DISTRIB') > 0 or instr('&op', 'TIMELINE') > 0)
and     '&_IF_LOWER_THAN_ORA11' is null
---------
union all
---------
select
        '-----------------------------------------------'
from
        dual
where
        (instr('&op', 'ASH') > 0 or instr('&op', 'DISTRIB') > 0 or instr('&op', 'TIMELINE') > 0)
;

column message clear

set heading on

set pagesize 0 feedback on

/* The following code snippet represents the core ASH based information for the plan line related ASH info */
/* It will be re-used if no execution plan could be found */
/* Therefore it will be saved to a file and re-loaded into the SQL buffer after execution of this statement */

/* Activity details on execution plan line level */

/* No read consistency on V$ views, therefore we materialize here the ASH content required */
with /* XPLAN_ASH ACTIVITY_PLAN_LINE */
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
&_IF_LOWER_THAN_ORA11         , to_date('&ls', '&dm')                                                           as sql_exec_start
  from
          &global_ash ash
  where
          sql_id = '&si'
  and     &ash_pred1 &ash_pred2
  and     cast(sample_time as date) between to_date('&ash_min_sample_time', 'YYYY-MM-DD HH24:MI:SS') and to_date('&ash_max_sample_time', 'YYYY-MM-DD HH24:MI:SS')
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
                                      , case when to_number(nvl('&ic', '0')) > 1 then &inst_id || '-' end || regexp_replace(program, '^.*\((P[[:alnum:]][[:digit:]][[:digit:]])\)$', '\1', 1, 1, 'c') as process
                                      , count(*) over (partition by sql_plan_line_id, &inst_id || '-' || regexp_replace(program, '^.*\((P[[:alnum:]][[:digit:]][[:digit:]])\)$', '\1', 1, 1, 'c'))    as cnt
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
                    round((min(sample_time) - min(sql_exec_start)) * 86400)               as start_active
                  , round(((max(sample_time) - min(sample_time)) * 86400)) + &sample_freq as duration_secs
                  , sql_plan_line_id                                                      as plan_line
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
          &plan_table_name p
  where
          sql_id = '&si'
  and     &second_id = &cn
  and     &third_id
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
                    /* From 11.2.0.2 on this will execute the given cursor on all RAC instances but effectively only on that instance where the plan should reside */
                    /* The GV$ table function is undocumented but used for a similar purpose by 11.2.0.2+ Real-Time SQL Monitoring */
&_IF_ORA11202_OR_HIGHER                   table(gv$(cursor(select * from table(&plan_function('&si',&cn, &par_fil.'&fo')) where USERENV('INSTANCE') = &plan_inst_id))) dc
                    /* Prior to 11.2.0.2 this problem is not solved yet as GV$() is not supported and DBMS_XPLAN.DISPLAY cannot show Rowsource statistics and would require a different parameter set to call */
&_IF_LOWER_THAN_ORA11202                  table(&plan_function('&si',&cn, &par_fil.'&fo')) dc
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
select  /* XPLAN_ASH ACTIVITY_PLAN_LINE */
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
select  /* XPLAN_ASH ACTIVITY_PLAN_LINE */
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

undefine _EXPERIMENTAL
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
undefine topnl
undefine topna
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
undefine _IF_ORA11202_OR_HIGHER
undefine _IF_LOWER_THAN_ORA11202
undefine _IF_ORA112_OR_HIGHERP
undefine _IF_ORA11_OR_HIGHERP
undefine _IF_CROSS_INSTANCE
undefine _SQL_EXEC2
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
undefine curr_third_id
undefine hist_global_ash
undefine hist_inst_id
undefine hist_plan_table
undefine hist_plan_table_stats
undefine hist_second_id
undefine hist_second_id_monitor
undefine hist_sample_freq
undefine hist_plan_function
undefine hist_par_fil
undefine hist_third_id
undefine mixed_global_ash
undefine mixed_inst_id
undefine mixed_plan_table
undefine mixed_plan_table_stats
undefine mixed_second_id
undefine mixed_second_id_monitor
undefine mixed_sample_freq
undefine mixed_plan_function
undefine mixed_par_fil
undefine mixed_third_id
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
undefine ash_pred1
undefine ash_pred2
undefine ash_ln_pred1
undefine ash_ln_pred2
undefine ash_min_sample_time
undefine ash_max_sample_time
undefine ca_sc
undefine plan_inst_id
undefine third_id

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
col ora11202_higher clear
col ora11202_lower  clear
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
col inst_count clear
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