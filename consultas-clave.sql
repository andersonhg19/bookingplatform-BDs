-- =====================================================================
--  Consultas clave del negocio
--  Sprint 1
--
--  Catorce preguntas. Todas corren sobre las tablas de schema.sql y todas
--  devuelven filas con los datos de seed.sql.
--
--  Usa metacomandos de psql (\echo), así que se ejecuta con `psql -f`,
--  no pegándolo en el editor SQL de Supabase.
--
--  Uso:  psql -f schema.sql -f seed.sql -f consultas-clave.sql
-- =====================================================================


-- 1. ¿Qué servicios puede reservar un cliente en Medellín, en qué sede
--    y a qué precio? Es la consulta del catálogo público, y aplica la
--    regla de HU-002: un proveedor pendiente no es visible.
\echo '=== 1. Catálogo de servicios reservables en Medellín ==='
select o.name              as organizacion,
       s.name              as servicio,
       l.name              as sede,
       s.duration_minutes  as minutos,
       s.price,
       cur.code            as moneda,
       s.customer_capacity as cupo
from services s
    inner join organizations     o   on o.id   = s.organization_id
    inner join service_locations sl  on sl.service_id = s.id
    inner join locations         l   on l.id   = sl.location_id
    inner join cities            c   on c.id   = l.city_id
    inner join currencies        cur on cur.id = s.currency_id
where c.name   = 'Medellín'
  and s.status = 'ACTIVE'
  and l.status = 'ACTIVE'
  and o.status = 'ACTIVE'
order by o.name, s.name;


-- 2. ¿Cuál es la ocupación por sede y semana? Es el reporte de uso que
--    pide el enunciado del caso.
\echo '=== 2. Ocupación e ingresos por sede y semana ==='
select l.name                                as sede,
       date_trunc('week', b.starts_at)::date as semana,
       count(*)                              as reservas,
       sum(b.attendees)                      as asistentes,
       sum(b.total_price)                    as ingresos
from bookings b
    inner join locations l on l.id = b.location_id
where b.status in ('CONFIRMED', 'COMPLETED')
group by l.name, date_trunc('week', b.starts_at)
order by semana, sede;


-- 3. ¿Qué servicios no puede prestar una sede porque no tiene recursos
--    suficientes? Detecta servicios publicados que en la práctica no se
--    pueden ejecutar ahí.
\echo '=== 3. Servicios publicados en una sede sin recursos suficientes ==='
select o.name                as organizacion,
       s.name                as servicio,
       l.name                as sede,
       rt.name               as tipo_de_recurso,
       srr.quantity_required as requiere,
       count(r.id)           as disponibles
from services s
    inner join organizations                  o   on o.id  = s.organization_id
    inner join service_locations              sl  on sl.service_id = s.id
    inner join locations                      l   on l.id  = sl.location_id
    inner join service_resource_requirements  srr on srr.service_id = s.id
    inner join resource_types                 rt  on rt.id = srr.resource_type_id
    left  join resources                      r   on r.resource_type_id = rt.id
                                                 and r.location_id      = l.id
                                                 and r.status           = 'ACTIVE'
group by o.name, s.name, l.name, rt.name, srr.quantity_required
having count(r.id) < srr.quantity_required
order by o.name, s.name, l.name;


-- 4. ¿Cuáles son los servicios más reservados de cada organización?
--    Con rank() y no row_number() para que los empates compartan puesto.
\echo '=== 4. Servicios más reservados por organización (con empates) ==='
select organizacion, servicio, reservas, posicion
from (
    select o.name      as organizacion,
           s.name      as servicio,
           count(b.id) as reservas,
           rank() over (partition by o.id order by count(b.id) desc) as posicion
    from services s
        inner join organizations o on o.id = s.organization_id
        left  join bookings      b on b.service_id = s.id
                                  and b.status in ('CONFIRMED', 'COMPLETED')
    group by o.id, o.name, s.name
) ranking
where posicion <= 3
order by organizacion, posicion, servicio;


-- 5. Si se suspende un proveedor, ¿qué reservas futuras quedan
--    afectadas? HU-003 pide ese informe antes de confirmar la suspensión.
\echo '=== 5. Informe de reservas afectadas por suspender un proveedor ==='
select b.id        as reserva,
       c.full_name as cliente,
       c.email,
       c.phone,
       s.name      as servicio,
       l.name      as sede,
       b.starts_at,
       b.status
from bookings b
    inner join services  s on s.id = b.service_id
    inner join clients   c on c.id = b.client_id
    inner join locations l on l.id = b.location_id
where s.organization_id = (select id from organizations where nit = '900123456-1')
  and b.starts_at >= now()
  and b.status in ('RESERVED', 'CONFIRMED')
order by b.starts_at;


-- 6. ¿Qué agenda tiene cada recurso pasado mañana y cuánta carga lleva?
--    El left join es lo que deja ver también los recursos libres.
\echo '=== 6. Agenda y carga de cada recurso para pasado mañana ==='
select l.name               as sede,
       r.name               as recurso,
       sch.start_time       as abre,
       sch.end_time         as cierra,
       count(br.booking_id) as reservas_vivas
from schedules sch
    inner join resources r on r.id = sch.resource_id
    inner join locations l on l.id = r.location_id
    left  join booking_resources br on br.resource_id = r.id
                                   and br.status in ('RESERVED', 'CONFIRMED')
                                   and br.starts_at::date = (now() + interval '2 days')::date
where sch.day_of_week = extract(isodow from now() + interval '2 days')
  and sch.active
group by l.name, r.name, sch.start_time, sch.end_time
order by l.name, r.name;


-- 7. ¿Qué proveedores llevan más tiempo esperando aprobación? Es la cola
--    de trabajo del administrador (HU-003).
\echo '=== 7. Cola de proveedores pendientes de aprobación ==='
select o.name                            as organizacion,
       o.nit,
       oc.name                           as categoria,
       o.contact_email,
       o.created_at::date                as solicitado_el,
       current_date - o.created_at::date as dias_esperando
from organizations o
    inner join organization_categories oc on oc.id = o.category_id
where o.status = 'PENDING_APPROVAL'
order by dias_esperando desc, o.name;


-- 8. ¿Está bloqueada una cuenta por intentos fallidos? La política es
--    cinco fallos en quince minutos (HU-021).
\echo '=== 8. Cuentas bloqueadas por intentos fallidos ==='
select email,
       count(*)          as fallos_recientes,
       max(attempted_at) as ultimo_intento,
       count(*) >= 5     as bloqueada
from login_attempts
where success = false
  and attempted_at > localtimestamp - interval '15 minutes'
group by email
order by fallos_recientes desc;


-- 9. ¿Qué clientes llevan más de 24 horas sin verificar el correo? Es la
--    lista a la que hay que reenviarles el enlace (HU-001).
\echo '=== 9. Clientes sin verificar hace más de 24 h ==='
select id,
       full_name,
       email,
       city,
       created_at,
       localtimestamp - created_at as lleva_esperando
from clients
where status = 'PENDING_VERIFICATION'
  and created_at < localtimestamp - interval '24 hours'
order by created_at;


-- 10. ¿Qué condiciones de cancelación rigen para cada reserva? Como cada
--     reserva apunta a la versión de política que regía al crearse, dos
--     reservas del mismo negocio salen con ventanas distintas. Es la
--     prueba de que la regla de HU-002 está resuelta en el modelo.
\echo '=== 10. Condiciones congeladas en cada reserva ==='
select o.name                              as organizacion,
       b.starts_at,
       b.status,
       op.version                          as version_politica,
       op.free_cancellation_window_minutes as minutos_cancelacion_gratis,
       case when op.replaced_at is null
            then 'vigente'
            else 'histórica' end           as estado_de_la_politica
from bookings b
    inner join organization_policies op on op.id = b.policy_id
    inner join organizations         o  on o.id  = op.organization_id
order by o.name, b.starts_at;


-- 11. ¿El correo, el documento o el NIT ya están registrados? Es la
--     validación previa al registro, en una sola ida a la base.
\echo '=== 11. Validación de unicidad antes de registrar ==='
select exists (select 1 from clients       where lower(email) = lower('laura@example.com')) as correo_ya_registrado,
       exists (select 1 from clients       where document     = '1020334455')               as documento_ya_registrado,
       exists (select 1 from organizations where nit          = '900123456-1')              as nit_ya_registrado;


-- 12. ¿Qué clientes se registraron y nunca han reservado? Subconsulta
--     correlacionada con el operador de existencia.
\echo '=== 12. Clientes que nunca han reservado ==='
select c.id, c.full_name, c.email, c.city, c.status
from   clients c
where  not exists (select 1
                   from   bookings b
                   where  b.client_id = c.id)
order by c.full_name;


-- 13. ¿Qué servicios se prestan en la Sede Poblado pero no en Envigado?
--     Operador de diferencia del álgebra relacional.
\echo '=== 13. Servicios de una sede que la otra no ofrece (diferencia) ==='
select s.name as servicio
from   service_locations sl
       inner join services  s on s.id = sl.service_id
       inner join locations l on l.id = sl.location_id
where  l.name = 'Sede Poblado'
except
select s.name
from   service_locations sl
       inner join services  s on s.id = sl.service_id
       inner join locations l on l.id = sl.location_id
where  l.name = 'Sede Envigado'
order by servicio;


-- 14. ¿Qué sedes ofrecen TODOS los servicios activos de su organización?
--     Es el operador de división del álgebra relacional, expresado con
--     la doble negación: no existe un servicio activo de la organización
--     que no se preste en esa sede.
\echo '=== 14. Sedes que ofrecen todos los servicios activos de su organización (división) ==='
select o.name as organizacion, l.name as sede
from   locations l
       inner join organizations o on o.id = l.organization_id
where  l.status = 'ACTIVE'
  and  not exists (select 1
                   from   services s
                   where  s.organization_id = l.organization_id
                     and  s.status = 'ACTIVE'
                     and  not exists (select 1
                                      from   service_locations sl
                                      where  sl.service_id  = s.id
                                        and  sl.location_id = l.id))
order by o.name, l.name;
