-- check for duplicates
count(*)
from stg_pan_numbers_dataset
group by pan_number
having count(*) > 1
order by count(*) desc


--Handle leading/trailing spaces
select * from stg_pan_numbers_dataset
where pan_number <> trim(pan_number)

--Correct letter case
select * from stg_pan_numbers_dataset where pan_number <> upper(pan_number)


--Cleaned Pan numbers
select distinct upper(trim(pan_number)) as pan_number
from stg_pan_numbers_dataset
where pan_number is not null
and trim(pan_number) <> ''

-- function to check if adjacent charcter are the same
-- WUFAR0132H ==> WUFAR

create or replace function fn_check_adjacent_charcters(p_str text)
returns boolean
language plpgsql
as $$
begin
	for i in 1 .. (length(p_str) - 1)
	loop --substring(string,start,length)
		if substring(p_str, i, 1) = substring(p_str, i+1, 1)
		then
			return true; -- characters are adjacent
		end if;
	end loop;
	return false; -- non of the character adjacent to each other were the same 
end;
$$
-- Function to check if sequencial character are used
create or replace function fn_check_sequencial_charcters(p_str text)
returns boolean
language plpgsql
as $$
begin
	for i in 1 .. (length(p_str) - 1)
	loop --substring(string,start,length)
		if ascii(substring(p_str,i+1,1)) - ascii(substring(p_str,i,1)) <> 1
		then
			return false; -- the string does not form the sequence
		end if;
	end loop;
	return true; -- the strings is forming a sequence 
end;
$$
select ascii('A')
select fn_check_sequencial_charcters ('AXCDE')


-- Regular expression to vaildate the pattern or structure of PAN number
--AAAAA1234A
select *
from  stg_pan_numbers_dataset
where pan_number  ~ '^[A-Z]{5}[0-9]{4}[A-Z]$'




--vaild and Invalid PAN categorization 

create or replace view vw_vaild_invaild_pans
as
with cte_cleaned_pan as (
		select distinct upper(trim(pan_number)) as pan_number
		from stg_pan_numbers_dataset
		where pan_number is not null
		and trim(pan_number) <> ''),
	cte_vaild_pans as(
		select *
		from cte_cleaned_pan
		where fn_check_adjacent_charcters(pan_number) = false
		and fn_check_sequencial_charcters(substring(pan_number, 1,5)) = false 
		and fn_check_sequencial_charcters(substring(pan_number, 6,4)) = false
		and pan_number  ~ '^[A-Z]{5}[0-9]{4}[A-Z]$')
select cln.pan_number,
case 
when vld.pan_number is not null 
then 'Vaild PAN' else 'Invalid PAN' end as status
from cte_cleaned_pan cln
left join cte_vaild_pans vld
on vld.pan_number = cln.pan_number

SELECT * FROM vw_vaild_invaild_pans



--Summary reports
stg_pan_numbers_dataset
vw_vaild_invaild_pans

with cte as(
select 
(select count(*) from stg_pan_numbers_dataset) as total_process_records,
count(*) filter (where status = 'Vaild PAN') as total_valid_pans,
count(*) filter (where status = 'Invalid PAN') as total_invalid_pans

from vw_vaild_invaild_pans)
select
total_process_records,
total_valid_pans,
total_invalid_pans,
total_process_records -(total_valid_pans + total_invalid_pans) as total_missing_pans
from cte

