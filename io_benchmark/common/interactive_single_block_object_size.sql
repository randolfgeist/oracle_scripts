prompt
prompt Enter number of blocks per process table and index - this means two times this number of blocks per process
prompt

accept num_rows default '8000' prompt 'Number of blocks per process table and index (default 8.000): '

column blocks_req_fm new_value blocks_req_fm noprint
column blocks_req new_value blocks_req noprint

select to_char(&num_rows * &num_slaves * 2, 'FM999G999G999') as blocks_req_fm, &num_rows * &num_slaves * 2 as blocks_req from dual;

prompt With &num_slaves processes and &num_rows blocks per table and index this means you'll need approx. &blocks_req_fm blocks in the target tablespace.
prompt

