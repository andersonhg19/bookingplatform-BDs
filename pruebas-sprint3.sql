-- =====================================================================
--  Triggers, procedimientos y permisos del Sprint 3, en acción
--
--  Parte 1: cada trigger nuevo rechaza lo que su HU prohíbe. Las 14
--           pruebas deben terminar en ERROR, y el mensaje dice qué HU
--           lo frenó.
--  Parte 2: los procedimientos y funciones hacen su trabajo, llamados por
--           rol_app como los llamaría el backend. Ninguna línea debe
--           decir ERROR.
--  Parte 3: lo que cada rol NO puede hacer con los objetos nuevos. Las 7
--           pruebas deben terminar en ERROR por permisos.
--
--  Todo pasa dentro de transacciones que se deshacen: el seed queda igual.
--
--  Uso:  psql -d reservas -f pruebas-sprint3.sql      (después del seed)
--  Se ejecuta SIN ON_ERROR_STOP para que se vean todos los rechazos.
-- =====================================================================

\set ON_ERROR_STOP off
set timezone = 'America/Bogota';

\echo ''
\echo '#####################  Parte 1: lo que los triggers rechazan  #####################'

\echo ''
\echo '--- 1. HU-012, tg_bookings_anticipacion: una cita que empieza en 30 minutos (la política pide 2 horas) ---'
begin;
insert into sessions (id, service_id, location_id, starts_at, ends_at)
values ('eeee0000-0000-0000-0000-0000000000a1', 'aaaa0000-0000-0000-0000-000000000001', '88888888-0000-0000-0000-000000000002',
        now() + interval '30 minutes', now() + interval '60 minutes');
insert into bookings (client_id, session_id, policy_id, total_price, currency_id)
values ('44444444-0000-0000-0000-000000000004', 'eeee0000-0000-0000-0000-0000000000a1', '77777777-0000-0000-0000-000000000002',
        38000, '33333333-0000-0000-0000-000000000001');
rollback;

\echo ''
\echo '--- 2. HU-012, tg_bookings_anticipacion: una cita dentro de 40 días (la política deja 30) ---'
begin;
insert into sessions (id, service_id, location_id, starts_at, ends_at)
values ('eeee0000-0000-0000-0000-0000000000a2', 'aaaa0000-0000-0000-0000-000000000001', '88888888-0000-0000-0000-000000000002',
        current_date + 40 + time '10:00', current_date + 40 + time '10:30');
insert into bookings (client_id, session_id, policy_id, total_price, currency_id)
values ('44444444-0000-0000-0000-000000000004', 'eeee0000-0000-0000-0000-0000000000a2', '77777777-0000-0000-0000-000000000002',
        38000, '33333333-0000-0000-0000-000000000001');
rollback;

\echo ''
\echo '--- 3. HU-012, tg_bookings_cruce_cliente: Mariana reserva en Envigado a la misma hora de su corte en Poblado ---'
begin;
insert into sessions (id, service_id, location_id, starts_at, ends_at)
values ('eeee0000-0000-0000-0000-0000000000a3', 'aaaa0000-0000-0000-0000-000000000001', '88888888-0000-0000-0000-000000000002',
        current_date + 2 + time '11:00', current_date + 2 + time '11:30');
insert into bookings (client_id, session_id, policy_id, total_price, currency_id)
values ('44444444-0000-0000-0000-000000000001', 'eeee0000-0000-0000-0000-0000000000a3', '77777777-0000-0000-0000-000000000002',
        38000, '33333333-0000-0000-0000-000000000001');
rollback;

\echo ''
\echo '--- 4. HU-013, tg_bookings_momento_del_estado: cancelar una cita que empezó hace 20 minutos ---'
begin;
insert into sessions (id, service_id, location_id, starts_at, ends_at)
values ('eeee0000-0000-0000-0000-0000000000a4', 'aaaa0000-0000-0000-0000-000000000001', '88888888-0000-0000-0000-000000000002',
        now() - interval '20 minutes', now() + interval '10 minutes');
insert into bookings (id, client_id, session_id, policy_id, total_price, currency_id, status, created_at)
values ('eeee0000-0000-0000-0000-0000000000b4', '44444444-0000-0000-0000-000000000004', 'eeee0000-0000-0000-0000-0000000000a4',
        '77777777-0000-0000-0000-000000000002', 38000, '33333333-0000-0000-0000-000000000001', 'CONFIRMED', now() - interval '1 day');
call sp_cancelar_reserva('eeee0000-0000-0000-0000-0000000000b4', 'Se me hizo tarde', '44444444-0000-0000-0000-000000000004', null);
rollback;

\echo ''
\echo '--- 5. HU-016, tg_bookings_momento_del_estado: registrar la asistencia al taller, que es en cinco días ---'
call sp_registrar_asistencia('dddd0000-0000-0000-0000-000000000008', true, '99999999-0000-0000-0000-000000000002', null);

\echo ''
\echo '--- 6. HU-016, tg_bookings_exige_historial: confirmar con un update directo, sin dejar la historia ---'
update bookings set status = 'CONFIRMED' where id = 'dddd0000-0000-0000-0000-000000000002';

\echo ''
\echo '--- 7. HU-013, tg_bookings_exige_historial: cancelar con un update directo, sin motivo ---'
update bookings set status = 'CANCELLED', cancelled_at = now() where id = 'dddd0000-0000-0000-0000-000000000003';

\echo ''
\echo '--- 8. HU-013, ck_booking_status_changes_reason: cancelar con un motivo en blanco ---'
call sp_cancelar_reserva('dddd0000-0000-0000-0000-000000000003', '   ', '44444444-0000-0000-0000-000000000003', null);

\echo ''
\echo '--- 9. HU-014, tg_booking_reschedules_reglas: Mariana ya usó su única reprogramación ---'
call sp_reprogramar_reserva('dddd0000-0000-0000-0000-000000000001', current_date + 2 + time '12:00',
                            'Otra vez', '44444444-0000-0000-0000-000000000001', null, null);

\echo ''
\echo '--- 10. HU-014, tg_booking_reschedules_reglas: pasar el taller a una sesión de barba ---'
insert into booking_reschedules (booking_id, from_session_id, to_session_id, reason)
values ('dddd0000-0000-0000-0000-000000000003', 'ffff0000-0000-0000-0000-000000000003',
        'ffff0000-0000-0000-0000-000000000002', 'Prefiero la barba');

\echo ''
\echo '--- 11. HU-014, tg_booking_reschedules_reglas: reprogramar una reserva que ya se atendió ---'
insert into booking_reschedules (booking_id, from_session_id, to_session_id)
values ('dddd0000-0000-0000-0000-000000000005', 'ffff0000-0000-0000-0000-000000000005',
        'ffff0000-0000-0000-0000-000000000014');

\echo ''
\echo '--- 12. HU-014, tg_bookings_exige_reprogramacion: mover una reserva con un update directo ---'
begin;
insert into sessions (id, service_id, location_id, starts_at, ends_at)
values ('eeee0000-0000-0000-0000-0000000000a5', 'aaaa0000-0000-0000-0000-000000000004', '88888888-0000-0000-0000-000000000003',
        current_date + 3 + time '10:00', current_date + 3 + time '10:40');
update bookings set session_id = 'eeee0000-0000-0000-0000-0000000000a5'
 where id = 'dddd0000-0000-0000-0000-000000000004';
rollback;

\echo ''
\echo '--- 13. HU-008, sp_crear_reserva: reservar en el festivo de la Sede Poblado, que no tiene franjas ---'
call sp_crear_reserva('44444444-0000-0000-0000-000000000004', 'aaaa0000-0000-0000-0000-000000000001',
                      '88888888-0000-0000-0000-000000000001', current_date + 7 + time '10:00', 1, null, null, null);

\echo ''
\echo '--- 14. HU-016, sp_registrar_asistencia: dar por atendida una reserva que nunca se confirmó ---'
call sp_registrar_asistencia('dddd0000-0000-0000-0000-000000000002', true, '99999999-0000-0000-0000-000000000002', null);


\echo ''
\echo '#####################  Parte 2: los procedimientos funcionando  #####################'
\echo 'rol_app hace el ciclo completo de una reserva. Al final se deshace todo.'
\echo 'Si alguna línea dice ERROR, falla un procedimiento o le falta un permiso a rol_app.'

begin;
-- Preparación, como administrador: dos citas de ayer que nadie cerró,
-- una de ellas con la cita en curso para registrar la asistencia
insert into sessions (id, service_id, location_id, starts_at, ends_at) values
    ('eeee0000-0000-0000-0000-0000000000c1', 'aaaa0000-0000-0000-0000-000000000001', '88888888-0000-0000-0000-000000000002',
     now() - interval '20 minutes', now() + interval '10 minutes'),
    ('eeee0000-0000-0000-0000-0000000000c2', 'aaaa0000-0000-0000-0000-000000000002', '88888888-0000-0000-0000-000000000001',
     current_date - 4 + time '09:00', current_date - 4 + time '09:45');
insert into bookings (id, client_id, session_id, policy_id, total_price, currency_id, status, created_at) values
    ('eeee0000-0000-0000-0000-0000000000d1', '44444444-0000-0000-0000-000000000004', 'eeee0000-0000-0000-0000-0000000000c1',
     '77777777-0000-0000-0000-000000000002', 38000, '33333333-0000-0000-0000-000000000001', 'CONFIRMED', now() - interval '1 day'),
    ('eeee0000-0000-0000-0000-0000000000d2', '44444444-0000-0000-0000-000000000001', 'eeee0000-0000-0000-0000-0000000000c2',
     '77777777-0000-0000-0000-000000000002', 45000, '33333333-0000-0000-0000-000000000001', 'CONFIRMED', now() - interval '6 days');

set local role rol_app;

\echo ''
\echo '>> HU-008 y HU-011: franjas de corte en la Sede Poblado dentro de cuatro días'
select count(*) as franjas, min(starts_at) as primera
from fn_franjas_disponibles('aaaa0000-0000-0000-0000-000000000001', '88888888-0000-0000-0000-000000000001', current_date + 4);

-- La primera franja y la tercera, para crear y luego reprogramar
select starts_at as franja1 from fn_franjas_disponibles('aaaa0000-0000-0000-0000-000000000001', '88888888-0000-0000-0000-000000000001', current_date + 4) limit 1 \gset
select starts_at as franja3 from fn_franjas_disponibles('aaaa0000-0000-0000-0000-000000000001', '88888888-0000-0000-0000-000000000001', current_date + 4) offset 2 limit 1 \gset

\echo ''
\echo '>> HU-012: Sara reserva la primera franja; queda confirmada, con código y con su silla'
call sp_crear_reserva('44444444-0000-0000-0000-000000000004', 'aaaa0000-0000-0000-0000-000000000001',
                      '88888888-0000-0000-0000-000000000001', :'franja1', 1, null, null, null);
select b.id as reserva_sara from bookings b inner join sessions se on se.id = b.session_id
 where b.client_id = '44444444-0000-0000-0000-000000000004' and se.starts_at = :'franja1' \gset
select b.code, b.status, r.name as recurso
from bookings b
    inner join session_resources sr on sr.session_id = b.session_id
    inner join resources r on r.id = sr.resource_id
where b.id = :'reserva_sara';

\echo ''
\echo '>> HU-015: la reserva encoló su aviso y sus dos recordatorios'
select kind, due_at from booking_notices where booking_id = :'reserva_sara' order by due_at;

\echo ''
\echo '>> HU-014: Sara la pasa a la tercera franja; le quedan 0 de 1'
call sp_reprogramar_reserva(:'reserva_sara', :'franja3', 'Salgo tarde del trabajo', '44444444-0000-0000-0000-000000000004', null, null);
select kind, due_at from booking_notices where booking_id = :'reserva_sara' order by created_at, due_at;

\echo ''
\echo '>> HU-013: y al final la cancela con tiempo: no es tardía'
call sp_cancelar_reserva(:'reserva_sara', 'Me salió un viaje', '44444444-0000-0000-0000-000000000004', null);

\echo ''
\echo '>> HU-016: la cita en curso queda atendida'
call sp_registrar_asistencia('eeee0000-0000-0000-0000-0000000000d1', true, '99999999-0000-0000-0000-000000000002', null);

\echo ''
\echo '>> HU-016: el cierre automático cierra la de hace cuatro días'
call sp_cerrar_reservas_vencidas(null);
select status from bookings where id = 'eeee0000-0000-0000-0000-0000000000d2';

\echo ''
\echo '>> HU-017: el historial de Sara y el comprobante de su reserva cancelada'
select code, service, starts_at, status, total_price, paid_amount, reschedules
from fn_historial_cliente('44444444-0000-0000-0000-000000000004') limit 3;
select code, status, client_name, provider, service, local_start, total_price, currency
from fn_comprobante_reserva((select code from bookings where id = :'reserva_sara'));

\echo ''
\echo '>> HU-019: ocupación de los recursos de la barbería en el último mes'
select * from fn_reporte_ocupacion('66666666-0000-0000-0000-000000000001', current_date - 30, current_date);

\echo ''
\echo '>> HU-015: el backend marca como enviados los avisos que ya salieron'
update booking_notices set processed_at = now()
 where booking_id = :'reserva_sara' and kind <> 'REMINDER';

rollback;


\echo ''
\echo '#####################  Parte 3: lo que cada rol NO puede  #####################'

\echo ''
\echo '--- 15. rol_app escribe un aviso: la cola sólo la llena tg_bookings_avisos ---'
begin;
set local role rol_app;
insert into booking_notices (booking_id, kind, due_at) values ('dddd0000-0000-0000-0000-000000000001', 'REMINDER', now());
rollback;

\echo ''
\echo '--- 16. rol_app cambia el código de una reserva: el código no cambia ---'
begin;
set local role rol_app;
update bookings set code = 'RSV-0000-0000-0000' where id = 'dddd0000-0000-0000-0000-000000000001';
rollback;

\echo ''
\echo '--- 17. rol_app borra una reprogramación: la historia sólo crece ---'
begin;
set local role rol_app;
delete from booking_reschedules;
rollback;

\echo ''
\echo '--- 18. rol_app recalcula la ocupación: eso es del job del administrador ---'
begin;
set local role rol_app;
select fn_calcular_ocupacion(current_date);
rollback;

\echo ''
\echo '--- 19. rol_lectura crea una reserva: sólo lee ---'
begin;
set local role rol_lectura;
call sp_crear_reserva('44444444-0000-0000-0000-000000000004', 'aaaa0000-0000-0000-0000-000000000001',
                      '88888888-0000-0000-0000-000000000001', current_date + 4 + time '08:00', 1, null, null, null);
rollback;

\echo ''
\echo '--- 20. rol_lectura pide el historial de un cliente: tiene datos personales ---'
begin;
set local role rol_lectura;
select * from fn_historial_cliente('44444444-0000-0000-0000-000000000001');
rollback;

\echo ''
\echo '--- 21. Un rol cualquiera (PUBLIC) consulta las franjas: PostgreSQL ya no le da EXECUTE ---'
begin;
create role prueba_sin_permisos;
grant usage on schema public to prueba_sin_permisos;
set local role prueba_sin_permisos;
select * from fn_franjas_disponibles('aaaa0000-0000-0000-0000-000000000001', '88888888-0000-0000-0000-000000000001', current_date + 4);
rollback;

\echo ''
\echo 'Y rol_lectura sí ve las franjas y el reporte, que no tienen datos personales.'
begin;
set local role rol_lectura;
select count(*) as franjas
from fn_franjas_disponibles('aaaa0000-0000-0000-0000-000000000001', '88888888-0000-0000-0000-000000000001', current_date + 4);
select count(*) as recursos_en_el_reporte
from fn_reporte_ocupacion('66666666-0000-0000-0000-000000000001', current_date - 30, current_date);
rollback;

\echo ''
\echo '====================================================================='
\echo ' Las pruebas 1 a 21 debieron terminar en ERROR, y la parte 2 sin'
\echo ' ningún ERROR. Si no, hay un trigger, un procedimiento o un permiso'
\echo ' mal puesto.'
\echo '====================================================================='
