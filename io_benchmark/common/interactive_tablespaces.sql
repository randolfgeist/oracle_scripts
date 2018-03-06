prompt
prompt Overview of current tablespaces:

column tablespace_name format a30
column block_size format a5
column free_mb format 9g999g999
column free_blocks format 9g999g999g999
column current_size_mb format 9g999g999
column current_size_blocks format 9g999g999g999
column max_size_mb format 9g999g999
column max_size_blocks format 9g999g999g999

with free_space as
(
select
        tablespace_name
      , round(sum(bytes) / 1024 / 1024) as free_mb
      , sum(bytes) as free
from
        dba_free_space
group by
        tablespace_name
),
tbs_info as
(
select
        tablespace_name
      , block_size
      , to_char(block_size / 1024, 'TM') || ' KB' as block_size_formatted
from
        dba_tablespaces
where
        contents = 'PERMANENT'
),
df_info as
(
select
        tablespace_name
      , round(sum(bytes) / 1024 / 1024) as current_size_mb
      , sum(bytes) as current_size
      , round(sum(case when maxbytes = 0 then bytes else maxbytes end) / 1024 / 1024) as max_size_mb
      , sum(case when maxbytes = 0 then bytes else maxbytes end) as max_size
from
        dba_data_files
group by
        tablespace_name
)
select
        t.tablespace_name
      , t.block_size_formatted as block_size
      , f.free_mb
      , round(f.free / t.block_size) as free_blocks
      , d.current_size_mb
      , round(d.current_size / t.block_size) as current_size_blocks
      , d.max_size_mb
      , round(d.max_size / t.block_size) as max_size_blocks
from
        tbs_info t
      , free_space f
      , df_info d
where
        t.tablespace_name = f.tablespace_name
and     t.tablespace_name = d.tablespace_name
order by
        t.tablespace_name
;
