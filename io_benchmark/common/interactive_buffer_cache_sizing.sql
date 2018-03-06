prompt
prompt Overview of current buffer cache sizing:

column component format a24
column current_size_mb format 9g999g999

select inst_id, component, round(current_size / 1024 / 1024) as current_size_mb
from (select rownum as rn, a.* from gv$memory_dynamic_components a)
where component like '%buffer cache'
order by inst_id, rn
;
