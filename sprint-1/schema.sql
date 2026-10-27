-- =====================================================================
--  Plataforma de Reservas de Servicios — modelo físico
--  Sprint 1
--
--  PostgreSQL 15+ (probado en 16). Compatible con Supabase.
--  Contra una base vacía crea las 19 tablas sin errores.
--
--  También corre contra una base que ya tenga `clients` y
--  `login_attempts` del mapeo JPA: esas dos se saltan, y sus
--  restricciones se añaden con bloques DO porque
--  `create table if not exists` no las agrega si la tabla ya existe.
--
--  Lo que este esquema NO garantiza está al final del archivo.
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


-- =====================================================================
--  Catálogos
--  Separados para eliminar dependencias transitivas (3FN).
-- =====================================================================

create table if not exists cities (
    id     uuid         primary key default gen_random_uuid(),
    name   varchar(120) not null,
    region varchar(120) not null,   -- departamento: hay municipios homónimos
    constraint uk_cities_name_region unique (name, region),
    constraint ck_cities_name        check (length(btrim(name)) > 0)
);

create table if not exists organization_categories (
    id   uuid        primary key default gen_random_uuid(),
    name varchar(80) not null,
    constraint uk_organization_categories_name unique (name),
    constraint ck_organization_categories_name check (length(btrim(name)) > 0)
);

create table if not exists currencies (
    id     uuid        primary key default gen_random_uuid(),
    code   char(3)     not null,
    name   varchar(60) not null,
    active boolean     not null default true,  -- la baja es lógica: hay servicios que la referencian
    constraint uk_currencies_code unique (code),
    constraint uk_currencies_name unique (name),
    constraint ck_currencies_code check (code ~ '^[A-Z]{3}$')   -- ISO 4217
);


-- =====================================================================
--  Identidad
--  Las credenciales viven en auth.users de Supabase, que este script no
--  crea. Por eso clients.id, organization_members.user_id y
--  account_status_changes.changed_by no tienen clave foránea declarada.
--
--  El perfil del personal de una organización tampoco vive aquí: de un
--  miembro sólo guardamos la membresía y el rol, y sus datos personales
--  quedan en auth.users. Duplicarlos en una tabla propia repetiría lo
--  que clients ya modela para el cliente final.
-- =====================================================================

-- clients: ya implementada por el equipo (ClientEntity).
-- No se altera ninguna columna ni ningún tipo.
create table if not exists clients (
    id                   uuid         not null,
    full_name            varchar(120) not null,
    document             varchar(30)  not null,
    birth_date           date         not null,
    email                varchar(160) not null,
    phone                varchar(20)  not null,
    city                 varchar(80)  not null,
    notification_channel varchar(20)  not null,
    status               varchar(30)  not null,
    created_at           timestamp(6) not null,
    updated_at           timestamp(6) not null,
    constraint pk_clients primary key (id)
);

-- Las restricciones van aparte: si la tabla ya existía, el
-- `create table if not exists` de arriba no habría añadido ninguna.
do $$
begin
    alter table clients add constraint uk_clients_email  unique (email);
exception when duplicate_table or duplicate_object then null; end $$;
do $$
begin
    alter table clients add constraint uk_clients_document unique (document);
exception when duplicate_table or duplicate_object then null; end $$;
do $$
begin
    alter table clients add constraint ck_clients_status
        check (status in ('PENDING_VERIFICATION', 'ACTIVE', 'SUSPENDED'));
exception when duplicate_object then null; end $$;
do $$
begin
    alter table clients add constraint ck_clients_notification_channel
        check (notification_channel in ('EMAIL', 'SMS', 'WHATSAPP'));
exception when duplicate_object then null; end $$;
do $$
begin
    -- HU-001: no se permite autorregistro de menores de 18 años
    alter table clients add constraint ck_clients_adult
        check (birth_date <= current_date - interval '18 years');
exception when duplicate_object then null; end $$;
do $$
begin
    -- HU-001: "rechazo por formato inválido de correo o teléfono"
    alter table clients add constraint ck_clients_email_formato
        check (email ~* '^[^@[:space:]]+@[^@[:space:]]+\.[a-z]{2,}$');
exception when duplicate_object then null; end $$;
do $$
begin
    alter table clients add constraint ck_clients_phone_formato
        check (phone ~ '^\+?[0-9]{7,15}$');
exception when duplicate_object then null; end $$;

-- El unique del equipo distingue mayúsculas, así que Ana@x.com y
-- ana@x.com entran como dos cuentas. Este índice lo cierra sin
-- quitarles nada.
create unique index if not exists ux_clients_email_lower on clients (lower(email));

-- login_attempts: ya implementada por el equipo. Soporta el bloqueo por
-- cuenta de HU-021, que GoTrue no cubre porque sólo limita por IP.
create table if not exists login_attempts (
    id           bigint       generated by default as identity,
    email        varchar(160) not null,
    success      boolean      not null,
    attempted_at timestamp(6) not null,
    constraint pk_login_attempts primary key (id)
);


-- =====================================================================
--  Organización (HU-002, HU-003)
-- =====================================================================

create table if not exists organizations (
    id            uuid         primary key default gen_random_uuid(),
    category_id   uuid         not null,
    name          varchar(160) not null,
    nit           varchar(20)  not null,
    contact_email varchar(160) not null,
    contact_phone varchar(20)  not null,
    timezone      varchar(60)  not null default 'America/Bogota',
    status        varchar(30)  not null default 'PENDING_APPROVAL',
    approved_at   timestamptz,
    created_at    timestamptz  not null default now(),
    updated_at    timestamptz  not null default now(),

    constraint uk_organizations_nit unique (nit),                 -- HU-002: NIT único

    constraint fk_organizations_category foreign key (category_id) references organization_categories (id) on delete restrict,

    constraint ck_organizations_status check (status in ('PENDING_APPROVAL', 'ACTIVE', 'SUSPENDED', 'REJECTED')),
    constraint ck_organizations_name   check (length(btrim(name)) > 0),
    constraint ck_organizations_nit    check (length(btrim(nit))  > 0),
    constraint ck_organizations_email  check (contact_email ~* '^[^@[:space:]]+@[^@[:space:]]+\.[a-z]{2,}$'),
    -- Sólo ACTIVE y SUSPENDED pueden tener fecha de aprobación, y ACTIVE
    -- la exige: no hay organización activa sin registro de quién la aprobó
    constraint ck_organizations_approved check (
        (status = 'ACTIVE'                        and approved_at is not null) or
        (status in ('PENDING_APPROVAL','REJECTED') and approved_at is null)    or
        (status = 'SUSPENDED'))
);

create table if not exists organization_members (
    id              uuid        primary key default gen_random_uuid(),
    organization_id uuid        not null,
    user_id         uuid        not null,
    role            varchar(30) not null,
    created_at      timestamptz not null default now(),
    -- La PK sustituta se conserva porque así la diseñó el equipo; la clave
    -- natural queda como UNIQUE, que preserva igual la dependencia funcional.
    constraint uk_organization_members      unique (organization_id, user_id),
    constraint fk_organization_members_org  foreign key (organization_id) references organizations (id) on delete cascade,
    constraint ck_organization_members_role check (role in ('OWNER', 'MANAGER', 'STAFF'))
);

-- Política versionada. HU-002 pide que los cambios apliquen sólo a las
-- reservas nuevas, así que en vez de copiar los parámetros en cada
-- reserva, cada reserva apunta a la versión que regía al crearse.
create table if not exists organization_policies (
    id                               uuid        primary key default gen_random_uuid(),
    organization_id                  uuid        not null,
    version                          integer     not null,
    booking_notice_minutes_min       integer     not null,
    booking_notice_minutes_max       integer     not null,
    free_cancellation_window_minutes integer     not null,
    effective_from                   timestamptz not null default now(),
    replaced_at                      timestamptz,

    constraint uk_organization_policies_version unique (organization_id, version),
    constraint uk_organization_policies_id_org  unique (id, organization_id),   -- clave alterna para CF compuesta
    constraint fk_organization_policies_org     foreign key (organization_id) references organizations (id) on delete restrict,

    constraint ck_organization_policies_version check (version > 0),
    constraint ck_organization_policies_notice  check (booking_notice_minutes_min >= 0
                                                   and booking_notice_minutes_max >= 0
                                                   and booking_notice_minutes_min <= booking_notice_minutes_max),
    constraint ck_organization_policies_cancel  check (free_cancellation_window_minutes >= 0),
    constraint ck_organization_policies_vigencia check (replaced_at is null or replaced_at > effective_from),
    -- Dos versiones no pueden regir a la vez, ni siquiera históricamente
    constraint ex_organization_policies_solape exclude using gist (
        organization_id with =,
        tstzrange(effective_from, replaced_at) with &&
    )
);

create table if not exists locations (
    id              uuid         primary key default gen_random_uuid(),
    organization_id uuid         not null,
    name            varchar(120) not null,
    address         varchar(200) not null,
    city_id         uuid         not null,
    -- Nulo = hereda la zona horaria de la organización. Al ser un
    -- override explícito, NO existe la dependencia city_id -> timezone
    -- que sacaría a esta tabla de 3FN.
    timezone        varchar(60),
    status          varchar(20)  not null default 'ACTIVE',
    created_at      timestamptz  not null default now(),
    updated_at      timestamptz  not null default now(),

    constraint uk_locations_org_name unique (organization_id, name),
    constraint uk_locations_id_org   unique (id, organization_id),   -- clave alterna para CF compuesta
    constraint fk_locations_org      foreign key (organization_id) references organizations (id) on delete restrict,
    constraint fk_locations_city     foreign key (city_id) references cities (id) on delete restrict,
    constraint ck_locations_status   check (status in ('ACTIVE', 'INACTIVE')),
    constraint ck_locations_name     check (length(btrim(name)) > 0)
);


-- =====================================================================
--  Servicios (HU-004)
-- =====================================================================

create table if not exists services (
    id                  uuid          primary key default gen_random_uuid(),
    organization_id     uuid          not null,
    name                varchar(120)  not null,
    description         varchar(500),
    duration_minutes    integer       not null,
    preparation_minutes integer       not null default 0,
    cleanup_minutes     integer       not null default 0,
    price               numeric(12,2) not null,
    currency_id         uuid          not null,
    customer_capacity   integer       not null default 1,
    status              varchar(20)   not null default 'ACTIVE',
    created_at          timestamptz   not null default now(),
    updated_at          timestamptz   not null default now(),

    constraint uk_services_org_name unique (organization_id, name),  -- HU-004: nombre único por proveedor
    constraint uk_services_id_org   unique (id, organization_id),    -- clave alterna para CF compuesta
    constraint fk_services_org      foreign key (organization_id) references organizations (id) on delete restrict,
    constraint fk_services_currency foreign key (currency_id) references currencies (id) on delete restrict,

    constraint ck_services_duration check (duration_minutes > 0),
    constraint ck_services_prep     check (preparation_minutes >= 0 and cleanup_minutes >= 0),
    constraint ck_services_price    check (price >= 0),
    constraint ck_services_capacity check (customer_capacity >= 1),  -- 1 = individual, >1 = grupal
    constraint ck_services_status   check (status in ('ACTIVE', 'INACTIVE')),
    constraint ck_services_name     check (length(btrim(name)) > 0)
);

-- Sedes donde se presta cada servicio (HU-004). organization_id se
-- arrastra para que las CF compuestas impidan publicar un servicio de
-- una organización en la sede de otra.
create table if not exists service_locations (
    service_id      uuid not null,
    location_id     uuid not null,
    organization_id uuid not null,
    constraint pk_service_locations     primary key (service_id, location_id),
    constraint fk_service_locations_svc foreign key (service_id,  organization_id) references services  (id, organization_id) on delete cascade,
    constraint fk_service_locations_loc foreign key (location_id, organization_id) references locations (id, organization_id) on delete cascade
);

create table if not exists resource_types (
    id              uuid         primary key default gen_random_uuid(),
    organization_id uuid         not null,
    name            varchar(80)  not null,
    description     varchar(300),
    created_at      timestamptz  not null default now(),
    constraint uk_resource_types_org_name unique (organization_id, name),
    constraint uk_resource_types_id_org   unique (id, organization_id),
    constraint fk_resource_types_org      foreign key (organization_id) references organizations (id) on delete restrict
);

create table if not exists service_resource_requirements (
    id                uuid    primary key default gen_random_uuid(),
    service_id        uuid    not null,
    resource_type_id  uuid    not null,
    organization_id   uuid    not null,
    quantity_required integer not null default 1,
    constraint uk_service_resource_req      unique (service_id, resource_type_id),
    constraint fk_service_resource_req_svc  foreign key (service_id,       organization_id) references services       (id, organization_id) on delete cascade,
    constraint fk_service_resource_req_type foreign key (resource_type_id, organization_id) references resource_types (id, organization_id) on delete restrict,
    constraint ck_service_resource_req_qty  check (quantity_required > 0)
);


-- =====================================================================
--  Recursos y agenda
--  El diagrama del equipo llegaba hasta el tipo de recurso. Sin la
--  instancia concreta no hay control de disponibilidad.
-- =====================================================================

create table if not exists resources (
    id               uuid         primary key default gen_random_uuid(),
    resource_type_id uuid         not null,
    location_id      uuid         not null,
    name             varchar(120) not null,
    status           varchar(20)  not null default 'ACTIVE',
    created_at       timestamptz  not null default now(),
    updated_at       timestamptz  not null default now(),
    constraint uk_resources_location_name unique (location_id, name),
    constraint uk_resources_id_location   unique (id, location_id),   -- clave alterna para CF compuesta
    constraint fk_resources_type          foreign key (resource_type_id) references resource_types (id) on delete restrict,
    constraint fk_resources_location      foreign key (location_id)      references locations (id)      on delete restrict,
    constraint ck_resources_status        check (status in ('ACTIVE', 'INACTIVE'))
);

-- Franja semanal recurrente. resource_id nulo = toda la sede.
create table if not exists schedules (
    id          uuid     primary key default gen_random_uuid(),
    location_id uuid     not null,
    resource_id uuid,
    day_of_week smallint not null,
    start_time  time     not null,
    end_time    time     not null,
    active      boolean  not null default true,
    created_at  timestamptz not null default now(),

    -- Sin esta clave la misma franja entra N veces e infla el
    -- denominador de los reportes de ocupación. El nulls not distinct
    -- hace falta para las franjas de sede completa.
    constraint uk_schedules_franja unique nulls not distinct
        (location_id, resource_id, day_of_week, start_time, end_time),

    constraint fk_schedules_location foreign key (location_id) references locations (id) on delete cascade,
    -- El recurso tiene que estar en esa sede. Con match simple, si
    -- resource_id es nulo la CF no se verifica.
    constraint fk_schedules_resource foreign key (resource_id, location_id) references resources (id, location_id) on delete cascade,

    constraint ck_schedules_dow   check (day_of_week between 1 and 7),   -- ISO: 1 = lunes
    constraint ck_schedules_rango check (end_time > start_time),

    -- Dos franjas activas del mismo recurso no se pueden solapar
    constraint ex_schedules_solape exclude using gist (
        location_id with =,
        coalesce(resource_id, '00000000-0000-0000-0000-000000000000'::uuid) with =,
        day_of_week with =,
        timerange(start_time, end_time) with &&
    ) where (active)
);


-- =====================================================================
--  Reservas
-- =====================================================================

create table if not exists bookings (
    id              uuid          primary key default gen_random_uuid(),
    client_id       uuid          not null,
    organization_id uuid          not null,
    service_id      uuid          not null,
    location_id     uuid          not null,
    policy_id       uuid          not null,
    -- Sesión a la que pertenece la reserva. En un servicio individual
    -- cada reserva es su propia sesión; en uno grupal, varias reservas
    -- comparten sesión y por tanto comparten recurso (ver booking_resources).
    session_id      uuid          not null,
    starts_at       timestamptz   not null,
    ends_at         timestamptz   not null,
    attendees       integer       not null default 1,
    total_price     numeric(12,2) not null,
    status          varchar(20)   not null default 'RESERVED',
    cancelled_at    timestamptz,
    created_at      timestamptz   not null default now(),
    updated_at      timestamptz   not null default now(),

    -- Destino de la CF compuesta de booking_resources: es lo que hace
    -- que el motor mantenga sincronizada la copia del rango.
    constraint uk_bookings_snapshot unique (id, starts_at, ends_at, status),

    constraint fk_bookings_client foreign key (client_id) references clients (id) on delete restrict,

    -- El servicio tiene que prestarse en esa sede (HU-004)
    constraint fk_bookings_service_location
        foreign key (service_id, location_id) references service_locations (service_id, location_id) on delete restrict,
    -- y servicio, sede y política tienen que ser de la misma organización
    constraint fk_bookings_service_org  foreign key (service_id,  organization_id) references services              (id, organization_id) on delete restrict,
    constraint fk_bookings_location_org foreign key (location_id, organization_id) references locations             (id, organization_id) on delete restrict,
    constraint fk_bookings_policy_org   foreign key (policy_id,   organization_id) references organization_policies (id, organization_id) on delete restrict,

    constraint ck_bookings_rango     check (ends_at > starts_at),
    constraint ck_bookings_attendees check (attendees > 0),
    constraint ck_bookings_price     check (total_price >= 0),
    constraint ck_bookings_status    check (status in ('RESERVED', 'CONFIRMED', 'CANCELLED', 'COMPLETED', 'NO_SHOW')),
    constraint ck_bookings_cancel    check (status <> 'CANCELLED' or cancelled_at is not null)
);

-- Recursos ocupados por una reserva.
--
-- starts_at, ends_at y status se repiten desde bookings a propósito.
-- PostgreSQL no evalúa un EXCLUDE a través de un join, así que para
-- impedir el doble uso de un recurso el rango tiene que estar en la
-- misma tabla que resource_id. Es una violación de 2FN asumida.
--
-- La copia no puede desviarse: la CF compuesta contra la clave alterna
-- de bookings la mantiene el motor, con on update cascade.
create table if not exists booking_resources (
    booking_id  uuid        not null,
    resource_id uuid        not null,
    location_id uuid        not null,
    session_id  uuid        not null,
    starts_at   timestamptz not null,
    ends_at     timestamptz not null,
    status      varchar(20) not null,

    constraint pk_booking_resources primary key (booking_id, resource_id),

    -- La copia la garantiza el motor, no la aplicación.
    constraint fk_booking_resources_bkg
        foreign key (booking_id, starts_at, ends_at, status)
        references bookings (id, starts_at, ends_at, status)
        on update cascade on delete cascade,

    -- El recurso tiene que estar en la sede de la reserva
    constraint fk_booking_resources_res
        foreign key (resource_id, location_id) references resources (id, location_id) on delete restrict,

    constraint ck_booking_resources_rango  check (ends_at > starts_at),
    constraint ck_booking_resources_status check (status in ('RESERVED', 'CONFIRMED', 'CANCELLED', 'COMPLETED', 'NO_SHOW')),

    -- Un recurso no puede estar en dos sesiones distintas que se
    -- solapen. El session_id with <> es lo que permite los servicios
    -- grupales: varias reservas de la misma sesión comparten el recurso
    -- sin chocar. Las canceladas no bloquean.
    constraint ex_booking_resources_solape exclude using gist (
        resource_id with =,
        session_id  with <>,
        tstzrange(starts_at, ends_at) with &&
    ) where (status in ('RESERVED', 'CONFIRMED'))
);

-- Traza de cambios de estado de una reserva. Con on delete restrict,
-- porque un historial que desaparece con lo que traza no sirve.
create table if not exists booking_status_changes (
    id          uuid         primary key default gen_random_uuid(),
    booking_id  uuid         not null,
    from_status varchar(20),
    to_status   varchar(20)  not null,
    reason      varchar(300),
    changed_by  uuid,
    changed_at  timestamptz  not null default now(),
    constraint fk_booking_status_changes foreign key (booking_id) references bookings (id) on delete restrict,
    constraint ck_bsc_from   check (from_status is null or from_status in ('RESERVED','CONFIRMED','CANCELLED','COMPLETED','NO_SHOW')),
    constraint ck_bsc_to     check (to_status in ('RESERVED','CONFIRMED','CANCELLED','COMPLETED','NO_SHOW')),
    -- Cancelar exige motivo, y un motivo en blanco no es un motivo
    constraint ck_bsc_reason check (to_status <> 'CANCELLED' or length(btrim(coalesce(reason,''))) > 0)
);

-- HU-003 exige motivo al aprobar, suspender o reactivar, e informe de
-- reservas afectadas al suspender. Eso es sobre cuentas, no sobre
-- reservas, así que necesita su propia tabla.
create table if not exists account_status_changes (
    id                uuid         primary key default gen_random_uuid(),
    subject_type      varchar(20)  not null,
    client_id         uuid,
    organization_id   uuid,
    from_status       varchar(30),
    to_status         varchar(30)  not null,
    reason            varchar(500) not null,      -- SIEMPRE obligatorio
    affected_bookings integer      not null default 0,
    changed_by        uuid,
    changed_at        timestamptz  not null default now(),
    constraint fk_account_status_changes_cli foreign key (client_id)       references clients (id)       on delete cascade,
    constraint fk_account_status_changes_org foreign key (organization_id) references organizations (id) on delete cascade,
    constraint ck_account_status_changes_subject check (
        (subject_type = 'CLIENT'       and client_id is not null and organization_id is null) or
        (subject_type = 'ORGANIZATION' and organization_id is not null and client_id is null)),
    constraint ck_account_status_changes_reason check (length(btrim(reason)) > 0),
    constraint ck_account_status_changes_count  check (affected_bookings >= 0)
);


-- =====================================================================
--  Reglas que no se pueden expresar con una restricción declarativa
--  Comparan entre tablas, y PostgreSQL no admite subconsultas en un
--  check. Van en triggers para que la garantía siga viviendo en la base.
-- =====================================================================

create or replace function fn_set_updated_at() returns trigger
language plpgsql as $$
begin
    new.updated_at := now();
    return new;
end $$;

-- Tres reglas: un proveedor pendiente no es reservable (HU-002), un
-- cliente sin verificar no confirma (HU-001) y no se supera el aforo.
create or replace function fn_bookings_reglas() returns trigger
language plpgsql as $$
declare
    v_cliente  varchar(30);
    v_org      varchar(30);
    v_servicio varchar(20);
    v_cupo     integer;
    v_ocupado  integer;
begin
    select status into v_cliente from clients where id = new.client_id;
    select status into v_org     from organizations where id = new.organization_id;
    select status, customer_capacity into v_servicio, v_cupo
      from services where id = new.service_id;

    if v_org <> 'ACTIVE' then
        raise exception 'HU-002: el proveedor está en estado %, no es reservable', v_org;
    end if;

    if v_servicio <> 'ACTIVE' and new.status in ('RESERVED','CONFIRMED') then
        raise exception 'HU-004: el servicio está inactivo, no admite reservas nuevas';
    end if;

    if new.status = 'CONFIRMED' and v_cliente <> 'ACTIVE' then
        raise exception 'HU-001: sólo un cliente verificado puede confirmar una reserva (estado %)', v_cliente;
    end if;

    -- Aforo de la sesión
    select coalesce(sum(attendees), 0) into v_ocupado
      from bookings
     where session_id = new.session_id
       and status in ('RESERVED','CONFIRMED')
       and id <> new.id;

    if v_ocupado + new.attendees > v_cupo and new.status in ('RESERVED','CONFIRMED') then
        raise exception 'HU-004: aforo superado: % ocupados + % solicitados > cupo %',
              v_ocupado, new.attendees, v_cupo;
    end if;

    return new;
end $$;

-- HU-003: cambiar el estado de una cuenta exige dejar el motivo.
create or replace function fn_exige_motivo_cuenta() returns trigger
language plpgsql as $$
begin
    if new.status is distinct from old.status
       and not exists (
           select 1 from account_status_changes a
            where a.to_status = new.status
              and (a.organization_id = new.id or a.client_id = new.id)
              and a.changed_at >= now() - interval '1 second') then
        raise exception
          'HU-003: cambiar el estado a % exige registrar el motivo en account_status_changes', new.status;
    end if;
    return new;
end $$;

drop trigger if exists tg_organizations_motivo      on organizations;
drop trigger if exists tg_organizations_updated_at  on organizations;
drop trigger if exists tg_locations_updated_at      on locations;
drop trigger if exists tg_services_updated_at       on services;
drop trigger if exists tg_resources_updated_at      on resources;
drop trigger if exists tg_bookings_updated_at       on bookings;
drop trigger if exists tg_bookings_reglas           on bookings;

create trigger tg_organizations_updated_at before update on organizations for each row execute function fn_set_updated_at();
create trigger tg_locations_updated_at     before update on locations     for each row execute function fn_set_updated_at();
create trigger tg_services_updated_at      before update on services      for each row execute function fn_set_updated_at();
create trigger tg_resources_updated_at     before update on resources     for each row execute function fn_set_updated_at();
create trigger tg_bookings_updated_at      before update on bookings      for each row execute function fn_set_updated_at();
create trigger tg_bookings_reglas          before insert or update on bookings for each row execute function fn_bookings_reglas();

-- HU-003: no se puede suspender ni reactivar una organización sin motivo.
--
-- El trigger se aplica sólo a `organizations`. La misma regla vale para
-- `clients`, pero ahí no se activa todavía: `ConfirmEmailUseCase` mueve el
-- estado a ACTIVE al confirmar el correo y ningún caso de uso escribe aún en
-- `account_status_changes`, así que activarlo rompería HU-001. Se habilita
-- cuando el módulo de identidad registre el motivo en la misma transacción.
create trigger tg_organizations_motivo after update of status on organizations
    for each row execute function fn_exige_motivo_cuenta();


-- =====================================================================
--  Índices
--  PostgreSQL indexa las PK y las unique, pero no las claves foráneas.
--  Aquí sólo van las FK cuya columna no es ya el prefijo de una unique:
--  un índice sobre organization_id sobra si existe
--  unique (organization_id, name).
-- =====================================================================

-- Una sola política vigente por organización
create unique index if not exists ux_organization_policies_vigente
    on organization_policies (organization_id) where replaced_at is null;

-- FK no cubiertas por el prefijo de una UNIQUE
create index if not exists ix_organization_members_user  on organization_members (user_id);
create index if not exists ix_locations_city             on locations (city_id);
create index if not exists ix_services_currency          on services (currency_id);
create index if not exists ix_service_locations_location on service_locations (location_id);
create index if not exists ix_service_resource_req_type  on service_resource_requirements (resource_type_id);
create index if not exists ix_resources_type             on resources (resource_type_id);
create index if not exists ix_schedules_resource         on schedules (resource_id);
create index if not exists ix_bookings_service           on bookings (service_id);
create index if not exists ix_bookings_policy            on bookings (policy_id);
create index if not exists ix_bookings_session           on bookings (session_id);
-- El GiST parcial no ve las canceladas; este sí
create index if not exists ix_booking_resources_resource on booking_resources (resource_id);
create index if not exists ix_bsc_booking                on booking_status_changes (booking_id);
create index if not exists ix_asc_org                    on account_status_changes (organization_id, changed_at desc);
create index if not exists ix_asc_client                 on account_status_changes (client_id, changed_at desc);

-- Consultas frecuentes
create index if not exists ix_login_attempts_email_time  on login_attempts (email, attempted_at);
create index if not exists ix_login_attempts_email_lower on login_attempts (lower(email), attempted_at);
create index if not exists ix_bookings_client_starts     on bookings (client_id, starts_at desc);
create index if not exists ix_bookings_location_starts   on bookings (location_id, starts_at);
create index if not exists ix_schedules_location_dow     on schedules (location_id, day_of_week) where active;
create index if not exists ix_organizations_status       on organizations (status);


-- =====================================================================
--  Comentarios de catálogo
-- =====================================================================

comment on table cities                        is 'Catálogo de ciudades. Evita repetir la ciudad como texto en perfiles y sedes';
comment on table organization_categories       is 'Catálogo de categorías de negocio (HU-003 filtra por categoría)';
comment on table currencies                    is 'Monedas en código ISO 4217. La baja es lógica (active), nunca física';
comment on table clients                       is 'Sprint 1 · IMPLEMENTADO. Perfil de cliente (HU-001); id = auth.users.id de Supabase';
comment on table login_attempts                is 'Sprint 1 · IMPLEMENTADO. Intentos de login para el bloqueo por cuenta (HU-021)';
comment on table organizations                 is 'Negocio proveedor (HU-002). Queda PENDING_APPROVAL hasta que un administrador lo valide';
comment on table organization_members          is 'Relación N:M entre personas y organizaciones, con el rol de cada quien';
comment on table organization_policies         is 'Reglas de operación VERSIONADAS (HU-002). Cada cambio crea una versión; las reservas conservan la suya';
comment on table locations                     is 'Sedes de una organización. HU-002 exige al menos una para publicar servicios';
comment on table services                      is 'Servicios ofertados (HU-004). customer_capacity = 1 individual, > 1 grupal';
comment on table service_locations             is 'En qué sedes se presta cada servicio (HU-004)';
comment on table resource_types                is 'Tipos de recurso NO consumibles: sala, silla de barbero, hidrolavadora, especialista';
comment on table service_resource_requirements is 'Cuántos recursos de cada tipo exige un servicio para poder ejecutarse';
comment on table resources                     is 'Instancia concreta de un tipo de recurso, en una sede. Es lo que realmente se ocupa';
comment on table schedules                     is 'Franjas semanales de disponibilidad. resource_id nulo = aplica a toda la sede';
comment on table bookings                      is 'Reserva. policy_id congela las condiciones vigentes al crearla (HU-002)';
comment on table booking_resources             is 'Recursos ocupados. El EXCLUDE impide que un recurso sirva a dos sesiones solapadas';
comment on table booking_status_changes        is 'Historia de estados de una RESERVA, con motivo obligatorio al cancelar';
comment on table account_status_changes        is 'Historia de estados de CUENTAS: aprobar, suspender y reactivar exigen motivo (HU-003)';

comment on column clients.city                      is 'Texto libre, heredado del mapeo JPA. El catálogo cities sí se usa en locations';
comment on column locations.timezone                is 'Nulo = hereda la de la organización. Es un override explícito, no una copia de la ciudad';
comment on column services.customer_capacity        is 'Cupo por sesión. 1 = individual; mayor que 1 = grupal (HU-004)';
comment on column services.preparation_minutes      is 'Minutos de alistamiento antes de prestar el servicio';
comment on column services.cleanup_minutes          is 'Minutos de limpieza después de prestar el servicio';
comment on column organization_policies.version     is 'Se incrementa en 1 cada vez que la organización cambia sus parámetros';
comment on column organization_policies.replaced_at is 'Nulo mientras la política esté vigente. Sólo puede haber una vigente por organización';
comment on column bookings.session_id               is 'Sesión del servicio. Individual: una por reserva. Grupal: compartida, y por eso comparten recurso';
comment on column bookings.total_price              is 'Precio pactado al reservar. NO es copia de services.price: ese puede cambiar después, así que no hay dependencia funcional';
comment on column booking_resources.starts_at       is 'Copia del rango de la reserva, mantenida por el motor vía CF compuesta con on update cascade';
comment on column schedules.day_of_week             is 'Día ISO: 1 = lunes … 7 = domingo';


-- =====================================================================
--  Lo que este esquema NO garantiza
--
--   · Que una reserva ocupe los recursos que su servicio exige.
--     service_resource_requirements dice cuántos hacen falta, pero nada
--     obliga a insertar las filas en booking_resources.
--   · Que una organización activa tenga al menos una sede, ni que un
--     servicio activo declare sedes y tipos de recurso. Son
--     cardinalidades mínimas entre tablas.
--   · Contraseñas, MFA, sesiones y enlaces de un solo uso de HU-021:
--     viven en Supabase Auth, fuera de este esquema.
--   · El rol de administrador de plataforma. organization_members.role
--     modela roles dentro de una organización, no el rol global.
--   · Excepciones de agenda como festivos o mantenimientos.
--   · Que timezone sea una zona real de la IANA.
-- =====================================================================
