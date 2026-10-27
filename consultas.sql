-- =====================================================================
--  Consultas clave del negocio
--  Sprint 1 (1 a 14) y Sprint 2 (15 a 24)
--
--  Cada consulta dice qué pregunta responde. Todas corren sobre las tablas
--  de schema.sql y todas devuelven filas con los datos de seed.sql.
--
--  Usa \echo de psql, así que se ejecuta con `psql -f` y no en el editor
--  SQL de Supabase:
--      psql -d reservas -f consultas.sql
--
--  Las del Sprint 1 son las mismas de esa entrega, ajustadas al modelo
--  actual: la 5 usa identification_number, la 6 lee los bloques desde la
--  agenda, y la 9 y la 12 sacan la ciudad del catálogo.
-- =====================================================================


-- =====================================================================
--  Sprint 1
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
where s.organization_id = (select id from organizations where identification_type = 'NIT' and identification_number = '900123456-1')
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
    inner join agendas   a on a.id = sch.agenda_id
                          and (now() + interval '2 days')::date >= a.valid_from
                          and (a.valid_until is null or (now() + interval '2 days')::date <= a.valid_until)
    inner join resources r on r.id = a.resource_id
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
       o.identification_type,
       o.identification_number,
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
  and attempted_at > now() - interval '15 minutes'
group by email
order by fallos_recientes desc;


-- 9. ¿Qué clientes llevan más de 24 horas sin verificar el correo? Es la
--    lista a la que hay que reenviarles el enlace (HU-001).
\echo '=== 9. Clientes sin verificar hace más de 24 h ==='
select c.id,
       c.full_name,
       c.email,
       ci.name               as ciudad,
       c.created_at,
       now() - c.created_at  as lleva_esperando
from clients c
    inner join cities ci on ci.id = c.city_id
where c.status = 'PENDING_VERIFICATION'
  and c.created_at < now() - interval '24 hours'
order by c.created_at;


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
       exists (select 1 from organizations where identification_type = 'NIT'
                                      and identification_number = '900123456-1')    as nit_ya_registrado;


-- 12. ¿Qué clientes se registraron y nunca han reservado? Subconsulta
--     correlacionada con el operador de existencia.
\echo '=== 12. Clientes que nunca han reservado ==='
select c.id, c.full_name, c.email, ci.name as ciudad, c.status
from   clients c
       inner join cities ci on ci.id = c.city_id
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


-- =====================================================================
--  Sprint 2
--  Preguntas que responden las tablas nuevas y las HU del Sprint 2.
-- =====================================================================


-- 15. ¿Qué porcentaje de su horario estuvo ocupado cada recurso en los
--     últimos 30 días? Es el reporte de ocupación del caso. Lee el
--     resumen diario, no las reservas. Ordenado del más al menos usado.
\echo '=== 15. Ocupación por recurso en los últimos 30 días ==='
select l.name                    as sede,
       r.name                    as recurso,
       sum(o.available_minutes)  as minutos_disponibles,
       sum(o.booked_minutes)     as minutos_ocupados,
       round(100.0 * sum(o.booked_minutes) / nullif(sum(o.available_minutes), 0), 1) as porcentaje
from resource_occupancy_daily o
    inner join resources r on r.id = o.resource_id
    inner join locations l on l.id = r.location_id
where o.occupancy_date between current_date - 30 and current_date - 1
group by l.name, r.name
having sum(o.available_minutes) > 0
order by porcentaje desc, sede, recurso;


-- 16. ¿Qué servicios tienen mejor calificación y con cuántas reseñas?
--     El promedio sale de la reserva: la reseña no copia el servicio.
\echo '=== 16. Calificación promedio por servicio ==='
select o.name                  as organizacion,
       s.name                  as servicio,
       count(*)                as resenas,
       round(avg(br.rating), 2) as promedio,
       min(br.rating)          as peor,
       max(br.rating)          as mejor
from booking_reviews br
    inner join bookings      b on b.id = br.booking_id
    inner join services      s on s.id = b.service_id
    inner join organizations o on o.id = s.organization_id
group by o.name, s.name
order by promedio desc, resenas desc;


-- 17. ¿Quién sigue en lista de espera para cada servicio y día, y en qué
--     turno? El turno es el orden de llegada.
\echo '=== 17. Lista de espera con turno ==='
select s.name          as servicio,
       l.name          as sede,
       w.desired_date  as dia,
       row_number() over (partition by w.service_id, w.location_id, w.desired_date
                          order by w.created_at) as turno,
       c.full_name     as cliente,
       w.attendees     as cupos_pedidos
from waitlist_entries w
    inner join clients   c on c.id = w.client_id
    inner join services  s on s.id = w.service_id
    inner join locations l on l.id = w.location_id
where w.status = 'WAITING'
  and w.desired_date >= current_date
order by servicio, sede, dia, turno;


-- 18. ¿Cuánto cobró, cuánto devolvió y cuánto le quedó a cada proveedor
--     por mes? Cada pago cuenta en el mes en que se cobró, y su reembolso
--     en el mes en que se devolvió, que puede ser otro. Los fallidos y
--     pendientes no cuentan. Une los dos movimientos con union all.
\echo '=== 18. Cobrado, devuelto y neto por proveedor y mes ==='
with movimientos as (
    select s.organization_id, p.currency_id,
           date_trunc('month', p.paid_at) as mes, p.amount as cobrado, 0 as devuelto
    from payments p
        inner join bookings b on b.id = p.booking_id
        inner join services s on s.id = b.service_id
    where p.status in ('PAID', 'REFUNDED')
    union all
    select s.organization_id, p.currency_id,
           date_trunc('month', p.refunded_at), 0, p.amount
    from payments p
        inner join bookings b on b.id = p.booking_id
        inner join services s on s.id = b.service_id
    where p.status = 'REFUNDED'
)
select o.name                          as organizacion,
       m.mes::date                     as mes,
       cur.code                        as moneda,
       sum(m.cobrado)                  as cobrado,
       sum(m.devuelto)                 as devuelto,
       sum(m.cobrado) - sum(m.devuelto) as neto
from movimientos m
    inner join organizations o   on o.id   = m.organization_id
    inner join currencies    cur on cur.id = m.currency_id
group by o.name, m.mes, cur.code
order by organizacion, mes;


-- 19. ¿Qué agendas cierran o recortan su horario en las próximas dos
--     semanas? Sirve para avisar a los clientes con reservas esos días.
\echo '=== 19. Cierres y jornadas recortadas en las próximas dos semanas ==='
select e.exception_date                                   as dia,
       l.name                                             as sede,
       coalesce(r.name, 'Toda la sede')                   as recurso,
       coalesce(e.start_time::text || ' - ' || e.end_time::text, 'Todo el día') as franja,
       e.reason                                           as motivo
from agenda_exceptions e
    inner join agendas   a on a.id = e.agenda_id
    inner join locations l on l.id = a.location_id
    left  join resources r on r.id = a.resource_id
where e.exception_date between current_date and current_date + 14
order by dia, sede, recurso;


-- 20. ¿Qué reservas vivas chocan con un mantenimiento programado? Son
--     las que hay que mover antes de que el cliente llegue (HU-009).
\echo '=== 20. Reservas que chocan con un mantenimiento ==='
select r.name       as recurso,
       m.starts_at  as mantenimiento_desde,
       m.ends_at    as mantenimiento_hasta,
       m.reason     as motivo,
       c.full_name  as cliente,
       br.starts_at as reserva
from resource_maintenances m
    inner join resources         r  on r.id = m.resource_id
    inner join booking_resources br on br.resource_id = m.resource_id
                                   and tstzrange(br.starts_at, br.ends_at) && tstzrange(m.starts_at, m.ends_at)
                                   and br.status in ('RESERVED', 'CONFIRMED')
    inner join bookings          b  on b.id = br.booking_id
    inner join clients           c  on c.id = b.client_id
order by br.starts_at;


-- 21. ¿Qué servicios encuentra quien busca "clasico", sin tilde? Es la
--     búsqueda pública de HU-005, que no distingue mayúsculas ni tildes.
\echo '=== 21. Búsqueda del catálogo sin tildes (HU-005) ==='
select o.name as organizacion, s.name as servicio, s.price
from services s
    inner join organizations o on o.id = s.organization_id
where s.status = 'ACTIVE'
  and o.status = 'ACTIVE'
  and (f_sin_tildes(s.name)        like '%' || f_sin_tildes('clasico') || '%'
    or f_sin_tildes(s.description) like '%' || f_sin_tildes('clasico') || '%'
    or f_sin_tildes(o.name)        like '%' || f_sin_tildes('clasico') || '%')
order by o.name, s.name;


-- 22. ¿Qué reservas atendidas en los últimos 30 días no tienen reseña?
--     Es a quién pedirle que califique. Antijoin con not exists.
\echo '=== 22. Reservas completadas sin reseña ==='
select c.full_name as cliente,
       c.email,
       s.name      as servicio,
       b.starts_at as atendida
from bookings b
    inner join clients  c on c.id = b.client_id
    inner join services s on s.id = b.service_id
where b.status = 'COMPLETED'
  and b.starts_at >= now() - interval '30 days'
  and not exists (select 1 from booking_reviews br where br.booking_id = b.id)
order by b.starts_at;


-- 23. ¿Quién cambió datos sensibles en la última semana y qué cambió?
--     Consulta del administrador sobre la auditoría: compara el antes y
--     el después de cada columna modificada.
\echo '=== 23. Cambios auditados en la última semana ==='
select a.changed_at,
       a.table_name,
       a.operation,
       a.db_user,
       a.app_user_id,
       d.key                 as columna,
       a.old_data -> d.key   as antes,
       d.value               as despues
from audit_log a
    cross join lateral jsonb_each(a.new_data) d
where a.operation = 'UPDATE'
  and a.changed_at >= now() - interval '7 days'
  and d.value is distinct from a.old_data -> d.key
  and d.key <> 'updated_at'
order by a.changed_at desc;


-- 24. ¿Cuántas reservas e ingresos dejó cada servicio de un proveedor en
--     el mes? Es la consulta que se analiza en
--     docs/analisis-almacenamiento.md (costo y optimización).
\echo '=== 24. Reservas e ingresos por servicio de un proveedor en el mes ==='
select s.name             as servicio,
       count(*)           as reservas,
       sum(b.total_price) as ingresos
from bookings b
    inner join services s on s.id = b.service_id
where s.organization_id = '66666666-0000-0000-0000-000000000001'
  and b.starts_at >= date_trunc('month', now())
  and b.starts_at <  date_trunc('month', now()) + interval '1 month'
  and b.status in ('CONFIRMED', 'COMPLETED')
group by s.name
order by ingresos desc;
