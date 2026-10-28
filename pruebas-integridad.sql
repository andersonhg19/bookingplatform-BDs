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
-- Las fechas del seed están en la hora de Medellín
set timezone = 'America/Bogota';

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
        '88888888-0000-0000-0000-000000000001', current_date + 5);

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
\echo '--- 18. Una reserva cancelada sin fecha de cancelación ---'
update bookings set status = 'CANCELLED' where id = 'dddd0000-0000-0000-0000-000000000002';

\echo ''
\echo '--- 19. Autorregistro de un menor de edad (HU-001) ---'
insert into clients (id, full_name, document, birth_date, email, phone, city_id, notification_channel)
values (gen_random_uuid(), 'Menor de Edad', '7777777', current_date - interval '10 years',
        'menor@example.com', '3001112233', '11111111-0000-0000-0000-000000000001', 'EMAIL');



\echo ''
\echo '#####################  Las reglas entre tablas  #####################'

\echo ''
\echo '--- 20. Publicar un servicio de la clínica en una sede de la barbería ---'
insert into service_locations (service_id, location_id)
values ('aaaa0000-0000-0000-0000-000000000004', '88888888-0000-0000-0000-000000000001');

\echo ''
\echo '--- 21. Exigir para un servicio un tipo de recurso de otro proveedor ---'
insert into service_resource_requirements (service_id, resource_type_id)
values ('aaaa0000-0000-0000-0000-000000000001', 'bbbb0000-0000-0000-0000-000000000003');

\echo ''
\echo '--- 22. Poner una unidad dental de la clínica en una sede de la barbería ---'
insert into resources (resource_type_id, location_id, name)
values ('bbbb0000-0000-0000-0000-000000000003', '88888888-0000-0000-0000-000000000001', 'Unidad prestada');

\echo ''
\echo '--- 23. Habilitar en una agenda un servicio que no se presta en su sede ---'
insert into agenda_services (agenda_id, service_id)
select id, 'aaaa0000-0000-0000-0000-000000000002' from agendas where resource_id = 'cccc0000-0000-0000-0000-000000000006';

\echo ''
\echo '--- 24. Reservar en la barbería con la política de la clínica ---'
insert into bookings (client_id, session_id, policy_id, total_price, currency_id)
values ('44444444-0000-0000-0000-000000000004', 'ffff0000-0000-0000-0000-000000000006',
        '77777777-0000-0000-0000-000000000003', 35000, '33333333-0000-0000-0000-000000000001');

\echo ''
\echo '--- 25. Pactar el precio en una moneda que no es la del servicio ---'
insert into bookings (client_id, session_id, policy_id, total_price, currency_id)
values ('44444444-0000-0000-0000-000000000004', 'ffff0000-0000-0000-0000-000000000006',
        '77777777-0000-0000-0000-000000000002', 10, '33333333-0000-0000-0000-000000000002');

\echo ''
\echo '--- 26. Asignar a una sesión de Poblado la silla de la sede Envigado ---'
insert into session_resources (session_id, resource_id)
values ('ffff0000-0000-0000-0000-000000000002', 'cccc0000-0000-0000-0000-000000000006');

\echo ''
\echo '--- 27. Sobreocupación: la silla 1 ya atiende otra sesión a esa misma hora ---'
insert into session_resources (session_id, resource_id)
values ('ffff0000-0000-0000-0000-000000000006', 'cccc0000-0000-0000-0000-000000000001');

\echo ''
\echo '--- 28. Mover una sesión encima de otra que usa la misma silla ---'
update sessions
   set starts_at = (select starts_at from sessions where id = 'ffff0000-0000-0000-0000-000000000001'),
       ends_at   = (select ends_at   from sessions where id = 'ffff0000-0000-0000-0000-000000000001')
 where id = 'ffff0000-0000-0000-0000-000000000011';

\echo ''
\echo '--- 29. Llevar a otra sede una sesión que ya tiene su silla asignada ---'
update sessions set location_id = '88888888-0000-0000-0000-000000000002'
where id = 'ffff0000-0000-0000-0000-000000000001';

\echo ''
\echo '--- 30. Cambiarle el servicio a una sesión que ya tiene reservas ---'
update sessions set service_id = 'aaaa0000-0000-0000-0000-000000000002'
where id = 'ffff0000-0000-0000-0000-000000000001';

\echo ''
\echo '--- 31. Pasar una reserva de corte a una sesión de barba ---'
update bookings set session_id = 'ffff0000-0000-0000-0000-000000000013'
where id = 'dddd0000-0000-0000-0000-000000000001';

\echo ''
\echo '--- 32. Cambiar de sede una silla que ya atendió sesiones ---'
update resources set location_id = '88888888-0000-0000-0000-000000000002'
where id = 'cccc0000-0000-0000-0000-000000000001';

\echo ''
\echo '--- 33. Pasarle una sede de la barbería a la clínica ---'
update locations set organization_id = '66666666-0000-0000-0000-000000000002'
where id = '88888888-0000-0000-0000-000000000002';

\echo ''
\echo '--- 34. Cambiar la moneda de un precio ya pactado ---'
update bookings set currency_id = '33333333-0000-0000-0000-000000000002'
where id = 'dddd0000-0000-0000-0000-000000000001';

\echo ''
\echo '--- 35. Pasarle a otro cliente una espera que ya terminó en reserva ---'
update waitlist_entries set client_id = '44444444-0000-0000-0000-000000000003'
where status = 'BOOKED';

\echo ''
\echo '--- 36. Una agenda que es de una sede y de un recurso a la vez ---'
insert into agendas (location_id, resource_id, name, slot_minutes, valid_from)
values ('88888888-0000-0000-0000-000000000001', 'cccc0000-0000-0000-0000-000000000004',
        'Agenda doble', 30, current_date);

\echo ''
\echo '--- 37. Mover una agenda a una sede donde no se prestan sus servicios ---'
begin;
insert into agendas (id, location_id, name, slot_minutes, valid_from)
values ('eeee0000-0000-0000-0000-0000000000a1', '88888888-0000-0000-0000-000000000001', 'Agenda general', 30, current_date);
insert into agenda_services (agenda_id, service_id)
values ('eeee0000-0000-0000-0000-0000000000a1', 'aaaa0000-0000-0000-0000-000000000002');
update agendas set location_id = '88888888-0000-0000-0000-000000000002'
where id = 'eeee0000-0000-0000-0000-0000000000a1';
rollback;


\echo ''
\echo '--- 38. Cancelar una reserva que ya se atendió y tiene reseña ---'
update bookings set status = 'CANCELLED', cancelled_at = now()
where id = 'dddd0000-0000-0000-0000-000000000005';

\echo ''
\echo '--- 39. Crear una reserva que nace ya atendida ---'
insert into bookings (client_id, session_id, policy_id, total_price, currency_id, status)
values ('44444444-0000-0000-0000-000000000004', 'ffff0000-0000-0000-0000-000000000006',
        '77777777-0000-0000-0000-000000000002', 35000, '33333333-0000-0000-0000-000000000001', 'COMPLETED');

\echo ''
\echo '--- 40. Reservar con un cliente suspendido ---'
insert into bookings (client_id, session_id, policy_id, total_price, currency_id)
values ('44444444-0000-0000-0000-000000000006', 'ffff0000-0000-0000-0000-000000000006',
        '77777777-0000-0000-0000-000000000002', 35000, '33333333-0000-0000-0000-000000000001');

\echo ''
\echo '--- 41. Asignar a una sesión la Unidad B, que está retirada ---'
insert into session_resources (session_id, resource_id)
values ('ffff0000-0000-0000-0000-000000000004', 'cccc0000-0000-0000-0000-000000000008');

\echo ''
\echo '--- 42. Cambiarle a una reserva la política que se pactó ---'
update bookings set policy_id = '77777777-0000-0000-0000-000000000001'
where id = 'dddd0000-0000-0000-0000-000000000001';

\echo ''
\echo '--- 43. Suspender un proveedor sin registrar el motivo en esa transacción ---'
update organizations set status = 'SUSPENDED'
where id = '66666666-0000-0000-0000-000000000001';


\echo '#####################  Parte 2: mínimo privilegio  #####################'

\echo ''
\echo '--- 44. rol_app borra una reserva: el backend nunca borra reservas, las cancela ---'
set role rol_app;
delete from bookings where id = 'dddd0000-0000-0000-0000-000000000006';
reset role;

\echo ''
\echo '--- 45. rol_app edita un historial: sólo puede agregarle filas ---'
set role rol_app;
update booking_status_changes set reason = 'otro motivo';
reset role;

\echo ''
\echo '--- 46. rol_app lee la auditoría: sólo la ve el administrador ---'
set role rol_app;
select count(*) from audit_log;
reset role;

\echo ''
\echo '--- 47. rol_app crea una tabla: los cambios de esquema son de rol_admin ---'
set role rol_app;
create table tabla_intrusa (id int);
reset role;

\echo ''
\echo '--- 48. rol_app cambia un catálogo: se cargan por migración ---'
set role rol_app;
insert into currencies (code, name) values ('EUR', 'Euro');
reset role;

\echo ''
\echo '--- 49. rol_lectura lee datos personales de los clientes ---'
set role rol_lectura;
select full_name, email from clients;
reset role;

\echo ''
\echo '--- 50. rol_lectura modifica una reserva: sólo lee ---'
set role rol_lectura;
update bookings set attendees = 2 where id = 'dddd0000-0000-0000-0000-000000000002';
reset role;


\echo ''
\echo '--- 51. rol_lectura lee el documento y el teléfono de un proveedor ---'
set role rol_lectura;
select name, identification_number, contact_phone from organizations;
reset role;


\echo ''
\echo '#####################  Parte 3: lo que rol_app sí puede  #####################'
\echo 'Crea una sesión, reserva, asigna un recurso, confirma, paga, cancela otra'
\echo 'reserva y reescribe los bloques de una agenda, como lo hace el backend. Al'
\echo 'final se deshace todo. Si alguna línea dice ERROR, a rol_app le falta un permiso.'

begin;
set local role rol_app;

-- Una cita nueva: primero la sesión, después la reserva y el recurso
insert into sessions (id, service_id, location_id, starts_at, ends_at)
values ('eeee0000-0000-0000-0000-0000000000c1', 'aaaa0000-0000-0000-0000-000000000002',
        '88888888-0000-0000-0000-000000000001',
        now() + interval '9 days', now() + interval '9 days' + interval '45 minutes');

insert into bookings (id, client_id, session_id, policy_id, total_price, currency_id)
values ('eeee0000-0000-0000-0000-000000000001', '44444444-0000-0000-0000-000000000004',
        'eeee0000-0000-0000-0000-0000000000c1', '77777777-0000-0000-0000-000000000002',
        45000, '33333333-0000-0000-0000-000000000001');

insert into session_resources (session_id, resource_id)
values ('eeee0000-0000-0000-0000-0000000000c1', 'cccc0000-0000-0000-0000-000000000003');

update bookings set status = 'CONFIRMED' where id = 'eeee0000-0000-0000-0000-000000000001';

insert into payments (booking_id, amount, currency_id, method)
values ('eeee0000-0000-0000-0000-000000000001', 45000, '33333333-0000-0000-0000-000000000001', 'CARD');

-- Laura cancela su barba: su sesión se queda sin reservas vivas y suelta la silla 2
update bookings set status = 'CANCELLED', cancelled_at = now()
 where id = 'dddd0000-0000-0000-0000-000000000002';
insert into booking_status_changes (booking_id, from_status, to_status, reason, changed_by)
values ('dddd0000-0000-0000-0000-000000000002', 'RESERVED', 'CANCELLED', 'La silla entra a mantenimiento',
        '99999999-0000-0000-0000-000000000002');
select count(*) as recursos_que_le_quedan from session_resources
 where session_id = 'ffff0000-0000-0000-0000-000000000002';

update services set description = 'Perfilado y afeitado con navaja caliente'
 where id = 'aaaa0000-0000-0000-0000-000000000002';

-- Reescribe los bloques de una agenda como AgendaRepositoryAdapter: borra y vuelve a crear
delete from schedules
 where agenda_id = (select id from agendas where resource_id = 'cccc0000-0000-0000-0000-000000000004');
insert into schedules (agenda_id, day_of_week, start_time, end_time)
select a.id, d, time '09:00', time '17:00'
from agendas a cross join generate_series(1, 5) d
where a.resource_id = 'cccc0000-0000-0000-0000-000000000004';

select count(*) as servicios_con_tilde from services where f_sin_tildes(name) like '%clasico%';

rollback;

\echo ''
\echo 'Y rol_lectura sí hace su reporte: calificaciones por servicio, sin datos personales.'
begin;
set local role rol_lectura;
select o.name as proveedor, s.name as servicio, round(avg(br.rating), 2) as promedio
from booking_reviews br
    inner join bookings      b  on b.id  = br.booking_id
    inner join sessions      se on se.id = b.session_id
    inner join services      s  on s.id  = se.service_id
    inner join organizations o  on o.id  = s.organization_id
group by o.name, s.name
order by promedio desc;
rollback;


\echo ''
\echo '====================================================================='
\echo ' Las pruebas 1 a 51 debieron terminar en ERROR, y la parte 3 sin'
\echo ' ningún ERROR. Si no, hay una regla o un permiso mal puesto.'
\echo '====================================================================='
