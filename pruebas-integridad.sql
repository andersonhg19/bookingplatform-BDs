-- =====================================================================
--  Las reglas de integridad y de seguridad en acción
--  Sprint 2
--
--  Cada instrucción de la primera y la segunda parte viola una regla a
--  propósito, y todas deben ser rechazadas. La tercera parte hace lo que
--  rol_app sí puede hacer, dentro de una transacción que se deshace.
--
--  Las dieciocho pruebas del Sprint 1 siguen en sprint-1/pruebas-integridad.sql.
--
--  Uso:  psql -d reservas -f pruebas-integridad.sql
--  Se ejecuta SIN ON_ERROR_STOP para que se vean todos los rechazos.
-- =====================================================================

\set ON_ERROR_STOP off

\echo ''
\echo '#####################  Parte 1: calidad de los datos  #####################'

\echo ''
\echo '--- 1. Calificar una reserva que todavía no se ha atendido ---'
insert into booking_reviews (booking_id, rating) values ('dddd0000-0000-0000-0000-000000000001', 5);

\echo ''
\echo '--- 2. Clave candidata: una segunda reseña para la misma reserva ---'
insert into booking_reviews (booking_id, rating) values ('dddd0000-0000-0000-0000-000000000005', 3);

\echo ''
\echo '--- 3. Dominio: una calificación de 6 ---'
insert into booking_reviews (booking_id, rating) values ('dddd0000-0000-0000-0000-000000000010', 6);

\echo ''
\echo '--- 4. Dominio: una reseña con el comentario en blanco ---'
insert into booking_reviews (booking_id, rating, comment) values ('dddd0000-0000-0000-0000-000000000010', 4, '   ');

\echo ''
\echo '--- 5. Una excepción de agenda con hora de inicio pero sin hora de fin ---'
insert into agenda_exceptions (agenda_id, exception_date, start_time, reason)
select id, current_date + 20, time '08:00', 'Media jornada' from agendas where resource_id = 'cccc0000-0000-0000-0000-000000000001';

\echo ''
\echo '--- 6. Una excepción que se pisa con el festivo ya registrado ese día ---'
insert into agenda_exceptions (agenda_id, exception_date, start_time, end_time, reason)
select id, current_date + 7, time '10:00', time '12:00', 'Reunión' from agendas where resource_id = 'cccc0000-0000-0000-0000-000000000001';

\echo ''
\echo '--- 7. Anotarse dos veces en la lista de espera del mismo taller y día ---'
insert into waitlist_entries (client_id, service_id, location_id, desired_date)
values ('44444444-0000-0000-0000-000000000002', 'aaaa0000-0000-0000-0000-000000000003',
        '88888888-0000-0000-0000-000000000001', (now() + interval '5 days')::date);

\echo ''
\echo '--- 8. Una entrada marcada como BOOKED que no apunta a ninguna reserva ---'
insert into waitlist_entries (client_id, service_id, location_id, desired_date, status)
values ('44444444-0000-0000-0000-000000000003', 'aaaa0000-0000-0000-0000-000000000001',
        '88888888-0000-0000-0000-000000000001', current_date + 2, 'BOOKED');

\echo ''
\echo '--- 9. Integridad referencial: esperar un servicio en una sede donde no se presta ---'
insert into waitlist_entries (client_id, service_id, location_id, desired_date)
values ('44444444-0000-0000-0000-000000000003', 'aaaa0000-0000-0000-0000-000000000004',
        '88888888-0000-0000-0000-000000000001', current_date + 2);

\echo ''
\echo '--- 10. Un segundo pago vivo para una reserva que ya está pagada ---'
insert into payments (booking_id, amount, currency_id, method)
values ('dddd0000-0000-0000-0000-000000000001', 35000, '33333333-0000-0000-0000-000000000001', 'CARD');

\echo ''
\echo '--- 11. Un pago marcado como PAID sin fecha de pago ---'
insert into payments (booking_id, amount, currency_id, method, status)
values ('dddd0000-0000-0000-0000-000000000002', 45000, '33333333-0000-0000-0000-000000000001', 'CARD', 'PAID');

\echo ''
\echo '--- 12. Un reembolso con fecha anterior al pago ---'
insert into payments (booking_id, amount, currency_id, method, status, paid_at, refunded_at)
values ('dddd0000-0000-0000-0000-000000000002', 45000, '33333333-0000-0000-0000-000000000001', 'CARD',
        'REFUNDED', now(), now() - interval '1 day');

\echo ''
\echo '--- 13. Dominio: un pago por cero pesos ---'
insert into payments (booking_id, amount, currency_id, method)
values ('dddd0000-0000-0000-0000-000000000002', 0, '33333333-0000-0000-0000-000000000001', 'CASH');

\echo ''
\echo '--- 14. Clave candidata: dos pagos con la misma referencia de la pasarela ---'
insert into payments (booking_id, amount, currency_id, method, status, external_reference)
values ('dddd0000-0000-0000-0000-000000000002', 45000, '33333333-0000-0000-0000-000000000001', 'CARD',
        'FAILED', 'TX-1001');


\echo ''
\echo '--- 15. Un pago marcado como reembolsado sin fecha de reembolso ---'
insert into payments (booking_id, amount, currency_id, method, status, paid_at)
values ('dddd0000-0000-0000-0000-000000000002', 45000, '33333333-0000-0000-0000-000000000001', 'CARD',
        'REFUNDED', now());

\echo ''
\echo '--- 16. Una lista de espera que dice haber terminado en la reserva de otro cliente ---'
insert into waitlist_entries (client_id, service_id, location_id, desired_date, status, booking_id, notified_at)
values ('44444444-0000-0000-0000-000000000003', 'aaaa0000-0000-0000-0000-000000000002',
        '88888888-0000-0000-0000-000000000001', current_date + 3, 'BOOKED',
        'dddd0000-0000-0000-0000-000000000002', now());

\echo ''
\echo '--- 17. Una entrada avisada sin fecha de aviso ---'
insert into waitlist_entries (client_id, service_id, location_id, desired_date, status)
values ('44444444-0000-0000-0000-000000000003', 'aaaa0000-0000-0000-0000-000000000001',
        '88888888-0000-0000-0000-000000000001', current_date + 4, 'NOTIFIED');


\echo ''
\echo '#####################  Las reglas que reemplazan a las FK compuestas  #####################'

\echo ''
\echo '--- 18. Publicar un servicio de la clínica en una sede de la barbería ---'
insert into service_locations (service_id, location_id)
values ('aaaa0000-0000-0000-0000-000000000004', '88888888-0000-0000-0000-000000000001');

\echo ''
\echo '--- 19. Exigir para un servicio un tipo de recurso de otro proveedor ---'
insert into service_resource_requirements (service_id, resource_type_id)
values ('aaaa0000-0000-0000-0000-000000000001', 'bbbb0000-0000-0000-0000-000000000003');

\echo ''
\echo '--- 20. Poner una unidad dental de la clínica en una sede de la barbería ---'
insert into resources (resource_type_id, location_id, name)
values ('bbbb0000-0000-0000-0000-000000000003', '88888888-0000-0000-0000-000000000001', 'Unidad prestada');

\echo ''
\echo '--- 21. Habilitar en una agenda un servicio que no se presta en su sede ---'
insert into agenda_services (agenda_id, service_id)
select id, 'aaaa0000-0000-0000-0000-000000000002' from agendas where resource_id = 'cccc0000-0000-0000-0000-000000000006';

\echo ''
\echo '--- 22. Reservar en la barbería con la política de la clínica ---'
insert into bookings (client_id, service_id, location_id, policy_id, session_id, starts_at, ends_at, total_price, currency_id)
values ('44444444-0000-0000-0000-000000000004', 'aaaa0000-0000-0000-0000-000000000001',
        '88888888-0000-0000-0000-000000000001', '77777777-0000-0000-0000-000000000003', gen_random_uuid(),
        now() + interval '12 days', now() + interval '12 days' + interval '30 minutes',
        35000, '33333333-0000-0000-0000-000000000001');

\echo ''
\echo '--- 23. Pactar el precio en una moneda que no es la del servicio ---'
insert into bookings (client_id, service_id, location_id, policy_id, session_id, starts_at, ends_at, total_price, currency_id)
values ('44444444-0000-0000-0000-000000000004', 'aaaa0000-0000-0000-0000-000000000001',
        '88888888-0000-0000-0000-000000000001', '77777777-0000-0000-0000-000000000002', gen_random_uuid(),
        now() + interval '12 days', now() + interval '12 days' + interval '30 minutes',
        10, '33333333-0000-0000-0000-000000000002');

\echo ''
\echo '--- 24. Asignar a una reserva de Poblado la silla de la sede Envigado ---'
insert into booking_resources (booking_id, resource_id, session_id, starts_at, ends_at, status)
select id, 'cccc0000-0000-0000-0000-000000000006', session_id, starts_at, ends_at, status
from bookings where id = 'dddd0000-0000-0000-0000-000000000002';

\echo ''
\echo '--- 25. Una reserva cancelada sin fecha de cancelación ---'
update bookings set status = 'CANCELLED' where id = 'dddd0000-0000-0000-0000-000000000002';

\echo ''
\echo '--- 26. Autorregistro de un menor de edad (HU-001) ---'
insert into clients (id, full_name, document, birth_date, email, phone, city_id, notification_channel)
values (gen_random_uuid(), 'Menor de Edad', '7777777', current_date - interval '10 years',
        'menor@example.com', '3001112233', '11111111-0000-0000-0000-000000000001', 'EMAIL');


\echo ''
\echo '#####################  Parte 2: mínimo privilegio  #####################'

\echo ''
\echo '--- 27. rol_app borra una reserva: el backend nunca borra reservas, las cancela ---'
set role rol_app;
delete from bookings where id = 'dddd0000-0000-0000-0000-000000000006';
reset role;

\echo ''
\echo '--- 28. rol_app edita un historial: sólo puede agregarle filas ---'
set role rol_app;
update booking_status_changes set reason = 'otro motivo';
reset role;

\echo ''
\echo '--- 29. rol_app lee la auditoría: sólo la ve el administrador ---'
set role rol_app;
select count(*) from audit_log;
reset role;

\echo ''
\echo '--- 30. rol_app crea una tabla: los cambios de esquema son de rol_admin ---'
set role rol_app;
create table tabla_intrusa (id int);
reset role;

\echo ''
\echo '--- 31. rol_app cambia un catálogo: se cargan por migración ---'
set role rol_app;
insert into currencies (code, name) values ('EUR', 'Euro');
reset role;

\echo ''
\echo '--- 32. rol_lectura lee datos personales de los clientes ---'
set role rol_lectura;
select full_name, email from clients;
reset role;

\echo ''
\echo '--- 33. rol_lectura modifica una reserva: sólo lee ---'
set role rol_lectura;
update bookings set attendees = 2 where id = 'dddd0000-0000-0000-0000-000000000002';
reset role;


\echo ''
\echo '--- 34. rol_lectura lee el documento y el teléfono de un proveedor ---'
set role rol_lectura;
select name, identification_number, contact_phone from organizations;
reset role;


\echo ''
\echo '#####################  Parte 3: lo que rol_app sí puede  #####################'
\echo 'Reserva, asigna un recurso, confirma, paga y reescribe una agenda, como lo'
\echo 'hace el backend. Al final se'
\echo 'deshace todo. Si alguna línea dice ERROR, a rol_app le falta un permiso.'

begin;
set local role rol_app;

insert into bookings (id, client_id, service_id, location_id, policy_id, session_id,
                      starts_at, ends_at, total_price, currency_id)
values ('eeee0000-0000-0000-0000-000000000001', '44444444-0000-0000-0000-000000000004',
        'aaaa0000-0000-0000-0000-000000000002', '88888888-0000-0000-0000-000000000001',
        '77777777-0000-0000-0000-000000000002', 'eeee0000-0000-0000-0000-000000000001',
        now() + interval '9 days', now() + interval '9 days' + interval '45 minutes',
        45000, '33333333-0000-0000-0000-000000000001');

insert into booking_resources (booking_id, resource_id, session_id, starts_at, ends_at, status)
select id, 'cccc0000-0000-0000-0000-000000000003', session_id, starts_at, ends_at, status
from bookings where id = 'eeee0000-0000-0000-0000-000000000001';

-- Al confirmar, la copia de booking_resources se actualiza sola
update bookings set status = 'CONFIRMED' where id = 'eeee0000-0000-0000-0000-000000000001';
select status as copia_sincronizada from booking_resources where booking_id = 'eeee0000-0000-0000-0000-000000000001';

insert into payments (booking_id, amount, currency_id, method)
values ('eeee0000-0000-0000-0000-000000000001', 45000, '33333333-0000-0000-0000-000000000001', 'CARD');

update services set description = 'Perfilado y afeitado con navaja caliente'
 where id = 'aaaa0000-0000-0000-0000-000000000002';

delete from schedules
 where agenda_id = (select id from agendas where resource_id = 'cccc0000-0000-0000-0000-000000000004');

select count(*) as servicios_con_tilde from services where f_sin_tildes(name) like '%clasico%';

rollback;

\echo ''
\echo 'Y rol_lectura sí hace su reporte: calificaciones por servicio, sin datos personales.'
begin;
set local role rol_lectura;
select o.name as proveedor, s.name as servicio, round(avg(br.rating), 2) as promedio
from booking_reviews br
    inner join bookings      b on b.id = br.booking_id
    inner join services      s on s.id = b.service_id
    inner join organizations o on o.id = s.organization_id
group by o.name, s.name
order by promedio desc;
rollback;


\echo ''
\echo '====================================================================='
\echo ' Las pruebas 1 a 34 debieron terminar en ERROR, y la parte 3 sin'
\echo ' ningún ERROR. Si no, hay una regla o un permiso mal puesto.'
\echo '====================================================================='
