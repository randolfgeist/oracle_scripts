store set .settings replace

-- Create a script to display the report just generated
set echo off heading off feedback off long 10000000 longchunksize 1000000 trimspool on newpage none pagesize 0 termout off verify off tab off timing off linesize 200 define "$"

spool display_performance_report.sql

select
        case
        when '$awr_statspack' in ('AWR', 'STATSPACK')
        then
          case
          when instr('$os', 'WIN_NT') > 0
          then 'host start &rep_name'
          else 'host nohup xdg-open &rep_name'
          end
        else
          'rem Nothing to do'
        end
        as spool_output
from
        dual
;

spool off

@.settings

@display_performance_report.sql

