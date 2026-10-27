-- =====================================================================
--  Datos de volumen para comprobar el análisis de almacenamiento
--  Sprint 2
--
--  Llena una base con el tamaño que la estimación de volumen le da al
--  sistema al final del primer año (ver README): 680 proveedores,
--  5 440 servicios, 56 000 clientes y 1 584 000 reservas. Con eso se
--  comparan los cálculos de docs/analisis-almacenamiento.md con lo que
--  mide PostgreSQL.
--
--  Es para una base aparte. La guarda aborta si no se llama `volumen`:
--      createdb volumen
--      psql -d volumen -f schema.sql -f docs/generar-volumen.sql
--  Tarda unos minutos.
--
--  Las reservas se cargan con los triggers de usuario apagados: son
--  históricas y masivas, y las reglas de cupo y de coherencia ya las
--  cumplen por construcción. Las FK y los CHECK sí se verifican.
-- =====================================================================

do $$
begin
    if current_database() <> 'volumen' then
        raise exception 'generar-volumen.sql es para la base "volumen", no para "%"', current_database();
    end if;
end $$;

-- Semilla fija: random() da siempre la misma secuencia, así que los
-- conteos y los planes del análisis se pueden reproducir.
select setseed(0.42);

\timing on

insert into cities (name, region) values ('Medellín', 'Antioquia'), ('Envigado', 'Antioquia'), ('Bogotá', 'Bogotá D.C.');
insert into organization_categories (name) values ('Salud'), ('Belleza'), ('Deporte'), ('Bienestar');
insert into currencies (code, name) values ('COP', 'Peso colombiano');

-- 680 proveedores activos
insert into organizations (id, category_id, name, identification_number, contact_email, contact_phone, status, approved_at)
select md5('o' || i)::uuid,
       (select id from organization_categories order by name offset (i % 4) limit 1),
       'Proveedor ' || i,
       '9' || lpad(i::text, 8, '0'),
       'proveedor' || i || '@example.com',
       '604' || lpad(i::text, 7, '0'),
       'ACTIVE', now() - interval '1 year'
from generate_series(1, 680) i;

insert into organization_policies (id, organization_id, version, booking_notice_minutes_min,
                                   booking_notice_minutes_max, free_cancellation_window_minutes, effective_from)
select md5('p' || i)::uuid, md5('o' || i)::uuid, 1, 60, 43200, 1440, now() - interval '2 years'
from generate_series(1, 680) i;

-- 1,5 sedes por proveedor: todos tienen una y los pares tienen dos (1 020)
insert into locations (id, organization_id, name, address, city_id)
select md5('l' || i || '-' || k)::uuid, md5('o' || i)::uuid, 'Sede ' || k, 'Calle ' || i || ' # ' || k,
       (select id from cities order by name offset (i % 3) limit 1)
from generate_series(1, 680) i
    cross join generate_series(1, 2) k
where k = 1 or i % 2 = 0;

-- 8 servicios por proveedor (5 440)
insert into services (id, organization_id, name, duration_minutes, price, currency_id, status)
select md5('s' || i || '-' || k)::uuid, md5('o' || i)::uuid, 'Servicio ' || k,
       30 + 15 * (k % 4), 20000 + 5000 * ((i + k) % 37),
       (select id from currencies), 'ACTIVE'
from generate_series(1, 680) i
    cross join generate_series(1, 8) k;

-- Cada servicio en la primera sede; los pares también en la segunda
insert into service_locations (service_id, location_id)
select md5('s' || i || '-' || k)::uuid, md5('l' || i || '-' || 1)::uuid
from generate_series(1, 680) i cross join generate_series(1, 8) k
union all
select md5('s' || i || '-' || k)::uuid, md5('l' || i || '-' || 2)::uuid
from generate_series(1, 680) i cross join generate_series(1, 8) k
where i % 2 = 0 and k % 2 = 0;

-- 56 000 clientes
insert into clients (id, full_name, document, birth_date, email, phone, city_id, notification_channel, status)
select md5('c' || i)::uuid, 'Cliente ' || i, (1000000000 + i)::text, date '1970-01-01' + (i % 7000),
       'cliente' || i || '@example.com', '300' || lpad(i::text, 7, '0'),
       (select id from cities order by name offset (i % 3) limit 1), 'EMAIL', 'ACTIVE'
from generate_series(1, 56000) i;

-- Tabla de apoyo para escoger un servicio al azar con su sede y su política
create temporary table svc as
select row_number() over (order by s.id) as n, s.id, sl.location_id,
       s.price, s.currency_id, s.duration_minutes,
       md5('p' || substr(o.name, 11))::uuid as policy_id   -- 'Proveedor 12' -> la política p12
from services s
    inner join organizations o on o.id = s.organization_id
    inner join lateral (select location_id from service_locations x
                         where x.service_id = s.id order by location_id limit 1) sl on true;

-- 1 584 000 reservas repartidas en 2026
alter table bookings disable trigger user;

insert into bookings (id, client_id, service_id, location_id, policy_id, session_id,
                      starts_at, ends_at, attendees, total_price, currency_id, status, cancelled_at, created_at, updated_at)
select r.id, r.client_id, v.id, v.location_id, v.policy_id, r.id,
       r.inicio, r.inicio + make_interval(mins => v.duration_minutes), 1, v.price, v.currency_id,
       r.estado,
       case when r.estado = 'CANCELLED' then r.inicio - interval '1 day' end,
       r.inicio - interval '3 days', r.inicio - interval '3 days'
from (
    select gen_random_uuid() as id,
           md5('c' || (1 + floor(random() * 56000))::int)::uuid as client_id,
           1 + floor(random() * 5440)::int as n,
           timestamptz '2026-01-01 13:00+00' + floor(random() * 365) * interval '1 day'
                                             + floor(random() * 20) * interval '30 minutes' as inicio,
           case when x < 0.60 then 'COMPLETED'
                when x < 0.75 then 'CONFIRMED'
                when x < 0.85 then 'RESERVED'
                when x < 0.95 then 'CANCELLED'
                else 'NO_SHOW' end as estado
    from (select random() as x from generate_series(1, 1584000)) g
) r
    inner join svc v on v.n = r.n
-- Sin este orden el join las deja agrupadas por servicio en el disco, y
-- en la vida real llegan revueltas. Tampoco se ordena por id: el índice
-- primario se llenaría en orden y quedaría más compacto que en producción.
order by random();

alter table bookings enable trigger user;

analyze;

\timing off

select relname, reltuples::bigint as tuplas, relpages as paginas, pg_size_pretty(pg_relation_size(oid)) as tamano
from pg_class
where relname in ('bookings', 'services', 'clients', 'pk_bookings', 'ix_bookings_service_starts')
order by relname;
