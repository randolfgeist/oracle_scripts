-- Generate AWR/STATSPACK report or do nothing
alter session set nls_language = american;

column snap_view new_value snap_view
column dbid_pred new_value dbid_pred

select  case '&awr_statspack'
        when 'AWR'
        then 'dba_hist_snapshot'
        else 'v$database'
        end as snap_view
      , case '&awr_statspack'
        when 'AWR'
        then 'snap_id = :b_snap_id and instance_number = (select instance_number from v$instance)'
        else '1 = 1'
        end as dbid_pred
from
        dual;

define metric_view = gv$sysmetric_history

column snap_view new_value snap_view noprint
column metric_view new_value metric_view noprint

-- This query fails deliberately in versions below 12.2 which is OK but is required in 12.2 to determine if the AWR is taken on PDB level or not
select
        case when is_122_pdb = 'is_122_pdb'
             then 'awr_pdb_snapshot'
             else 'dba_hist_snapshot'
             end as snap_view
      , case when is_122_pdb = 'is_122_pdb'
             then 'gv$con_sysmetric_history'
             else 'gv$sysmetric_history'
             end as metric_view
from (
select
             case when sys_context('userenv','dbid') !=
                  sys_context('userenv','con_dbid') and (select substr( banner, instr(banner, 'Release ') + 8, instr(substr(banner,instr(banner,'Release ') + 8),' ') ) from v$version where rownum <= 1) >= '12.2.0.1'
             then 'is_122_pdb'
             else 'isnot_122_pdb'
             end as is_122_pdb
from dual
);

variable dbid number

begin
  select dbid
  into :dbid
  from &snap_view
  where &dbid_pred
  ;
end;
/

column awr_type new_value awr_type noprint
column group_by_instance new_value group_by_instance noprint
column inst new_value inst noprint
column report_name new_value report_name noprint
column begin_snap new_value begin_snap
column end_snap new_value end_snap
column dbid new_value dbid
column inst_num new_value inst_num

select
        case when cnt > 1 then '_global' else '' end as awr_type
      , case when cnt > 1 then '' else '--' end as group_by_instance
      , case when cnt > 1 then 'cast(null as varchar2(30))' else (select to_char(instance_number, 'TM') from v$instance) end as inst
      , case '&awr_statspack'
        when 'AWR'
        then 'awr_report_&slave_name._&iter._&testtype._&tab_size._&wait_time._' || :b_snap_id || '_' || :e_snap_id || '_' || to_char(sysdate, 'YYYY_MM_DD_HH24_MI_SS') || '.html'
        when 'STATSPACK'
        then 'statspack_report_&slave_name._&iter._&testtype._&tab_size._&wait_time._' || :b_snap_id || '_' || :e_snap_id || '_' || to_char(sysdate, 'YYYY_MM_DD_HH24_MI_SS') || '.txt'
        else 'off'
        end as report_name
      , :b_snap_id as begin_snap
      , :e_snap_id as end_snap
      , :dbid as dbid
      , (select to_char(instance_number, 'TM') from v$instance) as inst_num
from
        (select count(*) as cnt from gv$instance)
;


store set .settings replace

-- Create a script to generate an AWR or STATSPACK report
set echo off heading off feedback off long 10000000 longchunksize 1000000 trimspool on newpage none pagesize 0 termout off verify off tab off timing off linesize 200 define "$" sqlblanklines on

spool generate_performance_report.sql

select
        case '$awr_statspack'
        when 'AWR'
        then 'select * from table(sys.dbms_workload_repository.awr&awr_type._report_html(:dbid, &inst, :b_snap_id, :e_snap_id));'
        when 'STATSPACK'
        then '
s' || 'et echo on termout on

p' || 'rompt Connecting as PERFSTAT...

c' || '' || 'onnect PERFSTAT&connect_string

' || '@' || '?/rdbms/admin/sprepins
'
        else 'rem Nothing to do'
        end as spool_output
from
        dual
;

spool off

@.settings

store set .settings replace

define rep_name = "&report_name"

set echo off termout off heading off feedback off long 10000000 longchunksize 1000000 trimspool on newpage none pagesize 0 verify off tab off timing off linesize 8000

spool &report_name

@generate_performance_report.sql

spool off

@.settings

