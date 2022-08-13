---------------- PROJECT-2 DLL ----------------

-- 1. СОЗДАЁМ таблицу shipping_country_rates (СПРАВОЧНИК СТОИМОСТИ ДОСТАВКИ В СТРАНЫ)
drop table if exists public.shipping_country_rates;

create table public.shipping_country_rates (
    id SERIAL,
	shipping_country text,                     -- страна доставки
	shipping_country_base_rate numeric(14,3),  -- стоимость доставки (% от payment_amount)
	primary key (id)
);
------ DATA FOR TABLE ------
insert into public.shipping_country_rates (shipping_country, shipping_country_base_rate)
select distinct shipping_country, shipping_country_base_rate 
from public.shipping;

-- 2. СОЗДАЁМ таблицу shipping_agreement (СПРАВОЧНИК СТОИМОСТИ ДОСТАВКИ ВЕНДОРА ПО ДОГОВОРУ) 
drop table if exists public.shipping_agreement;

create table public.shipping_agreement (
	agreementid int,                         -- id договора
    agreement_number text,                   -- номер договора
    agreement_rate numeric(14,3),            -- ставка налога за стоимость доставки товара для вендора
    agreement_commission numeric(14,3),      -- комиссия, то есть доля в платеже являющаяся доходом компании от сделки
    primary key (agreementid)
);
------ DATA FOR TABLE ------
insert into public.shipping_agreement (agreementid, agreement_number, agreement_rate, agreement_commission)
select distinct
       (regexp_split_to_array(vendor_agreement_description, ':'))[1] :: integer as agreementid,
       (regexp_split_to_array(vendor_agreement_description, ':'))[2]            as agreement_number,
       (regexp_split_to_array(vendor_agreement_description, ':'))[3] :: numeric as agreement_rate,
       (regexp_split_to_array(vendor_agreement_description, ':'))[4] :: numeric as agreement_commission
from public.shipping;

-- 3. СОЗДАЁМ таблицу shipping_transfer (СПРАВОЧНИК О ТИПАХ ДОСТАВКИ)
drop table if exists public.shipping_transfer;

create table public.shipping_transfer (
    id SERIAL,         
	transfer_type text,                   -- тип доставки
    transfer_model text,                  -- модель доставки
    shipping_transfer_rate numeric(14,3), -- стоимость доставки для вендора (% от payment_amount)
    primary key (id)
);
------ DATA FOR TABLE ------
insert into public.shipping_transfer (transfer_type, transfer_model, shipping_transfer_rate)
select distinct
       (regexp_split_to_array(shipping_transfer_description, ':'))[1] as transfer_type,
       (regexp_split_to_array(shipping_transfer_description, ':'))[2] as transfer_model,
       shipping_transfer_rate
from shipping;

-- 4. СОЗДАЁМ таблицу shipping_info (ТАБЛИЦА С УНИКАЛЬНЫМИ ДОСТАВКАМИ)
drop table if exists shipping_info;

create table public.shipping_info (
	shippingid int,
    vendorid bigint,
    payment_amount numeric(14,2),
    shipping_plan_datetime timestamp,
    transfer_type_id int,    
    shipping_country_id int, 
    agreementid int,          
    primary key (shippingid),
    foreign key (transfer_type_id) references public.shipping_transfer (id),
    foreign key (shipping_country_id) references public.shipping_country_rates (id),
	foreign key (agreementid) references public.shipping_agreement (agreementid)
);
------ DATA FOR TABLE ------
insert into public.shipping_info -- без указания полей тоже можно, но выше вероятность ошибки
select distinct
       shippingid,
       vendorid,
       payment_amount,
       shipping_plan_datetime,
       t3.id as transfer_type_id,
       t2.id as shipping_country_id,
       (regexp_split_to_array(vendor_agreement_description, ':'))[1] :: integer as agreementid
from shipping as t1
left join public.shipping_country_rates as t2 using (shipping_country)
left join public.shipping_transfer as t3 on t1.shipping_transfer_description = concat_ws(':', t3.transfer_type, t3.transfer_model);

-- 5. СОЗДАЁМ таблицу shipping_status (ТАБЛИЦА СО СТАТУСАМИ ДОСТАВОК)
drop table if exists public.shipping_status;

create table public.shipping_status (
	shippingid int,
	status text, -- максимальный статус доставки
	state text,  -- максимальное состояние доставки
	shipping_start_fact_datetime timestamp, --время, когда заказа перешёл в сосояние "boocked"
	shipping_end_fact_datetime timestamp,   --время, когда заказа перешёл в сосояние "received" PS - это не время последнего статуса
	primary key (shippingid)
);

------ DATA FOR TABLE ------
insert into public.shipping_status (shippingid, status, state, shipping_start_fact_datetime, shipping_end_fact_datetime)
with max_status as ( -- определим максимальный статус доставки
	select distinct on (shippingid) shippingid, -- воспользуемся конструкцией DISTINCT ON + ORDER BY
	       status,
	       state
	from shipping
	order by 1, state_datetime desc
)
select *
from max_status as ms
left join ( --добавим поля со временем статуса "boocked" и "received"
		select shippingid,
		       MAX(case when state = 'booked' then state_datetime end) as shipping_start_fact_datetime, --время, когда заказа перешёл в сосояние "boocked"
		       MAX(case when state = 'recieved' then state_datetime end) as shipping_end_fact_datetime  --время, когда заказа перешёл в сосояние "received"
		from shipping
		group by 1 ) as t2 using (shippingid);

-- 6. СОЗДАЁМ представление для аналитики shipping_datamart

drop view if exists public.shipping_datamart;

create view public.shipping_datamart  as (

select   t1.shippingid, 
         t1.vendorid, 
         st.transfer_type,
         date_part('day', ss.shipping_end_fact_datetime - ss.shipping_start_fact_datetime) as full_day_at_shipping,
         case when shipping_plan_datetime < ss.shipping_end_fact_datetime then 1 else 0 end as is_delay,
         case when ss.status = 'finished' then 1 else 0 end as is_shipping_finish,
         case when shipping_plan_datetime < ss.shipping_end_fact_datetime 
              then date_part('day', ss.shipping_end_fact_datetime - shipping_plan_datetime) else 0 end as delay_day_at_shipping,
         t1.payment_amount,
         t1.payment_amount * (st.shipping_transfer_rate + sa.agreement_rate + scr.shipping_country_base_rate) as vat,
         t1.payment_amount * sa.agreement_commission as profit
from shipping_info as t1
left join shipping_transfer as st on t1.transfer_type_id = st.id 
left join shipping_status ss using (shippingid)
left join shipping_agreement sa using (agreementid)
left join shipping_country_rates scr on t1.shipping_country_id = scr.id

);





