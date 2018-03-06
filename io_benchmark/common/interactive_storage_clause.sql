prompt
prompt If you want to specify a storage clause to assign the objects to a non-default buffer cache (RECYCLE or KEEP) please specify here otherwise leave blank
prompt

accept storage_clause prompt 'Enter either KEEP or RECYCLE or leave blank: '

column storage_clause new_value storage_clause noprint

select nvl2('&storage_clause', 'storage (buffer_pool &storage_clause)', '') as storage_clause from dual;
