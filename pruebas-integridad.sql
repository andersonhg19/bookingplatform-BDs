-- =====================================================================
--  Las reglas de integridad en acción
--  Sprint 1 · Bases de Datos · CodeF@ctory 2026-II
--
--  Las restricciones declaradas en el CREATE TABLE las hace cumplir el
--  motor, no la aplicación. Cada instrucción de este archivo viola una
--  regla de negocio a propósito, y todas deben ser rechazadas.
--
--  Uso:  psql -f schema.sql -f seed.sql -f pruebas-integridad.sql
--  Se ejecuta SIN ON_ERROR_STOP para que se vean los dieciocho rechazos.
-- =====================================================================

\set ON_ERROR_STOP off


\echo ''
\echo '--- 1. Clave candidata: el NIT ya está registrado (HU-002) ---'
insert into organizations (category_id, name, nit, contact_email, contact_phone)
values ('22222222-0000-0000-0000-000000000001', 'Otra Clínica', '900123456-1', 'x@y.com', '6040000000');


\echo ''
\echo '--- 2. Restricción de dominio: anticipación mínima mayor que la máxima (HU-002) ---'
insert into organization_policies (organization_id, version, booking_notice_minutes_min,
                                   booking_notice_minutes_max, free_cancellation_window_minutes)
values ('66666666-0000-0000-0000-000000000002', 2, 5000, 100, 60);


\echo ''
\echo '--- 3. Dos políticas vigentes a la vez en la misma organización (HU-002) ---'
insert into organization_policies (organization_id, version, booking_notice_minutes_min,
                                   booking_notice_minutes_max, free_cancellation_window_minutes)
values ('66666666-0000-0000-0000-000000000001', 3, 60, 1000, 60);


\echo ''
\echo '--- 4. Una organización activa sin fecha de aprobación (HU-002) ---'
insert into organizations (category_id, name, nit, contact_email, contact_phone, status)
values ('22222222-0000-0000-0000-000000000001', 'Sin Aprobar', '903000000-9', 'a@b.com', '6040000001', 'ACTIVE');


\echo ''
\echo '--- 5. Clave candidata: nombre de servicio repetido en el mismo proveedor (HU-004) ---'
insert into services (organization_id, name, duration_minutes, price, currency_id)
values ('66666666-0000-0000-0000-000000000001', 'Corte clásico', 30, 35000,
        '33333333-0000-0000-0000-000000000001');


\echo ''
\echo '--- 6. Restricción de dominio: un servicio con cupo cero (HU-004) ---'
insert into services (organization_id, name, duration_minutes, price, currency_id, customer_capacity)
values ('66666666-0000-0000-0000-000000000001', 'Servicio sin cupo', 30, 1000,
        '33333333-0000-0000-0000-000000000001', 0);


\echo ''
\echo '--- 7. Integridad referencial: reservar un servicio en una sede donde no se presta (HU-004) ---'
insert into bookings (client_id, organization_id, service_id, location_id, policy_id, session_id,
                      starts_at, ends_at, total_price)
values ('44444444-0000-0000-0000-000000000001', '66666666-0000-0000-0000-000000000001',
        'aaaa0000-0000-0000-0000-000000000002', '88888888-0000-0000-0000-000000000002',
        '77777777-0000-0000-0000-000000000002', gen_random_uuid(),
        now() + interval '9 days', now() + interval '9 days' + interval '45 minutes', 45000);


\echo ''
\echo '--- 8. Integridad referencial: mezclar organizaciones en una misma reserva ---'
insert into bookings (client_id, organization_id, service_id, location_id, policy_id, session_id,
                      starts_at, ends_at, total_price)
values ('44444444-0000-0000-0000-000000000001', '66666666-0000-0000-0000-000000000001',
        'aaaa0000-0000-0000-0000-000000000001', '88888888-0000-0000-0000-000000000001',
        '77777777-0000-0000-0000-000000000003', gen_random_uuid(),
        now() + interval '9 days', now() + interval '9 days' + interval '30 minutes', 35000);


\echo ''
\echo '--- 9. Un cliente sin verificar confirma una reserva (HU-001) ---'
insert into bookings (client_id, organization_id, service_id, location_id, policy_id, session_id,
                      starts_at, ends_at, total_price, status)
values ('44444444-0000-0000-0000-000000000005', '66666666-0000-0000-0000-000000000001',
        'aaaa0000-0000-0000-0000-000000000001', '88888888-0000-0000-0000-000000000001',
        '77777777-0000-0000-0000-000000000002', gen_random_uuid(),
        now() + interval '9 days', now() + interval '9 days' + interval '30 minutes', 35000, 'CONFIRMED');


\echo ''
\echo '--- 10. Aforo: más asistentes que el cupo del servicio (HU-004) ---'
insert into bookings (client_id, organization_id, service_id, location_id, policy_id, session_id,
                      starts_at, ends_at, attendees, total_price)
values ('44444444-0000-0000-0000-000000000001', '66666666-0000-0000-0000-000000000001',
        'aaaa0000-0000-0000-0000-000000000001', '88888888-0000-0000-0000-000000000001',
        '77777777-0000-0000-0000-000000000002', gen_random_uuid(),
        now() + interval '9 days', now() + interval '9 days' + interval '30 minutes', 500, 35000);


\echo ''
\echo '--- 11. Sobreocupación: otra sesión usando el mismo recurso en franja solapada ---'
insert into booking_resources (booking_id, resource_id, location_id, session_id, starts_at, ends_at, status)
select 'dddd0000-0000-0000-0000-000000000002', 'cccc0000-0000-0000-0000-000000000005',
       '88888888-0000-0000-0000-000000000001', gen_random_uuid(), starts_at, ends_at, status
from   bookings
where  id = 'dddd0000-0000-0000-0000-000000000003';


\echo ''
\echo '--- 12. Desincronizar la ocupación del estado de su reserva ---'
update booking_resources
set    status = 'CANCELLED'
where  booking_id = 'dddd0000-0000-0000-0000-000000000001';


\echo ''
\echo '--- 13. Franja de agenda solapada con otra del mismo recurso ---'
insert into schedules (location_id, resource_id, day_of_week, start_time, end_time)
values ('88888888-0000-0000-0000-000000000001', 'cccc0000-0000-0000-0000-000000000001', 1, '07:00', '23:00');


\echo ''
\echo '--- 14. Borrar una reserva que tiene historial de auditoría (HU-003) ---'
delete from bookings where id = 'dddd0000-0000-0000-0000-000000000001';


\echo ''
\echo '--- 15. Suspender una organización sin registrar el motivo (HU-003) ---'
update organizations set status = 'SUSPENDED' where id = '66666666-0000-0000-0000-000000000001';


\echo ''
\echo '--- 16. Obligatoriedad y dominio: cliente con correo inválido (HU-001) ---'
insert into clients values (gen_random_uuid(), 'Correo Malo', '8888', '1990-01-01',
                           'no-es-un-correo', '3009998877', 'Medellín', 'EMAIL', 'ACTIVE',
                           localtimestamp, localtimestamp);


\echo ''
\echo '--- 17. Clave candidata: el mismo correo con otra capitalización (HU-001) ---'
insert into clients values (gen_random_uuid(), 'Clon', '9999', '1990-01-01',
                           'MARIANA@example.com', '3009998877', 'Medellín', 'EMAIL', 'ACTIVE',
                           localtimestamp, localtimestamp);


\echo ''
\echo '--- 18. Restricción de dominio: autorregistro de un menor de edad (HU-001) ---'
insert into clients values (gen_random_uuid(), 'Menor de Edad', '7777', current_date - interval '10 years',
                           'menor@example.com', '3001112233', 'Medellín', 'EMAIL', 'ACTIVE',
                           localtimestamp, localtimestamp);


\echo ''
\echo '====================================================================='
\echo ' Las dieciocho instrucciones anteriores debieron ser rechazadas.'
\echo ' Si alguna dice INSERT, UPDATE o DELETE en vez de ERROR, hay una'
\echo ' regla de negocio que la base no está garantizando.'
\echo '====================================================================='
