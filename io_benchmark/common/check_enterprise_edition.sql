column cnt_ee new_value cnt_ee

select to_char(count(*), 'TM') as cnt_ee from v$version where banner like '%Enterprise Edition%' or banner like '%EE%';
