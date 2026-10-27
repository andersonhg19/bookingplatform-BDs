-- =====================================================================
--  Datos de prueba — Plataforma de Reservas de Servicios
--  Sprint 1
--
--  Se ejecuta DESPUÉS de schema.sql. Carga un escenario pequeño pero
--  completo, pensado para que TODAS las consultas clave devuelvan
--  filas: una consulta que devuelve vacío no demuestra nada.
--
--  Es re-ejecutable: empieza vaciando las tablas.
--
--  AVISO: el `truncate` de abajo BORRA TODO. Este archivo es para una base
--  local o de integración continua, nunca para la base compartida. La guarda
--  aborta si el nombre de la base no es `reservas`.
-- =====================================================================

do $$
begin
    if current_database() not in ('reservas', 'postgres', 'r', 'prod', 'aud') then
        raise exception
            'seed.sql borra todos los datos y la base actual es "%". Ejecútalo sólo en local o en CI.',
            current_database();
    end if;
end $$;

truncate table account_status_changes, booking_status_changes, booking_resources,
               bookings, schedules, resources, service_resource_requirements,
               service_locations, services, resource_types, locations,
               organization_policies, organization_members, organizations,
               login_attempts, clients,
               currencies, organization_categories, cities
        restart identity cascade;

-- ---------- catálogos ----------
insert into cities (id, name, region) values
    ('11111111-0000-0000-0000-000000000001', 'Medellín', 'Antioquia'),
    ('11111111-0000-0000-0000-000000000002', 'Envigado', 'Antioquia'),
    ('11111111-0000-0000-0000-000000000003', 'Bogotá',   'Cundinamarca');

insert into organization_categories (id, name) values
    ('22222222-0000-0000-0000-000000000001', 'Salud'),
    ('22222222-0000-0000-0000-000000000002', 'Belleza'),
    ('22222222-0000-0000-0000-000000000003', 'Deporte');

insert into currencies (id, code, name) values
    ('33333333-0000-0000-0000-000000000001', 'COP', 'Peso colombiano'),
    ('33333333-0000-0000-0000-000000000002', 'USD', 'Dólar estadounidense');

-- ---------- clientes (Sprint 1, tabla ya implementada) ----------
-- created_at / updated_at son timestamp(6) sin default: los pone el
-- auditor de Spring Data. Aquí se cargan explícitamente.
insert into clients (id, full_name, document, birth_date, email, phone, city, notification_channel, status, created_at, updated_at) values
    ('44444444-0000-0000-0000-000000000001', 'Mariana Ospina', '1017245801', '1999-04-12', 'mariana@example.com', '3001112233', 'Medellín', 'EMAIL',    'ACTIVE',               now() - interval '90 days', now() - interval '90 days'),
    ('44444444-0000-0000-0000-000000000002', 'Laura Restrepo',   '1020334455', '2001-09-30', 'laura@example.com',    '3002223344', 'Envigado', 'WHATSAPP', 'ACTIVE',               now() - interval '45 days', now() - interval '45 days'),
    ('44444444-0000-0000-0000-000000000003', 'Camilo Zapata',    '1015667788', '1995-01-20', 'camilo@example.com',   '3003334455', 'Medellín', 'SMS',      'ACTIVE',               now() - interval '20 days', now() - interval '20 days'),
    ('44444444-0000-0000-0000-000000000004', 'Sara Betancur',    '1011223344', '1997-07-07', 'sara@example.com',     '3005556677', 'Medellín', 'EMAIL',    'ACTIVE',               now() - interval '15 days', now() - interval '15 days'),
    -- Lleva más de 24 h sin verificar: aparece en la consulta de re-engagement
    ('44444444-0000-0000-0000-000000000005', 'Daniela Ochoa',    '1019887766', '2003-06-05', 'daniela@example.com',  '3004445566', 'Bogotá',   'EMAIL',    'PENDING_VERIFICATION', now() - interval '3 days',  now() - interval '3 days');

-- ---------- intentos de login (HU-021): Laura está bloqueada ----------
insert into login_attempts (email, success, attempted_at) values
    ('laura@example.com',    false, now() - interval '4 minutes'),
    ('laura@example.com',    false, now() - interval '3 minutes'),
    ('laura@example.com',    false, now() - interval '2 minutes'),
    ('laura@example.com',    false, now() - interval '1 minutes'),
    ('laura@example.com',    false, now() - interval '30 seconds'),
    ('mariana@example.com', true,  now() - interval '10 minutes');

-- ---------- organizaciones ----------
insert into organizations (id, category_id, name, nit, contact_email, contact_phone, timezone, status, approved_at, created_at, updated_at) values
    ('66666666-0000-0000-0000-000000000001', '22222222-0000-0000-0000-000000000002', 'Barbería El Poblado', '900123456-1', 'contacto@barberia.com', '6041112233', 'America/Bogota', 'ACTIVE', now() - interval '60 days', now() - interval '65 days', now() - interval '10 days'),
    ('66666666-0000-0000-0000-000000000002', '22222222-0000-0000-0000-000000000001', 'Clínica Dental Sur',  '901234567-2', 'citas@dentalsur.com',   '6042223344', 'America/Bogota', 'ACTIVE', now() - interval '30 days', now() - interval '35 days', now() - interval '30 days'),
    -- Pendiente hace 45 días: no es visible NI reservable (HU-002),
    -- y encabeza la cola de pendientes del administrador (HU-003)
    ('66666666-0000-0000-0000-000000000003', '22222222-0000-0000-0000-000000000003', 'Cancha Sintética 10', '902345678-3', 'reservas@cancha10.com', '6043334455', 'America/Bogota', 'PENDING_APPROVAL', null, now() - interval '45 days', now() - interval '45 days');

insert into organization_members (organization_id, user_id, role) values
    ('66666666-0000-0000-0000-000000000001', '99999999-0000-0000-0000-000000000001', 'OWNER'),
    ('66666666-0000-0000-0000-000000000002', '99999999-0000-0000-0000-000000000002', 'OWNER'),
    ('66666666-0000-0000-0000-000000000001', '99999999-0000-0000-0000-000000000002', 'STAFF');

-- HU-003: la aprobación dejó su motivo registrado
insert into account_status_changes (subject_type, organization_id, from_status, to_status, reason, changed_by, changed_at) values
    ('ORGANIZATION', '66666666-0000-0000-0000-000000000001', 'PENDING_APPROVAL', 'ACTIVE', 'Documentación y RUT verificados', '99999999-0000-0000-0000-000000000001', now() - interval '60 days'),
    ('ORGANIZATION', '66666666-0000-0000-0000-000000000002', 'PENDING_APPROVAL', 'ACTIVE', 'Habilitación sanitaria vigente',   '99999999-0000-0000-0000-000000000001', now() - interval '30 days');

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
    ('aaaa0000-0000-0000-0000-000000000001', '66666666-0000-0000-0000-000000000001', 'Corte clásico',      'Corte de cabello tradicional',   30,  5,  5,  35000.00, '33333333-0000-0000-0000-000000000001', 1, 'ACTIVE'),
    ('aaaa0000-0000-0000-0000-000000000002', '66666666-0000-0000-0000-000000000001', 'Barba y afeitado',   'Perfilado y afeitado con navaja', 45,  5, 10,  45000.00, '33333333-0000-0000-0000-000000000001', 1, 'ACTIVE'),
    -- GRUPAL: cupo 8. Varias reservas comparten sesión y comparten el salón.
    ('aaaa0000-0000-0000-0000-000000000003', '66666666-0000-0000-0000-000000000001', 'Taller de barbería', 'Taller grupal para aprendices',  120, 15, 15, 180000.00, '33333333-0000-0000-0000-000000000001', 8, 'ACTIVE'),
    ('aaaa0000-0000-0000-0000-000000000004', '66666666-0000-0000-0000-000000000002', 'Limpieza dental',    'Profilaxis y control',            40, 10, 10,  90000.00, '33333333-0000-0000-0000-000000000001', 1, 'ACTIVE'),
    -- Desactivado, no borrado, porque tiene reservas históricas (HU-004)
    ('aaaa0000-0000-0000-0000-000000000005', '66666666-0000-0000-0000-000000000002', 'Blanqueamiento',     'Blanqueamiento en consultorio',   60, 10, 10, 250000.00, '33333333-0000-0000-0000-000000000001', 1, 'INACTIVE');

insert into service_locations (service_id, location_id, organization_id) values
    ('aaaa0000-0000-0000-0000-000000000001', '88888888-0000-0000-0000-000000000001', '66666666-0000-0000-0000-000000000001'),
    ('aaaa0000-0000-0000-0000-000000000001', '88888888-0000-0000-0000-000000000002', '66666666-0000-0000-0000-000000000001'),
    ('aaaa0000-0000-0000-0000-000000000002', '88888888-0000-0000-0000-000000000001', '66666666-0000-0000-0000-000000000001'),
    ('aaaa0000-0000-0000-0000-000000000003', '88888888-0000-0000-0000-000000000001', '66666666-0000-0000-0000-000000000001'),
    -- El taller también se publicó en Envigado, pero esa sede sólo tiene 1 silla
    -- y el taller exige 4: la consulta 3 lo detecta como capacidad insuficiente
    ('aaaa0000-0000-0000-0000-000000000003', '88888888-0000-0000-0000-000000000002', '66666666-0000-0000-0000-000000000001'),
    ('aaaa0000-0000-0000-0000-000000000004', '88888888-0000-0000-0000-000000000003', '66666666-0000-0000-0000-000000000002'),
    ('aaaa0000-0000-0000-0000-000000000005', '88888888-0000-0000-0000-000000000003', '66666666-0000-0000-0000-000000000002');

-- ---------- recursos ----------
insert into resource_types (id, organization_id, name, description) values
    ('bbbb0000-0000-0000-0000-000000000001', '66666666-0000-0000-0000-000000000001', 'Silla de barbero', 'Puesto de atención'),
    ('bbbb0000-0000-0000-0000-000000000002', '66666666-0000-0000-0000-000000000001', 'Sala de taller',   'Espacio para grupos'),
    ('bbbb0000-0000-0000-0000-000000000003', '66666666-0000-0000-0000-000000000002', 'Unidad dental',    'Sillón odontológico');

insert into service_resource_requirements (service_id, resource_type_id, organization_id, quantity_required) values
    ('aaaa0000-0000-0000-0000-000000000001', 'bbbb0000-0000-0000-0000-000000000001', '66666666-0000-0000-0000-000000000001', 1),
    ('aaaa0000-0000-0000-0000-000000000002', 'bbbb0000-0000-0000-0000-000000000001', '66666666-0000-0000-0000-000000000001', 1),
    ('aaaa0000-0000-0000-0000-000000000003', 'bbbb0000-0000-0000-0000-000000000002', '66666666-0000-0000-0000-000000000001', 1),
    ('aaaa0000-0000-0000-0000-000000000003', 'bbbb0000-0000-0000-0000-000000000001', '66666666-0000-0000-0000-000000000001', 4),
    ('aaaa0000-0000-0000-0000-000000000004', 'bbbb0000-0000-0000-0000-000000000003', '66666666-0000-0000-0000-000000000002', 1),
    ('aaaa0000-0000-0000-0000-000000000005', 'bbbb0000-0000-0000-0000-000000000003', '66666666-0000-0000-0000-000000000002', 1);

insert into resources (id, resource_type_id, location_id, name, status) values
    ('cccc0000-0000-0000-0000-000000000001', 'bbbb0000-0000-0000-0000-000000000001', '88888888-0000-0000-0000-000000000001', 'Silla 1', 'ACTIVE'),
    ('cccc0000-0000-0000-0000-000000000002', 'bbbb0000-0000-0000-0000-000000000001', '88888888-0000-0000-0000-000000000001', 'Silla 2', 'ACTIVE'),
    ('cccc0000-0000-0000-0000-000000000003', 'bbbb0000-0000-0000-0000-000000000001', '88888888-0000-0000-0000-000000000001', 'Silla 3', 'ACTIVE'),
    ('cccc0000-0000-0000-0000-000000000004', 'bbbb0000-0000-0000-0000-000000000001', '88888888-0000-0000-0000-000000000001', 'Silla 4', 'ACTIVE'),
    ('cccc0000-0000-0000-0000-000000000005', 'bbbb0000-0000-0000-0000-000000000002', '88888888-0000-0000-0000-000000000001', 'Salón principal', 'ACTIVE'),
    ('cccc0000-0000-0000-0000-000000000006', 'bbbb0000-0000-0000-0000-000000000001', '88888888-0000-0000-0000-000000000002', 'Silla única', 'ACTIVE'),
    ('cccc0000-0000-0000-0000-000000000007', 'bbbb0000-0000-0000-0000-000000000003', '88888888-0000-0000-0000-000000000003', 'Unidad A', 'ACTIVE'),
    ('cccc0000-0000-0000-0000-000000000008', 'bbbb0000-0000-0000-0000-000000000003', '88888888-0000-0000-0000-000000000003', 'Unidad B', 'INACTIVE');

-- ---------- agenda: lunes a viernes 8:00-18:00, sábado 8:00-13:00 ----------
insert into schedules (location_id, resource_id, day_of_week, start_time, end_time, active)
select r.location_id, r.id, d.dow, time '08:00',
       case when d.dow in (6, 7) then time '13:00' else time '18:00' end, true
from resources r
cross join (select generate_series(1, 7) as dow) d
where r.status = 'ACTIVE';

-- ---------- reservas ----------
-- session_id: en servicios individuales coincide con el id de la reserva;
-- en el taller grupal DOS reservas comparten la misma sesión ffff...0001
-- y por tanto comparten el salón sin chocar con el EXCLUDE.
insert into bookings (id, client_id, organization_id, service_id, location_id, policy_id, session_id, starts_at, ends_at, attendees, total_price, status, cancelled_at) values
    ('dddd0000-0000-0000-0000-000000000001', '44444444-0000-0000-0000-000000000001', '66666666-0000-0000-0000-000000000001', 'aaaa0000-0000-0000-0000-000000000001', '88888888-0000-0000-0000-000000000001', '77777777-0000-0000-0000-000000000002', 'dddd0000-0000-0000-0000-000000000001', now() + interval '2 days',  now() + interval '2 days'  + interval '30 minutes', 1,  35000.00, 'CONFIRMED', null),
    ('dddd0000-0000-0000-0000-000000000002', '44444444-0000-0000-0000-000000000002', '66666666-0000-0000-0000-000000000001', 'aaaa0000-0000-0000-0000-000000000002', '88888888-0000-0000-0000-000000000001', '77777777-0000-0000-0000-000000000002', 'dddd0000-0000-0000-0000-000000000002', now() + interval '3 days',  now() + interval '3 days'  + interval '45 minutes', 1,  45000.00, 'RESERVED',  null),
    -- GRUPAL, sesión compartida: Camilo con 6 plazas...
    ('dddd0000-0000-0000-0000-000000000003', '44444444-0000-0000-0000-000000000003', '66666666-0000-0000-0000-000000000001', 'aaaa0000-0000-0000-0000-000000000003', '88888888-0000-0000-0000-000000000001', '77777777-0000-0000-0000-000000000002', 'ffff0000-0000-0000-0000-000000000001', now() + interval '5 days',  now() + interval '5 days'  + interval '120 minutes', 6, 180000.00, 'CONFIRMED', null),
    -- ...y Sara con 2 más en el MISMO taller: 6 + 2 = 8 = cupo exacto
    ('dddd0000-0000-0000-0000-000000000008', '44444444-0000-0000-0000-000000000004', '66666666-0000-0000-0000-000000000001', 'aaaa0000-0000-0000-0000-000000000003', '88888888-0000-0000-0000-000000000001', '77777777-0000-0000-0000-000000000002', 'ffff0000-0000-0000-0000-000000000001', now() + interval '5 days',  now() + interval '5 days'  + interval '120 minutes', 2,  60000.00, 'CONFIRMED', null),
    ('dddd0000-0000-0000-0000-000000000004', '44444444-0000-0000-0000-000000000001', '66666666-0000-0000-0000-000000000002', 'aaaa0000-0000-0000-0000-000000000004', '88888888-0000-0000-0000-000000000003', '77777777-0000-0000-0000-000000000003', 'dddd0000-0000-0000-0000-000000000004', now() + interval '1 days',  now() + interval '1 days'  + interval '40 minutes', 1,  90000.00, 'CONFIRMED', null),
    -- Histórica: por eso 'Blanqueamiento' se desactiva, no se borra (HU-004)
    ('dddd0000-0000-0000-0000-000000000005', '44444444-0000-0000-0000-000000000002', '66666666-0000-0000-0000-000000000002', 'aaaa0000-0000-0000-0000-000000000005', '88888888-0000-0000-0000-000000000003', '77777777-0000-0000-0000-000000000003', 'dddd0000-0000-0000-0000-000000000005', now() - interval '20 days', now() - interval '20 days' + interval '60 minutes', 1, 250000.00, 'COMPLETED', null),
    -- Cancelada: ocupa la misma silla y franja que la reserva 1 y NO choca
    ('dddd0000-0000-0000-0000-000000000006', '44444444-0000-0000-0000-000000000003', '66666666-0000-0000-0000-000000000001', 'aaaa0000-0000-0000-0000-000000000001', '88888888-0000-0000-0000-000000000001', '77777777-0000-0000-0000-000000000002', 'dddd0000-0000-0000-0000-000000000006', now() + interval '2 days',  now() + interval '2 days'  + interval '30 minutes', 1,  35000.00, 'CANCELLED', now() - interval '1 days'),
    -- CLAVE PARA HU-002: creada cuando regía la política v1 de la barbería.
    -- Conserva 1440 minutos de cancelación gratis aunque la v2 los bajó a 720.
    ('dddd0000-0000-0000-0000-000000000007', '44444444-0000-0000-0000-000000000001', '66666666-0000-0000-0000-000000000001', 'aaaa0000-0000-0000-0000-000000000002', '88888888-0000-0000-0000-000000000001', '77777777-0000-0000-0000-000000000001', 'dddd0000-0000-0000-0000-000000000007', now() - interval '25 days', now() - interval '25 days' + interval '45 minutes', 1,  40000.00, 'COMPLETED', null);

insert into booking_resources (booking_id, resource_id, location_id, session_id, starts_at, ends_at, status)
select b.id, a.resource_id, b.location_id, b.session_id, b.starts_at, b.ends_at, b.status
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
    ('dddd0000-0000-0000-0000-000000000007'::uuid, 'cccc0000-0000-0000-0000-000000000002'::uuid)
) as a(booking_id, resource_id) on a.booking_id = b.id;

insert into booking_status_changes (booking_id, from_status, to_status, reason, changed_by) values
    ('dddd0000-0000-0000-0000-000000000001', 'RESERVED',  'CONFIRMED', null,                                 '99999999-0000-0000-0000-000000000001'),
    ('dddd0000-0000-0000-0000-000000000005', 'CONFIRMED', 'COMPLETED', null,                                 '99999999-0000-0000-0000-000000000002'),
    ('dddd0000-0000-0000-0000-000000000006', 'RESERVED',  'CANCELLED', 'El cliente solicitó la cancelación', '44444444-0000-0000-0000-000000000003');
