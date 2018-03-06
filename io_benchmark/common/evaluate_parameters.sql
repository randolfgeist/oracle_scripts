column cnt_ee new_value cnt_ee

select to_char(count(*), 'TM') as cnt_ee from v$version where banner like '%Enterprise Edition%' or banner like '%EE%';

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
column 10 new_value 10
column 11 new_value 11

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
      , '' as "10"
      , '' as "11"
from
        dual
where
        rownum = 0;

-- Evaluate parameters, use defaults if not specified
column iter new_value iter noprint
column testtype new_value testtype noprint
column tab_size new_value tab_size noprint
column tbs new_value tbs noprint
column wait_time new_value wait_time noprint
column connect_string new_value connect_string noprint
column username new_value username noprint
column pwd new_value pwd noprint
column os_name new_value os_name noprint
column px_degree new_value px_degree noprint
column awr_statspack new_value awr_statspack noprint

select
        nvl('&1', '8')  as iter
      , nvl('&2', '&default_testtype') as testtype
      , nvl('&3', '&default_tab_size') as tab_size
      , nvl2('&4', 'tablespace &4', '') as tbs
      , nvl('&5', '600') as wait_time
      , nvl2('&6', '@"&6"', '') as connect_string
      , nvl('&7', lower('&_user')) as username
      , nvl('&8', lower('&_user')) as pwd
      , upper('&9') as os_name
      , nvl('&10', '1') as px_degree
      , nvl(upper('&11'), case when '&cnt_ee' = '1' then 'AWR' else 'STATSPACK' end) as awr_statspack
from
        dual;
