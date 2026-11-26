-- =====================================================================
--  Plataforma de Reservas de Servicios — modelo físico
--  Sprint 3
--
--  PostgreSQL 16 y Supabase. Contra una base vacía crea las 35 tablas,
--  sus restricciones, índices, triggers, procedimientos, roles y políticas.
--
--  Sprint 3: el ciclo de vida de la reserva (HU-008 a HU-019). Lo nuevo
--  va marcado con [S3] y el detalle está en el README, en "Cambios
--  respecto al Sprint 2":
--    · Tres tablas: booking_reschedules (HU-014),
--      organization_booking_reminders y booking_notices (HU-015).
--    · Las columnas que el equipo agregó en sus migraciones V11, V14, V17
--      y V18, con sus mismos nombres: bookings.code y cuatro reglas en
--      organization_policies. El contador de reprogramaciones y las
--      marcas de "tardía" de V15 y V17 no se copian: se calculan.
--    · Siete triggers nuevos y nueve procedimientos y funciones, cada uno
--      con la HU que atiende.
--    · EXECUTE sólo para quien invoca cada rutina.
--
--  Lo que sigue es la descripción del Sprint 2, que se mantiene.
--
--  Parte del esquema que el equipo tiene en producción (Sprint 1 más sus
--  migraciones V3 a V9) y lo lleva a BCNF (el detalle, en el README):
--    · Quita las columnas que se repetían para armar claves foráneas
--      compuestas (organization_id en sedes de servicio, recursos,
--      requisitos, agendas y reservas; location_id en agenda_services).
--      Esas reglas pasan a triggers.
--    · Saca de bookings el servicio, la sede y el horario, que dependían
--      de la sesión, a una tabla sessions. Los recursos se asignan a la
--      sesión (session_resources) y no a cada reserva.
--    · Una agenda es de una sede o de un recurso, no de los dos.
--    · Parte account_status_changes, que guardaba dos cosas distintas
--      en una tabla con columnas nulas, en una historia por tipo de cuenta.
--    · clients.city pasa de texto libre a una FK a cities.
--  Y suma nueve tablas, marcadas con [S2 nueva]. Una de ellas,
--  session_resources, reemplaza a booking_resources.
--
--  Convención de nombres: pk_, fk_, uk_, ck_, ex_ (exclusión), ix_ y ux_
--  (índice único), seguidos de la tabla y de lo que controlan.
--
--  Lo que este esquema NO garantiza está al final.
-- =====================================================================

-- En Supabase las extensiones van en el esquema `extensions`;
-- en un Postgres normal ese esquema no existe y cae al search_path.
do $$
begin
    create extension if not exists btree_gist with schema extensions;
exception when others then
    create extension if not exists btree_gist;
end $$;

-- PostgreSQL trae tstzrange y daterange, pero no un rango de `time`.
do $$
begin
    create type timerange as range (subtype = time);
exception when duplicate_object then null;
end $$;

-- [S3] Código legible de una reserva, para buscarla y para el comprobante
-- (HU-017, HU-018). Doce dígitos hexadecimales al azar: con un millón y
-- medio de reservas la probabilidad de un choque es de cuatro en mil, y
-- si ocurre lo para uk_bookings_code. Va aquí porque es el DEFAULT de
-- bookings.code y tiene que existir antes que la tabla.
create or replace function f_codigo_reserva() returns varchar
language sql volatile as $$
    select 'RSV-' || upper(substr(h, 1, 4) || '-' || substr(h, 5, 4) || '-' || substr(h, 9, 4))
      from (select replace(gen_random_uuid()::text, '-', '') as h) x
$$;


-- =====================================================================
--  1. Catálogos
-- =====================================================================

create table cities (
    id     uuid         not null default gen_random_uuid(),
    name   varchar(120) not null,
    region varchar(120) not null,   -- departamento: hay municipios homónimos
    constraint pk_cities             primary key (id),
    constraint uk_cities_name_region unique (name, region),
    constraint ck_cities_name        check (length(btrim(name)) > 0),
    constraint ck_cities_region      check (length(btrim(region)) > 0)
);

create table organization_categories (
    id   uuid        not null default gen_random_uuid(),
    name varchar(80) not null,
    constraint pk_organization_categories      primary key (id),
    constraint uk_organization_categories_name unique (name),
    constraint ck_organization_categories_name check (length(btrim(name)) > 0)
);

create table currencies (
    id     uuid        not null default gen_random_uuid(),
    code   char(3)     not null,
    name   varchar(60) not null,
    active boolean     not null default true,  -- la baja es lógica: hay servicios que la referencian
    constraint pk_currencies      primary key (id),
    constraint uk_currencies_code unique (code),
    constraint uk_currencies_name unique (name),
    constraint ck_currencies_code check (code ~ '^[A-Z]{3}$')   -- ISO 4217
);


-- =====================================================================
--  2. Identidad
--  Las credenciales viven en auth.users de Supabase. Por eso clients.id,
--  organization_members.user_id y los changed_by no tienen FK declarada.
-- =====================================================================

create table clients (
    id                   uuid         not null,     -- = auth.users.id
    full_name            varchar(120) not null,
    document             varchar(30)  not null,
    birth_date           date         not null,
    email                varchar(160) not null,
    phone                varchar(20)  not null,
    city_id              uuid         not null,     -- antes texto libre
    notification_channel varchar(20)  not null,
    status               varchar(30)  not null default 'PENDING_VERIFICATION',
    created_at           timestamptz  not null default now(),
    updated_at           timestamptz  not null default now(),
    constraint pk_clients          primary key (id),
    constraint uk_clients_email    unique (email),
    constraint uk_clients_document unique (document),
    constraint fk_clients_city     foreign key (city_id) references cities (id) on delete restrict,
    constraint ck_clients_status   check (status in ('PENDING_VERIFICATION', 'ACTIVE', 'SUSPENDED')),
    constraint ck_clients_notification_channel check (notification_channel in ('EMAIL', 'SMS', 'WHATSAPP')),
    constraint ck_clients_full_name check (length(btrim(full_name)) > 0),
    constraint ck_clients_document  check (length(btrim(document)) > 0),
    constraint ck_clients_email     check (email ~* '^[^@[:space:]]+@[^@[:space:]]+\.[a-z]{2,}$'),
    constraint ck_clients_phone     check (phone ~ '^\+?[0-9]{7,15}$')
    -- La mayoría de edad (HU-001) va en un trigger: PostgreSQL da por hecho
    -- que un CHECK es inmutable, y uno con current_date no lo es. Además la
    -- regla vale para el momento del registro, no para siempre.
);

-- Soporta el bloqueo por cuenta de HU-021. El correo no es FK a clients:
-- también se registran intentos con correos que no existen.
create table login_attempts (
    id           bigint       generated by default as identity,
    email        varchar(160) not null,
    success      boolean      not null,
    attempted_at timestamptz  not null default now(),
    constraint pk_login_attempts       primary key (id),
    constraint ck_login_attempts_email check (length(btrim(email)) > 0)
);


-- =====================================================================
--  3. Organización (HU-002, HU-003)
-- =====================================================================

create table organizations (
    id                    uuid         not null default gen_random_uuid(),
    category_id           uuid         not null,
    name                  varchar(160) not null,
    -- NIT para empresas; CC, CE o PASAPORTE para personas naturales (V4)
    identification_type   varchar(20)  not null default 'NIT',
    identification_number varchar(20)  not null,
    contact_email         varchar(160) not null,
    contact_phone         varchar(20)  not null,
    timezone              varchar(60)  not null default 'America/Bogota',
    status                varchar(30)  not null default 'PENDING_APPROVAL',
    approved_at           timestamptz,
    created_at            timestamptz  not null default now(),
    updated_at            timestamptz  not null default now(),

    constraint pk_organizations                primary key (id),
    constraint uk_organizations_identification unique (identification_type, identification_number),
    constraint fk_organizations_category       foreign key (category_id) references organization_categories (id) on delete restrict,

    constraint ck_organizations_identification_type   check (identification_type in ('NIT', 'CC', 'CE', 'PASAPORTE')),
    constraint ck_organizations_identification_number check (length(btrim(identification_number)) > 0),
    constraint ck_organizations_status check (status in ('PENDING_APPROVAL', 'ACTIVE', 'SUSPENDED', 'REJECTED')),
    constraint ck_organizations_name   check (length(btrim(name)) > 0),
    constraint ck_organizations_email  check (contact_email ~* '^[^@[:space:]]+@[^@[:space:]]+\.[a-z]{2,}$'),
    constraint ck_organizations_phone  check (contact_phone ~ '^\+?[0-9]{7,15}$'),
    -- No hay organización activa sin fecha de aprobación
    constraint ck_organizations_approved check (
        (status = 'ACTIVE'                         and approved_at is not null) or
        (status in ('PENDING_APPROVAL','REJECTED') and approved_at is null)    or
        (status = 'SUSPENDED'))
);

-- Rol dentro del proveedor (ADR-0008): OWNER = proveedor,
-- MANAGER = gerente, STAFF = recepcionista.
create table organization_members (
    organization_id uuid        not null,
    user_id         uuid        not null,
    role            varchar(30) not null,
    created_at      timestamptz not null default now(),
    constraint pk_organization_members      primary key (organization_id, user_id),
    constraint fk_organization_members_org  foreign key (organization_id) references organizations (id) on delete cascade,
    constraint ck_organization_members_role check (role in ('OWNER', 'MANAGER', 'STAFF'))
);

-- Política versionada: cada reserva apunta a la versión que regía al crearse.
create table organization_policies (
    id                               uuid        not null default gen_random_uuid(),
    organization_id                  uuid        not null,
    version                          integer     not null,
    booking_notice_minutes_min       integer     not null,
    booking_notice_minutes_max       integer     not null,
    free_cancellation_window_minutes integer     not null,
    -- [S3] Las reglas del ciclo de vida que el equipo sumó en V14, V17 y
    -- V18. Son de la política y no del proveedor: así cada reserva se
    -- rige por las que había cuando se hizo.
    manual_confirmation              boolean     not null default false,        -- HU-012: el proveedor confirma a mano
    max_reschedules                  integer     not null default 1,            -- HU-014
    default_closure_status           varchar(20) not null default 'COMPLETED',  -- HU-016: cómo se cierra una confirmada sin registro
    auto_close_delay_hours           integer     not null default 24,           -- HU-016: cuánto se espera para cerrarla
    effective_from                   timestamptz not null default now(),
    replaced_at                      timestamptz,

    constraint pk_organization_policies         primary key (id),
    constraint uk_organization_policies_version unique (organization_id, version),
    constraint fk_organization_policies_org     foreign key (organization_id) references organizations (id) on delete restrict,

    constraint ck_organization_policies_version  check (version > 0),
    constraint ck_organization_policies_notice   check (booking_notice_minutes_min >= 0
                                                    and booking_notice_minutes_min <= booking_notice_minutes_max),
    constraint ck_organization_policies_cancel   check (free_cancellation_window_minutes >= 0),
    constraint ck_organization_policies_reschedules    check (max_reschedules >= 0),
    constraint ck_organization_policies_closure_status check (default_closure_status in ('COMPLETED', 'NO_SHOW')),
    constraint ck_organization_policies_auto_close_hours check (auto_close_delay_hours > 0),
    constraint ck_organization_policies_vigencia check (replaced_at is null or replaced_at > effective_from),
    -- Dos versiones no pueden regir a la vez
    constraint ex_organization_policies_solape exclude using gist (
        organization_id with =,
        tstzrange(effective_from, replaced_at) with &&
    )
);

create table locations (
    id              uuid         not null default gen_random_uuid(),
    organization_id uuid         not null,
    name            varchar(120) not null,
    address         varchar(200) not null,
    city_id         uuid         not null,
    timezone        varchar(60),              -- nulo = la de la organización
    status          varchar(20)  not null default 'ACTIVE',
    created_at      timestamptz  not null default now(),
    updated_at      timestamptz  not null default now(),

    constraint pk_locations          primary key (id),
    constraint uk_locations_org_name unique (organization_id, name),
    constraint fk_locations_org      foreign key (organization_id) references organizations (id) on delete restrict,
    constraint fk_locations_city     foreign key (city_id) references cities (id) on delete restrict,
    constraint ck_locations_status   check (status in ('ACTIVE', 'INACTIVE')),
    constraint ck_locations_name     check (length(btrim(name)) > 0),
    constraint ck_locations_address  check (length(btrim(address)) > 0)
);


-- =====================================================================
--  4. Servicios y recursos (HU-004, HU-009)
-- =====================================================================

create table services (
    id                  uuid          not null default gen_random_uuid(),
    organization_id     uuid          not null,
    name                varchar(120)  not null,
    description         varchar(500),
    duration_minutes    integer       not null,
    preparation_minutes integer       not null default 0,
    cleanup_minutes     integer       not null default 0,
    price               numeric(12,2) not null,
    currency_id         uuid          not null,
    customer_capacity   integer       not null default 1,
    status              varchar(20)   not null default 'INACTIVE',  -- HU-009: no se activa sin recursos
    created_at          timestamptz   not null default now(),
    updated_at          timestamptz   not null default now(),

    constraint pk_services          primary key (id),
    constraint uk_services_org_name unique (organization_id, name),
    constraint fk_services_org      foreign key (organization_id) references organizations (id) on delete restrict,
    constraint fk_services_currency foreign key (currency_id) references currencies (id) on delete restrict,

    constraint ck_services_duration check (duration_minutes > 0),
    constraint ck_services_prep     check (preparation_minutes >= 0 and cleanup_minutes >= 0),
    constraint ck_services_price    check (price >= 0),
    constraint ck_services_capacity check (customer_capacity >= 1),  -- 1 = individual, >1 = grupal
    constraint ck_services_status   check (status in ('ACTIVE', 'INACTIVE')),
    constraint ck_services_name     check (length(btrim(name)) > 0)
);

-- Sedes donde se presta cada servicio. Que servicio y sede sean del mismo
-- proveedor lo revisa tg_service_locations_mismo_proveedor.
create table service_locations (
    service_id  uuid not null,
    location_id uuid not null,
    constraint pk_service_locations          primary key (service_id, location_id),
    constraint fk_service_locations_service  foreign key (service_id)  references services  (id) on delete cascade,
    constraint fk_service_locations_location foreign key (location_id) references locations (id) on delete cascade
);

create table resource_types (
    id              uuid         not null default gen_random_uuid(),
    organization_id uuid         not null,
    name            varchar(80)  not null,
    description     varchar(300),
    created_at      timestamptz  not null default now(),
    constraint pk_resource_types          primary key (id),
    constraint uk_resource_types_org_name unique (organization_id, name),
    constraint fk_resource_types_org      foreign key (organization_id) references organizations (id) on delete restrict,
    constraint ck_resource_types_name     check (length(btrim(name)) > 0)
);

-- Cuántos recursos de cada tipo exige un servicio. Es una relación N:M con
-- atributo, así que su clave es el par.
create table service_resource_requirements (
    service_id        uuid    not null,
    resource_type_id  uuid    not null,
    quantity_required integer not null default 1,
    constraint pk_service_resource_requirements      primary key (service_id, resource_type_id),
    constraint fk_service_resource_requirements_svc  foreign key (service_id)       references services       (id) on delete cascade,
    constraint fk_service_resource_requirements_type foreign key (resource_type_id) references resource_types (id) on delete restrict,
    constraint ck_service_resource_requirements_qty  check (quantity_required > 0)
);

create table resources (
    id               uuid         not null default gen_random_uuid(),
    resource_type_id uuid         not null,
    location_id      uuid         not null,
    name             varchar(120) not null,
    capacity         integer      not null default 1,       -- personas a la vez (HU-009)
    status           varchar(20)  not null default 'ACTIVE',
    created_at       timestamptz  not null default now(),
    updated_at       timestamptz  not null default now(),
    constraint pk_resources               primary key (id),
    constraint uk_resources_location_name unique (location_id, name),
    constraint fk_resources_type         foreign key (resource_type_id) references resource_types (id) on delete restrict,
    constraint fk_resources_location      foreign key (location_id)      references locations (id)      on delete restrict,
    constraint ck_resources_capacity      check (capacity >= 1),
    constraint ck_resources_name          check (length(btrim(name)) > 0),
    -- "En mantenimiento" no es un estado sino un periodo: resource_maintenances
    constraint ck_resources_status        check (status in ('ACTIVE', 'RETIRED'))
);

create table resource_maintenances (
    id          uuid         not null default gen_random_uuid(),
    resource_id uuid         not null,
    starts_at   timestamptz  not null,
    ends_at     timestamptz  not null,
    reason      varchar(300),
    created_at  timestamptz  not null default now(),
    constraint pk_resource_maintenances          primary key (id),
    constraint fk_resource_maintenances_resource foreign key (resource_id) references resources (id) on delete cascade,
    constraint ck_resource_maintenances_rango    check (ends_at > starts_at),
    constraint ex_resource_maintenances_solape   exclude using gist (
        resource_id with =,
        tstzrange(starts_at, ends_at) with &&
    )
);


-- =====================================================================
--  5. Agendas (HU-006)
-- =====================================================================

-- Una agenda es de una sede entera o de un recurso, nunca de los dos.
-- Antes guardaba la sede también en las agendas de un recurso, y como el
-- recurso ya dice en qué sede está, resource_id -> location_id rompía la
-- BCNF. Ahora la sede de una agenda de recurso sale del recurso.
create table agendas (
    id              uuid         not null default gen_random_uuid(),
    location_id     uuid,                       -- agenda de toda la sede
    resource_id     uuid,                       -- agenda de un recurso
    name            varchar(120) not null,
    slot_minutes    smallint     not null,
    valid_from      date         not null,
    valid_until     date,                       -- nulo = sin fecha de fin
    created_at      timestamptz  not null default now(),
    updated_at      timestamptz  not null default now(),

    constraint pk_agendas               primary key (id),
    constraint uk_agendas_location_name unique (location_id, name),
    constraint uk_agendas_resource_name unique (resource_id, name),
    constraint fk_agendas_location      foreign key (location_id) references locations (id) on delete restrict,
    constraint fk_agendas_resource      foreign key (resource_id) references resources (id) on delete restrict,
    -- Exactamente uno de los dos
    constraint ck_agendas_duenio        check ((location_id is null) <> (resource_id is null)),
    constraint ck_agendas_slot          check (slot_minutes in (15, 30, 60)),
    constraint ck_agendas_vigencia      check (valid_until is null or valid_until >= valid_from),
    constraint ck_agendas_name          check (length(btrim(name)) > 0),
    -- Una sede, o un recurso, no tiene dos agendas vigentes a la vez
    constraint ex_agendas_sede_solape exclude using gist (
        location_id with =,
        daterange(valid_from, valid_until, '[]') with &&
    ) where (location_id is not null),
    constraint ex_agendas_recurso_solape exclude using gist (
        resource_id with =,
        daterange(valid_from, valid_until, '[]') with &&
    ) where (resource_id is not null)
);

-- Servicios reservables en cada agenda. Que el servicio se preste en la
-- sede de la agenda lo revisa tg_agenda_services_en_sede.
create table agenda_services (
    agenda_id  uuid not null,
    service_id uuid not null,
    constraint pk_agenda_services         primary key (agenda_id, service_id),
    constraint fk_agenda_services_agenda  foreign key (agenda_id)  references agendas  (id) on delete cascade,
    constraint fk_agenda_services_service foreign key (service_id) references services (id) on delete cascade
);

-- Bloques semanales de una agenda
create table schedules (
    id          uuid        not null default gen_random_uuid(),
    agenda_id   uuid        not null,
    day_of_week smallint    not null,           -- ISO: 1 = lunes
    start_time  time        not null,
    end_time    time        not null,
    active      boolean     not null default true,
    created_at  timestamptz not null default now(),
    constraint pk_schedules        primary key (id),
    constraint fk_schedules_agenda foreign key (agenda_id) references agendas (id) on delete cascade,
    constraint ck_schedules_dow    check (day_of_week between 1 and 7),
    constraint ck_schedules_rango  check (end_time > start_time),
    constraint ex_schedules_solape exclude using gist (
        agenda_id with =,
        day_of_week with =,
        timerange(start_time, end_time) with &&
    ) where (active)
);

-- [S2 nueva] Días en que la agenda no atiende, o atiende menos: festivos,
-- cierres, una jornada recortada. schedules sólo sabe de días de la semana.
create table agenda_exceptions (
    id             uuid         not null default gen_random_uuid(),
    agenda_id      uuid         not null,
    exception_date date         not null,
    start_time     time,                        -- los dos nulos = cerrado todo el día
    end_time       time,
    reason         varchar(300) not null,
    created_at     timestamptz  not null default now(),
    constraint pk_agenda_exceptions        primary key (id),
    constraint fk_agenda_exceptions_agenda foreign key (agenda_id) references agendas (id) on delete cascade,
    constraint ck_agenda_exceptions_franja check (
        (start_time is null and end_time is null) or
        (start_time is not null and end_time is not null and end_time > start_time)),
    constraint ck_agenda_exceptions_reason check (length(btrim(reason)) > 0),
    -- Dos excepciones del mismo día no se pisan
    constraint ex_agenda_exceptions_solape exclude using gist (
        agenda_id with =,
        exception_date with =,
        timerange(coalesce(start_time, time '00:00'), coalesce(end_time, time '24:00')) with &&
    )
);


-- =====================================================================
--  6. Reservas
-- =====================================================================

-- [S2 nueva] Una sesión es un servicio, en una sede, a una hora. En un
-- servicio individual tiene una sola reserva; en uno grupal, varias,
-- hasta el cupo. Antes el servicio, la sede y el horario se repetían en
-- cada reserva de la sesión: session_id -> starts_at era una dependencia
-- transitiva en bookings.
create table sessions (
    id          uuid        not null default gen_random_uuid(),
    service_id  uuid        not null,
    location_id uuid        not null,
    starts_at   timestamptz not null,
    -- Se guarda y no se calcula: la duración del servicio puede cambiar
    -- después, y la sesión ya pactada no.
    ends_at     timestamptz not null,
    created_at  timestamptz not null default now(),
    updated_at  timestamptz not null default now(),

    constraint pk_sessions primary key (id),
    -- El servicio tiene que prestarse en esa sede (HU-004)
    constraint fk_sessions_service_location foreign key (service_id, location_id) references service_locations (service_id, location_id) on delete restrict,
    constraint ck_sessions_rango check (ends_at > starts_at)
);

-- La reserva de un cliente en una sesión. El proveedor, el servicio, la
-- sede y el horario salen de la sesión. policy_id y currency_id sí se
-- guardan: congelan las condiciones y la moneda vigentes al reservar.
create table bookings (
    id           uuid          not null default gen_random_uuid(),
    code         varchar(64)   not null default f_codigo_reserva(),   -- [S3] HU-018, V11 del equipo
    client_id    uuid          not null,
    session_id   uuid          not null,
    policy_id    uuid          not null,
    attendees    integer       not null default 1,
    total_price  numeric(12,2) not null,
    currency_id  uuid          not null,
    status       varchar(20)   not null default 'RESERVED',
    cancelled_at timestamptz,
    created_at   timestamptz   not null default now(),
    updated_at   timestamptz   not null default now(),

    constraint pk_bookings primary key (id),
    -- [S3] Otra clave candidata: el código identifica la reserva igual que
    -- el id, así que bookings sigue en BCNF
    constraint uk_bookings_code    unique (code),

    constraint fk_bookings_client  foreign key (client_id)   references clients (id)               on delete restrict,
    constraint fk_bookings_session  foreign key (session_id)  references sessions (id)              on delete restrict,
    constraint fk_bookings_policy   foreign key (policy_id)   references organization_policies (id) on delete restrict,
    constraint fk_bookings_currency foreign key (currency_id) references currencies (id)            on delete restrict,

    constraint ck_bookings_attendees check (attendees > 0),
    constraint ck_bookings_price     check (total_price >= 0),
    constraint ck_bookings_status    check (status in ('RESERVED', 'CONFIRMED', 'CANCELLED', 'COMPLETED', 'NO_SHOW')),
    constraint ck_bookings_cancel    check ((status = 'CANCELLED') = (cancelled_at is not null)),
    constraint ck_bookings_code      check (code ~ '^RSV-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}$')
);

-- [S2 nueva] Recursos que ocupa una sesión. Reemplaza a booking_resources:
-- las reservas de un taller comparten el salón, así que el recurso es de
-- la sesión y no de cada reserva. Que un recurso no quede en dos sesiones
-- que se cruzan lo revisa tg_session_resources_reglas. Antes lo hacía un
-- EXCLUDE, pero necesitaba el horario copiado en esta tabla y esa copia
-- la dejaba en 1FN.
create table session_resources (
    session_id  uuid not null,
    resource_id uuid not null,
    constraint pk_session_resources          primary key (session_id, resource_id),
    constraint fk_session_resources_session  foreign key (session_id)  references sessions  (id) on delete cascade,
    constraint fk_session_resources_resource foreign key (resource_id) references resources (id) on delete restrict
);

create table booking_status_changes (
    id          uuid         not null default gen_random_uuid(),
    booking_id  uuid         not null,
    from_status varchar(20),
    to_status   varchar(20)  not null,
    reason      varchar(300),
    changed_by  uuid,
    changed_at  timestamptz  not null default now(),
    constraint pk_booking_status_changes         primary key (id),
    constraint fk_booking_status_changes_booking foreign key (booking_id) references bookings (id) on delete restrict,
    constraint ck_booking_status_changes_from    check (from_status is null or from_status in ('RESERVED','CONFIRMED','CANCELLED','COMPLETED','NO_SHOW')),
    constraint ck_booking_status_changes_to      check (to_status in ('RESERVED','CONFIRMED','CANCELLED','COMPLETED','NO_SHOW')),
    constraint ck_booking_status_changes_cambio  check (from_status is distinct from to_status),
    -- Cancelar exige motivo, y un motivo en blanco no cuenta
    constraint ck_booking_status_changes_reason  check (to_status <> 'CANCELLED' or length(btrim(coalesce(reason, ''))) > 0)
);

-- [S3 nueva] Cada vez que una reserva pasa a otro horario (HU-014). El
-- equipo guarda en bookings cuántas veces se reprogramó (reschedule_count,
-- V17) y si la última fue tardía (late_reschedule). Las dos se deducen de
-- esta tabla: la primera es un count(*) y la segunda compara
-- rescheduled_at con el inicio de la sesión de origen y la ventana de la
-- política. Guardarlas sería repetir un dato calculable, con el riesgo de
-- que el contador diga 1 y la historia tenga 2. Además, al pasar la
-- reserva a otra sesión se perdía de cuál venía.
create table booking_reschedules (
    id              uuid         not null default gen_random_uuid(),
    booking_id      uuid         not null,
    from_session_id uuid         not null,
    to_session_id   uuid         not null,
    reason          varchar(300),
    rescheduled_by  uuid,                        -- quien la movió: el cliente o alguien del proveedor
    rescheduled_at  timestamptz  not null default now(),
    constraint pk_booking_reschedules         primary key (id),
    constraint fk_booking_reschedules_booking foreign key (booking_id)      references bookings (id) on delete restrict,
    constraint fk_booking_reschedules_from    foreign key (from_session_id) references sessions (id) on delete restrict,
    constraint fk_booking_reschedules_to      foreign key (to_session_id)   references sessions (id) on delete restrict,
    constraint ck_booking_reschedules_cambio  check (from_session_id <> to_session_id),
    constraint ck_booking_reschedules_reason  check (reason is null or length(btrim(reason)) > 0)
);

-- Historia de estados de un proveedor (HU-003). Antes compartía tabla con
-- la de los clientes, con un tipo y dos FK de las que siempre una era nula.
create table organization_status_changes (
    id                uuid         not null default gen_random_uuid(),
    organization_id   uuid         not null,
    from_status       varchar(30),
    to_status         varchar(30)  not null,
    reason            varchar(500) not null,
    affected_bookings integer      not null default 0,   -- informe de HU-003 al suspender
    changed_by        uuid,
    changed_at        timestamptz  not null default now(),
    constraint pk_organization_status_changes     primary key (id),
    constraint fk_organization_status_changes_org foreign key (organization_id) references organizations (id) on delete restrict,
    constraint ck_organization_status_changes_from   check (from_status is null or from_status in ('PENDING_APPROVAL', 'ACTIVE', 'SUSPENDED', 'REJECTED')),
    constraint ck_organization_status_changes_to     check (to_status in ('PENDING_APPROVAL', 'ACTIVE', 'SUSPENDED', 'REJECTED')),
    constraint ck_organization_status_changes_reason check (length(btrim(reason)) > 0),
    constraint ck_organization_status_changes_count  check (affected_bookings >= 0)
);

create table client_status_changes (
    id          uuid         not null default gen_random_uuid(),
    client_id   uuid         not null,
    from_status varchar(30),
    to_status   varchar(30)  not null,
    reason      varchar(500) not null,
    changed_by  uuid,
    changed_at  timestamptz  not null default now(),
    constraint pk_client_status_changes        primary key (id),
    constraint fk_client_status_changes_client foreign key (client_id) references clients (id) on delete restrict,
    constraint ck_client_status_changes_from   check (from_status is null or from_status in ('PENDING_VERIFICATION', 'ACTIVE', 'SUSPENDED')),
    constraint ck_client_status_changes_to     check (to_status in ('PENDING_VERIFICATION', 'ACTIVE', 'SUSPENDED')),
    constraint ck_client_status_changes_reason check (length(btrim(reason)) > 0)
);

-- [S2 nueva] Calificación del cliente a una reserva ya atendida.
-- El cliente y el servicio no se copian: salen de la reserva.
create table booking_reviews (
    id         uuid          not null default gen_random_uuid(),
    booking_id uuid          not null,
    rating     smallint      not null,
    comment    varchar(1000),
    created_at timestamptz   not null default now(),
    updated_at timestamptz   not null default now(),
    constraint pk_booking_reviews         primary key (id),
    constraint uk_booking_reviews_booking unique (booking_id),   -- una reseña por reserva
    constraint fk_booking_reviews_booking foreign key (booking_id) references bookings (id) on delete restrict,
    constraint ck_booking_reviews_rating  check (rating between 1 and 5),
    constraint ck_booking_reviews_comment check (comment is null or length(btrim(comment)) > 0)
);

-- [S2 nueva] Cuando no hay cupo, el cliente se anota para un día. Si se
-- libera un espacio, se le avisa en orden de llegada (created_at).
create table waitlist_entries (
    id           uuid        not null default gen_random_uuid(),
    client_id    uuid        not null,
    service_id   uuid        not null,
    location_id  uuid        not null,
    desired_date date        not null,
    attendees    integer     not null default 1,
    status       varchar(20) not null default 'WAITING',
    booking_id   uuid,                          -- la reserva en que terminó
    notified_at  timestamptz,                   -- cuándo se le avisó del cupo
    created_at   timestamptz not null default now(),
    updated_at   timestamptz not null default now(),
    constraint pk_waitlist_entries                  primary key (id),
    constraint uk_waitlist_entries_booking          unique (booking_id),   -- una reserva sale de a lo sumo una espera
    constraint fk_waitlist_entries_client           foreign key (client_id) references clients (id) on delete cascade,
    constraint fk_waitlist_entries_service_location foreign key (service_id, location_id) references service_locations (service_id, location_id) on delete cascade,
    constraint fk_waitlist_entries_booking          foreign key (booking_id) references bookings (id) on delete restrict,
    constraint ck_waitlist_entries_attendees check (attendees > 0),
    constraint ck_waitlist_entries_status    check (status in ('WAITING', 'NOTIFIED', 'BOOKED', 'EXPIRED', 'CANCELLED')),
    -- Sólo la que se convirtió en reserva apunta a una
    constraint ck_waitlist_entries_booked    check ((status = 'BOOKED') = (booking_id is not null)),
    -- Quien ya fue avisado tiene fecha de aviso, para saber cuándo vence
    constraint ck_waitlist_entries_notified  check (status not in ('NOTIFIED', 'BOOKED', 'EXPIRED') or notified_at is not null)
);

-- [S2 nueva] Pagos de una reserva. Puede haber varios intentos (uno
-- falla, el siguiente pasa), pero sólo uno vivo a la vez: ver
-- ux_payments_vigente. amount y currency_id son lo que de verdad cobró
-- la pasarela, que no siempre coincide con el precio pactado: una
-- tarjeta internacional se cobra en otra moneda. Por eso no se derivan
-- de la reserva.
create table payments (
    id                 uuid          not null default gen_random_uuid(),
    booking_id         uuid          not null,
    amount             numeric(12,2) not null,
    currency_id        uuid          not null,
    method             varchar(20)   not null,
    status             varchar(20)   not null default 'PENDING',
    external_reference varchar(100),              -- referencia de la pasarela
    paid_at            timestamptz,
    refunded_at        timestamptz,
    created_at         timestamptz   not null default now(),
    updated_at         timestamptz   not null default now(),
    constraint pk_payments                    primary key (id),
    constraint uk_payments_external_reference unique (external_reference),
    constraint fk_payments_booking  foreign key (booking_id)  references bookings (id)   on delete restrict,
    constraint fk_payments_currency foreign key (currency_id) references currencies (id) on delete restrict,
    constraint ck_payments_amount check (amount > 0),
    constraint ck_payments_external_reference check (external_reference is null or length(btrim(external_reference)) > 0),
    constraint ck_payments_method check (method in ('CARD', 'BANK_TRANSFER', 'CASH')),
    constraint ck_payments_status check (status in ('PENDING', 'PAID', 'FAILED', 'REFUNDED')),
    -- Cada estado con sus fechas: no hay pago sin fecha ni reembolso de algo no pagado
    constraint ck_payments_fechas check (
        (status in ('PENDING', 'FAILED') and paid_at is null     and refunded_at is null) or
        (status = 'PAID'                 and paid_at is not null and refunded_at is null) or
        (status = 'REFUNDED'             and paid_at is not null and refunded_at is not null
                                         and refunded_at >= paid_at))
);


-- =====================================================================
--  7. Notificaciones
-- =====================================================================

-- Render bloquea SMTP (ADR-0007), así que el correo se guarda aquí. El
-- destinatario no es FK: puede ser una dirección que no es de un cliente.
create table sent_emails (
    id         uuid         not null default gen_random_uuid(),
    recipient  varchar(160) not null,
    subject    varchar(200) not null,
    body       text         not null,
    sent_at    timestamptz  not null default now(),
    constraint pk_sent_emails           primary key (id),
    constraint ck_sent_emails_recipient check (recipient ~* '^[^@[:space:]]+@[^@[:space:]]+\.[a-z]{2,}$'),
    constraint ck_sent_emails_subject   check (length(btrim(subject)) > 0)
);

-- [S3 nueva] Con cuánta anticipación quiere cada proveedor que se le
-- recuerde la cita al cliente (HU-015, V12 del equipo): 1440 y 120 son
-- "un día antes y dos horas antes". Un recordatorio por fila, en vez de
-- una lista en una columna, para que cada valor sea atómico.
create table organization_booking_reminders (
    organization_id uuid        not null,
    minutes_before  integer     not null,
    created_at      timestamptz not null default now(),
    constraint pk_organization_booking_reminders         primary key (organization_id, minutes_before),
    constraint fk_organization_booking_reminders_org     foreign key (organization_id) references organizations (id) on delete cascade,
    -- Entre un cuarto de hora y una semana antes
    constraint ck_organization_booking_reminders_minutes check (minutes_before between 15 and 10080)
);

-- [S3 nueva] Cola de avisos de una reserva (HU-015). La llena
-- tg_bookings_avisos, no la aplicación: un aviso inmediato cuando la
-- reserva se crea, se confirma, se cancela o se reprograma, y uno por
-- cada recordatorio del proveedor. El backend envía los que ya vencieron
-- por el canal que eligió el cliente y les pone processed_at.
create table booking_notices (
    id           uuid        not null default gen_random_uuid(),
    booking_id   uuid        not null,
    kind         varchar(20) not null,
    due_at       timestamptz not null,           -- cuándo se debe enviar
    processed_at timestamptz,                    -- nulo = pendiente
    created_at   timestamptz not null default now(),
    constraint pk_booking_notices         primary key (id),
    constraint fk_booking_notices_booking foreign key (booking_id) references bookings (id) on delete restrict,
    constraint ck_booking_notices_kind    check (kind in ('CREATED', 'CONFIRMED', 'CANCELLED', 'RESCHEDULED', 'REMINDER')),
    constraint ck_booking_notices_proceso check (processed_at is null or processed_at >= created_at)
);


-- =====================================================================
--  8. Reportes y auditoría
-- =====================================================================

-- [S2 nueva] Resumen diario de ocupación por recurso, para los "reportes
-- sobre ocupación y uso" del caso. Es un dato derivado a propósito, como
-- en un data mart: lo llena fn_calcular_ocupacion una vez al día, y así
-- el reporte de un mes lee 30 filas por recurso en vez de todas las reservas.
create table resource_occupancy_daily (
    resource_id       uuid        not null,
    occupancy_date    date        not null,
    available_minutes integer     not null,
    booked_minutes    integer     not null,
    sessions_count    integer     not null,
    calculated_at     timestamptz not null default now(),
    constraint pk_resource_occupancy_daily          primary key (resource_id, occupancy_date),
    constraint fk_resource_occupancy_daily_resource foreign key (resource_id) references resources (id) on delete cascade,
    constraint ck_resource_occupancy_daily_minutos  check (available_minutes >= 0 and booked_minutes >= 0 and sessions_count >= 0)
);

-- [S2 nueva] Quién cambió qué. La llena un trigger, no la aplicación,
-- así que nadie puede saltársela. Sólo el administrador la lee.
create table audit_log (
    id          bigint       generated always as identity,
    table_name  varchar(63)  not null,
    operation   varchar(6)   not null,
    record_id   text         not null,         -- la clave primaria; si es compuesta, separada por /
    db_user     varchar(63)  not null default session_user,
    app_user_id uuid,                          -- el usuario de la app, si la sesión lo informa
    changed_at  timestamptz  not null default now(),
    constraint pk_audit_log           primary key (id),
    constraint ck_audit_log_operation check (operation in ('INSERT', 'UPDATE', 'DELETE')),
    constraint ck_audit_log_table     check (length(btrim(table_name)) > 0)
);

-- [S2 nueva] Una fila por cada columna que cambió. Antes el antes y el
-- después de la fila completa iban en dos jsonb, que no son valores
-- atómicos: audit_log no estaba ni en 1FN.
create table audit_log_changes (
    audit_log_id bigint      not null,
    column_name  varchar(63) not null,
    old_value    text,                         -- nulo en un INSERT o si la columna estaba vacía
    new_value    text,                         -- nulo en un DELETE o si la columna quedó vacía
    constraint pk_audit_log_changes        primary key (audit_log_id, column_name),
    constraint fk_audit_log_changes_audit  foreign key (audit_log_id) references audit_log (id) on delete cascade,
    constraint ck_audit_log_changes_cambio check (old_value is distinct from new_value)
);


-- =====================================================================
--  9. Funciones y triggers
--  Reglas que cruzan tablas: un CHECK no admite subconsultas.
-- =====================================================================

create or replace function fn_set_updated_at() returns trigger
language plpgsql as $$
begin
    new.updated_at := now();
    return new;
end $$;

-- HU-001: no se permite el autorregistro de menores de 18 años. Se mira
-- al escribir la fila, que es cuando la regla tiene sentido.
create or replace function fn_clients_mayor_de_edad() returns trigger
language plpgsql as $$
begin
    if new.birth_date > current_date - interval '18 years' then
        raise exception 'HU-001: el cliente debe ser mayor de edad (nació el %)', new.birth_date;
    end if;
    return new;
end $$;

-- Reglas de una reserva (HU-001, HU-002, HU-004). Cada una mira sólo el
-- cambio que la afecta, para que suspender un proveedor no deje sus
-- reservas sin poder cancelarse (V3 del equipo).
create or replace function fn_bookings_reglas() returns trigger
language plpgsql as $$
declare
    v_cliente  varchar(30);
    v_org      varchar(30);
    v_servicio varchar(20);
    v_sede     varchar(20);
    v_cupo     integer;
    v_ocupado  integer;
    v_entra    boolean;   -- pasa a ocupar cupo: se crea
    v_mueve    boolean;   -- se pasa a otra sesión
    v_crece    boolean;   -- suma asistentes
begin
    -- La vida de una reserva: nace RESERVED o CONFIRMED y de ahí sólo
    -- avanza. CANCELLED, COMPLETED y NO_SHOW son finales, así que una
    -- reserva atendida, con su reseña, ya no se puede cancelar.
    if tg_op = 'INSERT' and new.status not in ('RESERVED', 'CONFIRMED') then
        raise exception 'Una reserva nace RESERVED o CONFIRMED, no %', new.status;
    end if;
    if tg_op = 'UPDATE' and new.status <> old.status and not (
           (old.status = 'RESERVED'  and new.status in ('CONFIRMED', 'CANCELLED', 'NO_SHOW')) or
           (old.status = 'CONFIRMED' and new.status in ('CANCELLED', 'COMPLETED', 'NO_SHOW'))) then
        raise exception 'Una reserva no pasa de % a %', old.status, new.status;
    end if;

    if new.status not in ('RESERVED', 'CONFIRMED') then
        return new;
    end if;

    if tg_op = 'INSERT' then
        v_entra := true;
        v_mueve := false;
        v_crece := false;
    else
        v_entra := false;
        v_mueve := new.session_id <> old.session_id;
        v_crece := new.attendees > old.attendees;
    end if;

    if v_entra or v_mueve then
        select o.status, s.status, l.status into v_org, v_servicio, v_sede
          from sessions se
              inner join services      s on s.id = se.service_id
              inner join organizations o on o.id = s.organization_id
              inner join locations     l on l.id = se.location_id
         where se.id = new.session_id;
        if v_org <> 'ACTIVE' then
            raise exception 'HU-002: el proveedor está en estado %, no es reservable', v_org;
        end if;
        if v_servicio <> 'ACTIVE' then
            raise exception 'HU-004: el servicio está inactivo, no admite reservas nuevas';
        end if;
        if v_sede <> 'ACTIVE' then
            raise exception 'La sede de la sesión % está inactiva', new.session_id;
        end if;
    end if;

    if v_entra and (select status from clients where id = new.client_id) = 'SUSPENDED' then
        raise exception 'HU-003: un cliente suspendido no puede reservar';
    end if;

    if new.status = 'CONFIRMED' and (tg_op = 'INSERT' or old.status <> 'CONFIRMED') then
        select status into v_cliente from clients where id = new.client_id;
        if v_cliente <> 'ACTIVE' then
            raise exception 'HU-001: sólo un cliente verificado puede confirmar una reserva (estado %)', v_cliente;
        end if;
    end if;

    if v_entra or v_mueve or v_crece then
        -- Sin este candado, dos reservas simultáneas por el último cupo
        -- sumaban el mismo ocupado y entraban las dos. Con él, la segunda
        -- espera a que la primera termine su transacción, y como en READ
        -- COMMITTED cada sentencia toma una instantánea nueva, su suma ya
        -- incluye la primera. Se libera solo al terminar la transacción.
        perform pg_advisory_xact_lock(hashtextextended(new.session_id::text, 0));

        select s.customer_capacity into v_cupo
          from sessions se
              inner join services s on s.id = se.service_id
         where se.id = new.session_id;

        select coalesce(sum(attendees), 0) into v_ocupado
          from bookings
         where session_id = new.session_id
           and status in ('RESERVED', 'CONFIRMED')
           and id <> new.id;

        if v_ocupado + new.attendees > v_cupo then
            raise exception 'HU-004: aforo superado: % ocupados + % solicitados > cupo %',
                  v_ocupado, new.attendees, v_cupo;
        end if;
    end if;

    return new;
end $$;

-- Lo que antes garantizaban las FK compuestas con organization_id y
-- location_id repetidos. Todas tienen la misma forma: dos cosas que se
-- relacionan tienen que ser del mismo proveedor, o estar en la misma sede.
-- Si alguna de las dos no existe, la regla no opina: ese error lo da la FK.

create or replace function fn_service_locations_mismo_proveedor() returns trigger
language plpgsql as $$
declare
    v_servicio uuid := (select organization_id from services  where id = new.service_id);
    v_sede     uuid := (select organization_id from locations where id = new.location_id);
begin
    if v_servicio <> v_sede then
        raise exception 'El servicio % y la sede % son de proveedores distintos', new.service_id, new.location_id;
    end if;
    return new;
end $$;

create or replace function fn_service_resource_requirements_mismo_proveedor() returns trigger
language plpgsql as $$
declare
    v_servicio uuid := (select organization_id from services       where id = new.service_id);
    v_tipo     uuid := (select organization_id from resource_types where id = new.resource_type_id);
begin
    if v_servicio <> v_tipo then
        raise exception 'El servicio % y el tipo de recurso % son de proveedores distintos', new.service_id, new.resource_type_id;
    end if;
    return new;
end $$;

-- Un recurso: su tipo y su sede son del mismo proveedor. Y si ya tiene
-- sesiones o agenda propia, no se cambia de sede: esas sesiones quedarían
-- en una sede donde el recurso no estaba, y la agenda con servicios que
-- quizá no se prestan en la nueva. Se retira y se crea otro.
create or replace function fn_resources_coherencia() returns trigger
language plpgsql as $$
declare
    v_tipo uuid := (select organization_id from resource_types where id = new.resource_type_id);
    v_sede uuid := (select organization_id from locations      where id = new.location_id);
begin
    if v_tipo <> v_sede then
        raise exception 'El tipo de recurso % y la sede % son de proveedores distintos', new.resource_type_id, new.location_id;
    end if;
    if tg_op = 'UPDATE' and new.location_id <> old.location_id
       and (exists (select 1 from session_resources where resource_id = new.id) or
            exists (select 1 from agendas           where resource_id = new.id)) then
        raise exception 'El recurso % ya tiene sesiones o agenda: no se cambia de sede, se retira y se crea otro', new.id;
    end if;
    return new;
end $$;

-- El proveedor de una sede, un servicio o un tipo de recurso no cambia.
-- Así las reglas de "mismo proveedor" no se pueden romper desde arriba.
create or replace function fn_proveedor_inmutable() returns trigger
language plpgsql as $$
begin
    if new.organization_id <> old.organization_id then
        raise exception '%: el proveedor de un registro no cambia', tg_table_name;
    end if;
    return new;
end $$;

-- La sede de una agenda: la suya, o la de su recurso
create or replace function f_sede_de_agenda(p_location_id uuid, p_resource_id uuid) returns uuid
language sql stable as $$
    select coalesce(p_location_id, (select location_id from resources where id = p_resource_id))
$$;

-- El servicio tiene que prestarse en la sede de la agenda (HU-006)
create or replace function fn_agenda_services_en_sede() returns trigger
language plpgsql as $$
begin
    if not exists (select 1
                     from agendas a
                         inner join service_locations sl on sl.location_id = f_sede_de_agenda(a.location_id, a.resource_id)
                    where a.id = new.agenda_id
                      and sl.service_id = new.service_id) then
        raise exception 'El servicio % no se presta en la sede de la agenda %', new.service_id, new.agenda_id;
    end if;
    return new;
end $$;

-- Si una agenda cambia de sede o de recurso, sus servicios tienen que
-- prestarse en la sede nueva
create or replace function fn_agendas_servicios_en_sede() returns trigger
language plpgsql as $$
declare
    v_sede uuid := f_sede_de_agenda(new.location_id, new.resource_id);
begin
    if exists (select 1
                 from agenda_services ags
                where ags.agenda_id = new.id
                  and not exists (select 1 from service_locations sl
                                   where sl.service_id = ags.service_id
                                     and sl.location_id = v_sede)) then
        raise exception 'La agenda % tiene servicios que no se prestan en la sede %', new.id, v_sede;
    end if;
    return new;
end $$;

-- Un servicio que deja de prestarse en una sede deja de ser reservable en
-- las agendas de esa sede. También si la fila se edita en vez de borrarse.
create or replace function fn_service_locations_quita_de_agendas() returns trigger
language plpgsql as $$
begin
    if tg_op = 'UPDATE' and (new.service_id, new.location_id) = (old.service_id, old.location_id) then
        return null;
    end if;
    delete from agenda_services ags
     using agendas a
     where a.id = ags.agenda_id
       and f_sede_de_agenda(a.location_id, a.resource_id) = old.location_id
       and ags.service_id = old.service_id;
    return old;
end $$;

-- Una reserva: la política es del proveedor del servicio, el precio se
-- pacta en la moneda del servicio y ya no cambia de moneda, y si la
-- reserva se pasa a otra sesión, es del mismo servicio. Cambiar de
-- servicio es cancelar y reservar otra vez.
create or replace function fn_bookings_coherencia() returns trigger
language plpgsql as $$
declare
    v_servicio     uuid;
    v_org_servicio uuid;
    v_moneda       uuid;
begin
    select s.id, s.organization_id, s.currency_id into v_servicio, v_org_servicio, v_moneda
      from sessions se
          inner join services s on s.id = se.service_id
     where se.id = new.session_id;

    if (select organization_id from organization_policies where id = new.policy_id) <> v_org_servicio then
        raise exception 'La política % no es del proveedor del servicio %', new.policy_id, v_servicio;
    end if;
    if tg_op = 'INSERT' then
        -- La versión que regía cuando se hizo la reserva (HU-002)
        if not exists (select 1 from organization_policies p
                        where p.id = new.policy_id
                          and p.effective_from <= new.created_at
                          and (p.replaced_at is null or p.replaced_at > new.created_at)) then
            raise exception 'La política % no estaba vigente al crear la reserva', new.policy_id;
        end if;
        if new.currency_id <> v_moneda then
            raise exception 'El precio se pacta en la moneda del servicio';
        end if;
    end if;
    if tg_op = 'UPDATE' and new.policy_id <> old.policy_id then
        raise exception 'Las condiciones pactadas de una reserva no cambian';
    end if;
    if tg_op = 'UPDATE' and new.currency_id <> old.currency_id then
        raise exception 'La moneda del precio pactado no cambia';
    end if;
    if tg_op = 'UPDATE' and new.session_id <> old.session_id then
        if v_servicio <> (select service_id from sessions where id = old.session_id) then
            raise exception 'La reserva % sólo se puede pasar a otra sesión del mismo servicio', new.id;
        end if;
        -- Si salió de una lista de espera, sigue en la sede que se esperaba
        if exists (select 1 from waitlist_entries w
                       inner join sessions se on se.id = new.session_id
                    where w.booking_id = new.id
                      and w.location_id <> se.location_id) then
            raise exception 'La reserva % salió de una lista de espera de otra sede', new.id;
        end if;
    end if;
    return new;
end $$;

-- Una sesión no cambia de servicio, y si cambia de sede o de horario, sus
-- recursos tienen que estar en la sede nueva y libres en el horario nuevo.
create or replace function fn_sessions_coherencia() returns trigger
language plpgsql as $$
declare
    v_recurso uuid;
begin
    if new.service_id <> old.service_id then
        raise exception 'La sesión % no cambia de servicio: se cancela y se crea otra', new.id;
    end if;

    -- [S3] HU-014: una sesión con reservas no se mueve de hora ni de sede.
    -- Si están vigentes, moverla pasaría a sus clientes a otra hora sin la
    -- anticipación de HU-012, sin el tope ni la historia de HU-014, sin
    -- revisar sus cruces y con los recordatorios de HU-015 a la hora vieja:
    -- lo que se mueve es cada reserva, con sp_reprogramar_reserva. Si ya se
    -- cerraron, moverla reescribiría la historia: una cancelación tardía
    -- dejaría de serlo y la ocupación de ese día cambiaría.
    if ((new.starts_at, new.ends_at, new.location_id) is distinct from (old.starts_at, old.ends_at, old.location_id))
       and exists (select 1 from bookings where session_id = new.id) then
        raise exception 'HU-014: la sesión % tiene reservas; se reprograma cada reserva, no la sesión', new.id;
    end if;

    if new.location_id <> old.location_id
       and exists (select 1 from session_resources sr
                       inner join resources r on r.id = sr.resource_id
                    where sr.session_id = new.id
                      and r.location_id <> new.location_id) then
        raise exception 'La sesión % tiene recursos de otra sede', new.id;
    end if;

    if (new.starts_at, new.ends_at) is distinct from (old.starts_at, old.ends_at) then
        -- El mismo candado por recurso de tg_session_resources_reglas, tomado
        -- en orden para que dos sesiones que se mueven a la vez no se
        -- bloqueen la una a la otra.
        for v_recurso in select resource_id from session_resources where session_id = new.id order by resource_id loop
            perform pg_advisory_xact_lock(hashtextextended(v_recurso::text, 1));
        end loop;

        if exists (select 1
                     from session_resources mio
                         inner join session_resources otra on otra.resource_id = mio.resource_id
                                                          and otra.session_id <> mio.session_id
                         inner join sessions          s    on s.id = otra.session_id
                    where mio.session_id = new.id
                      and s.starts_at < new.ends_at
                      and s.ends_at   > new.starts_at) then
            raise exception 'Al mover la sesión % uno de sus recursos queda ocupado dos veces', new.id;
        end if;
    end if;
    return new;
end $$;

-- Un recurso asignado a una sesión: está en la sede de la sesión y no
-- está ocupado por otra sesión que se cruce con ella.
create or replace function fn_session_resources_reglas() returns trigger
language plpgsql as $$
declare
    v_sede   uuid;
    v_inicio timestamptz;
    v_fin    timestamptz;
begin
    -- for share: si otra transacción está moviendo la sesión, se espera a
    -- que termine y se lee el horario nuevo
    select location_id, starts_at, ends_at into v_sede, v_inicio, v_fin
      from sessions where id = new.session_id
       for share;

    if (select location_id from resources where id = new.resource_id) <> v_sede then
        raise exception 'El recurso % no está en la sede de la sesión %', new.resource_id, new.session_id;
    end if;
    if (select status from resources where id = new.resource_id) = 'RETIRED' then
        raise exception 'El recurso % está retirado', new.resource_id;
    end if;

    -- Dos asignaciones simultáneas del mismo recurso se turnan: la segunda
    -- espera a que la primera termine, y como en READ COMMITTED cada
    -- sentencia toma una instantánea nueva, su consulta ya la ve.
    perform pg_advisory_xact_lock(hashtextextended(new.resource_id::text, 1));

    if exists (select 1
                 from session_resources sr
                     inner join sessions s on s.id = sr.session_id
                where sr.resource_id = new.resource_id
                  and sr.session_id <> new.session_id
                  and s.starts_at < v_fin
                  and s.ends_at   > v_inicio) then
        raise exception 'El recurso % ya está ocupado por otra sesión en ese horario', new.resource_id;
    end if;
    return new;
end $$;

-- Cuando se cancela la última reserva viva de una sesión, o se pasa a otra
-- sesión, la sesión suelta sus recursos para que otro los pueda tomar.
-- Las atendidas y las de inasistencia los conservan: son historia y
-- cuentan en la ocupación, porque el recurso estuvo apartado. Como una
-- reserva cancelada ya no vuelve a activarse, la sesión no recupera nada. Es security definer porque rol_app no tiene
-- permiso de borrar en session_resources.
create or replace function fn_sessions_libera_recursos() returns trigger
language plpgsql security definer set search_path = public as $$
begin
    if (new.status = 'CANCELLED' and old.status <> 'CANCELLED') or new.session_id <> old.session_id then
        -- El candado del cupo: así nadie entra a la sesión mientras se suelta
        perform pg_advisory_xact_lock(hashtextextended(old.session_id::text, 0));
        if not exists (select 1 from bookings
                        where session_id = old.session_id
                          and status <> 'CANCELLED') then
            delete from session_resources where session_id = old.session_id;
        end if;
    end if;
    return null;
end $$;

-- HU-003: cambiar el estado de un proveedor exige dejar el motivo en la
-- misma transacción, con el estado de origen y el de destino. now() es la
-- hora de inicio de la transacción, así que un motivo viejo, o uno
-- fechado a mano en el futuro, no autoriza nada.
create or replace function fn_exige_motivo_cuenta() returns trigger
language plpgsql as $$
begin
    if new.status is distinct from old.status
       and not exists (
           select 1 from organization_status_changes c
            where c.organization_id = new.id
              and c.from_status is not distinct from old.status
              and c.to_status = new.status
              and c.changed_at = now()) then
        raise exception
          'HU-003: cambiar el estado a % exige registrar el motivo en organization_status_changes', new.status;
    end if;
    return new;
end $$;

-- Búsqueda sin mayúsculas ni tildes (HU-005, V9 del equipo)
create or replace function f_sin_tildes(texto text) returns text
language sql immutable strict parallel safe as $$
    select translate(lower(texto),
                     'áàäâãéèëêíìïîóòöôõúùüûñç',
                     'aaaaaeeeeiiiiooooouuuunc')
$$;

-- [S2 nueva] Sólo se califica lo que ya se atendió
create or replace function fn_booking_reviews_completada() returns trigger
language plpgsql as $$
declare
    v_estado varchar(20);
begin
    select status into v_estado from bookings where id = new.booking_id;
    if v_estado is distinct from 'COMPLETED' then
        raise exception 'Sólo se puede calificar una reserva completada (estado %)', v_estado;
    end if;
    return new;
end $$;

-- [S2 nueva] La reserva en que terminó una espera tiene que ser de ese
-- cliente, de ese servicio y en esa sede.
create or replace function fn_waitlist_entries_reserva() returns trigger
language plpgsql as $$
begin
    if new.booking_id is not null and not exists (
           select 1 from bookings b
               inner join sessions se on se.id = b.session_id
            where b.id = new.booking_id
              and b.client_id    = new.client_id
              and se.service_id  = new.service_id
              and se.location_id = new.location_id) then
        raise exception 'La reserva % no es del mismo cliente, servicio y sede de la lista de espera', new.booking_id;
    end if;
    return new;
end $$;

-- [S2 nueva] Auditoría genérica. Es security definer para que escriba en
-- audit_log aunque quien hizo el cambio no tenga permiso sobre esa tabla.
-- La aplicación puede informar su usuario con: set local app.user_id = '<uuid>'
-- Pasa la fila a jsonb sólo para compararla columna por columna; lo que
-- guarda son valores sueltos, uno por fila de audit_log_changes.
create or replace function fn_auditar() returns trigger
language plpgsql security definer set search_path = public as $$
declare
    v_old   jsonb;
    v_new   jsonb;
    v_id    text;
    v_app   uuid;
    v_audit bigint;
begin
    if tg_op in ('UPDATE', 'DELETE') then v_old := to_jsonb(old); end if;
    if tg_op in ('INSERT', 'UPDATE') then v_new := to_jsonb(new); end if;

    -- Un update que sólo toca updated_at no cambió nada que importe
    if tg_op = 'UPDATE' and v_old - 'updated_at' = v_new - 'updated_at' then
        return null;
    end if;

    -- La clave primaria de la fila, sirva para cualquier tabla
    select string_agg(coalesce(v_new, v_old) ->> a.attname, '/' order by k.orden)
      into v_id
      from pg_index i
          cross join lateral unnest(i.indkey) with ordinality as k(attnum, orden)
          inner join pg_attribute a on a.attrelid = i.indrelid and a.attnum = k.attnum
     where i.indrelid = tg_relid
       and i.indisprimary;

    begin
        v_app := nullif(current_setting('app.user_id', true), '')::uuid;
    exception when others then
        v_app := null;  -- un valor mal formado no debe tumbar la transacción
    end;

    insert into audit_log (table_name, operation, record_id, db_user, app_user_id)
    values (tg_table_name, tg_op, v_id, session_user, v_app)
    returning id into v_audit;

    -- Un alta guarda las columnas con valor, una baja las que tenía y un
    -- cambio sólo las que cambiaron
    insert into audit_log_changes (audit_log_id, column_name, old_value, new_value)
    select v_audit, k.columna, v_old ->> k.columna, v_new ->> k.columna
      from jsonb_object_keys(coalesce(v_new, v_old)) as k(columna)
     where k.columna <> 'updated_at'
       and (v_old ->> k.columna) is distinct from (v_new ->> k.columna);
    return null;
end $$;

-- [S2 nueva] Llena resource_occupancy_daily para un día. Disponible = los
-- bloques de la agenda propia del recurso menos lo que cierran las
-- excepciones. Ocupado = las sesiones de ese día con alguna reserva no
-- cancelada (también la inasistencia: el recurso quedó apartado),
-- contadas en la zona horaria de la sede. Una sesión grupal
-- cuenta una vez, aunque tenga varias reservas. Se puede repetir:
-- reescribe el día.
create or replace function fn_calcular_ocupacion(p_dia date) returns integer
language plpgsql as $$
declare
    n integer;
begin
    insert into resource_occupancy_daily as rod
           (resource_id, occupancy_date, available_minutes, booked_minutes, sessions_count)
    select r.id,
           p_dia,
           coalesce(disp.minutos, 0),
           coalesce(uso.minutos, 0),
           coalesce(uso.sesiones, 0)
    from resources r
        inner join locations     l on l.id = r.location_id
        inner join organizations o on o.id = l.organization_id
        left join lateral (
            select sum(extract(epoch from s.end_time - s.start_time) / 60
                       - coalesce((select sum(extract(epoch from upper(cruce) - lower(cruce)) / 60)
                                     from agenda_exceptions e,
                                          lateral (select timerange(s.start_time, s.end_time)
                                                        * timerange(coalesce(e.start_time, time '00:00'),
                                                                    coalesce(e.end_time,   time '24:00')) as cruce) x
                                    where e.agenda_id = a.id
                                      and e.exception_date = p_dia
                                      and not isempty(cruce)), 0))::integer as minutos
            from agendas a
                inner join schedules s on s.agenda_id = a.id and s.active
            where a.resource_id = r.id
              and s.day_of_week = extract(isodow from p_dia)
              and p_dia >= a.valid_from
              and (a.valid_until is null or p_dia <= a.valid_until)
        ) disp on true
        left join lateral (
            select (sum(extract(epoch from se.ends_at - se.starts_at)) / 60)::integer as minutos,
                   count(*)::integer as sesiones
            from session_resources sr
                inner join sessions se on se.id = sr.session_id
            where sr.resource_id = r.id
              and (se.starts_at at time zone coalesce(l.timezone, o.timezone))::date = p_dia
              and exists (select 1 from bookings b
                           where b.session_id = se.id
                             and b.status <> 'CANCELLED')
        ) uso on true
    where r.status = 'ACTIVE'
    on conflict (resource_id, occupancy_date) do update
       set available_minutes = excluded.available_minutes,
           booked_minutes    = excluded.booked_minutes,
           sessions_count    = excluded.sessions_count,
           calculated_at     = now();

    get diagnostics n = row_count;
    return n;
end $$;

-- ---------------------------------------------------------------------
--  [S3] Triggers del ciclo de vida de la reserva
-- ---------------------------------------------------------------------

-- HU-012 y HU-014: la cita cae dentro de la ventana de anticipación de la
-- política, ni muy pronto ni muy lejos. Al crear se mide desde created_at,
-- para que una reserva cargada como historia se juzgue con su fecha; al
-- reprogramar, desde ahora. Las reservas que nacen cerradas son historia.
create or replace function fn_bookings_anticipacion() returns trigger
language plpgsql as $$
declare
    v_inicio timestamptz;
    v_min    integer;
    v_max    integer;
    v_desde  timestamptz;
    v_hu     text;
begin
    if new.status not in ('RESERVED', 'CONFIRMED')
       or (tg_op = 'UPDATE' and new.session_id = old.session_id) then
        return new;
    end if;

    select starts_at into v_inicio from sessions where id = new.session_id;
    select booking_notice_minutes_min, booking_notice_minutes_max into v_min, v_max
      from organization_policies where id = new.policy_id;

    if tg_op = 'INSERT' then
        v_desde := new.created_at;
        v_hu    := 'HU-012';
    else
        v_desde := now();
        v_hu    := 'HU-014';
    end if;

    if v_inicio < v_desde + make_interval(mins => v_min) then
        raise exception '%: la cita se reserva con al menos % minutos de anticipación', v_hu, v_min;
    end if;
    if v_inicio > v_desde + make_interval(mins => v_max) then
        raise exception '%: la cita se reserva con máximo % minutos de anticipación', v_hu, v_max;
    end if;
    return new;
end $$;

-- HU-012: un cliente no tiene dos reservas vivas que se crucen en el
-- tiempo, aunque sean de proveedores distintos. Para sumar personas a un
-- taller se aumentan los asistentes de la reserva que ya tiene. El
-- candado por cliente evita que dos pestañas reserven a la vez.
create or replace function fn_bookings_cruce_cliente() returns trigger
language plpgsql as $$
declare
    v_inicio timestamptz;
    v_fin    timestamptz;
begin
    if new.status not in ('RESERVED', 'CONFIRMED')
       or (tg_op = 'UPDATE' and new.session_id = old.session_id
                            and old.status in ('RESERVED', 'CONFIRMED')) then
        return new;
    end if;

    perform pg_advisory_xact_lock(hashtextextended(new.client_id::text, 2));

    select starts_at, ends_at into v_inicio, v_fin from sessions where id = new.session_id;

    if exists (select 1
                 from bookings b
                     inner join sessions s on s.id = b.session_id
                where b.client_id = new.client_id
                  and b.id <> new.id
                  and b.status in ('RESERVED', 'CONFIRMED')
                  and s.starts_at < v_fin
                  and s.ends_at   > v_inicio) then
        raise exception 'HU-012: el cliente ya tiene otra reserva que se cruza con ese horario';
    end if;
    return new;
end $$;

-- HU-013 y HU-016: cada estado tiene su momento. Una cita que ya empezó
-- no se cancela: se cierra como atendida o como inasistencia. Y la
-- asistencia no se registra antes de que la cita empiece.
create or replace function fn_bookings_momento_del_estado() returns trigger
language plpgsql as $$
declare
    v_inicio timestamptz;
begin
    -- Los cambios desde un estado cerrado los rechaza fn_bookings_reglas
    if new.status = old.status or old.status not in ('RESERVED', 'CONFIRMED') then
        return new;
    end if;
    select starts_at into v_inicio from sessions where id = new.session_id;

    if new.status = 'CANCELLED' and v_inicio <= now() then
        raise exception 'HU-013: la cita ya empezó; se cierra como atendida o como inasistencia, no se cancela';
    end if;
    if new.status in ('COMPLETED', 'NO_SHOW') and v_inicio > now() then
        raise exception 'HU-016: la asistencia se registra cuando la cita ya empezó (empieza el %)', v_inicio;
    end if;
    -- La hora de la cancelación la pone la base, no quien cancela: de ella
    -- sale si la cancelación fue tardía (HU-013)
    if new.status = 'CANCELLED' then
        new.cancelled_at := now();
    end if;
    return new;
end $$;

-- HU-013 y HU-016: un cambio de estado deja su rastro en
-- booking_status_changes en la misma transacción, con el estado de origen
-- y el de destino. Para una cancelación, ck_booking_status_changes_reason
-- exige además el motivo. Es la misma idea de fn_exige_motivo_cuenta
-- (HU-003): now() es la hora de inicio de la transacción, así que una
-- fila vieja no sirve.
create or replace function fn_bookings_exige_historial() returns trigger
language plpgsql as $$
begin
    if new.status is distinct from old.status
       and not exists (
           select 1 from booking_status_changes c
            where c.booking_id = new.id
              and c.from_status is not distinct from old.status
              and c.to_status  = new.status
              and c.changed_at = now()) then
        raise exception '%: pasar la reserva a % exige registrar el cambio en booking_status_changes',
              case new.status when 'CANCELLED' then 'HU-013' else 'HU-016' end, new.status;
    end if;
    return null;
end $$;

-- HU-014: una reprogramación parte de la sesión actual de una reserva
-- viva, va a otra sesión del mismo servicio y en la misma sede, y no pasa
-- el tope de la política que congeló la reserva. El for update serializa
-- dos reprogramaciones simultáneas de la misma reserva: sin él, las dos
-- contarían las mismas filas y la segunda se saltaría el tope.
create or replace function fn_booking_reschedules_reglas() returns trigger
language plpgsql as $$
declare
    v_estado  varchar(20);
    v_sesion  uuid;
    v_max     integer;
    v_hechas  integer;
begin
    select b.status, b.session_id, p.max_reschedules into v_estado, v_sesion, v_max
      from bookings b
          inner join organization_policies p on p.id = b.policy_id
     where b.id = new.booking_id
       for update of b;

    if v_estado not in ('RESERVED', 'CONFIRMED') then
        raise exception 'HU-014: sólo se reprograma una reserva vigente (está en %)', v_estado;
    end if;
    if new.from_session_id <> v_sesion then
        raise exception 'HU-014: la reprogramación parte de la sesión actual de la reserva';
    end if;
    if not exists (select 1
                     from sessions de
                         inner join sessions a on a.service_id  = de.service_id
                                              and a.location_id = de.location_id
                    where de.id = new.from_session_id
                      and a.id  = new.to_session_id) then
        raise exception 'HU-014: se reprograma al mismo servicio y en la misma sede; para cambiarlos se cancela y se reserva otra vez';
    end if;

    select count(*) into v_hechas from booking_reschedules where booking_id = new.booking_id;
    if v_hechas >= v_max then
        raise exception 'HU-014: la reserva llegó al tope de su política: % reprogramación(es)', v_max;
    end if;
    return new;
end $$;

-- HU-014: pasar una reserva a otra sesión exige dejar la reprogramación
-- en booking_reschedules en la misma transacción. Así las reglas de
-- arriba no se pueden saltar con un update directo.
create or replace function fn_bookings_exige_reprogramacion() returns trigger
language plpgsql as $$
begin
    if new.session_id <> old.session_id
       and not exists (
           select 1 from booking_reschedules r
            where r.booking_id      = new.id
              and r.from_session_id = old.session_id
              and r.to_session_id   = new.session_id
              and r.rescheduled_at  = now()) then
        raise exception 'HU-014: pasar la reserva a otra sesión exige registrar la reprogramación en booking_reschedules';
    end if;
    return null;
end $$;

-- HU-015: encola los avisos de la reserva. Uno inmediato al crearla,
-- confirmarla, cancelarla o reprogramarla, y los recordatorios del
-- proveedor que todavía no han vencido. Al cancelar o reprogramar se
-- descartan los recordatorios pendientes, y si la reserva sigue viva se
-- vuelven a calcular con el horario nuevo. Es security definer porque
-- rol_app no escribe en booking_notices: la cola sólo la llena la base.
create or replace function fn_bookings_avisos() returns trigger
language plpgsql security definer set search_path = public as $$
declare
    v_tipo varchar(20);
begin
    if tg_op = 'INSERT' then
        if new.status not in ('RESERVED', 'CONFIRMED') then
            return null;                       -- historia cargada: no se avisa
        end if;
        v_tipo := 'CREATED';
    elsif new.session_id <> old.session_id then
        v_tipo := 'RESCHEDULED';
    elsif new.status <> old.status and new.status in ('CONFIRMED', 'CANCELLED') then
        v_tipo := new.status;
    else
        return null;
    end if;

    insert into booking_notices (booking_id, kind, due_at) values (new.id, v_tipo, now());

    if tg_op = 'UPDATE' then
        delete from booking_notices
         where booking_id = new.id
           and kind = 'REMINDER'
           and processed_at is null;
    end if;

    if new.status in ('RESERVED', 'CONFIRMED') then
        insert into booking_notices (booking_id, kind, due_at)
        select new.id, 'REMINDER', se.starts_at - make_interval(mins => r.minutes_before)
          from sessions se
              inner join services                       s on s.id = se.service_id
              inner join organization_booking_reminders r on r.organization_id = s.organization_id
         where se.id = new.session_id
           and se.starts_at - make_interval(mins => r.minutes_before) > now();
    end if;
    return null;
end $$;

-- updated_at
create trigger tg_clients_updated_at          before update on clients          for each row execute function fn_set_updated_at();
create trigger tg_organizations_updated_at    before update on organizations    for each row execute function fn_set_updated_at();
create trigger tg_locations_updated_at        before update on locations        for each row execute function fn_set_updated_at();
create trigger tg_services_updated_at         before update on services         for each row execute function fn_set_updated_at();
create trigger tg_resources_updated_at        before update on resources        for each row execute function fn_set_updated_at();
create trigger tg_agendas_updated_at          before update on agendas          for each row execute function fn_set_updated_at();
create trigger tg_sessions_updated_at         before update on sessions         for each row execute function fn_set_updated_at();
create trigger tg_bookings_updated_at         before update on bookings         for each row execute function fn_set_updated_at();
create trigger tg_booking_reviews_updated_at  before update on booking_reviews  for each row execute function fn_set_updated_at();
create trigger tg_waitlist_entries_updated_at before update on waitlist_entries for each row execute function fn_set_updated_at();
create trigger tg_payments_updated_at         before update on payments         for each row execute function fn_set_updated_at();

-- Reglas de negocio
create trigger tg_clients_mayor_de_edad before insert or update of birth_date on clients
    for each row execute function fn_clients_mayor_de_edad();
create trigger tg_bookings_reglas before insert or update on bookings
    for each row execute function fn_bookings_reglas();
-- Sólo en organizations. En clients rompería HU-001: la confirmación del
-- correo cambia el estado sin registrar motivo.
create trigger tg_organizations_motivo after update of status on organizations
    for each row execute function fn_exige_motivo_cuenta();
create trigger tg_booking_reviews_completada before insert or update of booking_id on booking_reviews
    for each row execute function fn_booking_reviews_completada();
create trigger tg_waitlist_entries_reserva before insert or update of booking_id, client_id, service_id, location_id on waitlist_entries
    for each row execute function fn_waitlist_entries_reserva();

-- Coherencia entre tablas, en lugar de las FK compuestas
create trigger tg_service_locations_mismo_proveedor before insert or update on service_locations
    for each row execute function fn_service_locations_mismo_proveedor();
create trigger tg_service_resource_requirements_mismo_proveedor before insert or update on service_resource_requirements
    for each row execute function fn_service_resource_requirements_mismo_proveedor();
create trigger tg_resources_coherencia before insert or update of resource_type_id, location_id on resources
    for each row execute function fn_resources_coherencia();
create trigger tg_locations_proveedor_inmutable before update of organization_id on locations
    for each row execute function fn_proveedor_inmutable();
create trigger tg_services_proveedor_inmutable before update of organization_id on services
    for each row execute function fn_proveedor_inmutable();
create trigger tg_resource_types_proveedor_inmutable before update of organization_id on resource_types
    for each row execute function fn_proveedor_inmutable();
create trigger tg_agenda_services_en_sede before insert or update on agenda_services
    for each row execute function fn_agenda_services_en_sede();
create trigger tg_agendas_servicios_en_sede before update of location_id, resource_id on agendas
    for each row execute function fn_agendas_servicios_en_sede();
create trigger tg_service_locations_quita_de_agendas after delete or update on service_locations
    for each row execute function fn_service_locations_quita_de_agendas();
create trigger tg_bookings_coherencia before insert or update of session_id, policy_id, currency_id on bookings
    for each row execute function fn_bookings_coherencia();
create trigger tg_sessions_coherencia before update of service_id, location_id, starts_at, ends_at on sessions
    for each row execute function fn_sessions_coherencia();
create trigger tg_session_resources_reglas before insert or update of session_id, resource_id on session_resources
    for each row execute function fn_session_resources_reglas();
create trigger tg_sessions_libera_recursos after update of status, session_id on bookings
    for each row execute function fn_sessions_libera_recursos();

-- Auditoría: las tablas donde un cambio tiene consecuencias de negocio o
-- de seguridad, o donde alguien podría querer cambiar algo sin dejar
-- rastro, como una calificación. bookings ya tiene su propia historia en
-- booking_status_changes.
create trigger tg_auditar_clients               after insert or update or delete on clients               for each row execute function fn_auditar();
create trigger tg_auditar_organizations         after insert or update or delete on organizations         for each row execute function fn_auditar();
create trigger tg_auditar_organization_members  after insert or update or delete on organization_members  for each row execute function fn_auditar();
create trigger tg_auditar_organization_policies after insert or update or delete on organization_policies for each row execute function fn_auditar();
create trigger tg_auditar_services              after insert or update or delete on services              for each row execute function fn_auditar();
create trigger tg_auditar_payments              after insert or update or delete on payments              for each row execute function fn_auditar();
create trigger tg_auditar_booking_reviews       after insert or update or delete on booking_reviews       for each row execute function fn_auditar();
-- [S3] Los recordatorios son configuración del proveedor, como su política
create trigger tg_auditar_organization_booking_reminders after insert or update or delete on organization_booking_reminders for each row execute function fn_auditar();

-- [S3] Ciclo de vida de la reserva. En PostgreSQL los BEFORE de una misma
-- tabla se disparan en orden alfabético; ninguno de estos depende de otro.
create trigger tg_bookings_anticipacion before insert or update of session_id on bookings
    for each row execute function fn_bookings_anticipacion();
create trigger tg_bookings_cruce_cliente before insert or update of session_id, status on bookings
    for each row execute function fn_bookings_cruce_cliente();
create trigger tg_bookings_momento_del_estado before update of status on bookings
    for each row execute function fn_bookings_momento_del_estado();
create trigger tg_bookings_exige_historial after update of status on bookings
    for each row execute function fn_bookings_exige_historial();
create trigger tg_booking_reschedules_reglas before insert on booking_reschedules
    for each row execute function fn_booking_reschedules_reglas();
create trigger tg_bookings_exige_reprogramacion after update of session_id on bookings
    for each row execute function fn_bookings_exige_reprogramacion();
create trigger tg_bookings_avisos after insert or update of status, session_id on bookings
    for each row execute function fn_bookings_avisos();


-- =====================================================================
--  10. [S3] Procedimientos y funciones de las historias de usuario
--
--  Convención: sp_ para un procedimiento, que cambia datos y se llama con
--  CALL; fn_ para una función que se consulta con SELECT; f_ para una
--  función auxiliar que usan las demás. Los procedimientos devuelven su
--  resultado en parámetros OUT: en el CALL se pasa null en su lugar.
--
--  Todas son security invoker, el comportamiento por defecto: corren con
--  los permisos de quien las llama. Así un procedimiento no le abre a
--  rol_app nada que sus GRANT no le den, y los triggers de las tablas
--  revisan cada fila igual que si la aplicación escribiera directo.
-- =====================================================================

-- HU-008, HU-009 y HU-010: un recurso puede atender en [p_inicio, p_fin)
-- si está activo, no lo ocupa otra sesión, no está en mantenimiento y, si
-- tiene agenda propia, ese rato cae en uno de sus bloques y fuera de sus
-- excepciones. Las horas de la agenda son las de la sede.
create or replace function f_recurso_atiende(p_resource_id uuid, p_inicio timestamptz, p_fin timestamptz)
returns boolean
language sql stable as $$
    select r.status = 'ACTIVE'
       and not exists (select 1
                         from session_resources sr
                             inner join sessions s on s.id = sr.session_id
                        where sr.resource_id = r.id
                          and s.starts_at < p_fin
                          and s.ends_at   > p_inicio)
       and not exists (select 1
                         from resource_maintenances m
                        where m.resource_id = r.id
                          and m.starts_at < p_fin
                          and m.ends_at   > p_inicio)
       and (not exists (select 1
                          from agendas a
                         where a.resource_id = r.id
                           and (p_inicio at time zone z.tz)::date between a.valid_from and coalesce(a.valid_until, 'infinity'))
            or exists (select 1
                         from agendas a
                             inner join schedules sc on sc.agenda_id = a.id and sc.active
                        where a.resource_id = r.id
                          and (p_inicio at time zone z.tz)::date between a.valid_from and coalesce(a.valid_until, 'infinity')
                          and sc.day_of_week = extract(isodow from p_inicio at time zone z.tz)
                          and (p_inicio at time zone z.tz) >= (p_inicio at time zone z.tz)::date + sc.start_time
                          and (p_fin    at time zone z.tz) <= (p_inicio at time zone z.tz)::date + sc.end_time
                          and not exists (select 1
                                            from agenda_exceptions e
                                           where e.agenda_id = a.id
                                             and e.exception_date = (p_inicio at time zone z.tz)::date
                                             and tsrange(e.exception_date + coalesce(e.start_time, time '00:00'),
                                                         e.exception_date + coalesce(e.end_time,   time '24:00'))
                                                 && tsrange(p_inicio at time zone z.tz, p_fin at time zone z.tz))))
      from resources r
          inner join locations     l on l.id = r.location_id
          inner join organizations o on o.id = l.organization_id
          cross join lateral (select coalesce(l.timezone, o.timezone) as tz) z
     where r.id = p_resource_id
$$;

-- HU-008 y HU-011: las franjas en que se puede reservar un servicio en una
-- sede un día dado, con los cupos que quedan. Una franja sale de un bloque
-- de alguna agenda de la sede, o de uno de sus recursos, que ofrezca el
-- servicio, cada slot_minutes y sin pisar una excepción de esa agenda
-- (HU-007). Queda si está dentro de la anticipación de la política, si le
-- quedan cupos y, cuando hay que abrir la sesión, si hay recursos de cada
-- tipo que el servicio exige que puedan atender (HU-010).
--   select * from fn_franjas_disponibles('<servicio>', '<sede>', current_date + 1);
create or replace function fn_franjas_disponibles(p_service_id uuid, p_location_id uuid, p_fecha date)
returns table (starts_at timestamptz, ends_at timestamptz, free_places integer)
language sql stable as $$
    with servicio as (
        select s.id, s.duration_minutes, s.customer_capacity, s.organization_id,
               coalesce(l.timezone, o.timezone) as tz
          from services s
              inner join service_locations sl on sl.service_id = s.id and sl.location_id = p_location_id
              inner join locations         l  on l.id = sl.location_id
              inner join organizations     o  on o.id = s.organization_id
         where s.id = p_service_id
           and s.status = 'ACTIVE'
           and l.status = 'ACTIVE'
           and o.status = 'ACTIVE'
    ),
    politica as (
        select p.booking_notice_minutes_min as minimo,
               p.booking_notice_minutes_max as maximo
          from organization_policies p
              inner join servicio sv on sv.organization_id = p.organization_id
         where p.replaced_at is null
    ),
    candidatas as (
        select distinct t as inicio_local
          from servicio sv
              inner join agendas         a  on f_sede_de_agenda(a.location_id, a.resource_id) = p_location_id
              inner join agenda_services ag on ag.agenda_id = a.id and ag.service_id = sv.id
              inner join schedules       sc on sc.agenda_id = a.id
                                           and sc.active
                                           and sc.day_of_week = extract(isodow from p_fecha)
              cross join lateral generate_series(
                         p_fecha + sc.start_time,
                         p_fecha + sc.end_time - make_interval(mins => sv.duration_minutes),
                         make_interval(mins => a.slot_minutes)) as t
         where p_fecha between a.valid_from and coalesce(a.valid_until, 'infinity')
           and not exists (select 1
                             from agenda_exceptions e
                            where e.agenda_id = a.id
                              and e.exception_date = p_fecha
                              and tsrange(p_fecha + coalesce(e.start_time, time '00:00'),
                                          p_fecha + coalesce(e.end_time,   time '24:00'))
                                  && tsrange(t, t + make_interval(mins => sv.duration_minutes)))
    ),
    franjas as (
        select c.inicio_local at time zone sv.tz                                              as inicio,
               (c.inicio_local + make_interval(mins => sv.duration_minutes)) at time zone sv.tz as fin
          from candidatas c
              cross join servicio sv
    )
    select f.inicio, f.fin, sv.customer_capacity - coalesce(o.ocupados, 0)
      from franjas f
          cross join servicio sv
          cross join politica p
          left join lateral (
              select sum(b.attendees)::integer as ocupados
                from sessions se
                    inner join bookings b on b.session_id = se.id
                                         and b.status in ('RESERVED', 'CONFIRMED')
               where se.service_id  = sv.id
                 and se.location_id = p_location_id
                 and se.starts_at   = f.inicio
          ) o on true
     where f.inicio >= now() + make_interval(mins => p.minimo)
       and f.inicio <= now() + make_interval(mins => p.maximo)
       and sv.customer_capacity - coalesce(o.ocupados, 0) > 0
       -- Una sesión que ya existe tiene sus recursos. Si hay que abrirla,
       -- tiene que haber recursos libres de cada tipo exigido.
       and (o.ocupados is not null
            or not exists (select 1
                             from service_resource_requirements q
                            where q.service_id = sv.id
                              and (select count(*)
                                     from resources r
                                    where r.resource_type_id = q.resource_type_id
                                      and r.location_id = p_location_id
                                      and f_recurso_atiende(r.id, f.inicio, f.fin)) < q.quantity_required))
     order by f.inicio
$$;

-- HU-012 y HU-014: la sesión donde cae una reserva a esa hora. Si ya hay
-- una con reservas vivas (un taller con cupo), esa; si no, abre una nueva
-- y le asigna los recursos que el servicio exige (HU-010). Antes revisa
-- que la hora sea una de las franjas de fn_franjas_disponibles.
create or replace function f_sesion_para_reserva(p_service_id uuid, p_location_id uuid, p_starts_at timestamptz)
returns uuid
language plpgsql as $$
declare
    v_sesion    uuid;
    v_fin       timestamptz;
    v_fecha     date;
    v_req       record;
    v_asignados integer;
begin
    -- Dos reservas que abren la misma franja a la vez se turnan: la
    -- segunda ve la sesión que abrió la primera y entra a ella
    perform pg_advisory_xact_lock(hashtextextended(p_service_id::text || p_location_id::text || p_starts_at::text, 3));

    select (p_starts_at at time zone coalesce(l.timezone, o.timezone))::date into v_fecha
      from locations l
          inner join organizations o on o.id = l.organization_id
     where l.id = p_location_id;

    select f.ends_at into v_fin
      from fn_franjas_disponibles(p_service_id, p_location_id, v_fecha) f
     where f.starts_at = p_starts_at;
    if v_fin is null then
        raise exception 'HU-008: % no es una franja disponible de ese servicio en esa sede', p_starts_at;
    end if;

    select se.id into v_sesion
      from sessions se
     where se.service_id  = p_service_id
       and se.location_id = p_location_id
       and se.starts_at   = p_starts_at
       and exists (select 1 from bookings b
                    where b.session_id = se.id
                      and b.status in ('RESERVED', 'CONFIRMED'))
     limit 1;
    if v_sesion is not null then
        return v_sesion;
    end if;

    insert into sessions (service_id, location_id, starts_at, ends_at)
    values (p_service_id, p_location_id, p_starts_at, v_fin)
    returning id into v_sesion;

    for v_req in select resource_type_id, quantity_required
                   from service_resource_requirements
                  where service_id = p_service_id loop
        insert into session_resources (session_id, resource_id)
        select v_sesion, r.id
          from resources r
         where r.resource_type_id = v_req.resource_type_id
           and r.location_id = p_location_id
           and f_recurso_atiende(r.id, p_starts_at, v_fin)
         order by r.name
         limit v_req.quantity_required;

        get diagnostics v_asignados = row_count;
        if v_asignados < v_req.quantity_required then
            raise exception 'HU-010: no hay % recursos libres del tipo que exige el servicio en esa franja',
                  v_req.quantity_required;
        end if;
    end loop;
    return v_sesion;
end $$;

-- HU-012: crea una reserva. Toma la política vigente del proveedor, pacta
-- el precio en la moneda del servicio y la deja CONFIRMED si el proveedor
-- no confirma a mano y el cliente ya verificó su correo (HU-001); si no,
-- RESERVED. Deja el primer estado en la historia.
--   call sp_crear_reserva('<cliente>', '<servicio>', '<sede>', '2026-12-01 10:00-05', 1, null, null, null);
create or replace procedure sp_crear_reserva(
    p_client_id   uuid,
    p_service_id  uuid,
    p_location_id uuid,
    p_starts_at   timestamptz,
    p_attendees   integer,
    out o_booking_id uuid,
    out o_code       varchar,
    out o_status     varchar)
language plpgsql as $$
declare
    v_politica uuid;
    v_manual   boolean;
    v_precio   numeric(12,2);
    v_moneda   uuid;
    v_cliente  varchar(30);
    v_sesion   uuid;
begin
    select status into v_cliente from clients where id = p_client_id;
    if v_cliente is null then
        raise exception 'HU-012: el cliente % no existe', p_client_id;
    end if;

    select p.id, p.manual_confirmation, s.price * p_attendees, s.currency_id
      into v_politica, v_manual, v_precio, v_moneda
      from services s
          inner join organization_policies p on p.organization_id = s.organization_id
                                            and p.replaced_at is null
     where s.id = p_service_id;
    if v_politica is null then
        raise exception 'HU-012: el servicio % no existe o su proveedor no tiene una política vigente', p_service_id;
    end if;

    v_sesion := f_sesion_para_reserva(p_service_id, p_location_id, p_starts_at);

    o_status := case when not v_manual and v_cliente = 'ACTIVE' then 'CONFIRMED' else 'RESERVED' end;

    insert into bookings (client_id, session_id, policy_id, attendees, total_price, currency_id, status)
    values (p_client_id, v_sesion, v_politica, p_attendees, v_precio, v_moneda, o_status)
    returning id, code into o_booking_id, o_code;

    insert into booking_status_changes (booking_id, from_status, to_status, changed_by)
    values (o_booking_id, null, o_status, p_client_id);
end $$;

-- HU-013: cancela una reserva con su motivo. Devuelve si fue tardía, es
-- decir, dentro de la ventana en que la política ya no la deja gratis.
-- Ese dato no se guarda: sale de la hora de la cancelación, del inicio de
-- la cita y de la política que congeló la reserva.
--   call sp_cancelar_reserva('<reserva>', 'Tengo un viaje', '<quien>', null);
create or replace procedure sp_cancelar_reserva(
    p_booking_id   uuid,
    p_reason       varchar,
    p_cancelled_by uuid,
    out o_late     boolean)
language plpgsql as $$
declare
    v_estado  varchar(20);
    v_inicio  timestamptz;
    v_ventana integer;
begin
    -- Primero se bloquea sólo la reserva y después se lee su sesión. Con el
    -- join en el mismo for update, si otra transacción la acababa de pasar a
    -- otra sesión, PostgreSQL relee la fila, el join deja de coincidir y la
    -- reserva parecía no existir.
    perform 1 from bookings where id = p_booking_id for update;

    select b.status, s.starts_at, p.free_cancellation_window_minutes
      into v_estado, v_inicio, v_ventana
      from bookings b
          inner join sessions              s on s.id = b.session_id
          inner join organization_policies p on p.id = b.policy_id
     where b.id = p_booking_id;
    if v_estado is null then
        raise exception 'HU-013: la reserva % no existe', p_booking_id;
    end if;
    if v_estado not in ('RESERVED', 'CONFIRMED') then
        raise exception 'HU-013: la reserva ya está en estado %, no se puede cancelar', v_estado;
    end if;
    if length(btrim(coalesce(p_reason, ''))) = 0 then
        raise exception 'HU-013: cancelar una reserva exige el motivo';
    end if;

    insert into booking_status_changes (booking_id, from_status, to_status, reason, changed_by)
    values (p_booking_id, v_estado, 'CANCELLED', p_reason, p_cancelled_by);

    -- cancelled_at lo pone tg_bookings_momento_del_estado
    update bookings set status = 'CANCELLED' where id = p_booking_id;

    o_late := now() > v_inicio - make_interval(mins => v_ventana);
end $$;

-- HU-014: pasa una reserva a otra hora del mismo servicio y sede. Deja la
-- reprogramación en la historia y devuelve la sesión nueva y cuántas
-- reprogramaciones le quedan. La sesión vieja suelta sus recursos si se
-- queda sin reservas (tg_sessions_libera_recursos).
--   call sp_reprogramar_reserva('<reserva>', '2026-12-02 11:00-05', 'Cambio de turno', '<quien>', null, null);
create or replace procedure sp_reprogramar_reserva(
    p_booking_id     uuid,
    p_starts_at      timestamptz,
    p_reason         varchar,
    p_rescheduled_by uuid,
    out o_session_id uuid,
    out o_remaining  integer)
language plpgsql as $$
declare
    v_actual   uuid;
    v_servicio uuid;
    v_sede     uuid;
    v_estado   varchar(20);
    v_max      integer;
begin
    -- Igual que en sp_cancelar_reserva: se bloquea la reserva sola y después
    -- se lee su sesión, que otra reprogramación pudo haber cambiado
    perform 1 from bookings where id = p_booking_id for update;

    select b.session_id, s.service_id, s.location_id, b.status, p.max_reschedules
      into v_actual, v_servicio, v_sede, v_estado, v_max
      from bookings b
          inner join sessions              s on s.id = b.session_id
          inner join organization_policies p on p.id = b.policy_id
     where b.id = p_booking_id;
    if v_actual is null then
        raise exception 'HU-014: la reserva % no existe', p_booking_id;
    end if;
    if v_estado not in ('RESERVED', 'CONFIRMED') then
        raise exception 'HU-014: sólo se reprograma una reserva vigente (está en %)', v_estado;
    end if;

    o_session_id := f_sesion_para_reserva(v_servicio, v_sede, p_starts_at);

    insert into booking_reschedules (booking_id, from_session_id, to_session_id, reason, rescheduled_by)
    values (p_booking_id, v_actual, o_session_id, p_reason, p_rescheduled_by);

    update bookings set session_id = o_session_id where id = p_booking_id;

    o_remaining := v_max - (select count(*) from booking_reschedules where booking_id = p_booking_id);
end $$;

-- HU-016: registra si el cliente asistió. Una reserva confirmada queda
-- COMPLETED o NO_SHOW; una sin confirmar sólo puede quedar NO_SHOW.
--   call sp_registrar_asistencia('<reserva>', true, '<quien>', null);
create or replace procedure sp_registrar_asistencia(
    p_booking_id  uuid,
    p_attended    boolean,
    p_recorded_by uuid,
    out o_status  varchar)
language plpgsql as $$
declare
    v_estado varchar(20);
begin
    select status into v_estado from bookings where id = p_booking_id for update;
    if v_estado is null then
        raise exception 'HU-016: la reserva % no existe', p_booking_id;
    end if;
    if v_estado not in ('RESERVED', 'CONFIRMED') then
        raise exception 'HU-016: la reserva ya está cerrada como %', v_estado;
    end if;
    if p_attended is null then
        raise exception 'HU-016: hay que decir si el cliente asistió (true) o no (false)';
    end if;
    if p_attended and v_estado = 'RESERVED' then
        raise exception 'HU-016: una reserva sin confirmar no queda como atendida; se confirma primero';
    end if;

    o_status := case when p_attended then 'COMPLETED' else 'NO_SHOW' end;

    insert into booking_status_changes (booking_id, from_status, to_status, changed_by)
    values (p_booking_id, v_estado, o_status, p_recorded_by);

    update bookings set status = o_status where id = p_booking_id;
end $$;

-- HU-016: cierra las reservas que siguen vivas cuando ya pasaron las
-- horas que da la política después del final de la cita. Una confirmada
-- se cierra como diga la política; una que nunca se confirmó, como
-- inasistencia. Lo corre un job (pg_cron en Supabase) o el backend; skip
-- locked deja pasar las que alguien está tocando en ese momento.
--   call sp_cerrar_reservas_vencidas(null);
create or replace procedure sp_cerrar_reservas_vencidas(out o_closed integer)
language plpgsql as $$
declare
    v_reserva record;
begin
    o_closed := 0;
    for v_reserva in
        select b.id, b.status,
               case when b.status = 'CONFIRMED' then p.default_closure_status else 'NO_SHOW' end as destino,
               p.auto_close_delay_hours
          from bookings b
              inner join sessions              s on s.id = b.session_id
              inner join organization_policies p on p.id = b.policy_id
         where b.status in ('RESERVED', 'CONFIRMED')
           and s.ends_at + make_interval(hours => p.auto_close_delay_hours) <= now()
           for update of b skip locked
    loop
        insert into booking_status_changes (booking_id, from_status, to_status, reason)
        values (v_reserva.id, v_reserva.status, v_reserva.destino,
                'Cierre automático: pasaron ' || v_reserva.auto_close_delay_hours || ' horas sin registrar la asistencia');
        update bookings set status = v_reserva.destino where id = v_reserva.id;
        o_closed := o_closed + 1;
    end loop;
end $$;

-- HU-017: el historial de reservas de un cliente, de la más reciente a la
-- más vieja, con lo que pagó.
--   select * from fn_historial_cliente('<cliente>');
create or replace function fn_historial_cliente(p_client_id uuid)
returns table (code varchar, service varchar, provider varchar, location varchar,
               starts_at timestamptz, status varchar, total_price numeric, currency char(3),
               paid_amount numeric, reschedules bigint)
language sql stable as $$
    select b.code, s.name, o.name, l.name, se.starts_at, b.status, b.total_price, c.code,
           (select coalesce(sum(p.amount), 0)
              from payments p
             where p.booking_id = b.id
               and p.status = 'PAID'
               and p.currency_id = b.currency_id),
           (select count(*) from booking_reschedules r where r.booking_id = b.id)
      from bookings b
          inner join sessions      se on se.id = b.session_id
          inner join services      s  on s.id  = se.service_id
          inner join organizations o  on o.id  = s.organization_id
          inner join locations     l  on l.id  = se.location_id
          inner join currencies    c  on c.id  = b.currency_id
     where b.client_id = p_client_id
     order by se.starts_at desc
$$;

-- HU-017 y HU-018: los datos del comprobante de una reserva, buscada por
-- su código. El backend arma el PDF con esta fila. La hora va en la zona
-- de la sede, que es la que el cliente tiene en la cabeza.
--   select * from fn_comprobante_reserva('RSV-1A2B-3C4D-5E6F');
create or replace function fn_comprobante_reserva(p_code varchar)
returns table (code varchar, status varchar, client_name varchar, client_document varchar,
               provider varchar, provider_identification varchar, location varchar, address varchar,
               city varchar, service varchar, local_start timestamp, attendees integer,
               total_price numeric, currency char(3), payment_method varchar, payment_status varchar,
               payment_reference varchar, paid_at timestamptz)
language sql stable as $$
    select b.code, b.status, cl.full_name, cl.document,
           o.name, o.identification_type || ' ' || o.identification_number,
           l.name, l.address, ci.name, s.name,
           se.starts_at at time zone coalesce(l.timezone, o.timezone),
           b.attendees, b.total_price, cu.code,
           pg.method, pg.status, pg.external_reference, pg.paid_at
      from bookings b
          inner join clients       cl on cl.id = b.client_id
          inner join sessions      se on se.id = b.session_id
          inner join services      s  on s.id  = se.service_id
          inner join organizations o  on o.id  = s.organization_id
          inner join locations     l  on l.id  = se.location_id
          inner join cities        ci on ci.id = l.city_id
          inner join currencies    cu on cu.id = b.currency_id
          -- El pago que cuenta: el vigente o el reembolsado antes que un
          -- intento fallido, y entre iguales el más reciente
          left join lateral (select p.method, p.status, p.external_reference, p.paid_at
                               from payments p
                              where p.booking_id = b.id
                              order by p.status = 'FAILED', p.created_at desc
                              limit 1) pg on true
     where b.code = p_code
$$;

-- HU-019: la ocupación de los recursos de un proveedor entre dos fechas,
-- leída del resumen diario que calcula fn_calcular_ocupacion. El
-- porcentaje es nulo si el recurso no tuvo horas disponibles.
--   select * from fn_reporte_ocupacion('<proveedor>', current_date - 30, current_date);
create or replace function fn_reporte_ocupacion(p_organization_id uuid, p_from date, p_to date)
returns table (location varchar, resource varchar, available_minutes bigint,
               booked_minutes bigint, sessions bigint, occupancy_pct numeric)
language sql stable as $$
    select l.name, r.name,
           sum(d.available_minutes), sum(d.booked_minutes), sum(d.sessions_count),
           round(100.0 * sum(d.booked_minutes) / nullif(sum(d.available_minutes), 0), 1)
      from resource_occupancy_daily d
          inner join resources r on r.id = d.resource_id
          inner join locations l on l.id = r.location_id
     where l.organization_id = p_organization_id
       and d.occupancy_date between p_from and p_to
     group by l.name, r.name
     order by l.name, r.name
$$;


-- =====================================================================
--  11. Índices
--  PostgreSQL indexa las PK y las UNIQUE, pero no las FK. Aquí van las
--  FK que no son ya el prefijo de otra clave, y las consultas frecuentes.
-- =====================================================================

-- Unicidad que no se puede declarar como restricción
create unique index ux_clients_email_lower           on clients (lower(email));
create unique index ux_organization_policies_vigente on organization_policies (organization_id) where replaced_at is null;
-- Un cliente no se anota dos veces a lo mismo mientras siga esperando
create unique index ux_waitlist_entries_activa on waitlist_entries (client_id, service_id, location_id, desired_date)
    where status in ('WAITING', 'NOTIFIED');
-- Un solo pago vivo por reserva
create unique index ux_payments_vigente on payments (booking_id) where status in ('PENDING', 'PAID');
-- [S3] Un recordatorio no se programa dos veces para la misma hora
create unique index ux_booking_notices_recordatorio on booking_notices (booking_id, due_at) where kind = 'REMINDER';

-- FK no cubiertas por el prefijo de otra clave
create index ix_clients_city                         on clients (city_id);
create index ix_organization_members_user            on organization_members (user_id);
create index ix_locations_city                       on locations (city_id);
create index ix_services_currency                    on services (currency_id);
create index ix_service_locations_location           on service_locations (location_id);
create index ix_service_resource_requirements_type   on service_resource_requirements (resource_type_id);
create index ix_resources_type                       on resources (resource_type_id);
create index ix_agenda_services_service              on agenda_services (service_id);
-- El EXCLUDE de schedules es parcial (where active) y no sirve para el
-- "delete from schedules where agenda_id = ?" con que el backend reescribe
-- los bloques, ni para el borrado en cascada de una agenda.
create index ix_schedules_agenda                     on schedules (agenda_id);
-- Sirve a la FK por service_id (es el prefijo) y a los reportes de un
-- servicio en un rango de fechas. Ver docs/analisis-almacenamiento.md.
create index ix_sessions_service_starts              on sessions (service_id, starts_at);
create index ix_sessions_location_starts             on sessions (location_id, starts_at);
create index ix_bookings_client                      on bookings (client_id);
-- El cupo suma los asistentes de una sesión, y los reportes pasan de la
-- sesión a sus reservas
create index ix_bookings_session                     on bookings (session_id);
create index ix_bookings_policy                      on bookings (policy_id);
-- tg_session_resources_reglas busca las otras sesiones del recurso
create index ix_session_resources_resource           on session_resources (resource_id);
create index ix_booking_status_changes_booking      on booking_status_changes (booking_id);
create index ix_organization_status_changes_org      on organization_status_changes (organization_id, changed_at desc);
create index ix_client_status_changes_client         on client_status_changes (client_id, changed_at desc);
create index ix_waitlist_entries_service_location    on waitlist_entries (service_id, location_id, desired_date);
create index ix_waitlist_entries_client              on waitlist_entries (client_id);
create index ix_payments_booking                     on payments (booking_id);
-- [S3] El tope de HU-014 cuenta las reprogramaciones de una reserva
create index ix_booking_reschedules_booking          on booking_reschedules (booking_id, rescheduled_at);
create index ix_booking_reschedules_from             on booking_reschedules (from_session_id);
create index ix_booking_reschedules_to               on booking_reschedules (to_session_id);
create index ix_booking_notices_booking              on booking_notices (booking_id);

-- Consultas frecuentes
create index ix_login_attempts_email_lower   on login_attempts (lower(email), attempted_at);
create index ix_organizations_status        on organizations (status);
create index ix_sent_emails_recipient        on sent_emails (lower(recipient), sent_at desc);
create index ix_resource_occupancy_daily_date on resource_occupancy_daily (occupancy_date);
create index ix_audit_log_registro           on audit_log (table_name, record_id, changed_at desc);
-- [S3] El proceso que envía avisos sólo mira los pendientes que ya vencieron
create index ix_booking_notices_pendientes   on booking_notices (due_at) where processed_at is null;
-- [S3] El cupo de una sesión y fn_franjas_disponibles suman sólo las
-- reservas vivas, y el cierre automático de HU-016 sólo las recorre a
-- ellas: son pocas frente a toda la historia
create index ix_bookings_vivas               on bookings (session_id) where status in ('RESERVED', 'CONFIRMED');


-- =====================================================================
--  12. Comentarios de catálogo
-- =====================================================================

comment on table cities                        is 'Catálogo de ciudades, con departamento';
comment on table organization_categories       is 'Catálogo de categorías de negocio';
comment on table currencies                    is 'Monedas ISO 4217. La baja es lógica (active)';
comment on table clients                       is 'Perfil del cliente (HU-001); id = auth.users.id de Supabase';
comment on table login_attempts                is 'Intentos de ingreso para el bloqueo por cuenta (HU-021)';
comment on table organizations                 is 'Negocio proveedor (HU-002). PENDING_APPROVAL hasta que un administrador lo apruebe';
comment on table organization_members          is 'Quién trabaja en qué proveedor y con qué rol (ADR-0008)';
comment on table organization_policies         is 'Reglas de anticipación y cancelación, versionadas (HU-002)';
comment on table locations                     is 'Sedes de un proveedor';
comment on table services                      is 'Servicios ofertados (HU-004). customer_capacity 1 = individual, > 1 = grupal';
comment on table service_locations             is 'En qué sedes se presta cada servicio (HU-004)';
comment on table resource_types                is 'Tipos de recurso no consumible: sala, silla, especialista';
comment on table service_resource_requirements is 'Cuántos recursos de cada tipo exige un servicio';
comment on table resources                     is 'Recurso concreto en una sede, con capacidad y estado (HU-009)';
comment on table resource_maintenances         is 'Periodos de mantenimiento: el recurso no genera disponibilidad (HU-009)';
comment on table agendas                       is 'Agenda de una sede o de un recurso, nunca de los dos: granularidad, vigencia y servicios (HU-006)';
comment on table agenda_services               is 'Servicios reservables en una agenda (HU-006)';
comment on table schedules                     is 'Bloques horarios semanales de una agenda (HU-006)';
comment on table agenda_exceptions             is 'Festivos, cierres y jornadas recortadas de una agenda';
comment on table sessions                      is 'Un servicio en una sede y a una hora. Individual: una reserva; grupal: varias, hasta el cupo';
comment on table bookings                      is 'Reserva de un cliente en una sesión. policy_id y currency_id congelan las condiciones y la moneda al crearla';
comment on table session_resources             is 'Recursos que ocupa una sesión; un trigger impide que un recurso quede en dos sesiones a la vez';
comment on table booking_status_changes        is 'Historia de estados de una reserva';
comment on table organization_status_changes   is 'Historia de estados de un proveedor, con motivo obligatorio (HU-003)';
comment on table client_status_changes         is 'Historia de estados de un cliente, con motivo obligatorio (HU-003)';
comment on table booking_reviews               is 'Calificación de 1 a 5 de una reserva completada';
comment on table waitlist_entries              is 'Lista de espera por servicio, sede y día';
comment on table payments                      is 'Pagos y reembolsos de una reserva';
comment on table sent_emails                   is 'Correos guardados en vez de enviados por SMTP (ADR-0007)';
comment on table resource_occupancy_daily      is 'Ocupación diaria por recurso, calculada por fn_calcular_ocupacion';
comment on table audit_log                     is 'Auditoría de cambios en tablas sensibles, escrita por trigger: quién, cuándo y sobre qué fila';
comment on table audit_log_changes             is 'Columnas que cambió cada evento de audit_log, con el valor de antes y el de después';

comment on column bookings.total_price        is 'Precio pactado al reservar. No es copia de services.price, que puede cambiar';
comment on column bookings.currency_id        is 'Moneda del precio pactado, la del servicio en el momento de reservar';
comment on column sessions.ends_at            is 'Fin pactado. No se calcula con la duración del servicio, que puede cambiar después';
comment on column audit_log.app_user_id       is 'Usuario de la aplicación, tomado de set local app.user_id si la sesión lo informa';
comment on table booking_reschedules            is '[S3] Reprogramaciones de una reserva: de qué sesión a cuál, quién y por qué (HU-014)';
comment on table organization_booking_reminders is '[S3] Cuántos minutos antes de la cita recuerda cada proveedor (HU-015)';
comment on table booking_notices                is '[S3] Cola de avisos y recordatorios de una reserva, llenada por tg_bookings_avisos (HU-015)';
comment on column bookings.code                 is '[S3] Código legible de la reserva, para buscarla y para el comprobante (HU-017, HU-018)';
comment on column organization_policies.manual_confirmation    is '[S3] HU-012: si es true, la reserva nace RESERVED y el proveedor la confirma';
comment on column organization_policies.max_reschedules        is '[S3] HU-014: cuántas veces se puede reprogramar una reserva';
comment on column organization_policies.default_closure_status is '[S3] HU-016: cómo se cierra sola una reserva confirmada sin registro de asistencia';
comment on column organization_policies.auto_close_delay_hours is '[S3] HU-016: horas tras el final de la cita antes del cierre automático';

comment on function fn_clients_mayor_de_edad()                         is 'HU-001: el cliente tiene al menos 18 años al registrarse';
comment on function fn_bookings_reglas()                               is 'HU-001 a 004: estados válidos, proveedor, servicio y sede activos, cliente no suspendido, verificado para confirmar, y cupo de la sesión';
comment on function fn_bookings_coherencia()                           is 'Política del proveedor y vigente al reservar, que ya no cambia; precio en la moneda del servicio; otra sesión sólo del mismo servicio';
comment on function fn_sessions_coherencia()                           is 'La sesión no cambia de servicio; si se mueve, sus recursos siguen en la sede y libres';
comment on function fn_session_resources_reglas()                      is 'El recurso está activo, en la sede de la sesión y no está ocupado por otra sesión que se cruce';
comment on function fn_sessions_libera_recursos()                      is 'Una sesión sin reservas vivas suelta sus recursos';
comment on function fn_service_locations_mismo_proveedor()             is 'El servicio y la sede son del mismo proveedor';
comment on function fn_service_locations_quita_de_agendas()            is 'Si un servicio deja de prestarse en una sede, por borrado o edición, sale de las agendas de esa sede';
comment on function fn_service_resource_requirements_mismo_proveedor() is 'El servicio y el tipo de recurso son del mismo proveedor';
comment on function fn_resources_coherencia()                          is 'Tipo y sede del mismo proveedor; un recurso con sesiones o agenda no cambia de sede';
comment on function fn_proveedor_inmutable()                           is 'El proveedor de una sede, un servicio o un tipo de recurso no cambia';
comment on function fn_agenda_services_en_sede()                       is 'El servicio se presta en la sede de la agenda (HU-006)';
comment on function fn_agendas_servicios_en_sede()                     is 'Si la agenda cambia de sede o de recurso, sus servicios se prestan en la sede nueva';
comment on function f_sede_de_agenda(uuid, uuid)                       is 'La sede de una agenda: la suya, o la de su recurso';
comment on function fn_booking_reviews_completada()                    is 'Sólo se califica una reserva completada';
comment on function fn_waitlist_entries_reserva()                      is 'La reserva en que terminó la espera es del mismo cliente, servicio y sede';
comment on function fn_exige_motivo_cuenta()                           is 'HU-003: cambiar el estado de un proveedor exige el motivo en organization_status_changes';
comment on function fn_auditar()                                       is 'Escribe en audit_log quién cambió qué fila y en audit_log_changes cada columna que cambió';
comment on function fn_set_updated_at()                                is 'Mantiene updated_at';
comment on function fn_calcular_ocupacion(date)                        is 'HU-019: llena resource_occupancy_daily para un día';
comment on function f_sin_tildes(text)                                 is 'HU-005: búsqueda sin mayúsculas ni tildes';

comment on function fn_bookings_anticipacion()         is '[S3] HU-012 y HU-014: la cita cae dentro de la ventana de anticipación de la política';
comment on function fn_bookings_cruce_cliente()        is '[S3] HU-012: un cliente no tiene dos reservas vivas que se crucen';
comment on function fn_bookings_momento_del_estado()   is '[S3] HU-013 y HU-016: no se cancela una cita que empezó ni se registra asistencia antes de que empiece';
comment on function fn_bookings_exige_historial()      is '[S3] HU-013 y HU-016: un cambio de estado exige su fila en booking_status_changes';
comment on function fn_booking_reschedules_reglas()    is '[S3] HU-014: reprogramar una reserva vigente, desde su sesión, al mismo servicio y sede, sin pasar el tope';
comment on function fn_bookings_exige_reprogramacion() is '[S3] HU-014: cambiar de sesión exige su fila en booking_reschedules';
comment on function fn_bookings_avisos()               is '[S3] HU-015: encola avisos y programa los recordatorios del proveedor';
comment on function f_codigo_reserva()                 is '[S3] HU-018: código legible y aleatorio de una reserva';
comment on function f_recurso_atiende(uuid, timestamptz, timestamptz)       is '[S3] HU-008 a HU-010: el recurso está activo, libre, sin mantenimiento y dentro de su agenda';
comment on function fn_franjas_disponibles(uuid, uuid, date)                is '[S3] HU-008 y HU-011: franjas reservables de un servicio en una sede un día, con cupos libres';
comment on function f_sesion_para_reserva(uuid, uuid, timestamptz)          is '[S3] HU-010, HU-012 y HU-014: sesión de la franja, abierta con sus recursos si hace falta';
comment on procedure sp_crear_reserva(uuid, uuid, uuid, timestamptz, integer) is '[S3] HU-012: crea una reserva con la política vigente y el precio pactado';
comment on procedure sp_cancelar_reserva(uuid, varchar, uuid)                 is '[S3] HU-013: cancela con motivo y dice si fue tardía';
comment on procedure sp_reprogramar_reserva(uuid, timestamptz, varchar, uuid) is '[S3] HU-014: pasa la reserva a otra franja y deja la historia';
comment on procedure sp_registrar_asistencia(uuid, boolean, uuid)             is '[S3] HU-016: marca la reserva como atendida o inasistencia';
comment on procedure sp_cerrar_reservas_vencidas()                            is '[S3] HU-016: cierre automático de las reservas que nadie cerró';
comment on function fn_historial_cliente(uuid)                              is '[S3] HU-017: historial de reservas de un cliente';
comment on function fn_comprobante_reserva(varchar)                         is '[S3] HU-017 y HU-018: datos del comprobante de una reserva por su código';
comment on function fn_reporte_ocupacion(uuid, date, date)                  is '[S3] HU-019: ocupación de los recursos de un proveedor en un rango';


-- =====================================================================
--  13. Seguridad: roles, permisos y RLS
--
--  Tres roles de grupo, sin login. Una persona o un servicio entra con
--  un usuario propio que hereda de uno de ellos, por ejemplo:
--      create role app_bookingplatform login password '...' in role rol_app;
--  Las contraseñas no van en este archivo.
--
--    rol_admin    administración y mantenimiento: todo
--    rol_app      el backend: sólo lo que el código hace
--    rol_lectura  reportes: leer, sin datos personales ni de seguridad
--
--  La matriz completa y su justificación están en el README.
-- =====================================================================

do $$
begin
    if not exists (select 1 from pg_roles where rolname = 'rol_admin')   then create role rol_admin   nologin; end if;
    if not exists (select 1 from pg_roles where rolname = 'rol_app')     then create role rol_app     nologin; end if;
    if not exists (select 1 from pg_roles where rolname = 'rol_lectura') then create role rol_lectura nologin; end if;
end $$;

-- Nadie recibe nada por defecto
revoke create on schema public from public;
revoke all on all tables    in schema public from public;
revoke all on all sequences in schema public from public;
-- [S3] PostgreSQL le da EXECUTE a PUBLIC sobre toda función o procedimiento
-- que se crea. En el Sprint 2 se le quitaba sólo a las dos que se
-- invocaban a mano; ahora, a todas las rutinas propias, y cada rol recibe
-- abajo sólo las que usa. Se dejan las de btree_gist (deptype 'e', son de
-- la extensión) y las que PostgreSQL crea con el tipo timerange (deptype
-- 'i', como el constructor timerange(time, time)): las usan los EXCLUDE y
-- no son nuestras. Las funciones de trigger no necesitan EXECUTE:
-- PostgreSQL no lo revisa al dispararlas.
do $$
declare
    r record;
begin
    for r in select p.oid::regprocedure as firma,
                    case p.prokind when 'p' then 'procedure' else 'function' end as tipo
               from pg_proc p
                   inner join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public'
                and not exists (select 1 from pg_depend d
                                 where d.classid = 'pg_proc'::regclass
                                   and d.objid = p.oid
                                   and d.deptype in ('e', 'i')) loop
        execute format('revoke all on %s %s from public', r.tipo, r.firma);
    end loop;
end $$;
-- Y lo mismo para lo que se cree después en este esquema
alter default privileges in schema public revoke execute on routines from public;

grant usage  on schema public to rol_admin, rol_app, rol_lectura;
grant create on schema public to rol_admin;

-- rol_admin: todo
grant all     on all tables    in schema public to rol_admin;
grant all     on all sequences in schema public to rol_admin;
grant execute on all routines  in schema public to rol_admin;

-- rol_app: catálogos de solo lectura (se cargan por migración)
grant select on cities, organization_categories, currencies to rol_app;

-- rol_app: tablas operativas, leer, crear y modificar
grant select, insert, update on
    clients, organizations, organization_members, organization_policies, locations,
    services, resource_types, service_resource_requirements,
    resources, resource_maintenances, agendas, schedules, agenda_exceptions,
    sessions, session_resources, booking_reviews, waitlist_entries
to rol_app;

-- rol_app: tablas que son sólo una clave. Se crean, no se editan.
grant select, insert on service_locations, agenda_services to rol_app;

-- rol_app: una reserva o un pago no cambian de cliente, precio ni moneda
-- después de creados. Sólo se editan las columnas que el flujo mueve.
grant select, insert on payments to rol_app;
-- [S3] La reserva se crea sólo con lo que el cliente pide. code, created_at,
-- updated_at y cancelled_at los pone la base: de created_at mide
-- tg_bookings_anticipacion, y si la aplicación pudiera fecharlo en el
-- pasado se saltaría la anticipación de HU-012.
grant select on bookings to rol_app;
grant insert (id, client_id, session_id, policy_id, attendees, total_price, currency_id, status) on bookings to rol_app;
-- [S3] Sólo la sesión (al reprogramar) y el estado. cancelled_at la pone la
-- base al cancelar y ya no se edita: de ella sale si la cancelación fue
-- tardía. attendees tampoco: el precio se pactó por persona, y cambiar los
-- asistentes es cancelar y reservar otra vez.
grant update (session_id, status) on bookings to rol_app;
grant update (status, external_reference, paid_at, refunded_at) on payments to rol_app;

-- rol_app: historiales, sólo se agregan filas. Si la aplicación pudiera
-- editarlos, dejarían de servir como evidencia de lo que pasó.
grant select, insert on
    login_attempts, booking_status_changes, organization_status_changes, client_status_changes, sent_emails
to rol_app;
grant usage on sequence login_attempts_id_seq to rol_app;

-- rol_app: los únicos borrados que hace el backend. ManageServiceUseCase
-- borra un servicio que nunca se reservó y AgendaRepositoryAdapter
-- reescribe los bloques de una agenda. Una excepción de agenda mal
-- puesta también tiene que poder quitarse.
grant delete on services, schedules, agenda_exceptions to rol_app;

-- rol_app: lee la ocupación para mostrarla; la calcula el administrador
grant select on resource_occupancy_daily to rol_app;
grant execute on function f_sin_tildes(text) to rol_app, rol_lectura;
-- audit_log y audit_log_changes: rol_app no las toca. Las escribe
-- fn_auditar (security definer).

-- [S3] rol_app: tablas nuevas.
-- booking_reschedules es historia: se agrega, no se edita.
grant select, insert on booking_reschedules to rol_app;
-- Los recordatorios los configura el proveedor; quitar uno es borrar su fila.
grant select, insert, delete on organization_booking_reminders to rol_app;
-- La cola de avisos la llena tg_bookings_avisos (security definer). El
-- backend sólo la lee y marca lo que ya envió.
grant select on booking_notices to rol_app;
grant update (processed_at) on booking_notices to rol_app;
-- bookings.code no está en el grant de update de arriba: el código no cambia.

-- [S3] rol_app: las rutinas de las HU. Las auxiliares también, porque
-- todo es security invoker y PostgreSQL revisa EXECUTE en cada llamada
-- anidada, también dentro de un trigger o de un DEFAULT.
grant execute on procedure
    sp_crear_reserva(uuid, uuid, uuid, timestamptz, integer),
    sp_cancelar_reserva(uuid, varchar, uuid),
    sp_reprogramar_reserva(uuid, timestamptz, varchar, uuid),
    sp_registrar_asistencia(uuid, boolean, uuid),
    sp_cerrar_reservas_vencidas()
to rol_app;
grant execute on function
    fn_franjas_disponibles(uuid, uuid, date),
    fn_historial_cliente(uuid),
    fn_comprobante_reserva(varchar),
    fn_reporte_ocupacion(uuid, date, date),
    f_sesion_para_reserva(uuid, uuid, timestamptz),
    f_recurso_atiende(uuid, timestamptz, timestamptz),
    f_sede_de_agenda(uuid, uuid),
    f_codigo_reserva()
to rol_app;
-- fn_calcular_ocupacion queda sólo para rol_admin: la corre el job diario.

-- [S3] rol_lectura: las dos consultas que no muestran datos personales.
-- El historial y el comprobante sí los tienen (nombre y documento).
grant execute on function
    fn_franjas_disponibles(uuid, uuid, date),
    fn_reporte_ocupacion(uuid, date, date),
    f_recurso_atiende(uuid, timestamptz, timestamptz),
    f_sede_de_agenda(uuid, uuid)
to rol_lectura;

-- rol_lectura: todo para leer, menos datos personales y de seguridad
grant select on all tables in schema public to rol_lectura;
revoke select on clients, client_status_changes, login_attempts, sent_emails, audit_log, audit_log_changes from rol_lectura;
-- Un proveedor puede ser una persona natural (V4): su documento, su
-- correo y su teléfono son datos personales. El comentario de una reseña
-- es texto libre del cliente. De esas dos tablas, sólo ciertas columnas.
revoke select on organizations, booking_reviews from rol_lectura;
grant select (id, category_id, name, timezone, status, approved_at, created_at, updated_at) on organizations to rol_lectura;
grant select (id, booking_id, rating, created_at, updated_at) on booking_reviews to rol_lectura;

-- RLS en todas las tablas (ADR-0002 del equipo). Con RLS activo y sin
-- políticas nadie distinto del dueño ve filas, así que cada rol propio
-- recibe una política explícita. Las políticas abren filas; lo que cada
-- rol puede HACER lo siguen limitando los GRANT de arriba. El control por
-- organización lo hace el backend (OrganizationAccess, ADR-0008).
do $$
declare
    t text;
begin
    for t in select tablename from pg_tables where schemaname = 'public' loop
        execute format('alter table public.%I enable row level security', t);
        execute format('create policy %I on public.%I to rol_admin using (true) with check (true)', t || '_admin', t);
        execute format('create policy %I on public.%I to rol_app using (true) with check (true)', t || '_app', t);
        execute format('create policy %I on public.%I for select to rol_lectura using (true)', t || '_lectura', t);
    end loop;
end $$;

-- Supabase: los roles del Data API (anon, authenticated) sólo existen
-- allá. Sin acceso a nada, salvo los catálogos públicos y lo propio de
-- cada cliente. En un PostgreSQL local este bloque no hace nada.
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon')
       and exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                    where n.nspname = 'auth' and p.proname = 'uid') then

        execute 'revoke all on all tables    in schema public from anon, authenticated';
        execute 'revoke all on all sequences in schema public from anon, authenticated';
        execute 'revoke all on all routines  in schema public from anon, authenticated';

        -- Catálogos: no son datos sensibles
        execute 'grant select on cities, organization_categories, currencies to anon, authenticated';
        execute 'create policy cities_publico     on cities                  for select to anon, authenticated using (true)';
        execute 'create policy categorias_publico on organization_categories for select to anon, authenticated using (true)';
        execute 'create policy monedas_publico    on currencies              for select to anon, authenticated using (true)';

        -- Cada cliente ve sus reservas, las sesiones de esas reservas (ahí
        -- están el servicio, la sede y la hora), su lista de espera y sus reseñas
        execute 'grant select on bookings, sessions, waitlist_entries, booking_reviews to authenticated';
        execute 'create policy reservas_propias on bookings for select to authenticated
                     using (client_id = (select auth.uid()))';
        execute 'create policy sesiones_propias on sessions for select to authenticated
                     using (exists (select 1 from bookings b
                                     where b.session_id = sessions.id and b.client_id = (select auth.uid())))';
        execute 'create policy espera_propia    on waitlist_entries for select to authenticated
                     using (client_id = (select auth.uid()))';
        execute 'create policy resenas_propias  on booking_reviews for select to authenticated
                     using (exists (select 1 from bookings b
                                     where b.id = booking_id and b.client_id = (select auth.uid())))';

        -- [S3] Las tablas nuevas tienen RLS como todas. El cliente ve las
        -- reprogramaciones y los avisos de sus propias reservas; los
        -- recordatorios de un proveedor no los ve nadie desde el Data API.
        execute 'grant select on booking_reschedules, booking_notices to authenticated';
        execute 'create policy reprogramaciones_propias on booking_reschedules for select to authenticated
                     using (exists (select 1 from bookings b
                                     where b.id = booking_id and b.client_id = (select auth.uid())))';
        execute 'create policy avisos_propios on booking_notices for select to authenticated
                     using (exists (select 1 from bookings b
                                     where b.id = booking_id and b.client_id = (select auth.uid())))';

        raise notice 'Políticas de Supabase creadas para anon y authenticated';
    else
        raise notice 'Sin roles de Supabase (PostgreSQL local): se omiten las políticas del Data API';
    end if;
end $$;


-- =====================================================================
--  Lo que este esquema NO garantiza
--
--   · Que una sesión ocupe los recursos que su servicio exige, y que caiga
--     dentro de un bloque de agenda, fuera de una excepción y fuera de un
--     mantenimiento. [S3] sp_crear_reserva y sp_reprogramar_reserva sí lo
--     garantizan; un insert directo en sessions, no.
--   · [S3] Que los avisos de booking_notices se envíen: la base los
--     encola, y enviarlos es del backend.
--   · [S3] Una reserva insertada directo, sin sp_crear_reserva, no se
--     revisa contra la confirmación manual del proveedor ni contra el
--     precio del servicio, y no deja su primer estado en la historia. Las
--     demás reglas sí corren: anticipación, cruce, cupo, estado y política.
--   · [S3] sp_reprogramar_reserva no deja mover una reserva a una franja
--     que se cruza con su propia hora actual: sus recursos aparecen
--     ocupados por ella misma. Se reprograma a una hora que no se cruce.
--   · Los candados del cupo y de los recursos suponen READ COMMITTED, el
--     nivel por defecto. En REPEATABLE READ la consulta que sigue al
--     candado no vería lo que la otra transacción acaba de confirmar.
--   · Dos reservas que se cruzan de sesión a la vez (A a B y B a A) se
--     pueden bloquear mutuamente. PostgreSQL detecta el bloqueo y aborta
--     una de las dos, que se reintenta.
--   · Nada programa fn_calcular_ocupacion: se corre una vez al día con un
--     job (pg_cron en Supabase) o a mano.
--   · Que una excepción de agenda caiga dentro de la vigencia de la agenda.
--   · fn_calcular_ocupacion sólo cuenta agendas propias del recurso; un
--     recurso que sólo depende de la agenda de su sede queda con 0
--     minutos disponibles. Tampoco descuenta mantenimientos.
--   · Contraseñas, MFA y sesiones: viven en Supabase Auth.
--   · Que timezone sea una zona real de la IANA.
-- =====================================================================
