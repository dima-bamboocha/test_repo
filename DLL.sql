-------- PROJECT-2 DLL --------

-- 1. Создаём таблицу shipping_country_rates (СПРАВОЧНИК СТОИМОСТИ ДОСТАВКИ В СТРАНЫ)

drop table if exists shipping_country_rates;

create table public.shipping_country_rates (
    id SERIAL,
	shipping_country text,
	shipping_country_base_rate numeric(14,3),
	primary key (id)
);
-- данные для shipping_country_rates
-- select distinct shipping_country, shipping_country_base_rate from public.shipping

-- 2. Создаём таблицу shipping_country_rates

drop table if exists shipping_country_rates;

create table public.shipping_country_rates (


