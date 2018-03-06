accept tablespace_name prompt 'Enter target tablespace name: '

column object_size new_value object_size noprint
column block_size new_value block_size noprint

select
        to_char(block_size / 1024, 'TM') || ' KB' as block_size
      , to_char(round(block_size * &blocks_req / 1024 / 1024), 'FM9G999G999G999') as object_size
from
        dba_tablespaces
where
        tablespace_name = upper('&tablespace_name');

prompt
prompt The target tablespace "&tablespace_name" uses a block size of &block_size.. This means the objects require approx. &object_size MB in this tablespace.
