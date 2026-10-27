-- =====================================================================
--  Datos de prueba — Plataforma de Reservas de Servicios
--  Sprint 2
--
--  Se ejecuta DESPUÉS de schema.sql. Carga un escenario pequeño pero
--  completo, pensado para que TODAS las consultas clave devuelvan
--  filas: una consulta que devuelve vacío no demuestra nada.
--
--  Es re-ejecutable: empieza vaciando las tablas.
--
--  AVISO: el `truncate` de abajo BORRA TODO. Este archivo es para una base
--  local, nunca para la base compartida. La guarda aborta si la base no se
--  llama `reservas`.
--
--  Las fechas son relativas a now(), así que el escenario siempre tiene
--  reservas pasadas, de hoy y futuras.
-- =====================================================================

do $$
begin
    if current_database() <> 'reservas' then
        raise exception
            'seed.sql borra todos los datos y la base actual es "%". Ejecútalo sólo en local.',
            current_database();
    end if;
end $$;

truncate table audit_log, resource_occupancy_daily, payments, waitlist_entries, booking_reviews,
               client_status_changes, organization_status_changes, booking_status_changes,
               booking_resources, bookings, agenda_exceptions, schedules, agenda_services, agendas,
               resource_maintenances, sent_emails, resources, service_resource_requirements,
               service_locations, services, resource_types, locations,
               organization_policies, organization_members, organizations,
               login_attempts, clients,
               currencies, organization_categories, cities
        restart identity cascade;


-- ---------- catálogos ----------
insert into cities (id, name, region) values
    ('11111111-0000-0000-0000-000000000001', 'Medellín', 'Antioquia'),
    ('11111111-0000-0000-0000-000000000002', 'Envigado', 'Antioquia'),
    ('11111111-0000-0000-0000-000000000003', 'Bogotá',   'Bogotá D.C.');

insert into organization_categories (id, name) values
    ('22222222-0000-0000-0000-000000000001', 'Salud'),
    ('22222222-0000-0000-0000-000000000002', 'Belleza'),
    ('22222222-0000-0000-0000-000000000003', 'Deporte');

insert into currencies (id, code, name) values
    ('33333333-0000-0000-0000-000000000001', 'COP', 'Peso colombiano'),
    ('33333333-0000-0000-0000-000000000002', 'USD', 'Dólar estadounidense');


-- ---------- clientes ----------
insert into clients (id, full_name, document, birth_date, email, phone, city_id, notification_channel, status, created_at, updated_at) values
    ('44444444-0000-0000-0000-000000000001', 'Mariana Ospina',  '1017245801', '1999-04-12', 'mariana@example.com', '3001112233', '11111111-0000-0000-0000-000000000001', 'EMAIL',    'ACTIVE',               now() - interval '90 days', now() - interval '90 days'),
    ('44444444-0000-0000-0000-000000000002', 'Laura Restrepo',  '1020334455', '2001-09-30', 'laura@example.com',   '3002223344', '11111111-0000-0000-0000-000000000002', 'WHATSAPP', 'ACTIVE',               now() - interval '45 days', now() - interval '45 days'),
    ('44444444-0000-0000-0000-000000000003', 'Camilo Zapata',   '1015667788', '1995-01-20', 'camilo@example.com',  '3003334455', '11111111-0000-0000-0000-000000000001', 'SMS',      'ACTIVE',               now() - interval '20 days', now() - interval '20 days'),
    ('44444444-0000-0000-0000-000000000004', 'Sara Betancur',   '1011223344', '1997-07-07', 'sara@example.com',    '3005556677', '11111111-0000-0000-0000-000000000001', 'EMAIL',    'ACTIVE',               now() - interval '15 days', now() - interval '15 days'),
    -- Lleva más de 24 h sin verificar: aparece en la consulta de re-engagement
    ('44444444-0000-0000-0000-000000000005', 'Daniela Ochoa',   '1019887766', '2003-06-05', 'daniela@example.com', '3004445566', '11111111-0000-0000-0000-000000000003', 'EMAIL',    'PENDING_VERIFICATION', now() - interval '3 days',  now() - interval '3 days'),
    -- Suspendida por no presentarse varias veces: su motivo queda en client_status_changes
    ('44444444-0000-0000-0000-000000000006', 'Andrés Cardona',  '1032556677', '1990-11-02', 'andres@example.com',  '3006667788', '11111111-0000-0000-0000-000000000001', 'EMAIL',    'SUSPENDED',            now() - interval '70 days', now() - interval '5 days');

insert into client_status_changes (client_id, from_status, to_status, reason, changed_by, changed_at) values
    ('44444444-0000-0000-0000-000000000006', 'ACTIVE', 'SUSPENDED', 'Tres inasistencias sin aviso en un mes', '99999999-0000-0000-0000-000000000009', now() - interval '5 days');


-- ---------- intentos de login (HU-021): Laura está bloqueada ----------
insert into login_attempts (email, success, attempted_at) values
    ('laura@example.com',   false, now() - interval '4 minutes'),
    ('laura@example.com',   false, now() - interval '3 minutes'),
    ('laura@example.com',   false, now() - interval '2 minutes'),
    ('laura@example.com',   false, now() - interval '1 minutes'),
    ('laura@example.com',   false, now() - interval '30 seconds'),
    ('mariana@example.com', true,  now() - interval '10 minutes'),
    -- Alguien probando con un correo que no existe
    ('nadie@example.com',   false, now() - interval '8 minutes');


-- ---------- proveedores ----------
insert into organizations (id, category_id, name, identification_type, identification_number, contact_email, contact_phone, timezone, status, approved_at, created_at, updated_at) values
    ('66666666-0000-0000-0000-000000000001', '22222222-0000-0000-0000-000000000002', 'Barbería El Poblado', 'NIT', '900123456-1', 'contacto@barberia.com', '6041112233', 'America/Bogota', 'ACTIVE', now() - interval '60 days', now() - interval '65 days', now() - interval '10 days'),
    ('66666666-0000-0000-0000-000000000002', '22222222-0000-0000-0000-000000000001', 'Clínica Dental Sur',  'NIT', '901234567-2', 'citas@dentalsur.com',   '6042223344', 'America/Bogota', 'ACTIVE', now() - interval '30 days', now() - interval '35 days', now() - interval '30 days'),
    -- Pendiente hace 45 días: no es visible NI reservable (HU-002),
    -- y encabeza la cola de pendientes del administrador (HU-003)
    ('66666666-0000-0000-0000-000000000003', '22222222-0000-0000-0000-000000000003', 'Cancha Sintética 10', 'NIT', '902345678-3', 'reservas@cancha10.com', '6043334455', 'America/Bogota', 'PENDING_APPROVAL', null, now() - interval '45 days', now() - interval '45 days'),
    -- Una persona natural que presta servicios con su cédula (V4)
    ('66666666-0000-0000-0000-000000000004', '22222222-0000-0000-0000-000000000002', 'Uñas Valeria',        'CC',  '1036998877',  'valeria@example.com',   '3017778899', 'America/Bogota', 'PENDING_APPROVAL', null, now() - interval '2 days',  now() - interval '2 days');

insert into organization_members (organization_id, user_id, role) values
    ('66666666-0000-0000-0000-000000000001', '99999999-0000-0000-0000-000000000001', 'OWNER'),
    ('66666666-0000-0000-0000-000000000002', '99999999-0000-0000-0000-000000000002', 'OWNER'),
    ('66666666-0000-0000-0000-000000000001', '99999999-0000-0000-0000-000000000002', 'STAFF'),
    ('66666666-0000-0000-0000-000000000001', '99999999-0000-0000-0000-000000000003', 'MANAGER');

-- HU-003: la aprobación dejó su motivo registrado
insert into organization_status_changes (organization_id, from_status, to_status, reason, changed_by, changed_at) values
    ('66666666-0000-0000-0000-000000000001', 'PENDING_APPROVAL', 'ACTIVE', 'Documentación y RUT verificados', '99999999-0000-0000-0000-000000000009', now() - interval '60 days'),
    ('66666666-0000-0000-0000-000000000002', 'PENDING_APPROVAL', 'ACTIVE', 'Habilitación sanitaria vigente',  '99999999-0000-0000-0000-000000000009', now() - interval '30 days');

-- Política versionada: la v1 fue reemplazada por la v2 (HU-002)
insert into organization_policies (id, organization_id, version, booking_notice_minutes_min, booking_notice_minutes_max, free_cancellation_window_minutes, effective_from, replaced_at) values
    ('77777777-0000-0000-0000-000000000001', '66666666-0000-0000-0000-000000000001', 1,  60, 20160, 1440, now() - interval '60 days', now() - interval '10 days'),
    ('77777777-0000-0000-0000-000000000002', '66666666-0000-0000-0000-000000000001', 2, 120, 43200,  720, now() - interval '10 days', null),
    ('77777777-0000-0000-0000-000000000003', '66666666-0000-0000-0000-000000000002', 1,  30, 10080, 2880, now() - interval '30 days', null);

insert into locations (id, organization_id, name, address, city_id, timezone, status) values
    ('88888888-0000-0000-0000-000000000001', '66666666-0000-0000-0000-000000000001', 'Sede Poblado',   'Cra 43A # 5-15',     '11111111-0000-0000-0000-000000000001', null, 'ACTIVE'),
    ('88888888-0000-0000-0000-000000000002', '66666666-0000-0000-0000-000000000001', 'Sede Envigado',  'Cll 37 Sur # 41-20', '11111111-0000-0000-0000-000000000002', null, 'ACTIVE'),
    ('88888888-0000-0000-0000-000000000003', '66666666-0000-0000-0000-000000000002', 'Sede Principal', 'Cra 48 # 20-10',     '11111111-0000-0000-0000-000000000001', null, 'ACTIVE');


-- ---------- servicios ----------
insert into services (id, organization_id, name, description, duration_minutes, preparation_minutes, cleanup_minutes, price, currency_id, customer_capacity, status) values
    ('aaaa0000-0000-0000-0000-000000000001', '66666666-0000-0000-0000-000000000001', 'Corte clásico',      'Corte de cabello tradicional',    30,  5,  5,  35000.00, '33333333-0000-0000-0000-000000000001', 1, 'ACTIVE'),
    ('aaaa0000-0000-0000-0000-000000000002', '66666666-0000-0000-0000-000000000001', 'Barba y afeitado',   'Perfilado y afeitado con navaja', 45,  5, 10,  45000.00, '33333333-0000-0000-0000-000000000001', 1, 'ACTIVE'),
    -- GRUPAL: cupo 8. Varias reservas comparten sesión y comparten el salón.
    ('aaaa0000-0000-0000-0000-000000000003', '66666666-0000-0000-0000-000000000001', 'Taller de barbería', 'Taller grupal para aprendices',  120, 15, 15, 180000.00, '33333333-0000-0000-0000-000000000001', 8, 'ACTIVE'),
    ('aaaa0000-0000-0000-0000-000000000004', '66666666-0000-0000-0000-000000000002', 'Limpieza dental',    'Profilaxis y control',            40, 10, 10,  90000.00, '33333333-0000-0000-0000-000000000001', 1, 'ACTIVE'),
    -- Desactivado, no borrado, porque tiene reservas históricas (HU-004)
    ('aaaa0000-0000-0000-0000-000000000005', '66666666-0000-0000-0000-000000000002', 'Blanqueamiento',     'Blanqueamiento en consultorio',   60, 10, 10, 250000.00, '33333333-0000-0000-0000-000000000001', 1, 'INACTIVE');

insert into service_locations (service_id, location_id) values
    ('aaaa0000-0000-0000-0000-000000000001', '88888888-0000-0000-0000-000000000001'),
    ('aaaa0000-0000-0000-0000-000000000001', '88888888-0000-0000-0000-000000000002'),
    ('aaaa0000-0000-0000-0000-000000000002', '88888888-0000-0000-0000-000000000001'),
    ('aaaa0000-0000-0000-0000-000000000003', '88888888-0000-0000-0000-000000000001'),
    -- El taller también se publicó en Envigado, pero esa sede sólo tiene 1 silla
    -- y el taller exige 4: la consulta 3 lo detecta como capacidad insuficiente
    ('aaaa0000-0000-0000-0000-000000000003', '88888888-0000-0000-0000-000000000002'),
    ('aaaa0000-0000-0000-0000-000000000004', '88888888-0000-0000-0000-000000000003'),
    ('aaaa0000-0000-0000-0000-000000000005', '88888888-0000-0000-0000-000000000003');


-- ---------- recursos ----------
insert into resource_types (id, organization_id, name, description) values
    ('bbbb0000-0000-0000-0000-000000000001', '66666666-0000-0000-0000-000000000001', 'Silla de barbero', 'Puesto de atención'),
    ('bbbb0000-0000-0000-0000-000000000002', '66666666-0000-0000-0000-000000000001', 'Sala de taller',   'Espacio para grupos'),
    ('bbbb0000-0000-0000-0000-000000000003', '66666666-0000-0000-0000-000000000002', 'Unidad dental',    'Sillón odontológico');

insert into service_resource_requirements (service_id, resource_type_id, quantity_required) values
    ('aaaa0000-0000-0000-0000-000000000001', 'bbbb0000-0000-0000-0000-000000000001', 1),
    ('aaaa0000-0000-0000-0000-000000000002', 'bbbb0000-0000-0000-0000-000000000001', 1),
    ('aaaa0000-0000-0000-0000-000000000003', 'bbbb0000-0000-0000-0000-000000000002', 1),
    ('aaaa0000-0000-0000-0000-000000000003', 'bbbb0000-0000-0000-0000-000000000001', 4),
    ('aaaa0000-0000-0000-0000-000000000004', 'bbbb0000-0000-0000-0000-000000000003', 1),
    ('aaaa0000-0000-0000-0000-000000000005', 'bbbb0000-0000-0000-0000-000000000003', 1);

-- capacity: personas que el recurso atiende a la vez. El salón recibe al grupo.
insert into resources (id, resource_type_id, location_id, name, capacity, status) values
    ('cccc0000-0000-0000-0000-000000000001', 'bbbb0000-0000-0000-0000-000000000001', '88888888-0000-0000-0000-000000000001', 'Silla 1',         1,  'ACTIVE'),
    ('cccc0000-0000-0000-0000-000000000002', 'bbbb0000-0000-0000-0000-000000000001', '88888888-0000-0000-0000-000000000001', 'Silla 2',         1,  'ACTIVE'),
    ('cccc0000-0000-0000-0000-000000000003', 'bbbb0000-0000-0000-0000-000000000001', '88888888-0000-0000-0000-000000000001', 'Silla 3',         1,  'ACTIVE'),
    ('cccc0000-0000-0000-0000-000000000004', 'bbbb0000-0000-0000-0000-000000000001', '88888888-0000-0000-0000-000000000001', 'Silla 4',         1,  'ACTIVE'),
    ('cccc0000-0000-0000-0000-000000000005', 'bbbb0000-0000-0000-0000-000000000002', '88888888-0000-0000-0000-000000000001', 'Salón principal', 12, 'ACTIVE'),
    ('cccc0000-0000-0000-0000-000000000006', 'bbbb0000-0000-0000-0000-000000000001', '88888888-0000-0000-0000-000000000002', 'Silla única',     1,  'ACTIVE'),
    ('cccc0000-0000-0000-0000-000000000007', 'bbbb0000-0000-0000-0000-000000000003', '88888888-0000-0000-0000-000000000003', 'Unidad A',        1,  'ACTIVE'),
    ('cccc0000-0000-0000-0000-000000000008', 'bbbb0000-0000-0000-0000-000000000003', '88888888-0000-0000-0000-000000000003', 'Unidad B',        1,  'RETIRED');

-- La silla 2 entra a mantenimiento justo cuando Laura tiene su barba:
-- la consulta 20 lo detecta.
insert into resource_maintenances (resource_id, starts_at, ends_at, reason) values
    ('cccc0000-0000-0000-0000-000000000002', now() + interval '3 days' - interval '1 hour', now() + interval '3 days' + interval '2 hours', 'Cambio de tapicería'),
    ('cccc0000-0000-0000-0000-000000000004', now() - interval '20 days', now() - interval '19 days', 'Revisión del sillón hidráulico');


-- ---------- agendas: una por recurso activo ----------
-- Granularidad de 30 minutos, vigente desde hace dos meses y sin fecha de
-- fin, con los servicios que se prestan en su sede. Lunes a viernes de
-- 8:00 a 18:00 y fines de semana de 8:00 a 13:00.
insert into agendas (location_id, resource_id, name, slot_minutes, valid_from)
select r.location_id, r.id, 'Agenda ' || r.name, 30, current_date - 60
from resources r
where r.status = 'ACTIVE';

insert into agenda_services (agenda_id, service_id)
select a.id, sl.service_id
from agendas a
    inner join service_locations sl on sl.location_id = a.location_id;

insert into schedules (agenda_id, day_of_week, start_time, end_time, active)
select a.id, d.dow, time '08:00',
       case when d.dow in (6, 7) then time '13:00' else time '18:00' end, true
from agendas a
    cross join (select generate_series(1, 7) as dow) d;

-- Festivo en toda la Sede Poblado dentro de una semana, una jornada
-- recortada en la clínica mañana y un cierre que ya pasó, para que se
-- note en la ocupación.
insert into agenda_exceptions (agenda_id, exception_date, start_time, end_time, reason)
select a.id, current_date + 7, null, null, 'Festivo'
from agendas a
where a.location_id = '88888888-0000-0000-0000-000000000001';

insert into agenda_exceptions (agenda_id, exception_date, start_time, end_time, reason)
select a.id, current_date + 1, time '14:00', time '18:00', 'Capacitación del personal'
from agendas a
where a.resource_id = 'cccc0000-0000-0000-0000-000000000007';

insert into agenda_exceptions (agenda_id, exception_date, start_time, end_time, reason)
select a.id, current_date - 5, null, null, 'Cierre por fumigación'
from agendas a
where a.resource_id = 'cccc0000-0000-0000-0000-000000000003';


-- ---------- reservas ----------
-- session_id: en servicios individuales coincide con el id de la reserva;
-- en el taller grupal DOS reservas comparten la sesión ffff...0001 y por
-- tanto comparten el salón sin chocar con el EXCLUDE.
-- COMPLETED y NO_SHOW no pasan por las reglas de cupo: ya ocurrieron.
insert into bookings (id, client_id, service_id, location_id, policy_id, session_id, starts_at, ends_at, attendees, total_price, currency_id, status, cancelled_at) values
    ('dddd0000-0000-0000-0000-000000000001', '44444444-0000-0000-0000-000000000001', 'aaaa0000-0000-0000-0000-000000000001', '88888888-0000-0000-0000-000000000001', '77777777-0000-0000-0000-000000000002', 'dddd0000-0000-0000-0000-000000000001', now() + interval '2 days',  now() + interval '2 days'  + interval '30 minutes',  1,  35000.00, '33333333-0000-0000-0000-000000000001', 'CONFIRMED', null),
    ('dddd0000-0000-0000-0000-000000000002', '44444444-0000-0000-0000-000000000002', 'aaaa0000-0000-0000-0000-000000000002', '88888888-0000-0000-0000-000000000001', '77777777-0000-0000-0000-000000000002', 'dddd0000-0000-0000-0000-000000000002', now() + interval '3 days',  now() + interval '3 days'  + interval '45 minutes',  1,  45000.00, '33333333-0000-0000-0000-000000000001', 'RESERVED',  null),
    -- GRUPAL, sesión compartida: Camilo con 6 plazas...
    ('dddd0000-0000-0000-0000-000000000003', '44444444-0000-0000-0000-000000000003', 'aaaa0000-0000-0000-0000-000000000003', '88888888-0000-0000-0000-000000000001', '77777777-0000-0000-0000-000000000002', 'ffff0000-0000-0000-0000-000000000001', now() + interval '5 days',  now() + interval '5 days'  + interval '120 minutes', 6, 180000.00, '33333333-0000-0000-0000-000000000001', 'CONFIRMED', null),
    -- ...y Sara con 2 más en el MISMO taller: 6 + 2 = 8 = cupo exacto
    ('dddd0000-0000-0000-0000-000000000008', '44444444-0000-0000-0000-000000000004', 'aaaa0000-0000-0000-0000-000000000003', '88888888-0000-0000-0000-000000000001', '77777777-0000-0000-0000-000000000002', 'ffff0000-0000-0000-0000-000000000001', now() + interval '5 days',  now() + interval '5 days'  + interval '120 minutes', 2,  60000.00, '33333333-0000-0000-0000-000000000001', 'CONFIRMED', null),
    ('dddd0000-0000-0000-0000-000000000004', '44444444-0000-0000-0000-000000000001', 'aaaa0000-0000-0000-0000-000000000004', '88888888-0000-0000-0000-000000000003', '77777777-0000-0000-0000-000000000003', 'dddd0000-0000-0000-0000-000000000004', now() + interval '1 days',  now() + interval '1 days'  + interval '40 minutes',  1,  90000.00, '33333333-0000-0000-0000-000000000001', 'CONFIRMED', null),
    -- Histórica: por eso 'Blanqueamiento' se desactiva, no se borra (HU-004)
    ('dddd0000-0000-0000-0000-000000000005', '44444444-0000-0000-0000-000000000002', 'aaaa0000-0000-0000-0000-000000000005', '88888888-0000-0000-0000-000000000003', '77777777-0000-0000-0000-000000000003', 'dddd0000-0000-0000-0000-000000000005', now() - interval '20 days', now() - interval '20 days' + interval '60 minutes',  1, 250000.00, '33333333-0000-0000-0000-000000000001', 'COMPLETED', null),
    -- Cancelada: ocupa la misma silla y franja que la reserva 1 y NO choca
    ('dddd0000-0000-0000-0000-000000000006', '44444444-0000-0000-0000-000000000003', 'aaaa0000-0000-0000-0000-000000000001', '88888888-0000-0000-0000-000000000001', '77777777-0000-0000-0000-000000000002', 'dddd0000-0000-0000-0000-000000000006', now() + interval '2 days',  now() + interval '2 days'  + interval '30 minutes',  1,  35000.00, '33333333-0000-0000-0000-000000000001', 'CANCELLED', now() - interval '1 days'),
    -- CLAVE PARA HU-002: creada cuando regía la política v1 de la barbería.
    -- Conserva 1440 minutos de cancelación gratis aunque la v2 los bajó a 720.
    ('dddd0000-0000-0000-0000-000000000007', '44444444-0000-0000-0000-000000000001', 'aaaa0000-0000-0000-0000-000000000002', '88888888-0000-0000-0000-000000000001', '77777777-0000-0000-0000-000000000001', 'dddd0000-0000-0000-0000-000000000007', now() - interval '25 days', now() - interval '25 days' + interval '45 minutes',  1,  40000.00, '33333333-0000-0000-0000-000000000001', 'COMPLETED', null),
    ('dddd0000-0000-0000-0000-000000000009', '44444444-0000-0000-0000-000000000003', 'aaaa0000-0000-0000-0000-000000000001', '88888888-0000-0000-0000-000000000001', '77777777-0000-0000-0000-000000000002', 'dddd0000-0000-0000-0000-000000000009', now() - interval '8 days',  now() - interval '8 days'  + interval '30 minutes',  1,  35000.00, '33333333-0000-0000-0000-000000000001', 'COMPLETED', null),
    ('dddd0000-0000-0000-0000-000000000010', '44444444-0000-0000-0000-000000000004', 'aaaa0000-0000-0000-0000-000000000004', '88888888-0000-0000-0000-000000000003', '77777777-0000-0000-0000-000000000003', 'dddd0000-0000-0000-0000-000000000010', now() - interval '3 days',  now() - interval '3 days'  + interval '40 minutes',  1,  90000.00, '33333333-0000-0000-0000-000000000001', 'COMPLETED', null),
    ('dddd0000-0000-0000-0000-000000000011', '44444444-0000-0000-0000-000000000006', 'aaaa0000-0000-0000-0000-000000000001', '88888888-0000-0000-0000-000000000001', '77777777-0000-0000-0000-000000000002', 'dddd0000-0000-0000-0000-000000000011', now() - interval '12 days', now() - interval '12 days' + interval '30 minutes',  1,  35000.00, '33333333-0000-0000-0000-000000000001', 'NO_SHOW',   null),
    ('dddd0000-0000-0000-0000-000000000012', '44444444-0000-0000-0000-000000000002', 'aaaa0000-0000-0000-0000-000000000001', '88888888-0000-0000-0000-000000000002', '77777777-0000-0000-0000-000000000002', 'dddd0000-0000-0000-0000-000000000012', now() - interval '6 days',  now() - interval '6 days'  + interval '30 minutes',  1,  35000.00, '33333333-0000-0000-0000-000000000001', 'COMPLETED', null),
    ('dddd0000-0000-0000-0000-000000000013', '44444444-0000-0000-0000-000000000004', 'aaaa0000-0000-0000-0000-000000000002', '88888888-0000-0000-0000-000000000001', '77777777-0000-0000-0000-000000000002', 'dddd0000-0000-0000-0000-000000000013', now() - interval '2 days',  now() - interval '2 days'  + interval '45 minutes',  1,  45000.00, '33333333-0000-0000-0000-000000000001', 'COMPLETED', null),
    ('dddd0000-0000-0000-0000-000000000014', '44444444-0000-0000-0000-000000000003', 'aaaa0000-0000-0000-0000-000000000004', '88888888-0000-0000-0000-000000000003', '77777777-0000-0000-0000-000000000003', 'dddd0000-0000-0000-0000-000000000014', now() - interval '15 days', now() - interval '15 days' + interval '40 minutes',  1,  90000.00, '33333333-0000-0000-0000-000000000001', 'COMPLETED', null);

insert into booking_resources (booking_id, resource_id, session_id, starts_at, ends_at, status)
select b.id, a.resource_id, b.session_id, b.starts_at, b.ends_at, b.status
from bookings b
join (values
    ('dddd0000-0000-0000-0000-000000000001'::uuid, 'cccc0000-0000-0000-0000-000000000001'::uuid),
    ('dddd0000-0000-0000-0000-000000000002'::uuid, 'cccc0000-0000-0000-0000-000000000002'::uuid),
    -- las dos reservas del taller ocupan EL MISMO salón, misma sesión
    ('dddd0000-0000-0000-0000-000000000003'::uuid, 'cccc0000-0000-0000-0000-000000000005'::uuid),
    ('dddd0000-0000-0000-0000-000000000008'::uuid, 'cccc0000-0000-0000-0000-000000000005'::uuid),
    ('dddd0000-0000-0000-0000-000000000004'::uuid, 'cccc0000-0000-0000-0000-000000000007'::uuid),
    ('dddd0000-0000-0000-0000-000000000005'::uuid, 'cccc0000-0000-0000-0000-000000000007'::uuid),
    ('dddd0000-0000-0000-0000-000000000006'::uuid, 'cccc0000-0000-0000-0000-000000000001'::uuid),
    ('dddd0000-0000-0000-0000-000000000007'::uuid, 'cccc0000-0000-0000-0000-000000000002'::uuid),
    ('dddd0000-0000-0000-0000-000000000009'::uuid, 'cccc0000-0000-0000-0000-000000000003'::uuid),
    ('dddd0000-0000-0000-0000-000000000010'::uuid, 'cccc0000-0000-0000-0000-000000000007'::uuid),
    ('dddd0000-0000-0000-0000-000000000011'::uuid, 'cccc0000-0000-0000-0000-000000000001'::uuid),
    ('dddd0000-0000-0000-0000-000000000012'::uuid, 'cccc0000-0000-0000-0000-000000000006'::uuid),
    ('dddd0000-0000-0000-0000-000000000013'::uuid, 'cccc0000-0000-0000-0000-000000000002'::uuid),
    ('dddd0000-0000-0000-0000-000000000014'::uuid, 'cccc0000-0000-0000-0000-000000000007'::uuid)
) as a(booking_id, resource_id) on a.booking_id = b.id;

insert into booking_status_changes (booking_id, from_status, to_status, reason, changed_by, changed_at) values
    ('dddd0000-0000-0000-0000-000000000001', 'RESERVED',  'CONFIRMED', null,                                 '44444444-0000-0000-0000-000000000001', now() - interval '1 days'),
    ('dddd0000-0000-0000-0000-000000000005', 'CONFIRMED', 'COMPLETED', null,                                 '99999999-0000-0000-0000-000000000002', now() - interval '20 days'),
    ('dddd0000-0000-0000-0000-000000000006', 'RESERVED',  'CANCELLED', 'El cliente solicitó la cancelación', '44444444-0000-0000-0000-000000000003', now() - interval '1 days'),
    ('dddd0000-0000-0000-0000-000000000011', 'CONFIRMED', 'NO_SHOW',   null,                                 '99999999-0000-0000-0000-000000000002', now() - interval '12 days');


-- ---------- reseñas ----------
-- Las reservas 10 y 14 quedan sin reseña a propósito: la consulta 22 las encuentra
insert into booking_reviews (booking_id, rating, comment, created_at) values
    ('dddd0000-0000-0000-0000-000000000005', 4, 'Buen resultado, aunque la espera fue larga', now() - interval '19 days'),
    ('dddd0000-0000-0000-0000-000000000007', 5, 'Muy buena atención',                         now() - interval '24 days'),
    ('dddd0000-0000-0000-0000-000000000009', 5, null,                                         now() - interval '7 days'),
    ('dddd0000-0000-0000-0000-000000000012', 3, 'Llegué a tiempo y me atendieron tarde',      now() - interval '5 days'),
    ('dddd0000-0000-0000-0000-000000000013', 4, null,                                         now() - interval '1 days');


-- ---------- lista de espera ----------
-- El taller grupal está lleno (8 de 8): Laura y Daniela esperan cupo
insert into waitlist_entries (client_id, service_id, location_id, desired_date, attendees, status, booking_id, notified_at, created_at) values
    ('44444444-0000-0000-0000-000000000002', 'aaaa0000-0000-0000-0000-000000000003', '88888888-0000-0000-0000-000000000001', (now() + interval '5 days')::date, 1, 'WAITING', null, null,                      now() - interval '2 days'),
    ('44444444-0000-0000-0000-000000000005', 'aaaa0000-0000-0000-0000-000000000003', '88888888-0000-0000-0000-000000000001', (now() + interval '5 days')::date, 2, 'WAITING', null, null,                      now() - interval '1 days'),
    -- Se le avisó y no tomó el cupo a tiempo
    ('44444444-0000-0000-0000-000000000001', 'aaaa0000-0000-0000-0000-000000000001', '88888888-0000-0000-0000-000000000001', current_date - 10,                 1, 'EXPIRED', null, now() - interval '11 days', now() - interval '12 days'),
    -- Esta sí terminó en reserva: la barba de Laura
    ('44444444-0000-0000-0000-000000000002', 'aaaa0000-0000-0000-0000-000000000002', '88888888-0000-0000-0000-000000000001', (now() + interval '3 days')::date, 1, 'BOOKED', 'dddd0000-0000-0000-0000-000000000002', now() - interval '4 days', now() - interval '5 days');


-- ---------- pagos ----------
insert into payments (booking_id, amount, currency_id, method, status, external_reference, paid_at, refunded_at, created_at) values
    ('dddd0000-0000-0000-0000-000000000001',  35000.00, '33333333-0000-0000-0000-000000000001', 'CARD',          'PAID',     'TX-1001', now() - interval '1 days',  null,                     now() - interval '1 days'),
    ('dddd0000-0000-0000-0000-000000000003', 180000.00, '33333333-0000-0000-0000-000000000001', 'BANK_TRANSFER', 'PAID',     'TX-1002', now() - interval '2 days',  null,                     now() - interval '2 days'),
    ('dddd0000-0000-0000-0000-000000000008',  60000.00, '33333333-0000-0000-0000-000000000001', 'CARD',          'PENDING',  null,      null,                      null,                     now() - interval '1 hours'),
    -- Primer intento rechazado, segundo aprobado
    ('dddd0000-0000-0000-0000-000000000004',  90000.00, '33333333-0000-0000-0000-000000000001', 'CARD',          'FAILED',   'TX-1003', null,                      null,                     now() - interval '2 days'),
    ('dddd0000-0000-0000-0000-000000000004',  90000.00, '33333333-0000-0000-0000-000000000001', 'CARD',          'PAID',     'TX-1004', now() - interval '2 days',  null,                     now() - interval '2 days'),
    ('dddd0000-0000-0000-0000-000000000005', 250000.00, '33333333-0000-0000-0000-000000000001', 'CASH',          'PAID',     null,      now() - interval '20 days', null,                     now() - interval '20 days'),
    ('dddd0000-0000-0000-0000-000000000007',  40000.00, '33333333-0000-0000-0000-000000000001', 'CARD',          'PAID',     'TX-0990', now() - interval '25 days', null,                     now() - interval '25 days'),
    ('dddd0000-0000-0000-0000-000000000009',  35000.00, '33333333-0000-0000-0000-000000000001', 'CASH',          'PAID',     null,      now() - interval '8 days',  null,                     now() - interval '8 days'),
    ('dddd0000-0000-0000-0000-000000000010',  90000.00, '33333333-0000-0000-0000-000000000001', 'CARD',          'PAID',     'TX-1005', now() - interval '3 days',  null,                     now() - interval '3 days'),
    -- La reserva cancelada se había pagado y se devolvió
    ('dddd0000-0000-0000-0000-000000000006',  35000.00, '33333333-0000-0000-0000-000000000001', 'CARD',          'REFUNDED', 'TX-1006', now() - interval '3 days',  now() - interval '1 days', now() - interval '3 days'),
    ('dddd0000-0000-0000-0000-000000000012',  35000.00, '33333333-0000-0000-0000-000000000001', 'CASH',          'PAID',     null,      now() - interval '6 days',  null,                     now() - interval '6 days'),
    -- Un turista paga con tarjeta internacional: se cobra en dólares
    ('dddd0000-0000-0000-0000-000000000013',     11.00, '33333333-0000-0000-0000-000000000002', 'CARD',          'PAID',     'TX-1007', now() - interval '2 days',  null,                     now() - interval '2 days'),
    ('dddd0000-0000-0000-0000-000000000014',  90000.00, '33333333-0000-0000-0000-000000000001', 'BANK_TRANSFER', 'PAID',     'TX-0995', now() - interval '15 days', null,                     now() - interval '15 days');


-- ---------- bandeja de correo ----------
insert into sent_emails (recipient, subject, body, sent_at) values
    ('mariana@example.com', 'Tu reserva quedó confirmada', 'Corte clásico en Sede Poblado. Te esperamos.',          now() - interval '1 days'),
    ('laura@example.com',   'Se liberó un cupo',           'Hay cupo para Barba y afeitado. Ya quedó tu reserva.',  now() - interval '4 days'),
    ('sara@example.com',    '¿Cómo te fue?',               'Cuéntanos cómo te fue en tu limpieza dental.',          now() - interval '2 days');


-- ---------- un cambio auditado ----------
-- El dueño de la barbería sube el precio del corte. Las reservas ya hechas
-- conservan los 35000 pactados; audit_log guarda el antes y el después.
begin;
set local app.user_id = '99999999-0000-0000-0000-000000000001';
update services set price = 38000.00 where id = 'aaaa0000-0000-0000-0000-000000000001';
commit;


-- ---------- ocupación diaria: los dos últimos meses y la próxima semana ----------
select sum(fn_calcular_ocupacion(d::date)) as filas_de_ocupacion
from generate_series(current_date - 60, current_date + 7, interval '1 day') d;
