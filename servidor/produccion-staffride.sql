-- ================================================================
-- TallerNeto · BUNDLE DE PRODUCCIÓN para el proyecto Supabase «staffride»
-- Generado 2026-11-21 por concatenación de los SQL de producción de
-- servidor/ en orden de dependencias (según las cabeceras de cada
-- archivo y el orden usado por los scripts probar-*.sh).
-- NO incluye datos demo (ver semilla-demo-staffride.sql) ni pruebas.
-- Verificado: cero choques de nombres con las tablas/funciones de
-- StaffRide (tablas sr: 22; funciones sr_*; TallerNeto usa pr_*).
-- NO APLICAR sin autorización de Miguel.
-- ================================================================

-- === archivo: esquema.sql ===
-- TallerNeto — esquema v1 (PostgreSQL / Supabase)
-- Gestión de piezas y utensilios para el taller de una compañía de transporte.
--
-- Arquitectura HEREDADA de RutaNeto (mismos patrones, no otra):
--  - TODA la lógica vive en el servidor, en funciones pr_* (security definer).
--  - Las tablas tienen RLS activa SIN políticas: el cliente (panel) no lee
--    ni escribe tablas directo; todo pasa por las funciones pr_*.
--  - Sesiones reales con token: de él solo se guarda el HASH SHA-256
--    (tabla `sesiones`); 12 h en el panel. Interruptor `exigir_token`
--    en `configuracion` (nace en 'true' aquí: TallerNeto nace DESPUÉS de
--    la corrección de RutaNeto, así que nace exigiendo token siempre).
--  - Fechas del negocio en hora de República Dominicana: pr_hoy().
--  - PIN con hash bcrypt (pgcrypto): pr_hash_pin / pr_verificar_pin.
--    PIN obligatorio de 4-6 dígitos y NUNCA '1234' para usuarios reales.
--  - Cada función valida actor + empresa: nadie opera fuera de su empresa.
-- Fuente de verdad del proyecto. No aplicar a producción sin revisión.

-- ============ EMPRESAS Y LICENCIAS ============
create table if not exists empresas (
  id uuid primary key default gen_random_uuid(),
  nombre text not null,
  activa boolean not null default true,
  creada_en timestamptz not null default now()
);

-- El plan se mide por nº de VEHÍCULOS (en RutaNeto era por choferes).
create table if not exists licencias (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references empresas(id) on delete cascade,
  estado text not null default 'activa' check (estado in ('activa','suspendida','vencida')),
  vence date,
  max_vehiculos int,
  creada_en timestamptz not null default now()
);

-- ============ CONFIGURACIÓN GLOBAL (interruptores) ============
create table if not exists configuracion (
  clave text primary key,
  valor text not null,
  descripcion text
);

-- ============ PERSONAS ============
-- Roles del taller: admin (oficina/dueño local), almacen (encargado del
-- almacén de piezas), mecanico. superadmin = dueño del sistema (sin empresa).
create table if not exists usuarios (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid references empresas(id) on delete cascade,
  rol text not null check (rol in ('superadmin','admin','almacen','mecanico')),
  nombre text not null,
  codigo text not null,
  pin_hash text,
  activo boolean not null default true,
  unique (empresa_id, codigo)
);

-- ============ SESIONES (solo hash del token) ============
create table if not exists sesiones (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references usuarios(id) on delete cascade,
  empresa_id uuid references empresas(id) on delete cascade,
  contexto text,
  token_hash text not null unique,
  creada_en timestamptz not null default now(),
  expira_en timestamptz not null,
  ultimo_uso timestamptz not null default now(),
  revocada_en timestamptz
);
create index if not exists idx_sesiones_token on sesiones(token_hash);
create index if not exists idx_sesiones_usuario on sesiones(usuario_id);

-- ============ REGISTRO DE ACTIVIDAD (auditoría ligera) ============
create table if not exists registro_actividad (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid references empresas(id) on delete cascade,
  actor_id uuid references usuarios(id),
  accion text not null,
  detalle text,
  creada_en timestamptz not null default now()
);
create index if not exists idx_registro_empresa_fecha on registro_actividad(empresa_id, creada_en desc);

-- ============ VEHÍCULOS ============
create table if not exists vehiculos (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references empresas(id) on delete cascade,
  codigo text not null,
  placa text not null,
  marca text not null,
  modelo text not null,
  anio int,
  estado text not null default 'activo' check (estado in ('activo','en_taller','fuera_servicio')),
  activo boolean not null default true,
  creada_en timestamptz not null default now(),
  unique (empresa_id, codigo),
  unique (empresa_id, placa)
);

-- ============ PIEZAS (inventario) ============
create table if not exists piezas (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references empresas(id) on delete cascade,
  codigo text not null,
  nombre text not null,
  ubicacion text,
  costo numeric(12,2) not null default 0 check (costo >= 0),
  stock int not null default 0 check (stock >= 0),
  stock_minimo int not null default 0 check (stock_minimo >= 0),
  activa boolean not null default true,
  creada_en timestamptz not null default now(),
  unique (empresa_id, codigo)
);

-- ============ MOVIMIENTOS DE PIEZAS ============
-- entrada: suma stock (compra/devolución). salida: resta stock y EXIGE
-- vehiculo_id (a qué vehículo se le montó la pieza). costo_unitario copia
-- el costo de la pieza al momento del movimiento: el costo por vehículo
-- no cambia si mañana la pieza sube de precio.
create table if not exists movimientos (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references empresas(id) on delete cascade,
  tipo text not null check (tipo in ('entrada','salida')),
  pieza_id uuid not null references piezas(id),
  cantidad int not null check (cantidad > 0),
  costo_unitario numeric(12,2) not null default 0,
  vehiculo_id uuid references vehiculos(id),
  usuario_id uuid not null references usuarios(id),
  nota text,
  fecha date not null default (now() at time zone 'America/Santo_Domingo')::date,
  creada_en timestamptz not null default now(),
  check (tipo <> 'salida' or vehiculo_id is not null)
);
create index if not exists idx_mov_empresa_fecha on movimientos(empresa_id, fecha desc);
create index if not exists idx_mov_pieza on movimientos(empresa_id, pieza_id);
create index if not exists idx_mov_vehiculo on movimientos(empresa_id, vehiculo_id);

-- ============ HERRAMIENTAS Y PRÉSTAMOS ============
create table if not exists herramientas (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references empresas(id) on delete cascade,
  codigo text not null,
  nombre text not null,
  estado text not null default 'disponible' check (estado in ('disponible','prestada','reparacion')),
  activa boolean not null default true,
  creada_en timestamptz not null default now(),
  unique (empresa_id, codigo)
);

-- Un préstamo abierto = fecha_devolucion null. La herramienta queda
-- 'prestada' mientras exista un préstamo abierto suyo.
create table if not exists prestamos (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references empresas(id) on delete cascade,
  herramienta_id uuid not null references herramientas(id),
  responsable_id uuid not null references usuarios(id),
  fecha_salida timestamptz not null default now(),
  fecha_devolucion timestamptz,
  registrada_por uuid references usuarios(id),
  devuelta_por uuid references usuarios(id)
);
create index if not exists idx_prestamos_empresa on prestamos(empresa_id, fecha_salida desc);
create unique index if not exists idx_prestamo_abierto_unico
  on prestamos(herramienta_id) where fecha_devolucion is null;

-- RLS activa en todo: el acceso real pasa por las funciones pr_*.
alter table empresas enable row level security;
alter table licencias enable row level security;
alter table configuracion enable row level security;
alter table usuarios enable row level security;
alter table sesiones enable row level security;
alter table registro_actividad enable row level security;
alter table vehiculos enable row level security;
alter table piezas enable row level security;
alter table movimientos enable row level security;
alter table herramientas enable row level security;
alter table prestamos enable row level security;

-- Interruptor de sesiones: TallerNeto nace exigiéndolo (ver encabezado).
insert into configuracion (clave, valor, descripcion) values
  ('exigir_token', 'true',
   'Si vale true, las RPC sensibles rechazan llamadas sin token de sesión. TallerNeto nace en true.')
on conflict (clave) do nothing;

-- ================================================================
-- AYUDANTES (patrones copiados de RutaNeto)
-- ================================================================

-- «Hoy» para el negocio es el día en Santo Domingo, no el día UTC.
create or replace function pr_hoy() returns date
language sql stable as $$
  select (now() at time zone 'America/Santo_Domingo')::date;
$$;

create or replace function pr_ahora_rd() returns timestamp
language sql stable as $$
  select now() at time zone 'America/Santo_Domingo';
$$;

-- Hash de PIN con bcrypt (pgcrypto). pgcrypto puede vivir en el esquema
-- `extensions` (Supabase) o en el esquema visible (PG local): se intenta
-- primero `extensions` y se cae al nombre simple.
create or replace function pr_hash_pin(p_pin text) returns text
language plpgsql as $$
declare v text;
begin
  begin
    execute 'select extensions.crypt($1, extensions.gen_salt(''bf'', 8))' into v using p_pin;
  exception when invalid_schema_name or undefined_function or undefined_object then
    execute 'select crypt($1, gen_salt(''bf'', 8))' into v using p_pin;
  end;
  return v;
end;
$$;

create or replace function pr_verificar_pin(p_pin text, p_hash text) returns boolean
language plpgsql stable as $$
declare v boolean;
begin
  if p_pin is null or p_hash is null then return false; end if;
  begin
    execute 'select $2 = extensions.crypt($1, $2)' into v using p_pin, p_hash;
  exception when invalid_schema_name or undefined_function or undefined_object then
    execute 'select $2 = crypt($1, $2)' into v using p_pin, p_hash;
  end;
  return coalesce(v, false);
end;
$$;

-- Token opaco aleatorio (64 hex = 32 bytes).
create or replace function pr_gen_token() returns text
language plpgsql as $$
declare v text;
begin
  begin
    execute 'select encode(extensions.gen_random_bytes(32), ''hex'')' into v;
  exception when invalid_schema_name or undefined_function or undefined_object then
    execute 'select encode(gen_random_bytes(32), ''hex'')' into v;
  end;
  return v;
end;
$$;

-- Del token solo se guarda su hash SHA-256.
create or replace function pr_hash_token(p_token text) returns text
language plpgsql immutable as $$
declare v text;
begin
  if p_token is null then return null; end if;
  begin
    execute 'select encode(extensions.digest($1, ''sha256''), ''hex'')' into v using p_token;
  exception when invalid_schema_name or undefined_function or undefined_object then
    execute 'select encode(digest($1, ''sha256''), ''hex'')' into v using p_token;
  end;
  return v;
end;
$$;

create or replace function pr_exigir_token() returns boolean
language sql stable security definer as $$
  select coalesce(
    (select valor from configuracion where clave = 'exigir_token'),
    'true') = 'true';
$$;

-- Usuario dueño de la sesión que trae p_token, o null si no existe /
-- está revocada / expiró / su usuario está desactivado.
create or replace function pr_actor_de_token(p_token text) returns usuarios
language plpgsql stable security definer as $$
declare
  s sesiones;
  u usuarios;
begin
  if p_token is null or length(trim(p_token)) = 0 then return null; end if;
  select * into s from sesiones
  where token_hash = pr_hash_token(p_token) and revocada_en is null;
  if s.id is null or s.expira_en <= now() then return null; end if;
  select * into u from usuarios where id = s.usuario_id and activo;
  if u.id is null then return null; end if;
  return u;
end;
$$;

-- Valida que p_token es una sesión viva DE p_actor.
create or replace function pr_validar_token(p_actor uuid, p_token text)
returns void language plpgsql security definer as $$
declare
  s sesiones;
  dueno usuarios;
begin
  if p_token is null then
    if pr_exigir_token() then
      raise exception 'Debes iniciar sesión de nuevo: esta operación necesita una sesión válida';
    end if;
    return;
  end if;
  select * into s from sesiones where token_hash = pr_hash_token(p_token);
  if s.id is null or s.revocada_en is not null then
    raise exception 'Tu sesión no es válida: vuelve a iniciar sesión';
  end if;
  if s.expira_en <= now() then
    raise exception 'Tu sesión expiró: vuelve a iniciar sesión';
  end if;
  if s.usuario_id <> p_actor then
    raise exception 'Tu sesión no es válida: vuelve a iniciar sesión';
  end if;
  select * into dueno from usuarios where id = p_actor and activo;
  if dueno.id is null then
    raise exception 'Tu sesión no es válida: vuelve a iniciar sesión';
  end if;
  -- En transacciones de solo lectura (PostgREST/STABLE) el UPDATE puede
  -- reventar: se salta en ese caso (parche RutaNeto 2026-11-19).
  begin
    update sesiones set ultimo_uso = now() where id = s.id;
  exception when read_only_sql_transaction then
    null;
  end;
end;
$$;

create or replace function pr_revocar_sesiones(p_usuario uuid)
returns void language plpgsql security definer as $$
begin
  update sesiones set revocada_en = now()
  where usuario_id = p_usuario and revocada_en is null;
end;
$$;

create or replace function pr_cerrar_sesion(p_token text)
returns void language plpgsql security definer as $$
begin
  if p_token is null then return; end if;
  update sesiones set revocada_en = now()
  where token_hash = pr_hash_token(p_token) and revocada_en is null;
end;
$$;

create or replace function pr_licencia_ok(p_empresa uuid) returns boolean
language sql stable as $$
  select exists (
    select 1 from empresas e
    join licencias l on l.empresa_id = e.id
    where e.id = p_empresa and e.activa
      and l.estado = 'activa' and (l.vence is null or l.vence >= pr_hoy())
  );
$$;

create or replace function pr_registrar_accion(p_empresa uuid, p_actor uuid,
                                               p_accion text, p_detalle text)
returns void language plpgsql security definer as $$
begin
  insert into registro_actividad (empresa_id, actor_id, accion, detalle)
  values (p_empresa, p_actor, p_accion, p_detalle);
end;
$$;

create or replace function pr_exigir_superadmin(p_quien uuid) returns usuarios
language plpgsql stable security definer as $$
declare q usuarios;
begin
  select * into q from usuarios where id = p_quien and activo;
  if q.id is null or q.rol <> 'superadmin' then
    raise exception 'Esta operación es solo del administrador de TallerNeto';
  end if;
  return q;
end;
$$;

-- EL candado central: valida el actor (sesión + usuario activo) y que
-- pertenece a p_empresa (o es superadmin en modo consulta). Devuelve
-- al actor. Toda función de negocio pasa por aquí.
create or replace function pr_actor_empresa(p_empresa uuid, p_quien uuid, p_token text)
returns usuarios language plpgsql security definer as $$
declare q usuarios;
begin
  if p_quien is null then
    raise exception 'Debes iniciar sesión: falta quién hace esta operación';
  end if;
  perform pr_validar_token(p_quien, p_token);
  select * into q from usuarios where id = p_quien and activo;
  if q.id is null then raise exception 'Usuario no válido'; end if;
  if q.rol = 'superadmin' then return q; end if;
  if q.empresa_id is distinct from p_empresa then
    raise exception 'No tienes permiso para operar en esta empresa';
  end if;
  return q;
end;
$$;

-- Exige además un rol concreto (p. ej. solo admin crea usuarios).
create or replace function pr_actor_con_rol(p_empresa uuid, p_quien uuid, p_token text,
                                           p_roles text[])
returns usuarios language plpgsql security definer as $$
declare q usuarios;
begin
  q := pr_actor_empresa(p_empresa, p_quien, p_token);
  if q.rol = 'superadmin' then
    raise exception 'El administrador de TallerNeto no opera dentro de las empresas: entra como consulta';
  end if;
  if not (q.rol = any (p_roles)) then
    raise exception 'Tu rol (%) no puede hacer esta operación', q.rol;
  end if;
  return q;
end;
$$;

-- ================================================================
-- SESIÓN
-- ================================================================
create or replace function pr_iniciar_sesion(p_codigo text, p_pin text, p_contexto text default null)
returns jsonb language plpgsql security definer as $$
declare
  candidatos int := 0;
  u usuarios;
  e empresas;
  lic licencias;
  v_token text;
  v_expira timestamptz;
begin
  select count(*) into candidatos
  from usuarios x
  where x.activo and upper(x.codigo) = upper(trim(p_codigo))
    and pr_verificar_pin(p_pin, x.pin_hash);

  if candidatos = 0 then
    raise exception 'Código o PIN incorrecto';
  end if;
  if candidatos > 1 then
    raise exception 'Ese código existe en más de una empresa. Pide ayuda a TallerNeto para entrar.';
  end if;

  select * into u from usuarios x
  where x.activo and upper(x.codigo) = upper(trim(p_codigo))
    and pr_verificar_pin(p_pin, x.pin_hash);

  -- Superadmin (dueño del sistema): sin empresa ni licencia.
  if u.empresa_id is null then
    if p_contexto = 'panel' and u.rol <> 'superadmin' then
      raise exception 'Esta cuenta no entra por el panel de empresa';
    end if;
    v_token := pr_gen_token();
    v_expira := now() + interval '12 hours';
    insert into sesiones (usuario_id, empresa_id, contexto, token_hash, expira_en)
    values (u.id, null, p_contexto, pr_hash_token(v_token), v_expira);
    return jsonb_build_object(
      'usuario', jsonb_build_object('id', u.id, 'nombre', u.nombre, 'codigo', u.codigo, 'rol', u.rol),
      'empresa', null,
      'licencia', null,
      'sesion', jsonb_build_object('token', v_token, 'expiraEn', v_expira)
    );
  end if;

  select * into e from empresas where id = u.empresa_id;
  if e.id is null or not e.activa then
    raise exception 'Tu empresa está inactiva. Contacta a TallerNeto.';
  end if;

  select * into lic from licencias where empresa_id = e.id order by creada_en desc limit 1;
  if lic.id is null then
    raise exception 'Tu empresa todavía no tiene licencia. Contacta a TallerNeto.';
  end if;
  if lic.estado = 'suspendida' then
    raise exception 'La licencia de tu empresa está suspendida. Contacta a TallerNeto.';
  end if;
  if lic.estado = 'vencida' or (lic.vence is not null and lic.vence < pr_hoy()) then
    raise exception 'La licencia de tu empresa está vencida. Contacta a TallerNeto para renovarla.';
  end if;

  perform pr_registrar_accion(u.empresa_id, u.id, 'inicio_sesion',
    case p_contexto when 'panel' then 'Inició sesión por el panel'
                    else 'Inició sesión' end);

  v_token := pr_gen_token();
  v_expira := now() + interval '12 hours';
  insert into sesiones (usuario_id, empresa_id, contexto, token_hash, expira_en)
  values (u.id, u.empresa_id, p_contexto, pr_hash_token(v_token), v_expira);

  return jsonb_build_object(
    'usuario', jsonb_build_object('id', u.id, 'nombre', u.nombre, 'codigo', u.codigo, 'rol', u.rol),
    'empresa', jsonb_build_object('id', e.id, 'nombre', e.nombre),
    'licencia', jsonb_build_object(
      'estado', lic.estado,
      'vence', lic.vence,
      'maxVehiculos', lic.max_vehiculos,
      'diasRestantes', case when lic.vence is null then null else lic.vence - pr_hoy() end,
      'porVencer', case when lic.vence is null then false
                        else (lic.vence - pr_hoy()) between 0 and 30 end
    ),
    'sesion', jsonb_build_object('token', v_token, 'expiraEn', v_expira)
  );
end;
$$;

-- ================================================================
-- SNAPSHOT: la foto completa que pinta el panel + el resumen
-- (alertas de stock bajo, herramientas fuera, costo por vehículo).
-- ================================================================
create or replace function pr_snapshot(p_empresa uuid default null,
                                       p_quien uuid default null,
                                       p_token text default null)
returns jsonb language plpgsql security definer as $$
declare
  q usuarios;
  e empresas;
  lic licencias;
  v_empresa uuid;
  v_mes date := date_trunc('month', pr_hoy())::date;
begin
  q := pr_actor_empresa(p_empresa, p_quien, p_token);
  v_empresa := coalesce(p_empresa, q.empresa_id);
  if v_empresa is null then
    raise exception 'Indica qué empresa quieres ver';
  end if;
  -- Un usuario de empresa solo ve LA SUYA (pr_actor_empresa ya lo validó
  -- cuando p_empresa venía; si venía null, v_empresa es la suya).
  if q.rol <> 'superadmin' and v_empresa is distinct from q.empresa_id then
    raise exception 'No tienes permiso para ver esta empresa';
  end if;

  select * into e from empresas where id = v_empresa;
  if e.id is null then raise exception 'Empresa no encontrada'; end if;
  select * into lic from licencias where empresa_id = v_empresa order by creada_en desc limit 1;

  return jsonb_build_object(
    'empresa', jsonb_build_object('id', e.id, 'nombre', e.nombre, 'activa', e.activa),
    'licencia', case when lic.id is null then null else jsonb_build_object(
      'estado', lic.estado, 'vence', lic.vence, 'maxVehiculos', lic.max_vehiculos,
      'diasRestantes', case when lic.vence is null then null else lic.vence - pr_hoy() end,
      'porVencer', case when lic.vence is null then false
                        else (lic.vence - pr_hoy()) between 0 and 30 end
    ) end,
    'usuarios', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', u.id, 'rol', u.rol, 'nombre', u.nombre, 'codigo', u.codigo, 'activo', u.activo
      ) order by u.codigo)
      from usuarios u where u.empresa_id = v_empresa
    ), '[]'::jsonb),
    'vehiculos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', v.id, 'codigo', v.codigo, 'placa', v.placa, 'marca', v.marca,
        'modelo', v.modelo, 'anio', v.anio, 'estado', v.estado, 'activo', v.activo
      ) order by v.codigo)
      from vehiculos v where v.empresa_id = v_empresa
    ), '[]'::jsonb),
    'piezas', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id, 'codigo', p.codigo, 'nombre', p.nombre, 'ubicacion', p.ubicacion,
        'costo', p.costo, 'stock', p.stock, 'stockMinimo', p.stock_minimo, 'activa', p.activa
      ) order by p.codigo)
      from piezas p where p.empresa_id = v_empresa
    ), '[]'::jsonb),
    'movimientos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', m.id, 'tipo', m.tipo, 'piezaId', m.pieza_id, 'cantidad', m.cantidad,
        'costoUnitario', m.costo_unitario, 'vehiculoId', m.vehiculo_id,
        'usuarioId', m.usuario_id, 'nota', m.nota, 'fecha', m.fecha,
        'creadaEn', m.creada_en
      ) order by m.creada_en desc)
      from (select * from movimientos where empresa_id = v_empresa
            order by creada_en desc limit 300) m
    ), '[]'::jsonb),
    'herramientas', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', h.id, 'codigo', h.codigo, 'nombre', h.nombre, 'estado', h.estado, 'activa', h.activa
      ) order by h.codigo)
      from herramientas h where h.empresa_id = v_empresa
    ), '[]'::jsonb),
    'prestamos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', pr.id, 'herramientaId', pr.herramienta_id, 'responsableId', pr.responsable_id,
        'fechaSalida', pr.fecha_salida, 'fechaDevolucion', pr.fecha_devolucion
      ) order by pr.fecha_salida desc)
      from (select * from prestamos where empresa_id = v_empresa
            order by fecha_salida desc limit 200) pr
    ), '[]'::jsonb),
    -- Costo por vehículo: salidas (cantidad × costo_unitario), mes y total.
    'costos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'vehiculoId', c.vehiculo_id,
        'costoMes', c.costo_mes,
        'costoTotal', c.costo_total,
        'numSalidas', c.num_salidas
      ))
      from (
        select v.id as vehiculo_id,
               coalesce(sum(case when m.fecha >= v_mes
                                 then m.cantidad * m.costo_unitario end), 0) as costo_mes,
               coalesce(sum(m.cantidad * m.costo_unitario), 0) as costo_total,
               count(m.id) as num_salidas
        from vehiculos v
        left join movimientos m
          on m.vehiculo_id = v.id and m.tipo = 'salida' and m.empresa_id = v_empresa
        where v.empresa_id = v_empresa
        group by v.id
      ) c
    ), '[]'::jsonb)
  );
end;
$$;

-- ================================================================
-- USUARIOS
-- ================================================================
create or replace function pr_crear_usuario(p_empresa uuid, p_nombre text, p_codigo text,
                                            p_rol text, p_pin text default null,
                                            p_quien uuid default null,
                                            p_token text default null)
returns usuarios language plpgsql security definer as $$
declare
  nuevo usuarios;
  q usuarios;
begin
  q := pr_actor_con_rol(p_empresa, p_quien, p_token, array['admin']);
  if p_rol not in ('admin','almacen','mecanico') then
    raise exception 'Rol no válido: %', p_rol;
  end if;
  if p_pin is null or length(trim(p_pin)) = 0 then
    raise exception 'El PIN es obligatorio: indica un PIN de 4 a 6 dígitos para el usuario nuevo';
  end if;
  if trim(p_pin) !~ '^[0-9]{4,6}$' then
    raise exception 'El PIN debe tener de 4 a 6 dígitos';
  end if;
  if trim(p_pin) = '1234' then
    raise exception 'El PIN 1234 está prohibido por seguridad: elige otro PIN';
  end if;
  if exists (select 1 from usuarios
             where empresa_id = p_empresa and upper(codigo) = upper(trim(p_codigo))) then
    raise exception 'Ya existe un usuario con el código %', p_codigo;
  end if;
  insert into usuarios (empresa_id, rol, nombre, codigo, pin_hash)
  values (p_empresa, p_rol, trim(p_nombre), trim(p_codigo), pr_hash_pin(trim(p_pin)))
  returning * into nuevo;
  perform pr_registrar_accion(p_empresa, q.id, 'usuario_creado',
    format('Se creó el usuario %s (%s, %s)', nuevo.codigo, nuevo.nombre, nuevo.rol));
  return nuevo;
end;
$$;

create or replace function pr_cambiar_activo_usuario(p_usuario uuid, p_activo boolean,
                                                     p_quien uuid default null,
                                                     p_token text default null)
returns void language plpgsql security definer as $$
declare u usuarios;
begin
  select * into u from usuarios where id = p_usuario;
  if u.id is null then raise exception 'Usuario no encontrado'; end if;
  perform pr_actor_con_rol(u.empresa_id, p_quien, p_token, array['admin']);
  update usuarios set activo = p_activo where id = p_usuario;
  if not p_activo then
    perform pr_revocar_sesiones(p_usuario);
  end if;
  perform pr_registrar_accion(u.empresa_id, p_quien, 'usuario_editado',
    format('%s al usuario %s (%s)', case when p_activo then 'Se activó' else 'Se desactivó' end,
           u.codigo, u.nombre));
end;
$$;

create or replace function pr_cambiar_pin(p_usuario uuid, p_pin_actual text,
                                          p_pin_nuevo text)
returns boolean language plpgsql security definer as $$
declare u usuarios;
begin
  select * into u from usuarios where id = p_usuario;
  if u.id is null then raise exception 'Usuario no encontrado'; end if;
  if not pr_verificar_pin(p_pin_actual, u.pin_hash) then
    raise exception 'El PIN actual no es correcto';
  end if;
  if p_pin_nuevo is null or trim(p_pin_nuevo) !~ '^[0-9]{4,6}$' then
    raise exception 'El PIN nuevo debe tener de 4 a 6 dígitos';
  end if;
  if trim(p_pin_nuevo) = '1234' then
    raise exception 'El PIN 1234 está prohibido por seguridad: elige otro PIN';
  end if;
  update usuarios set pin_hash = pr_hash_pin(trim(p_pin_nuevo)) where id = p_usuario;
  perform pr_revocar_sesiones(p_usuario);
  perform pr_registrar_accion(u.empresa_id, p_usuario, 'pin_cambiado', 'Cambió su PIN de acceso');
  return true;
end;
$$;

-- ================================================================
-- VEHÍCULOS
-- ================================================================
create or replace function pr_crear_vehiculo(p_empresa uuid, p_codigo text, p_placa text,
                                             p_marca text, p_modelo text, p_anio int,
                                             p_quien uuid default null,
                                             p_token text default null)
returns vehiculos language plpgsql security definer as $$
declare
  nuevo vehiculos;
  lic licencias;
  ya int;
  q usuarios;
begin
  q := pr_actor_con_rol(p_empresa, p_quien, p_token, array['admin','almacen']);
  select * into lic from licencias where empresa_id = p_empresa order by creada_en desc limit 1;
  if lic.max_vehiculos is not null then
    select count(*) into ya from vehiculos where empresa_id = p_empresa and activo;
    if ya >= lic.max_vehiculos then
      raise exception 'Tu licencia permite hasta % vehículos. Contacta a TallerNeto para ampliarla.', lic.max_vehiculos;
    end if;
  end if;
  if exists (select 1 from vehiculos
             where empresa_id = p_empresa and upper(codigo) = upper(trim(p_codigo))) then
    raise exception 'Ya existe un vehículo con el código %', p_codigo;
  end if;
  if exists (select 1 from vehiculos
             where empresa_id = p_empresa and upper(placa) = upper(trim(p_placa))) then
    raise exception 'Ya existe un vehículo con la placa %', p_placa;
  end if;
  insert into vehiculos (empresa_id, codigo, placa, marca, modelo, anio)
  values (p_empresa, trim(p_codigo), trim(p_placa), trim(p_marca), trim(p_modelo), p_anio)
  returning * into nuevo;
  perform pr_registrar_accion(p_empresa, q.id, 'vehiculo_creado',
    format('Se creó el vehículo %s (%s %s, placa %s)', nuevo.codigo, nuevo.marca, nuevo.modelo, nuevo.placa));
  return nuevo;
end;
$$;

create or replace function pr_actualizar_vehiculo(p_vehiculo uuid, p_placa text, p_marca text,
                                                  p_modelo text, p_anio int, p_estado text,
                                                  p_quien uuid default null,
                                                  p_token text default null)
returns void language plpgsql security definer as $$
declare v vehiculos;
begin
  select * into v from vehiculos where id = p_vehiculo;
  if v.id is null then raise exception 'Vehículo no encontrado'; end if;
  perform pr_actor_con_rol(v.empresa_id, p_quien, p_token, array['admin','almacen']);
  if p_estado not in ('activo','en_taller','fuera_servicio') then
    raise exception 'Estado no válido: %', p_estado;
  end if;
  if exists (select 1 from vehiculos
             where empresa_id = v.empresa_id and id <> p_vehiculo
               and upper(placa) = upper(trim(p_placa))) then
    raise exception 'Ya existe otro vehículo con la placa %', p_placa;
  end if;
  update vehiculos
  set placa = trim(p_placa), marca = trim(p_marca), modelo = trim(p_modelo),
      anio = p_anio, estado = p_estado
  where id = p_vehiculo;
end;
$$;

-- ================================================================
-- PIEZAS
-- ================================================================
create or replace function pr_crear_pieza(p_empresa uuid, p_codigo text, p_nombre text,
                                          p_ubicacion text, p_costo numeric, p_stock int,
                                          p_stock_minimo int,
                                          p_quien uuid default null,
                                          p_token text default null)
returns piezas language plpgsql security definer as $$
declare
  nueva piezas;
  q usuarios;
begin
  q := pr_actor_con_rol(p_empresa, p_quien, p_token, array['admin','almacen']);
  if p_costo is null or p_costo < 0 then raise exception 'El costo no puede ser negativo'; end if;
  if p_stock is null or p_stock < 0 then raise exception 'El stock inicial no puede ser negativo'; end if;
  if p_stock_minimo is null or p_stock_minimo < 0 then raise exception 'El stock mínimo no puede ser negativo'; end if;
  if exists (select 1 from piezas
             where empresa_id = p_empresa and upper(codigo) = upper(trim(p_codigo))) then
    raise exception 'Ya existe una pieza con el código %', p_codigo;
  end if;
  insert into piezas (empresa_id, codigo, nombre, ubicacion, costo, stock, stock_minimo)
  values (p_empresa, trim(p_codigo), trim(p_nombre), nullif(trim(p_ubicacion), ''),
          p_costo, p_stock, p_stock_minimo)
  returning * into nueva;
  perform pr_registrar_accion(p_empresa, q.id, 'pieza_creada',
    format('Se creó la pieza %s (%s)', nueva.codigo, nueva.nombre));
  return nueva;
end;
$$;

create or replace function pr_actualizar_pieza(p_pieza uuid, p_nombre text, p_ubicacion text,
                                               p_costo numeric, p_stock_minimo int,
                                               p_quien uuid default null,
                                               p_token text default null)
returns void language plpgsql security definer as $$
declare p piezas;
begin
  select * into p from piezas where id = p_pieza;
  if p.id is null then raise exception 'Pieza no encontrada'; end if;
  perform pr_actor_con_rol(p.empresa_id, p_quien, p_token, array['admin','almacen']);
  if p_costo is null or p_costo < 0 then raise exception 'El costo no puede ser negativo'; end if;
  if p_stock_minimo is null or p_stock_minimo < 0 then raise exception 'El stock mínimo no puede ser negativo'; end if;
  -- El stock NO se edita aquí: se mueve solo con entradas/salidas
  -- (pr_registrar_movimiento), para que el inventario siempre cuadre.
  update piezas
  set nombre = trim(p_nombre), ubicacion = nullif(trim(p_ubicacion), ''),
      costo = p_costo, stock_minimo = p_stock_minimo
  where id = p_pieza;
end;
$$;

-- ================================================================
-- MOVIMIENTOS: la función corazón del inventario.
-- Valida token + actor de la empresa, pieza de la empresa, vehículo
-- OBLIGATORIO en salidas y stock suficiente. Ajusta el stock y copia
-- el costo vigente de la pieza al movimiento.
-- ================================================================
create or replace function pr_registrar_movimiento(p_empresa uuid, p_tipo text, p_pieza uuid,
                                                   p_cantidad int, p_vehiculo uuid default null,
                                                   p_nota text default null,
                                                   p_quien uuid default null,
                                                   p_token text default null)
returns movimientos language plpgsql security definer as $$
declare
  q usuarios;
  p piezas;
  v vehiculos;
  nuevo movimientos;
begin
  q := pr_actor_empresa(p_empresa, p_quien, p_token);
  if q.rol = 'superadmin' then
    raise exception 'El administrador de TallerNeto no registra movimientos: entra con una cuenta de la empresa';
  end if;
  if p_tipo not in ('entrada','salida') then
    raise exception 'Tipo de movimiento no válido: %', p_tipo;
  end if;
  if p_cantidad is null or p_cantidad <= 0 then
    raise exception 'La cantidad debe ser mayor que cero';
  end if;

  select * into p from piezas where id = p_pieza and empresa_id = p_empresa;
  if p.id is null then raise exception 'Pieza no encontrada en esta empresa'; end if;
  if not p.activa then raise exception 'La pieza % está inactiva', p.codigo; end if;

  if p_tipo = 'salida' then
    if p_vehiculo is null then
      raise exception 'Toda salida debe decir a qué vehículo se le montó la pieza';
    end if;
    select * into v from vehiculos where id = p_vehiculo and empresa_id = p_empresa;
    if v.id is null then raise exception 'Vehículo no encontrado en esta empresa'; end if;
    if p.stock < p_cantidad then
      raise exception 'Stock insuficiente de % (%): quedan % y pides %',
        p.nombre, p.codigo, p.stock, p_cantidad;
    end if;
  end if;

  insert into movimientos (empresa_id, tipo, pieza_id, cantidad, costo_unitario,
                           vehiculo_id, usuario_id, nota, fecha)
  values (p_empresa, p_tipo, p_pieza, p_cantidad, p.costo,
          case when p_tipo = 'salida' then p_vehiculo else null end,
          q.id, nullif(trim(p_nota), ''), pr_hoy())
  returning * into nuevo;

  update piezas
  set stock = stock + case when p_tipo = 'entrada' then p_cantidad else -p_cantidad end
  where id = p_pieza;

  perform pr_registrar_accion(p_empresa, q.id,
    case when p_tipo = 'entrada' then 'movimiento_entrada' else 'movimiento_salida' end,
    case when p_tipo = 'entrada'
         then format('Entrada de %s × %s (%s)', p_cantidad, p.nombre, p.codigo)
         else format('Salida de %s × %s (%s) para el vehículo %s (%s)',
                     p_cantidad, p.nombre, p.codigo, v.codigo, v.placa) end);
  return nuevo;
end;
$$;

-- ================================================================
-- HERRAMIENTAS Y PRÉSTAMOS
-- ================================================================
create or replace function pr_crear_herramienta(p_empresa uuid, p_codigo text, p_nombre text,
                                                p_quien uuid default null,
                                                p_token text default null)
returns herramientas language plpgsql security definer as $$
declare
  nueva herramientas;
  q usuarios;
begin
  q := pr_actor_con_rol(p_empresa, p_quien, p_token, array['admin','almacen']);
  if exists (select 1 from herramientas
             where empresa_id = p_empresa and upper(codigo) = upper(trim(p_codigo))) then
    raise exception 'Ya existe una herramienta con el código %', p_codigo;
  end if;
  insert into herramientas (empresa_id, codigo, nombre)
  values (p_empresa, trim(p_codigo), trim(p_nombre))
  returning * into nueva;
  perform pr_registrar_accion(p_empresa, q.id, 'herramienta_creada',
    format('Se creó la herramienta %s (%s)', nueva.codigo, nueva.nombre));
  return nueva;
end;
$$;

-- Cambiar el estado de taller (disponible <-> reparación). Una
-- herramienta prestada NO se mueve aquí: se devuelve con
-- pr_devolver_herramienta.
create or replace function pr_cambiar_estado_herramienta(p_herramienta uuid, p_estado text,
                                                         p_quien uuid default null,
                                                         p_token text default null)
returns void language plpgsql security definer as $$
declare h herramientas;
begin
  select * into h from herramientas where id = p_herramienta;
  if h.id is null then raise exception 'Herramienta no encontrada'; end if;
  perform pr_actor_con_rol(h.empresa_id, p_quien, p_token, array['admin','almacen']);
  if p_estado not in ('disponible','reparacion') then
    raise exception 'Desde aquí la herramienta solo pasa a disponible o a reparación; para prestarla usa el préstamo';
  end if;
  if h.estado = 'prestada' then
    raise exception 'La herramienta está prestada: primero hay que devolverla';
  end if;
  update herramientas set estado = p_estado where id = p_herramienta;
end;
$$;

create or replace function pr_prestar_herramienta(p_herramienta uuid, p_responsable uuid,
                                                  p_quien uuid default null,
                                                  p_token text default null)
returns prestamos language plpgsql security definer as $$
declare
  h herramientas;
  r usuarios;
  nuevo prestamos;
  q usuarios;
begin
  select * into h from herramientas where id = p_herramienta;
  if h.id is null then raise exception 'Herramienta no encontrada'; end if;
  q := pr_actor_empresa(h.empresa_id, p_quien, p_token);
  if q.rol = 'superadmin' then
    raise exception 'El administrador de TallerNeto no presta herramientas: entra con una cuenta de la empresa';
  end if;
  if h.estado <> 'disponible' then
    raise exception 'La herramienta % no está disponible (está %)', h.codigo, h.estado;
  end if;
  select * into r from usuarios
  where id = p_responsable and empresa_id = h.empresa_id and activo;
  if r.id is null then
    raise exception 'El responsable debe ser un usuario activo de esta empresa';
  end if;
  insert into prestamos (empresa_id, herramienta_id, responsable_id, registrada_por)
  values (h.empresa_id, h.id, r.id, q.id)
  returning * into nuevo;
  update herramientas set estado = 'prestada' where id = h.id;
  perform pr_registrar_accion(h.empresa_id, q.id, 'herramienta_prestada',
    format('Se prestó %s (%s) a %s (%s)', h.nombre, h.codigo, r.nombre, r.codigo));
  return nuevo;
end;
$$;

create or replace function pr_devolver_herramienta(p_herramienta uuid,
                                                   p_quien uuid default null,
                                                   p_token text default null)
returns void language plpgsql security definer as $$
declare
  h herramientas;
  pr prestamos;
  q usuarios;
begin
  select * into h from herramientas where id = p_herramienta;
  if h.id is null then raise exception 'Herramienta no encontrada'; end if;
  q := pr_actor_empresa(h.empresa_id, p_quien, p_token);
  if q.rol = 'superadmin' then
    raise exception 'El administrador de TallerNeto no devuelve herramientas: entra con una cuenta de la empresa';
  end if;
  select * into pr from prestamos
  where herramienta_id = h.id and fecha_devolucion is null;
  if pr.id is null then
    raise exception 'La herramienta % no tiene un préstamo abierto', h.codigo;
  end if;
  update prestamos
  set fecha_devolucion = now(), devuelta_por = q.id
  where id = pr.id;
  update herramientas set estado = 'disponible' where id = h.id;
  perform pr_registrar_accion(h.empresa_id, q.id, 'herramienta_devuelta',
    format('Se devolvió %s (%s)', h.nombre, h.codigo));
end;
$$;


-- === archivo: trabajos.sql ===
-- TallerNeto · Extensión: TRABAJOS Y PAGO DE MECÁNICOS (destajo)
-- Se aplica DESPUÉS de servidor/esquema.sql. NO modifica esquema.sql:
-- todo es idempotente (create if not exists / create or replace).
--
-- Modelo (como las rutas EXTRA de RutaNeto):
--  - La administración mantiene un CATÁLOGO de tipos de trabajo, cada
--    uno con su precio de mano de obra (lo que se le paga al mecánico).
--  - El mecánico registra un trabajo terminado (vehículo + tipo +
--    descripción opcional + piezas usadas opcionales). Nace PENDIENTE
--    y guarda precio_snapshot: el precio del catálogo EN ESE MOMENTO
--    (si el catálogo cambia después, lo ya registrado no se mueve).
--  - La administración VALIDA o RECHAZA en el panel. Solo lo validado
--    cuenta para el pago: pago del período = suma de precio_snapshot
--    de los trabajos validados del mecánico.
--  - Al VALIDAR, las piezas usadas salen del inventario amarradas al
--    vehículo (movimientos de salida, misma lógica y mismas
--    validaciones que pr_registrar_movimiento). Si falta stock, la
--    validación FALLA con error claro y el trabajo queda pendiente.
--    Si se RECHAZA, no se mueve inventario.
-- Mismos patrones pr_*: token de sesión, actor y empresa validados,
-- fechas del negocio en hora RD (pr_hoy()).

-- ============ CATÁLOGO DE TIPOS DE TRABAJO ============
create table if not exists tipos_trabajo (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references empresas(id) on delete cascade,
  codigo text not null,
  nombre text not null,
  precio_mano_obra numeric(12,2) not null default 0 check (precio_mano_obra >= 0),
  activo boolean not null default true,
  creada_en timestamptz not null default now(),
  unique (empresa_id, codigo)
);

-- ============ TRABAJOS REGISTRADOS POR LOS MECÁNICOS ============
create table if not exists trabajos (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references empresas(id) on delete cascade,
  mecanico_id uuid not null references usuarios(id),
  vehiculo_id uuid not null references vehiculos(id),
  tipo_trabajo_id uuid not null references tipos_trabajo(id),
  descripcion text,
  -- Precio de mano de obra del catálogo AL REGISTRAR: el pago no
  -- cambia si la administración edita el catálogo después.
  precio_snapshot numeric(12,2) not null default 0 check (precio_snapshot >= 0),
  estado text not null default 'pendiente'
    check (estado in ('pendiente','validada','rechazada')),
  fecha date not null default (now() at time zone 'America/Santo_Domingo')::date,
  validado_por uuid references usuarios(id),
  validado_en timestamptz,
  nota_admin text,
  creada_en timestamptz not null default now()
);
create index if not exists idx_trabajos_empresa_fecha on trabajos(empresa_id, fecha desc);
create index if not exists idx_trabajos_mecanico on trabajos(empresa_id, mecanico_id, fecha desc);

-- Piezas que el mecánico dice haber usado en el trabajo. NO mueven
-- stock al registrar: salen del inventario recién al VALIDAR.
create table if not exists trabajo_piezas (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references empresas(id) on delete cascade,
  trabajo_id uuid not null references trabajos(id) on delete cascade,
  pieza_id uuid not null references piezas(id),
  cantidad int not null check (cantidad > 0),
  unique (trabajo_id, pieza_id)
);
create index if not exists idx_trabajo_piezas_trabajo on trabajo_piezas(trabajo_id);

alter table tipos_trabajo enable row level security;
alter table trabajos enable row level security;
alter table trabajo_piezas enable row level security;

-- ================================================================
-- AYUDANTE INTERNO: salida de inventario por validación de trabajo.
-- Es la MISMA lógica de pr_registrar_movimiento (pieza de la empresa
-- y activa, stock suficiente, copia el costo vigente al movimiento y
-- descuenta), pero sin validar actor: quien llama (pr_validar_trabajo)
-- ya validó actor, rol y empresa. El movimiento queda a nombre del
-- MECÁNICO (él consumió la pieza en su trabajo).
-- ================================================================
create or replace function pr__salida_por_trabajo(p_empresa uuid, p_pieza uuid,
                                                  p_cantidad int, p_vehiculo uuid,
                                                  p_mecanico uuid, p_nota text)
returns void language plpgsql security definer as $$
declare
  pz piezas;
  vh vehiculos;
begin
  select * into pz from piezas where id = p_pieza and empresa_id = p_empresa;
  if pz.id is null then raise exception 'Pieza no encontrada en esta empresa'; end if;
  if not pz.activa then raise exception 'La pieza % está inactiva', pz.codigo; end if;
  select * into vh from vehiculos where id = p_vehiculo and empresa_id = p_empresa;
  if vh.id is null then raise exception 'Vehículo no encontrado en esta empresa'; end if;
  if pz.stock < p_cantidad then
    raise exception 'No se puede validar: stock insuficiente de % (%): quedan % y el trabajo usa %',
      pz.nombre, pz.codigo, pz.stock, p_cantidad;
  end if;
  insert into movimientos (empresa_id, tipo, pieza_id, cantidad, costo_unitario,
                           vehiculo_id, usuario_id, nota, fecha)
  values (p_empresa, 'salida', pz.id, p_cantidad, pz.costo,
          vh.id, p_mecanico, p_nota, pr_hoy());
  update piezas set stock = stock - p_cantidad where id = pz.id;
end;
$$;

-- ================================================================
-- CATÁLOGO (solo administración)
-- ================================================================
create or replace function pr_crear_tipo_trabajo(p_empresa uuid, p_codigo text, p_nombre text,
                                                 p_precio numeric,
                                                 p_quien uuid default null,
                                                 p_token text default null)
returns tipos_trabajo language plpgsql security definer as $$
declare
  nuevo tipos_trabajo;
  q usuarios;
begin
  q := pr_actor_con_rol(p_empresa, p_quien, p_token, array['admin']);
  if p_precio is null or p_precio < 0 then
    raise exception 'El precio de mano de obra no puede ser negativo';
  end if;
  if exists (select 1 from tipos_trabajo
             where empresa_id = p_empresa and upper(codigo) = upper(trim(p_codigo))) then
    raise exception 'Ya existe un tipo de trabajo con el código %', p_codigo;
  end if;
  insert into tipos_trabajo (empresa_id, codigo, nombre, precio_mano_obra)
  values (p_empresa, trim(p_codigo), trim(p_nombre), p_precio)
  returning * into nuevo;
  perform pr_registrar_accion(p_empresa, q.id, 'tipo_trabajo_creado',
    format('Se creó el trabajo %s (%s) a RD$%s', nuevo.codigo, nuevo.nombre, nuevo.precio_mano_obra));
  return nuevo;
end;
$$;

create or replace function pr_actualizar_tipo_trabajo(p_tipo uuid, p_nombre text,
                                                      p_precio numeric, p_activo boolean,
                                                      p_quien uuid default null,
                                                      p_token text default null)
returns void language plpgsql security definer as $$
declare t tipos_trabajo;
begin
  select * into t from tipos_trabajo where id = p_tipo;
  if t.id is null then raise exception 'Tipo de trabajo no encontrado'; end if;
  perform pr_actor_con_rol(t.empresa_id, p_quien, p_token, array['admin']);
  if p_precio is null or p_precio < 0 then
    raise exception 'El precio de mano de obra no puede ser negativo';
  end if;
  -- OJO: cambiar el precio SOLO afecta trabajos futuros; los ya
  -- registrados guardan su precio_snapshot y no se tocan.
  update tipos_trabajo
  set nombre = trim(p_nombre), precio_mano_obra = p_precio, activo = p_activo
  where id = p_tipo;
end;
$$;

-- ================================================================
-- REGISTRAR TRABAJO (la app del mecánico)
-- El mecánico SOLO se registra a sí mismo: mecanico_id es siempre el
-- actor de la sesión (rol mecanico). Las piezas usadas quedan
-- anotadas; el stock se descuenta recién al validar.
-- p_piezas: jsonb [{"piezaId": uuid, "cantidad": n}, …] (opcional).
-- ================================================================
create or replace function pr_registrar_trabajo(p_empresa uuid, p_vehiculo uuid, p_tipo uuid,
                                                p_descripcion text default null,
                                                p_piezas jsonb default null,
                                                p_quien uuid default null,
                                                p_token text default null)
returns trabajos language plpgsql security definer as $$
declare
  q usuarios;
  v vehiculos;
  t tipos_trabajo;
  nuevo trabajos;
  item jsonb;
  v_pieza uuid;
  v_cantidad int;
  pz piezas;
begin
  q := pr_actor_con_rol(p_empresa, p_quien, p_token, array['mecanico']);

  select * into v from vehiculos where id = p_vehiculo and empresa_id = p_empresa;
  if v.id is null then raise exception 'Vehículo no encontrado en esta empresa'; end if;
  if not v.activo then raise exception 'El vehículo % está inactivo', v.codigo; end if;

  select * into t from tipos_trabajo where id = p_tipo and empresa_id = p_empresa;
  if t.id is null then raise exception 'Tipo de trabajo no encontrado en esta empresa'; end if;
  if not t.activo then raise exception 'El trabajo % está inactivo en el catálogo', t.codigo; end if;

  insert into trabajos (empresa_id, mecanico_id, vehiculo_id, tipo_trabajo_id,
                        descripcion, precio_snapshot, estado, fecha)
  values (p_empresa, q.id, v.id, t.id,
          nullif(trim(p_descripcion), ''), t.precio_mano_obra, 'pendiente', pr_hoy())
  returning * into nuevo;

  if p_piezas is not null and jsonb_typeof(p_piezas) = 'array' then
    for item in select * from jsonb_array_elements(p_piezas) loop
      v_pieza := (item ->> 'piezaId')::uuid;
      v_cantidad := coalesce((item ->> 'cantidad')::int, 0);
      if v_cantidad <= 0 then
        raise exception 'La cantidad de piezas usadas debe ser mayor que cero';
      end if;
      select * into pz from piezas where id = v_pieza and empresa_id = p_empresa;
      if pz.id is null then raise exception 'Pieza no encontrada en esta empresa'; end if;
      if not pz.activa then raise exception 'La pieza % está inactiva', pz.codigo; end if;
      insert into trabajo_piezas (empresa_id, trabajo_id, pieza_id, cantidad)
      values (p_empresa, nuevo.id, pz.id, v_cantidad)
      on conflict (trabajo_id, pieza_id)
        do update set cantidad = trabajo_piezas.cantidad + excluded.cantidad;
    end loop;
  end if;

  perform pr_registrar_accion(p_empresa, q.id, 'trabajo_registrado',
    format('Registró el trabajo %s (%s) en el vehículo %s (%s): RD$%s, pendiente de validación',
           t.nombre, t.codigo, v.codigo, v.placa, nuevo.precio_snapshot));
  return nuevo;
end;
$$;

-- ================================================================
-- VALIDAR (admin o almacén): el trabajo pasa a contar para el pago
-- y sus piezas salen del inventario amarradas al vehículo.
-- ================================================================
create or replace function pr_validar_trabajo(p_trabajo uuid,
                                              p_quien uuid default null,
                                              p_token text default null)
returns trabajos language plpgsql security definer as $$
declare
  tr trabajos;
  q usuarios;
  tp trabajo_piezas;
  pz piezas;
  t tipos_trabajo;
  v vehiculos;
  resultado trabajos;
begin
  select * into tr from trabajos where id = p_trabajo;
  if tr.id is null then raise exception 'Trabajo no encontrado'; end if;
  q := pr_actor_con_rol(tr.empresa_id, p_quien, p_token, array['admin','almacen']);
  if tr.estado <> 'pendiente' then
    raise exception 'Este trabajo ya fue %: no se puede validar de nuevo', tr.estado;
  end if;

  select * into t from tipos_trabajo where id = tr.tipo_trabajo_id;
  select * into v from vehiculos where id = tr.vehiculo_id;

  -- Primero se revisa TODO el stock; si falta algo, la validación
  -- falla con error claro y no se mueve ni una pieza.
  for tp in select * from trabajo_piezas where trabajo_id = tr.id loop
    select * into pz from piezas where id = tp.pieza_id;
    if pz.stock < tp.cantidad then
      raise exception 'No se puede validar: stock insuficiente de % (%): quedan % y el trabajo usa %',
        pz.nombre, pz.codigo, pz.stock, tp.cantidad;
    end if;
  end loop;

  -- Stock bien: salen las piezas, amarradas al vehículo del trabajo.
  for tp in select * from trabajo_piezas where trabajo_id = tr.id loop
    perform pr__salida_por_trabajo(tr.empresa_id, tp.pieza_id, tp.cantidad,
      tr.vehiculo_id, tr.mecanico_id,
      format('Trabajo validado: %s en %s (%s)', t.nombre, v.codigo, v.placa));
  end loop;

  update trabajos
  set estado = 'validada', validado_por = q.id, validado_en = now()
  where id = tr.id
  returning * into resultado;

  perform pr_registrar_accion(tr.empresa_id, q.id, 'trabajo_validado',
    format('Validó el trabajo %s de %s en el vehículo %s: RD$%s a pagar',
           t.nombre, (select nombre from usuarios where id = tr.mecanico_id),
           v.codigo, tr.precio_snapshot));
  return resultado;
end;
$$;

-- ================================================================
-- RECHAZAR (admin o almacén): no paga y NO mueve inventario.
-- ================================================================
create or replace function pr_rechazar_trabajo(p_trabajo uuid, p_nota text default null,
                                               p_quien uuid default null,
                                               p_token text default null)
returns trabajos language plpgsql security definer as $$
declare
  tr trabajos;
  q usuarios;
  resultado trabajos;
begin
  select * into tr from trabajos where id = p_trabajo;
  if tr.id is null then raise exception 'Trabajo no encontrado'; end if;
  q := pr_actor_con_rol(tr.empresa_id, p_quien, p_token, array['admin','almacen']);
  if tr.estado <> 'pendiente' then
    raise exception 'Este trabajo ya fue %: no se puede rechazar', tr.estado;
  end if;
  update trabajos
  set estado = 'rechazada', validado_por = q.id, validado_en = now(),
      nota_admin = nullif(trim(p_nota), '')
  where id = tr.id
  returning * into resultado;
  perform pr_registrar_accion(tr.empresa_id, q.id, 'trabajo_rechazado',
    format('Rechazó un trabajo de %s (%s)',
           (select nombre from usuarios where id = tr.mecanico_id),
           coalesce(nullif(trim(p_nota), ''), 'sin nota')));
  return resultado;
end;
$$;

-- ============ MODO DE PAGO POR MECÁNICO (opcional) ============
-- Cada mecánico cobra de UNA de dos formas, configurable por la
-- administración desde el panel:
--  - 'destajo': cobra la suma de sus trabajos VALIDADOS del período.
--  - 'sueldo': cobra un salario fijo mensual (sueldo_monto); sus
--    trabajos validados cuentan solo como productividad.
-- Los trabajos se registran y validan IGUAL para ambos modos; lo
-- único que cambia es cómo se calcula el total a pagar.
alter table usuarios add column if not exists modo_pago text not null default 'destajo';
alter table usuarios add column if not exists sueldo_monto numeric(12,2);

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'usuarios_modo_pago_check') then
    alter table usuarios add constraint usuarios_modo_pago_check
      check (modo_pago in ('destajo','sueldo'));
  end if;
end $$;

-- Fijar el modo de pago de un mecánico (solo administración).
create or replace function pr_fijar_modo_pago(p_empresa uuid, p_usuario uuid,
                                              p_modo text, p_sueldo numeric default null,
                                              p_quien uuid default null,
                                              p_token text default null)
returns usuarios language plpgsql security definer as $$
declare
  q usuarios;
  u usuarios;
begin
  q := pr_actor_con_rol(p_empresa, p_quien, p_token, array['admin']);
  if p_modo not in ('destajo','sueldo') then
    raise exception 'Modo de pago no válido: % (usa destajo o sueldo)', p_modo;
  end if;
  select * into u from usuarios where id = p_usuario and empresa_id = p_empresa;
  if u.id is null then raise exception 'Usuario no encontrado en esta empresa'; end if;
  if u.rol <> 'mecanico' then
    raise exception 'El modo de pago solo aplica a los mecánicos';
  end if;
  if p_modo = 'sueldo' then
    if p_sueldo is null or p_sueldo <= 0 then
      raise exception 'Para el modo sueldo hay que indicar el monto mensual (mayor que cero)';
    end if;
    update usuarios set modo_pago = 'sueldo', sueldo_monto = p_sueldo
    where id = u.id returning * into u;
  else
    update usuarios set modo_pago = 'destajo',
                        sueldo_monto = coalesce(p_sueldo, sueldo_monto)
    where id = u.id returning * into u;
  end if;
  perform pr_registrar_accion(p_empresa, q.id, 'modo_pago',
    case when p_modo = 'sueldo'
         then format('Puso a %s (%s) en SUELDO de %s al mes', u.nombre, u.codigo, p_sueldo)
         else format('Puso a %s (%s) en DESTAJO (por trabajo validado)', u.nombre, u.codigo)
    end);
  return u;
end;
$$;

-- ================================================================
-- RESUMEN DE PAGOS del período (panel, sección Pagos): por mecánico,
-- cuántos trabajos tiene en cada estado entre p_desde y p_hasta y
-- cuánto se le paga según su MODO: destajo = suma de validados;
-- sueldo = su salario fijo (los validados son productividad), con
-- el detalle de los trabajos validados (como el voucher).
-- ================================================================
create or replace function pr_resumen_pagos(p_empresa uuid, p_desde date, p_hasta date,
                                            p_quien uuid default null,
                                            p_token text default null)
returns jsonb language plpgsql security definer as $$
declare
  q usuarios;
begin
  q := pr_actor_con_rol(p_empresa, p_quien, p_token, array['admin','almacen']);
  if p_desde is null or p_hasta is null or p_hasta < p_desde then
    raise exception 'Rango de fechas no válido para el resumen de pagos';
  end if;
  return jsonb_build_object(
    'desde', p_desde,
    'hasta', p_hasta,
    'mecanicos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'mecanicoId', r.mecanico_id,
        'nombre', r.nombre,
        'codigo', r.codigo,
        'modoPago', r.modo_pago,
        'sueldoMonto', r.sueldo_monto,
        'validados', r.validados,
        'pendientes', r.pendientes,
        'rechazados', r.rechazados,
        'totalPagar', r.total_pagar
      ) order by r.total_pagar desc, r.codigo)
      from (
        select u.id as mecanico_id, u.nombre, u.codigo,
               u.modo_pago, u.sueldo_monto,
               count(t.id) filter (where t.estado = 'validada') as validados,
               count(t.id) filter (where t.estado = 'pendiente') as pendientes,
               count(t.id) filter (where t.estado = 'rechazada') as rechazados,
               case when u.modo_pago = 'sueldo'
                    then coalesce(u.sueldo_monto, 0)
                    else coalesce(sum(t.precio_snapshot) filter (where t.estado = 'validada'), 0)
               end as total_pagar
        from usuarios u
        left join trabajos t
          on t.mecanico_id = u.id and t.empresa_id = p_empresa
         and t.fecha between p_desde and p_hasta
        where u.empresa_id = p_empresa and u.rol = 'mecanico'
        group by u.id, u.nombre, u.codigo, u.modo_pago, u.sueldo_monto
      ) r
    ), '[]'::jsonb),
    'detalle', coalesce((
      select jsonb_agg(jsonb_build_object(
        'trabajoId', t.id,
        'mecanicoId', t.mecanico_id,
        'tipoNombre', tt.nombre,
        'vehiculoCodigo', v.codigo,
        'vehiculoPlaca', v.placa,
        'fecha', t.fecha,
        'precio', t.precio_snapshot,
        'descripcion', t.descripcion
      ) order by t.fecha desc, t.creada_en desc)
      from trabajos t
      join tipos_trabajo tt on tt.id = t.tipo_trabajo_id
      join vehiculos v on v.id = t.vehiculo_id
      where t.empresa_id = p_empresa and t.estado = 'validada'
        and t.fecha between p_desde and p_hasta
    ), '[]'::jsonb)
  );
end;
$$;

-- ================================================================
-- DATOS DEL MECÁNICO (la app): catálogo activo, vehículos, piezas,
-- MIS trabajos con estado y mis totales del mes en curso.
-- El mecánico solo se ve a sí mismo: todo sale de su sesión.
-- ================================================================
create or replace function pr_datos_mecanico(p_quien uuid default null,
                                             p_token text default null)
returns jsonb language plpgsql security definer as $$
declare
  u usuarios;
  q usuarios;
  e empresas;
  v_mes date := date_trunc('month', pr_hoy())::date;
  v_total_validado numeric;
  v_total_pendiente numeric;
begin
  select * into u from usuarios where id = p_quien and activo;
  if u.id is null then raise exception 'Usuario no válido'; end if;
  if u.empresa_id is null then
    raise exception 'Esta cuenta no es de un mecánico de empresa';
  end if;
  q := pr_actor_con_rol(u.empresa_id, p_quien, p_token, array['mecanico']);
  select * into e from empresas where id = q.empresa_id;

  select coalesce(sum(precio_snapshot), 0) into v_total_validado
  from trabajos
  where empresa_id = q.empresa_id and mecanico_id = q.id
    and estado = 'validada' and fecha >= v_mes;
  select coalesce(sum(precio_snapshot), 0) into v_total_pendiente
  from trabajos
  where empresa_id = q.empresa_id and mecanico_id = q.id
    and estado = 'pendiente' and fecha >= v_mes;

  return jsonb_build_object(
    'mecanico', jsonb_build_object(
      'id', q.id, 'nombre', q.nombre, 'codigo', q.codigo, 'rol', q.rol,
      'modoPago', q.modo_pago, 'sueldoMonto', q.sueldo_monto),
    'empresa', jsonb_build_object('id', e.id, 'nombre', e.nombre),
    'desdeMes', v_mes,
    'totalValidadoMes', v_total_validado,
    'totalPendienteMes', v_total_pendiente,
    'tiposTrabajo', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', t.id, 'codigo', t.codigo, 'nombre', t.nombre,
        'precioManoObra', t.precio_mano_obra, 'activo', t.activo
      ) order by t.codigo)
      from tipos_trabajo t
      where t.empresa_id = q.empresa_id and t.activo
    ), '[]'::jsonb),
    'vehiculos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', v.id, 'codigo', v.codigo, 'placa', v.placa, 'marca', v.marca,
        'modelo', v.modelo, 'anio', v.anio, 'estado', v.estado, 'activo', v.activo
      ) order by v.codigo)
      from vehiculos v where v.empresa_id = q.empresa_id and v.activo
    ), '[]'::jsonb),
    'piezas', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id, 'codigo', p.codigo, 'nombre', p.nombre, 'ubicacion', p.ubicacion,
        'costo', p.costo, 'stock', p.stock, 'stockMinimo', p.stock_minimo, 'activa', p.activa
      ) order by p.codigo)
      from piezas p where p.empresa_id = q.empresa_id and p.activa
    ), '[]'::jsonb),
    'trabajos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', t.id, 'mecanicoId', t.mecanico_id, 'vehiculoId', t.vehiculo_id,
        'tipoTrabajoId', t.tipo_trabajo_id, 'tipoNombre', tt.nombre,
        'descripcion', t.descripcion, 'precio', t.precio_snapshot,
        'estado', t.estado, 'fecha', t.fecha, 'notaAdmin', t.nota_admin,
        'creadaEn', t.creada_en,
        'piezas', coalesce((
          select jsonb_agg(jsonb_build_object('piezaId', tp.pieza_id, 'cantidad', tp.cantidad))
          from trabajo_piezas tp where tp.trabajo_id = t.id
        ), '[]'::jsonb)
      ) order by t.creada_en desc)
      from (select * from trabajos
            where empresa_id = q.empresa_id and mecanico_id = q.id
            order by creada_en desc limit 200) t
      join tipos_trabajo tt on tt.id = t.tipo_trabajo_id
    ), '[]'::jsonb)
  );
end;
$$;

-- ================================================================
-- SNAPSHOT EXTENDIDO: misma foto de esquema.sql + el módulo de
-- trabajos (catálogo, trabajos con sus piezas y el resumen de pagos
-- del mes en curso). Se reemplaza pr_snapshot conservando TODAS las
-- claves anteriores: el panel viejo sigue funcionando.
-- ================================================================
create or replace function pr_snapshot(p_empresa uuid default null,
                                       p_quien uuid default null,
                                       p_token text default null)
returns jsonb language plpgsql security definer as $$
declare
  q usuarios;
  e empresas;
  lic licencias;
  v_empresa uuid;
  v_mes date := date_trunc('month', pr_hoy())::date;
begin
  q := pr_actor_empresa(p_empresa, p_quien, p_token);
  v_empresa := coalesce(p_empresa, q.empresa_id);
  if v_empresa is null then
    raise exception 'Indica qué empresa quieres ver';
  end if;
  if q.rol <> 'superadmin' and v_empresa is distinct from q.empresa_id then
    raise exception 'No tienes permiso para ver esta empresa';
  end if;

  select * into e from empresas where id = v_empresa;
  if e.id is null then raise exception 'Empresa no encontrada'; end if;
  select * into lic from licencias where empresa_id = v_empresa order by creada_en desc limit 1;

  return jsonb_build_object(
    'empresa', jsonb_build_object('id', e.id, 'nombre', e.nombre, 'activa', e.activa),
    'licencia', case when lic.id is null then null else jsonb_build_object(
      'estado', lic.estado, 'vence', lic.vence, 'maxVehiculos', lic.max_vehiculos,
      'diasRestantes', case when lic.vence is null then null else lic.vence - pr_hoy() end,
      'porVencer', case when lic.vence is null then false
                        else (lic.vence - pr_hoy()) between 0 and 30 end
    ) end,
    'usuarios', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', u.id, 'rol', u.rol, 'nombre', u.nombre, 'codigo', u.codigo, 'activo', u.activo,
        'modoPago', u.modo_pago, 'sueldoMonto', u.sueldo_monto
      ) order by u.codigo)
      from usuarios u where u.empresa_id = v_empresa
    ), '[]'::jsonb),
    'vehiculos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', v.id, 'codigo', v.codigo, 'placa', v.placa, 'marca', v.marca,
        'modelo', v.modelo, 'anio', v.anio, 'estado', v.estado, 'activo', v.activo
      ) order by v.codigo)
      from vehiculos v where v.empresa_id = v_empresa
    ), '[]'::jsonb),
    'piezas', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id, 'codigo', p.codigo, 'nombre', p.nombre, 'ubicacion', p.ubicacion,
        'costo', p.costo, 'stock', p.stock, 'stockMinimo', p.stock_minimo, 'activa', p.activa
      ) order by p.codigo)
      from piezas p where p.empresa_id = v_empresa
    ), '[]'::jsonb),
    'movimientos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', m.id, 'tipo', m.tipo, 'piezaId', m.pieza_id, 'cantidad', m.cantidad,
        'costoUnitario', m.costo_unitario, 'vehiculoId', m.vehiculo_id,
        'usuarioId', m.usuario_id, 'nota', m.nota, 'fecha', m.fecha,
        'creadaEn', m.creada_en
      ) order by m.creada_en desc)
      from (select * from movimientos where empresa_id = v_empresa
            order by creada_en desc limit 300) m
    ), '[]'::jsonb),
    'herramientas', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', h.id, 'codigo', h.codigo, 'nombre', h.nombre, 'estado', h.estado, 'activa', h.activa
      ) order by h.codigo)
      from herramientas h where h.empresa_id = v_empresa
    ), '[]'::jsonb),
    'prestamos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', pr.id, 'herramientaId', pr.herramienta_id, 'responsableId', pr.responsable_id,
        'fechaSalida', pr.fecha_salida, 'fechaDevolucion', pr.fecha_devolucion
      ) order by pr.fecha_salida desc)
      from (select * from prestamos where empresa_id = v_empresa
            order by fecha_salida desc limit 200) pr
    ), '[]'::jsonb),
    'costos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'vehiculoId', c.vehiculo_id,
        'costoMes', c.costo_mes,
        'costoTotal', c.costo_total,
        'numSalidas', c.num_salidas
      ))
      from (
        select v.id as vehiculo_id,
               coalesce(sum(case when m.fecha >= v_mes
                                 then m.cantidad * m.costo_unitario end), 0) as costo_mes,
               coalesce(sum(m.cantidad * m.costo_unitario), 0) as costo_total,
               count(m.id) as num_salidas
        from vehiculos v
        left join movimientos m
          on m.vehiculo_id = v.id and m.tipo = 'salida' and m.empresa_id = v_empresa
        where v.empresa_id = v_empresa
        group by v.id
      ) c
    ), '[]'::jsonb),
    -- ===== Extensión trabajos/pagos (esta extensión) =====
    'tiposTrabajo', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', t.id, 'codigo', t.codigo, 'nombre', t.nombre,
        'precioManoObra', t.precio_mano_obra, 'activo', t.activo
      ) order by t.codigo)
      from tipos_trabajo t where t.empresa_id = v_empresa
    ), '[]'::jsonb),
    'trabajos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', t.id, 'mecanicoId', t.mecanico_id, 'vehiculoId', t.vehiculo_id,
        'tipoTrabajoId', t.tipo_trabajo_id, 'tipoNombre', tt.nombre,
        'descripcion', t.descripcion, 'precio', t.precio_snapshot,
        'estado', t.estado, 'fecha', t.fecha,
        'validadoPor', t.validado_por, 'notaAdmin', t.nota_admin,
        'creadaEn', t.creada_en,
        'piezas', coalesce((
          select jsonb_agg(jsonb_build_object('piezaId', tp.pieza_id, 'cantidad', tp.cantidad))
          from trabajo_piezas tp where tp.trabajo_id = t.id
        ), '[]'::jsonb)
      ) order by t.creada_en desc)
      from (select * from trabajos where empresa_id = v_empresa
            order by creada_en desc limit 300) t
      join tipos_trabajo tt on tt.id = t.tipo_trabajo_id
    ), '[]'::jsonb),
    'pagosMes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'mecanicoId', r.mecanico_id,
        'modoPago', r.modo_pago,
        'sueldoMonto', r.sueldo_monto,
        'validados', r.validados,
        'pendientes', r.pendientes,
        'rechazados', r.rechazados,
        'totalPagar', r.total_pagar
      ) order by r.total_pagar desc)
      from (
        select u.id as mecanico_id, u.modo_pago, u.sueldo_monto,
               count(t.id) filter (where t.estado = 'validada') as validados,
               count(t.id) filter (where t.estado = 'pendiente') as pendientes,
               count(t.id) filter (where t.estado = 'rechazada') as rechazados,
               case when u.modo_pago = 'sueldo'
                    then coalesce(u.sueldo_monto, 0)
                    else coalesce(sum(t.precio_snapshot) filter (where t.estado = 'validada'), 0)
               end as total_pagar
        from usuarios u
        left join trabajos t
          on t.mecanico_id = u.id and t.empresa_id = v_empresa and t.fecha >= v_mes
        where u.empresa_id = v_empresa and u.rol = 'mecanico'
        group by u.id, u.modo_pago, u.sueldo_monto
      ) r
    ), '[]'::jsonb)
  );
end;
$$;


-- === archivo: lavado.sql ===
-- TallerNeto · Extensión: MÓDULO DE LAVADO DE VEHÍCULOS (extra cobrable)
-- Se aplica DESPUÉS de servidor/esquema.sql y servidor/trabajos.sql.
-- NO modifica esos archivos: todo es idempotente.
--
-- Diseño:
--  - Es un EXTRA por empresa: interruptor `lavado_activo` en la
--    empresa (como las opciones por empresa de StaffRide). Apagado =
--    ni la app ni el panel muestran lavado, y las funciones pr_* de
--    lavado RECHAZAN con error claro.
--  - Rol nuevo `lavado` (coordinador de lavado): en la MISMA app del
--    mecánico, quien entra con este rol ve la interfaz de lavado.
--  - Anti-duplicado: UN registro por empresa+vehículo+fecha (unique).
--    El registro guarda el estado actual (activa = lavada) y la
--    auditoría de quién marcó/desmarcó y cuándo. Marcar dos veces el
--    mismo día es imposible; desmarcar y volver a marcar, sí.
--  - El reporte del panel sale del mismo sistema (snapshot): la
--    administración ve lavadas de hoy, historial y último lavado por
--    vehículo sin que el coordinador envíe nada.
-- Mismos patrones pr_*: token, actor/empresa, pr_hoy() en hora RD.

-- ============ INTERRUPTOR DEL MÓDULO EN LA EMPRESA ============
alter table empresas add column if not exists lavado_activo boolean not null default false;

-- ============ ROL NUEVO: lavado ============
-- El check de usuarios.rol nació sin «lavado»: se amplía.
alter table usuarios drop constraint if exists usuarios_rol_check;
alter table usuarios add constraint usuarios_rol_check
  check (rol in ('superadmin','admin','almacen','mecanico','lavado'));

-- pr_crear_usuario debe aceptar el rol nuevo (misma función de
-- esquema.sql, solo cambia la lista de roles válidos).
create or replace function pr_crear_usuario(p_empresa uuid, p_nombre text, p_codigo text,
                                            p_rol text, p_pin text default null,
                                            p_quien uuid default null,
                                            p_token text default null)
returns usuarios language plpgsql security definer as $$
declare
  nuevo usuarios;
  q usuarios;
begin
  q := pr_actor_con_rol(p_empresa, p_quien, p_token, array['admin']);
  if p_rol not in ('admin','almacen','mecanico','lavado') then
    raise exception 'Rol no válido: %', p_rol;
  end if;
  if p_pin is null or length(trim(p_pin)) = 0 then
    raise exception 'El PIN es obligatorio: indica un PIN de 4 a 6 dígitos para el usuario nuevo';
  end if;
  if trim(p_pin) !~ '^[0-9]{4,6}$' then
    raise exception 'El PIN debe tener de 4 a 6 dígitos';
  end if;
  if trim(p_pin) = '1234' then
    raise exception 'El PIN 1234 está prohibido por seguridad: elige otro PIN';
  end if;
  if exists (select 1 from usuarios
             where empresa_id = p_empresa and upper(codigo) = upper(trim(p_codigo))) then
    raise exception 'Ya existe un usuario con el código %', p_codigo;
  end if;
  insert into usuarios (empresa_id, rol, nombre, codigo, pin_hash)
  values (p_empresa, p_rol, trim(p_nombre), trim(p_codigo), pr_hash_pin(trim(p_pin)))
  returning * into nuevo;
  perform pr_registrar_accion(p_empresa, q.id, 'usuario_creado',
    format('Se creó el usuario %s (%s, %s)', nuevo.codigo, nuevo.nombre, nuevo.rol));
  return nuevo;
end;
$$;

-- ============ LAVADOS: un registro por vehículo y día ============
create table if not exists lavados (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references empresas(id) on delete cascade,
  vehiculo_id uuid not null references vehiculos(id),
  fecha date not null default (now() at time zone 'America/Santo_Domingo')::date,
  -- activa = el vehículo cuenta como lavado ese día. Desmarcar no
  -- borra: apaga `activa` y deja la auditoría del desmarcado.
  activa boolean not null default true,
  marcada_por uuid not null references usuarios(id),
  marcada_en timestamptz not null default now(),
  desmarcada_por uuid references usuarios(id),
  desmarcada_en timestamptz,
  creada_en timestamptz not null default now(),
  unique (empresa_id, vehiculo_id, fecha)
);
create index if not exists idx_lavados_empresa_fecha on lavados(empresa_id, fecha desc);
create index if not exists idx_lavados_vehiculo on lavados(empresa_id, vehiculo_id, fecha desc);

alter table lavados enable row level security;

-- ¿La empresa tiene el módulo encendido?
create or replace function pr__lavado_activo(p_empresa uuid) returns boolean
language sql stable security definer as $$
  select coalesce((select lavado_activo from empresas where id = p_empresa), false);
$$;

-- Candado del módulo: sin esto, ninguna función de lavado opera.
create or replace function pr__exigir_lavado_activo(p_empresa uuid) returns void
language plpgsql stable security definer as $$
begin
  if not pr__lavado_activo(p_empresa) then
    raise exception 'El módulo de lavado no está activo en esta empresa';
  end if;
end;
$$;

-- Encender/apagar el extra: solo el dueño del sistema (superadmin),
-- como las opciones comerciales por empresa de StaffRide.
create or replace function pr_configurar_lavado(p_empresa uuid, p_activo boolean,
                                                p_quien uuid default null)
returns void language plpgsql security definer as $$
declare e empresas;
begin
  perform pr_exigir_superadmin(p_quien);
  select * into e from empresas where id = p_empresa;
  if e.id is null then raise exception 'Empresa no encontrada'; end if;
  update empresas set lavado_activo = p_activo where id = p_empresa;
  perform pr_registrar_accion(p_empresa, p_quien, 'lavado_configurado',
    case when p_activo then 'Se activó el módulo de lavado'
         else 'Se desactivó el módulo de lavado' end);
end;
$$;

-- ================================================================
-- MARCAR LAVADO (app o panel; rol lavado, admin o almacén — el
-- panel marca desde la parrilla de unidades). Un vehículo, una vez
-- por día: si ya está marcado y activo, error claro.
-- ================================================================
create or replace function pr_marcar_lavado(p_empresa uuid, p_vehiculo uuid,
                                            p_quien uuid default null,
                                            p_token text default null)
returns lavados language plpgsql security definer as $$
declare
  q usuarios;
  v vehiculos;
  l lavados;
  v_hoy date := pr_hoy();
begin
  perform pr__exigir_lavado_activo(p_empresa);
  q := pr_actor_con_rol(p_empresa, p_quien, p_token, array['lavado','admin','almacen']);
  select * into v from vehiculos where id = p_vehiculo and empresa_id = p_empresa;
  if v.id is null then raise exception 'Vehículo no encontrado en esta empresa'; end if;
  if not v.activo then raise exception 'El vehículo % está inactivo', v.codigo; end if;

  select * into l from lavados
  where empresa_id = p_empresa and vehiculo_id = v.id and fecha = v_hoy;
  if l.id is not null and l.activa then
    raise exception 'El vehículo % ya está marcado como lavado hoy', v.codigo;
  end if;
  if l.id is not null then
    -- Estaba desmarcado: se reactiva con auditoría nueva de marcado.
    update lavados
    set activa = true, marcada_por = q.id, marcada_en = now(),
        desmarcada_por = null, desmarcada_en = null
    where id = l.id
    returning * into l;
  else
    insert into lavados (empresa_id, vehiculo_id, fecha, activa, marcada_por, marcada_en)
    values (p_empresa, v.id, v_hoy, true, q.id, now())
    returning * into l;
  end if;
  perform pr_registrar_accion(p_empresa, q.id, 'lavado_marcado',
    format('Marcó lavado el vehículo %s (%s)', v.codigo, v.placa));
  return l;
end;
$$;

-- ================================================================
-- DESMARCAR LAVADO (app o panel; rol lavado, admin o almacén): apaga el estado del
-- día y deja quién lo desmarcó y cuándo. No borra el registro.
-- ================================================================
create or replace function pr_desmarcar_lavado(p_empresa uuid, p_vehiculo uuid,
                                               p_quien uuid default null,
                                               p_token text default null)
returns lavados language plpgsql security definer as $$
declare
  q usuarios;
  v vehiculos;
  l lavados;
  v_hoy date := pr_hoy();
begin
  perform pr__exigir_lavado_activo(p_empresa);
  q := pr_actor_con_rol(p_empresa, p_quien, p_token, array['lavado','admin','almacen']);
  select * into v from vehiculos where id = p_vehiculo and empresa_id = p_empresa;
  if v.id is null then raise exception 'Vehículo no encontrado en esta empresa'; end if;
  select * into l from lavados
  where empresa_id = p_empresa and vehiculo_id = v.id and fecha = v_hoy;
  if l.id is null or not l.activa then
    raise exception 'El vehículo % no está marcado como lavado hoy', v.codigo;
  end if;
  update lavados
  set activa = false, desmarcada_por = q.id, desmarcada_en = now()
  where id = l.id
  returning * into l;
  perform pr_registrar_accion(p_empresa, q.id, 'lavado_desmarcado',
    format('Desmarcó el lavado del vehículo %s (%s)', v.codigo, v.placa));
  return l;
end;
$$;

-- ================================================================
-- DATOS DE LAVADO (la app del coordinador): vehículos activos de la
-- empresa con su estado de lavado de HOY y el resumen del día.
-- ================================================================
create or replace function pr_datos_lavado(p_quien uuid default null,
                                           p_token text default null)
returns jsonb language plpgsql security definer as $$
declare
  u usuarios;
  q usuarios;
  e empresas;
  v_hoy date := pr_hoy();
begin
  select * into u from usuarios where id = p_quien and activo;
  if u.id is null then raise exception 'Usuario no válido'; end if;
  if u.empresa_id is null then
    raise exception 'Esta cuenta no es de una empresa';
  end if;
  q := pr_actor_con_rol(u.empresa_id, p_quien, p_token, array['lavado','admin']);
  perform pr__exigir_lavado_activo(q.empresa_id);
  select * into e from empresas where id = q.empresa_id;

  return jsonb_build_object(
    'usuario', jsonb_build_object(
      'id', q.id, 'nombre', q.nombre, 'codigo', q.codigo, 'rol', q.rol),
    'empresa', jsonb_build_object(
      'id', e.id, 'nombre', e.nombre, 'lavadoActivo', e.lavado_activo),
    'fecha', v_hoy,
    'vehiculos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', v.id, 'codigo', v.codigo, 'placa', v.placa, 'marca', v.marca,
        'modelo', v.modelo, 'anio', v.anio, 'estado', v.estado, 'activo', v.activo,
        'lavadoHoy', coalesce(l.activa, false),
        'marcadaEn', case when l.activa then l.marcada_en else null end,
        'marcadaPor', case when l.activa then l.marcada_por else null end,
        'marcadaPorNombre', case when l.activa
          then (select nombre from usuarios where id = l.marcada_por) else null end
      ) order by v.codigo)
      from vehiculos v
      left join lavados l
        on l.vehiculo_id = v.id and l.empresa_id = q.empresa_id and l.fecha = v_hoy
      where v.empresa_id = q.empresa_id and v.activo
    ), '[]'::jsonb)
  );
end;
$$;

-- ================================================================
-- RESUMEN DE LAVADO (panel): lavadas de hoy con hora y responsable,
-- historial reciente y último lavado por vehículo (atrasos arriba).
-- ================================================================
create or replace function pr_resumen_lavado(p_empresa uuid,
                                             p_quien uuid default null,
                                             p_token text default null)
returns jsonb language plpgsql security definer as $$
declare
  q usuarios;
  v_hoy date := pr_hoy();
begin
  perform pr__exigir_lavado_activo(p_empresa);
  q := pr_actor_con_rol(p_empresa, p_quien, p_token, array['admin','almacen']);
  return jsonb_build_object(
    'fecha', v_hoy,
    'hoy', coalesce((
      select jsonb_agg(jsonb_build_object(
        'vehiculoId', l.vehiculo_id,
        'vehiculoCodigo', v.codigo,
        'vehiculoPlaca', v.placa,
        'hora', l.marcada_en,
        'responsableId', l.marcada_por,
        'responsableNombre', (select nombre from usuarios where id = l.marcada_por)
      ) order by l.marcada_en)
      from lavados l
      join vehiculos v on v.id = l.vehiculo_id
      where l.empresa_id = p_empresa and l.fecha = v_hoy and l.activa
    ), '[]'::jsonb),
    'historial', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', l.id, 'vehiculoId', l.vehiculo_id, 'fecha', l.fecha,
        'activa', l.activa, 'marcadaEn', l.marcada_en,
        'marcadaPor', l.marcada_por, 'desmarcadaEn', l.desmarcada_en,
        'desmarcadaPor', l.desmarcada_por
      ) order by l.fecha desc, l.marcada_en desc)
      from (select * from lavados where empresa_id = p_empresa
            order by fecha desc, marcada_en desc limit 300) l
    ), '[]'::jsonb),
    'porVehiculo', coalesce((
      select jsonb_agg(jsonb_build_object(
        'vehiculoId', r.vehiculo_id,
        'ultimoLavado', r.ultimo_lavado,
        'diasSinLavar', case when r.ultimo_lavado is null then null
                             else v_hoy - r.ultimo_lavado end
      ) order by r.ultimo_lavado asc nulls first)
      from (
        select v.id as vehiculo_id,
               (select max(l.fecha) from lavados l
                 where l.vehiculo_id = v.id and l.empresa_id = p_empresa
                   and l.activa) as ultimo_lavado
        from vehiculos v
        where v.empresa_id = p_empresa and v.activo
      ) r
    ), '[]'::jsonb)
  );
end;
$$;

-- ================================================================
-- SNAPSHOT: se vuelve a reemplazar (versión de trabajos.sql) para
-- que la empresa traiga `lavadoActivo` y la foto traiga los
-- `lavados` recientes: el panel pinta la sección Lavado de aquí.
-- TODAS las claves anteriores se conservan.
-- ================================================================
create or replace function pr_snapshot(p_empresa uuid default null,
                                       p_quien uuid default null,
                                       p_token text default null)
returns jsonb language plpgsql security definer as $$
declare
  q usuarios;
  e empresas;
  lic licencias;
  v_empresa uuid;
  v_mes date := date_trunc('month', pr_hoy())::date;
begin
  q := pr_actor_empresa(p_empresa, p_quien, p_token);
  v_empresa := coalesce(p_empresa, q.empresa_id);
  if v_empresa is null then
    raise exception 'Indica qué empresa quieres ver';
  end if;
  if q.rol <> 'superadmin' and v_empresa is distinct from q.empresa_id then
    raise exception 'No tienes permiso para ver esta empresa';
  end if;

  select * into e from empresas where id = v_empresa;
  if e.id is null then raise exception 'Empresa no encontrada'; end if;
  select * into lic from licencias where empresa_id = v_empresa order by creada_en desc limit 1;

  return jsonb_build_object(
    'empresa', jsonb_build_object(
      'id', e.id, 'nombre', e.nombre, 'activa', e.activa,
      'lavadoActivo', e.lavado_activo),
    'licencia', case when lic.id is null then null else jsonb_build_object(
      'estado', lic.estado, 'vence', lic.vence, 'maxVehiculos', lic.max_vehiculos,
      'diasRestantes', case when lic.vence is null then null else lic.vence - pr_hoy() end,
      'porVencer', case when lic.vence is null then false
                        else (lic.vence - pr_hoy()) between 0 and 30 end
    ) end,
    'usuarios', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', u.id, 'rol', u.rol, 'nombre', u.nombre, 'codigo', u.codigo, 'activo', u.activo,
        'modoPago', u.modo_pago, 'sueldoMonto', u.sueldo_monto
      ) order by u.codigo)
      from usuarios u where u.empresa_id = v_empresa
    ), '[]'::jsonb),
    'vehiculos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', v.id, 'codigo', v.codigo, 'placa', v.placa, 'marca', v.marca,
        'modelo', v.modelo, 'anio', v.anio, 'estado', v.estado, 'activo', v.activo
      ) order by v.codigo)
      from vehiculos v where v.empresa_id = v_empresa
    ), '[]'::jsonb),
    'piezas', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id, 'codigo', p.codigo, 'nombre', p.nombre, 'ubicacion', p.ubicacion,
        'costo', p.costo, 'stock', p.stock, 'stockMinimo', p.stock_minimo, 'activa', p.activa
      ) order by p.codigo)
      from piezas p where p.empresa_id = v_empresa
    ), '[]'::jsonb),
    'movimientos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', m.id, 'tipo', m.tipo, 'piezaId', m.pieza_id, 'cantidad', m.cantidad,
        'costoUnitario', m.costo_unitario, 'vehiculoId', m.vehiculo_id,
        'usuarioId', m.usuario_id, 'nota', m.nota, 'fecha', m.fecha,
        'creadaEn', m.creada_en
      ) order by m.creada_en desc)
      from (select * from movimientos where empresa_id = v_empresa
            order by creada_en desc limit 300) m
    ), '[]'::jsonb),
    'herramientas', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', h.id, 'codigo', h.codigo, 'nombre', h.nombre, 'estado', h.estado, 'activa', h.activa
      ) order by h.codigo)
      from herramientas h where h.empresa_id = v_empresa
    ), '[]'::jsonb),
    'prestamos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', pr.id, 'herramientaId', pr.herramienta_id, 'responsableId', pr.responsable_id,
        'fechaSalida', pr.fecha_salida, 'fechaDevolucion', pr.fecha_devolucion
      ) order by pr.fecha_salida desc)
      from (select * from prestamos where empresa_id = v_empresa
            order by fecha_salida desc limit 200) pr
    ), '[]'::jsonb),
    'costos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'vehiculoId', c.vehiculo_id,
        'costoMes', c.costo_mes,
        'costoTotal', c.costo_total,
        'numSalidas', c.num_salidas
      ))
      from (
        select v.id as vehiculo_id,
               coalesce(sum(case when m.fecha >= v_mes
                                 then m.cantidad * m.costo_unitario end), 0) as costo_mes,
               coalesce(sum(m.cantidad * m.costo_unitario), 0) as costo_total,
               count(m.id) as num_salidas
        from vehiculos v
        left join movimientos m
          on m.vehiculo_id = v.id and m.tipo = 'salida' and m.empresa_id = v_empresa
        where v.empresa_id = v_empresa
        group by v.id
      ) c
    ), '[]'::jsonb),
    'tiposTrabajo', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', t.id, 'codigo', t.codigo, 'nombre', t.nombre,
        'precioManoObra', t.precio_mano_obra, 'activo', t.activo
      ) order by t.codigo)
      from tipos_trabajo t where t.empresa_id = v_empresa
    ), '[]'::jsonb),
    'trabajos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', t.id, 'mecanicoId', t.mecanico_id, 'vehiculoId', t.vehiculo_id,
        'tipoTrabajoId', t.tipo_trabajo_id, 'tipoNombre', tt.nombre,
        'descripcion', t.descripcion, 'precio', t.precio_snapshot,
        'estado', t.estado, 'fecha', t.fecha,
        'validadoPor', t.validado_por, 'notaAdmin', t.nota_admin,
        'creadaEn', t.creada_en,
        'piezas', coalesce((
          select jsonb_agg(jsonb_build_object('piezaId', tp.pieza_id, 'cantidad', tp.cantidad))
          from trabajo_piezas tp where tp.trabajo_id = t.id
        ), '[]'::jsonb)
      ) order by t.creada_en desc)
      from (select * from trabajos where empresa_id = v_empresa
            order by creada_en desc limit 300) t
      join tipos_trabajo tt on tt.id = t.tipo_trabajo_id
    ), '[]'::jsonb),
    'pagosMes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'mecanicoId', r.mecanico_id,
        'modoPago', r.modo_pago,
        'sueldoMonto', r.sueldo_monto,
        'validados', r.validados,
        'pendientes', r.pendientes,
        'rechazados', r.rechazados,
        'totalPagar', r.total_pagar
      ) order by r.total_pagar desc)
      from (
        select u.id as mecanico_id, u.modo_pago, u.sueldo_monto,
               count(t.id) filter (where t.estado = 'validada') as validados,
               count(t.id) filter (where t.estado = 'pendiente') as pendientes,
               count(t.id) filter (where t.estado = 'rechazada') as rechazados,
               case when u.modo_pago = 'sueldo'
                    then coalesce(u.sueldo_monto, 0)
                    else coalesce(sum(t.precio_snapshot) filter (where t.estado = 'validada'), 0)
               end as total_pagar
        from usuarios u
        left join trabajos t
          on t.mecanico_id = u.id and t.empresa_id = v_empresa and t.fecha >= v_mes
        where u.empresa_id = v_empresa and u.rol = 'mecanico'
        group by u.id, u.modo_pago, u.sueldo_monto
      ) r
    ), '[]'::jsonb),
    -- ===== Extensión lavado (este archivo) =====
    'lavados', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', l.id, 'vehiculoId', l.vehiculo_id, 'fecha', l.fecha,
        'activa', l.activa, 'marcadaEn', l.marcada_en,
        'marcadaPor', l.marcada_por, 'desmarcadaEn', l.desmarcada_en,
        'desmarcadaPor', l.desmarcada_por
      ) order by l.fecha desc, l.marcada_en desc)
      from (select * from lavados where empresa_id = v_empresa
            order by fecha desc, marcada_en desc limit 300) l
    ), '[]'::jsonb)
  );
end;
$$;


-- === archivo: combustible.sql ===
-- TallerNeto · Extensión: MÓDULO DE COMBUSTIBLE (extra cobrable)
-- Se aplica DESPUÉS de servidor/esquema.sql, servidor/trabajos.sql y
-- servidor/lavado.sql. NO modifica esos archivos: todo es idempotente.
--
-- Diseño (mismo patrón que el módulo de lavado):
--  - Es un EXTRA por empresa: interruptor `combustible_activo` en la
--    empresa. Apagado = ni la app ni el panel muestran combustible,
--    y las funciones pr_* de combustible RECHAZAN con error claro.
--  - Rol nuevo `combustible` (despachador): en la MISMA app del
--    mecánico, quien entra con este rol ve la interfaz de despacho.
--  - Cada despacho registra: vehículo (OBLIGATORIO), galones, tipo
--    (diesel|gasolina|glp), odómetro del vehículo al despachar,
--    costo por galón y total (= galones × costo, guardado).
--  - REGLA DE INTEGRIDAD: el odómetro NO puede ser menor que el
--    último registrado para ese vehículo (rechazo con error claro).
--  - RENDIMIENTO por vehículo (lo calcula el resumen): distancia
--    recorrida en el período (odómetro mayor − menor del período)
--    ÷ galones del período. Unidad FIJA: km/gal (documentado aquí y
--    en la respuesta del resumen como `unidad`).
-- Mismos patrones pr_*: token, actor/empresa, pr_hoy() en hora RD.

-- ============ INTERRUPTOR DEL MÓDULO EN LA EMPRESA ============
alter table empresas add column if not exists combustible_activo boolean not null default false;

-- ============ ROL NUEVO: combustible ============
alter table usuarios drop constraint if exists usuarios_rol_check;
alter table usuarios add constraint usuarios_rol_check
  check (rol in ('superadmin','admin','almacen','mecanico','lavado','combustible'));

-- pr_crear_usuario debe aceptar el rol nuevo (misma función vigente,
-- solo cambia la lista de roles válidos).
create or replace function pr_crear_usuario(p_empresa uuid, p_nombre text, p_codigo text,
                                            p_rol text, p_pin text default null,
                                            p_quien uuid default null,
                                            p_token text default null)
returns usuarios language plpgsql security definer as $$
declare
  nuevo usuarios;
  q usuarios;
begin
  q := pr_actor_con_rol(p_empresa, p_quien, p_token, array['admin']);
  if p_rol not in ('admin','almacen','mecanico','lavado','combustible') then
    raise exception 'Rol no válido: %', p_rol;
  end if;
  if p_pin is null or length(trim(p_pin)) = 0 then
    raise exception 'El PIN es obligatorio: indica un PIN de 4 a 6 dígitos para el usuario nuevo';
  end if;
  if trim(p_pin) !~ '^[0-9]{4,6}$' then
    raise exception 'El PIN debe tener de 4 a 6 dígitos';
  end if;
  if trim(p_pin) = '1234' then
    raise exception 'El PIN 1234 está prohibido por seguridad: elige otro PIN';
  end if;
  if exists (select 1 from usuarios
             where empresa_id = p_empresa and upper(codigo) = upper(trim(p_codigo))) then
    raise exception 'Ya existe un usuario con el código %', p_codigo;
  end if;
  insert into usuarios (empresa_id, rol, nombre, codigo, pin_hash)
  values (p_empresa, p_rol, trim(p_nombre), trim(p_codigo), pr_hash_pin(trim(p_pin)))
  returning * into nuevo;
  perform pr_registrar_accion(p_empresa, q.id, 'usuario_creado',
    format('Se creó el usuario %s (%s, %s)', nuevo.codigo, nuevo.nombre, nuevo.rol));
  return nuevo;
end;
$$;

-- ============ DESPACHOS DE COMBUSTIBLE ============
create table if not exists despachos_combustible (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references empresas(id) on delete cascade,
  vehiculo_id uuid not null references vehiculos(id),
  despachador_id uuid not null references usuarios(id),
  fecha date not null default (now() at time zone 'America/Santo_Domingo')::date,
  galones numeric(10,2) not null check (galones > 0),
  tipo_combustible text not null check (tipo_combustible in ('diesel','gasolina','glp')),
  odometro numeric(12,1) not null check (odometro >= 0),
  costo_galon numeric(12,2) not null check (costo_galon >= 0),
  -- Total guardado al despachar (foto del momento, como el snapshot
  -- de precios de los trabajos): no se recalcula después.
  total numeric(14,2) not null,
  creada_en timestamptz not null default now()
);
create index if not exists idx_despachos_empresa_fecha
  on despachos_combustible(empresa_id, fecha desc);
create index if not exists idx_despachos_vehiculo
  on despachos_combustible(empresa_id, vehiculo_id, creada_en desc);

alter table despachos_combustible enable row level security;

-- Precios SUGERIDOS por galón (RD$): la app los precarga y el
-- despachador los puede editar en cada despacho. Son valores de
-- referencia de la demo, no una tarifa oficial.
create or replace function pr__precios_combustible() returns jsonb
language sql immutable as $$
  select jsonb_build_array(
    jsonb_build_object('tipo', 'diesel',   'precioSugerido', 250),
    jsonb_build_object('tipo', 'gasolina', 'precioSugerido', 290),
    jsonb_build_object('tipo', 'glp',      'precioSugerido', 145)
  );
$$;

create or replace function pr__combustible_activo(p_empresa uuid) returns boolean
language sql stable security definer as $$
  select coalesce((select combustible_activo from empresas where id = p_empresa), false);
$$;

create or replace function pr__exigir_combustible_activo(p_empresa uuid) returns void
language plpgsql stable security definer as $$
begin
  if not pr__combustible_activo(p_empresa) then
    raise exception 'El módulo de combustible no está activo en esta empresa';
  end if;
end;
$$;

-- Encender/apagar el extra: solo el dueño del sistema (superadmin).
create or replace function pr_configurar_combustible(p_empresa uuid, p_activo boolean,
                                                     p_quien uuid default null)
returns void language plpgsql security definer as $$
declare e empresas;
begin
  perform pr_exigir_superadmin(p_quien);
  select * into e from empresas where id = p_empresa;
  if e.id is null then raise exception 'Empresa no encontrada'; end if;
  update empresas set combustible_activo = p_activo where id = p_empresa;
  perform pr_registrar_accion(p_empresa, p_quien, 'combustible_configurado',
    case when p_activo then 'Se activó el módulo de combustible'
         else 'Se desactivó el módulo de combustible' end);
end;
$$;

-- Último odómetro registrado de un vehículo (null si nunca despachó).
create or replace function pr__ultimo_odometro(p_empresa uuid, p_vehiculo uuid)
returns numeric language sql stable security definer as $$
  select max(odometro) from despachos_combustible
  where empresa_id = p_empresa and vehiculo_id = p_vehiculo;
$$;

-- ================================================================
-- REGISTRAR DESPACHO (app; rol combustible o admin).
-- Vehículo obligatorio; el odómetro no puede bajar.
-- ================================================================
create or replace function pr_registrar_despacho(p_empresa uuid, p_vehiculo uuid,
                                                 p_galones numeric, p_tipo text,
                                                 p_odometro numeric, p_costo_galon numeric,
                                                 p_quien uuid default null,
                                                 p_token text default null)
returns despachos_combustible language plpgsql security definer as $$
declare
  q usuarios;
  v vehiculos;
  d despachos_combustible;
  v_ultimo numeric;
begin
  perform pr__exigir_combustible_activo(p_empresa);
  q := pr_actor_con_rol(p_empresa, p_quien, p_token, array['combustible','admin']);
  if p_vehiculo is null then
    raise exception 'Todo despacho debe decir el vehículo';
  end if;
  select * into v from vehiculos where id = p_vehiculo and empresa_id = p_empresa;
  if v.id is null then raise exception 'Vehículo no encontrado en esta empresa'; end if;
  if not v.activo then raise exception 'El vehículo % está inactivo', v.codigo; end if;
  if p_galones is null or p_galones <= 0 then
    raise exception 'La cantidad de galones debe ser mayor que cero';
  end if;
  if p_tipo not in ('diesel','gasolina','glp') then
    raise exception 'Tipo de combustible no válido: % (usa diesel, gasolina o glp)', p_tipo;
  end if;
  if p_odometro is null or p_odometro < 0 then
    raise exception 'El odómetro es obligatorio y no puede ser negativo';
  end if;
  if p_costo_galon is null or p_costo_galon < 0 then
    raise exception 'El costo por galón no puede ser negativo';
  end if;
  -- Regla de integridad: el odómetro nunca baja.
  v_ultimo := pr__ultimo_odometro(p_empresa, v.id);
  if v_ultimo is not null and p_odometro < v_ultimo then
    raise exception 'El odómetro (%) es menor que el último registrado (%) para el vehículo %: revísalo',
      p_odometro, v_ultimo, v.codigo;
  end if;
  insert into despachos_combustible
    (empresa_id, vehiculo_id, despachador_id, fecha, galones,
     tipo_combustible, odometro, costo_galon, total)
  values
    (p_empresa, v.id, q.id, pr_hoy(), p_galones,
     p_tipo, p_odometro, p_costo_galon, round(p_galones * p_costo_galon, 2))
  returning * into d;
  perform pr_registrar_accion(p_empresa, q.id, 'despacho_combustible',
    format('Despachó %s galones de %s al vehículo %s (odómetro %s, total %s)',
           p_galones, p_tipo, v.codigo, p_odometro, d.total));
  return d;
end;
$$;

-- ================================================================
-- DATOS DE COMBUSTIBLE (la app del despachador): vehículos con su
-- último odómetro, tipos con precio sugerido y despachos de HOY.
-- ================================================================
create or replace function pr_datos_combustible(p_quien uuid default null,
                                                p_token text default null)
returns jsonb language plpgsql security definer as $$
declare
  u usuarios;
  q usuarios;
  e empresas;
  v_hoy date := pr_hoy();
begin
  select * into u from usuarios where id = p_quien and activo;
  if u.id is null then raise exception 'Usuario no válido'; end if;
  if u.empresa_id is null then
    raise exception 'Esta cuenta no es de una empresa';
  end if;
  q := pr_actor_con_rol(u.empresa_id, p_quien, p_token, array['combustible','admin']);
  perform pr__exigir_combustible_activo(q.empresa_id);
  select * into e from empresas where id = q.empresa_id;

  return jsonb_build_object(
    'usuario', jsonb_build_object(
      'id', q.id, 'nombre', q.nombre, 'codigo', q.codigo, 'rol', q.rol),
    'empresa', jsonb_build_object(
      'id', e.id, 'nombre', e.nombre, 'combustibleActivo', e.combustible_activo),
    'fecha', v_hoy,
    'unidad', 'km/gal',
    'tipos', pr__precios_combustible(),
    'vehiculos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', v.id, 'codigo', v.codigo, 'placa', v.placa, 'marca', v.marca,
        'modelo', v.modelo, 'anio', v.anio, 'estado', v.estado, 'activo', v.activo,
        'ultimoOdometro', pr__ultimo_odometro(q.empresa_id, v.id)
      ) order by v.codigo)
      from vehiculos v
      where v.empresa_id = q.empresa_id and v.activo
    ), '[]'::jsonb),
    'despachosHoy', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', d.id, 'vehiculoId', d.vehiculo_id,
        'vehiculoCodigo', v.codigo, 'vehiculoPlaca', v.placa,
        'galones', d.galones, 'tipo', d.tipo_combustible,
        'odometro', d.odometro, 'costoUnitario', d.costo_galon,
        'total', d.total, 'creadaEn', d.creada_en,
        'despachadorId', d.despachador_id,
        'despachadorNombre', (select nombre from usuarios where id = d.despachador_id)
      ) order by d.creada_en desc)
      from despachos_combustible d
      join vehiculos v on v.id = d.vehiculo_id
      where d.empresa_id = q.empresa_id and d.fecha = v_hoy
    ), '[]'::jsonb),
    'totalGalonesHoy', coalesce((
      select sum(galones) from despachos_combustible
      where empresa_id = q.empresa_id and fecha = v_hoy
    ), 0),
    'totalCostoHoy', coalesce((
      select sum(total) from despachos_combustible
      where empresa_id = q.empresa_id and fecha = v_hoy
    ), 0)
  );
end;
$$;

-- ================================================================
-- RESUMEN DE COMBUSTIBLE (panel): por vehículo — galones, costo y
-- RENDIMIENTO del período (km/gal; el peor primero); despachos por
-- día y total general. Rendimiento = (odómetro mayor − menor del
-- período) ÷ galones del período; null si no se puede calcular.
-- ================================================================
create or replace function pr_resumen_combustible(p_empresa uuid, p_desde date, p_hasta date,
                                                  p_quien uuid default null,
                                                  p_token text default null)
returns jsonb language plpgsql security definer as $$
declare
  q usuarios;
begin
  perform pr__exigir_combustible_activo(p_empresa);
  q := pr_actor_con_rol(p_empresa, p_quien, p_token, array['admin','almacen']);
  if p_desde is null or p_hasta is null or p_hasta < p_desde then
    raise exception 'Rango de fechas no válido para el resumen de combustible';
  end if;
  return jsonb_build_object(
    'desde', p_desde,
    'hasta', p_hasta,
    'unidad', 'km/gal',
    'porVehiculo', coalesce((
      select jsonb_agg(jsonb_build_object(
        'vehiculoId', r.vehiculo_id,
        'vehiculoCodigo', r.codigo,
        'galones', r.galones,
        'costoTotal', r.costo_total,
        'despachos', r.despachos,
        'distancia', r.distancia,
        'rendimiento', r.rendimiento
      ) order by r.rendimiento asc nulls last, r.galones desc)
      from (
        select v.id as vehiculo_id, v.codigo,
               coalesce(sum(d.galones), 0) as galones,
               coalesce(sum(d.total), 0) as costo_total,
               count(d.id) as despachos,
               case when count(d.id) >= 2
                    then max(d.odometro) - min(d.odometro) end as distancia,
               case when count(d.id) >= 2 and sum(d.galones) > 0
                     and (max(d.odometro) - min(d.odometro)) > 0
                    then round((max(d.odometro) - min(d.odometro)) / sum(d.galones), 2)
               end as rendimiento
        from vehiculos v
        left join despachos_combustible d
          on d.vehiculo_id = v.id and d.empresa_id = p_empresa
         and d.fecha between p_desde and p_hasta
        where v.empresa_id = p_empresa and v.activo
        group by v.id, v.codigo
      ) r
    ), '[]'::jsonb),
    'porDia', coalesce((
      select jsonb_agg(jsonb_build_object(
        'fecha', s.fecha, 'galones', s.galones,
        'costoTotal', s.costo_total, 'despachos', s.despachos
      ) order by s.fecha desc)
      from (
        select fecha, sum(galones) as galones, sum(total) as costo_total,
               count(*) as despachos
        from despachos_combustible
        where empresa_id = p_empresa and fecha between p_desde and p_hasta
        group by fecha
      ) s
    ), '[]'::jsonb),
    'totalGeneral', (
      select jsonb_build_object(
        'galones', coalesce(sum(galones), 0),
        'costoTotal', coalesce(sum(total), 0),
        'despachos', count(*)
      )
      from despachos_combustible
      where empresa_id = p_empresa and fecha between p_desde and p_hasta
    )
  );
end;
$$;

-- ================================================================
-- SNAPSHOT: se vuelve a reemplazar (versión de lavado.sql) para que
-- la empresa traiga `combustibleActivo` y la foto traiga los
-- despachos recientes: el panel pinta la sección Combustible de
-- aquí. TODAS las claves anteriores se conservan.
-- ================================================================
create or replace function pr_snapshot(p_empresa uuid default null,
                                       p_quien uuid default null,
                                       p_token text default null)
returns jsonb language plpgsql security definer as $$
declare
  q usuarios;
  e empresas;
  lic licencias;
  v_empresa uuid;
  v_mes date := date_trunc('month', pr_hoy())::date;
begin
  q := pr_actor_empresa(p_empresa, p_quien, p_token);
  v_empresa := coalesce(p_empresa, q.empresa_id);
  if v_empresa is null then
    raise exception 'Indica qué empresa quieres ver';
  end if;
  if q.rol <> 'superadmin' and v_empresa is distinct from q.empresa_id then
    raise exception 'No tienes permiso para ver esta empresa';
  end if;

  select * into e from empresas where id = v_empresa;
  if e.id is null then raise exception 'Empresa no encontrada'; end if;
  select * into lic from licencias where empresa_id = v_empresa order by creada_en desc limit 1;

  return jsonb_build_object(
    'empresa', jsonb_build_object(
      'id', e.id, 'nombre', e.nombre, 'activa', e.activa,
      'lavadoActivo', e.lavado_activo,
      'combustibleActivo', e.combustible_activo),
    'licencia', case when lic.id is null then null else jsonb_build_object(
      'estado', lic.estado, 'vence', lic.vence, 'maxVehiculos', lic.max_vehiculos,
      'diasRestantes', case when lic.vence is null then null else lic.vence - pr_hoy() end,
      'porVencer', case when lic.vence is null then false
                        else (lic.vence - pr_hoy()) between 0 and 30 end
    ) end,
    'usuarios', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', u.id, 'rol', u.rol, 'nombre', u.nombre, 'codigo', u.codigo, 'activo', u.activo,
        'modoPago', u.modo_pago, 'sueldoMonto', u.sueldo_monto
      ) order by u.codigo)
      from usuarios u where u.empresa_id = v_empresa
    ), '[]'::jsonb),
    'vehiculos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', v.id, 'codigo', v.codigo, 'placa', v.placa, 'marca', v.marca,
        'modelo', v.modelo, 'anio', v.anio, 'estado', v.estado, 'activo', v.activo
      ) order by v.codigo)
      from vehiculos v where v.empresa_id = v_empresa
    ), '[]'::jsonb),
    'piezas', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id, 'codigo', p.codigo, 'nombre', p.nombre, 'ubicacion', p.ubicacion,
        'costo', p.costo, 'stock', p.stock, 'stockMinimo', p.stock_minimo, 'activa', p.activa
      ) order by p.codigo)
      from piezas p where p.empresa_id = v_empresa
    ), '[]'::jsonb),
    'movimientos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', m.id, 'tipo', m.tipo, 'piezaId', m.pieza_id, 'cantidad', m.cantidad,
        'costoUnitario', m.costo_unitario, 'vehiculoId', m.vehiculo_id,
        'usuarioId', m.usuario_id, 'nota', m.nota, 'fecha', m.fecha,
        'creadaEn', m.creada_en
      ) order by m.creada_en desc)
      from (select * from movimientos where empresa_id = v_empresa
            order by creada_en desc limit 300) m
    ), '[]'::jsonb),
    'herramientas', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', h.id, 'codigo', h.codigo, 'nombre', h.nombre, 'estado', h.estado, 'activa', h.activa
      ) order by h.codigo)
      from herramientas h where h.empresa_id = v_empresa
    ), '[]'::jsonb),
    'prestamos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', pr.id, 'herramientaId', pr.herramienta_id, 'responsableId', pr.responsable_id,
        'fechaSalida', pr.fecha_salida, 'fechaDevolucion', pr.fecha_devolucion
      ) order by pr.fecha_salida desc)
      from (select * from prestamos where empresa_id = v_empresa
            order by fecha_salida desc limit 200) pr
    ), '[]'::jsonb),
    'costos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'vehiculoId', c.vehiculo_id,
        'costoMes', c.costo_mes,
        'costoTotal', c.costo_total,
        'numSalidas', c.num_salidas
      ))
      from (
        select v.id as vehiculo_id,
               coalesce(sum(case when m.fecha >= v_mes
                                 then m.cantidad * m.costo_unitario end), 0) as costo_mes,
               coalesce(sum(m.cantidad * m.costo_unitario), 0) as costo_total,
               count(m.id) as num_salidas
        from vehiculos v
        left join movimientos m
          on m.vehiculo_id = v.id and m.tipo = 'salida' and m.empresa_id = v_empresa
        where v.empresa_id = v_empresa
        group by v.id
      ) c
    ), '[]'::jsonb),
    'tiposTrabajo', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', t.id, 'codigo', t.codigo, 'nombre', t.nombre,
        'precioManoObra', t.precio_mano_obra, 'activo', t.activo
      ) order by t.codigo)
      from tipos_trabajo t where t.empresa_id = v_empresa
    ), '[]'::jsonb),
    'trabajos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', t.id, 'mecanicoId', t.mecanico_id, 'vehiculoId', t.vehiculo_id,
        'tipoTrabajoId', t.tipo_trabajo_id, 'tipoNombre', tt.nombre,
        'descripcion', t.descripcion, 'precio', t.precio_snapshot,
        'estado', t.estado, 'fecha', t.fecha,
        'validadoPor', t.validado_por, 'notaAdmin', t.nota_admin,
        'creadaEn', t.creada_en,
        'piezas', coalesce((
          select jsonb_agg(jsonb_build_object('piezaId', tp.pieza_id, 'cantidad', tp.cantidad))
          from trabajo_piezas tp where tp.trabajo_id = t.id
        ), '[]'::jsonb)
      ) order by t.creada_en desc)
      from (select * from trabajos where empresa_id = v_empresa
            order by creada_en desc limit 300) t
      join tipos_trabajo tt on tt.id = t.tipo_trabajo_id
    ), '[]'::jsonb),
    'pagosMes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'mecanicoId', r.mecanico_id,
        'modoPago', r.modo_pago,
        'sueldoMonto', r.sueldo_monto,
        'validados', r.validados,
        'pendientes', r.pendientes,
        'rechazados', r.rechazados,
        'totalPagar', r.total_pagar
      ) order by r.total_pagar desc)
      from (
        select u.id as mecanico_id, u.modo_pago, u.sueldo_monto,
               count(t.id) filter (where t.estado = 'validada') as validados,
               count(t.id) filter (where t.estado = 'pendiente') as pendientes,
               count(t.id) filter (where t.estado = 'rechazada') as rechazados,
               case when u.modo_pago = 'sueldo'
                    then coalesce(u.sueldo_monto, 0)
                    else coalesce(sum(t.precio_snapshot) filter (where t.estado = 'validada'), 0)
               end as total_pagar
        from usuarios u
        left join trabajos t
          on t.mecanico_id = u.id and t.empresa_id = v_empresa and t.fecha >= v_mes
        where u.empresa_id = v_empresa and u.rol = 'mecanico'
        group by u.id, u.modo_pago, u.sueldo_monto
      ) r
    ), '[]'::jsonb),
    'lavados', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', l.id, 'vehiculoId', l.vehiculo_id, 'fecha', l.fecha,
        'activa', l.activa, 'marcadaEn', l.marcada_en,
        'marcadaPor', l.marcada_por, 'desmarcadaEn', l.desmarcada_en,
        'desmarcadaPor', l.desmarcada_por
      ) order by l.fecha desc, l.marcada_en desc)
      from (select * from lavados where empresa_id = v_empresa
            order by fecha desc, marcada_en desc limit 300) l
    ), '[]'::jsonb),
    -- ===== Extensión combustible (este archivo) =====
    'despachosCombustible', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', d.id, 'vehiculoId', d.vehiculo_id, 'despachadorId', d.despachador_id,
        'fecha', d.fecha, 'galones', d.galones, 'tipo', d.tipo_combustible,
        'odometro', d.odometro, 'costoUnitario', d.costo_galon,
        'total', d.total, 'creadaEn', d.creada_en
      ) order by d.creada_en desc)
      from (select * from despachos_combustible where empresa_id = v_empresa
            order by creada_en desc limit 300) d
    ), '[]'::jsonb)
  );
end;
$$;


-- === archivo: tanque.sql ===
-- TallerNeto · Extensión: INVENTARIO DEL TANQUE DE COMBUSTIBLE
-- Se aplica DESPUÉS de servidor/combustible.sql (y, para la demo,
-- los datos van en servidor/datos-tanque-demo.sql, después de
-- datos-combustible-demo.sql). NO modifica los archivos anteriores:
-- todo es idempotente y las funciones que cambian se REEMPLAZAN
-- conservando su firma y sus reglas.
--
-- Pedido de Miguel (2026-11-20): «el encargado del combustible puede
-- recibirlo y anotar cuántos galones recibió; el mismo sistema que
-- guarde la cantidad de combustible y vaya contando lo que resta
-- [con] cada [despacho a las] guagua[s]; y cuando se vaya agotando
-- le marque en el panel que queda poco combustible, [para que] la
-- administración [tenga] tiempo de pedir la recarga del tanque».
--
-- Diseño:
--  - Saldo del tanque POR TIPO (diesel|gasolina|glp), calculado:
--    Σ recepciones − Σ despachos de ese tipo. Sin tabla de saldos:
--    el saldo siempre sale de los movimientos (auditable).
--  - RECEPCIONES: las registra el rol combustible (y admin) con
--    tipo, galones (> 0), costo por galón de compra, proveedor y
--    nota opcionales. Cada recepción suma al saldo y queda con
--    auditoría (quién la registró y cuándo).
--  - DESPACHOS: pr_registrar_despacho ahora DESCUENTA del saldo
--    del tipo y RECHAZA si el saldo no alcanza, con el mensaje
--    «Tanque de <tipo> sin suficiente combustible: quedan X gal».
--    Todas las demás reglas quedan intactas (odómetro no baja,
--    vehículo obligatorio, roles, módulo activo).
--    OJO al desplegar: una empresa que ya despachaba sin tanque
--    debe registrar su carga inicial como una recepción, o sus
--    despachos serán rechazados por saldo insuficiente.
--  - UMBRAL de «poco combustible» por empresa y tipo, editable por
--    administración (pr_fijar_umbral_tanque). Defaults: diésel 100,
--    gasolina 50, GLP 30 galones. Saldo ≤ umbral ⇒ alerta.
--  - CAPACIDAD física del tanque por empresa y tipo (pedido de
--    Miguel: «que se pueda poner la capacidad del tanque, [para
--    que] se sepa en realidad por dónde está el tanque en la
--    barra»): vive en la misma tabla tanque_umbrales, se fija con
--    pr_configurar_tanque (umbral + capacidad). Con capacidad, el
--    bloque tanque trae `porcentaje` = saldo ÷ capacidad × 100
--    (el nivel REAL de la barra) y las recepciones que harían
--    superar la capacidad se RECHAZAN («El tanque de diésel es de
--    1,000 gal y tiene 391: no caben 700 más»). Sin capacidad
--    (NULL): sin límite físico y sin porcentaje.
--  - DÍAS ESTIMADOS de alcance: consumo promedio diario del tipo en
--    los últimos 14 días (Σ despachos de 14 días ÷ 14); días =
--    saldo ÷ promedio, redondeado a 1 decimal. Sin consumo reciente
--    no hay estimación (null): no se inventa un número.
--  - El bloque `tanque` viaja en pr_datos_combustible (app),
--    pr_resumen_combustible (panel) y pr_snapshot (panel: tarjetas,
--    historial de recepciones y edición de umbrales).

-- ============ RECEPCIONES DE COMBUSTIBLE (entradas al tanque) ====
create table if not exists recepciones_combustible (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references empresas(id) on delete cascade,
  recibido_por uuid not null references usuarios(id),
  fecha date not null default (now() at time zone 'America/Santo_Domingo')::date,
  galones numeric(10,2) not null check (galones > 0),
  tipo_combustible text not null check (tipo_combustible in ('diesel','gasolina','glp')),
  costo_galon numeric(12,2) not null check (costo_galon >= 0),
  -- Total de la compra guardado al recibir (foto del momento).
  total numeric(14,2) not null,
  proveedor text,
  nota text,
  creada_en timestamptz not null default now()
);
create index if not exists idx_recepciones_empresa_fecha
  on recepciones_combustible(empresa_id, fecha desc, creada_en desc);

alter table recepciones_combustible enable row level security;

-- ============ UMBRALES DE «POCO COMBUSTIBLE» POR EMPRESA/TIPO ===
create table if not exists tanque_umbrales (
  empresa_id uuid not null references empresas(id) on delete cascade,
  tipo_combustible text not null check (tipo_combustible in ('diesel','gasolina','glp')),
  umbral numeric(10,2) not null check (umbral >= 0),
  primary key (empresa_id, tipo_combustible)
);

alter table tanque_umbrales enable row level security;

-- CAPACIDAD del tanque (galones) por empresa y tipo: NULL = sin
-- configurar. Si viene, debe ser > 0 (regla física: un tanque de
-- 0 galones no existe).
alter table tanque_umbrales
  add column if not exists capacidad numeric(10,2);
do $$
begin
  if not exists (select 1 from pg_constraint
                 where conname = 'tanque_umbrales_capacidad_positiva') then
    alter table tanque_umbrales
      add constraint tanque_umbrales_capacidad_positiva
      check (capacidad is null or capacidad > 0);
  end if;
end;
$$;

-- Etiqueta legible del tipo (para mensajes y tarjetas).
create or replace function pr__tipo_combustible_etiqueta(p_tipo text) returns text
language sql immutable as $$
  select case p_tipo
    when 'diesel' then 'diésel'
    when 'gasolina' then 'gasolina'
    when 'glp' then 'GLP'
    else p_tipo
  end;
$$;

-- Umbral vigente: el configurado por la empresa o el default del tipo.
create or replace function pr__umbral_tanque(p_empresa uuid, p_tipo text)
returns numeric language sql stable security definer as $$
  select coalesce(
    (select umbral from tanque_umbrales
     where empresa_id = p_empresa and tipo_combustible = p_tipo),
    case p_tipo when 'diesel' then 100 when 'gasolina' then 50 else 30 end
  );
$$;

-- Capacidad configurada del tanque de un tipo (NULL = sin fijar).
create or replace function pr__capacidad_tanque(p_empresa uuid, p_tipo text)
returns numeric language sql stable security definer as $$
  select capacidad from tanque_umbrales
  where empresa_id = p_empresa and tipo_combustible = p_tipo;
$$;

-- Saldo del tanque de un tipo: recepciones menos despachos.
create or replace function pr__saldo_tanque(p_empresa uuid, p_tipo text)
returns numeric language sql stable security definer as $$
  select coalesce((select sum(galones) from recepciones_combustible
                   where empresa_id = p_empresa and tipo_combustible = p_tipo), 0)
       - coalesce((select sum(galones) from despachos_combustible
                   where empresa_id = p_empresa and tipo_combustible = p_tipo), 0);
$$;

-- Bloque `tanque` completo para una empresa: por tipo, saldo,
-- umbral, alerta, capacidad y porcentaje de nivel real (saldo ÷
-- capacidad × 100, 1 decimal; null sin capacidad), consumo
-- promedio diario (14 días), días estimados de alcance y las
-- últimas 5 recepciones del tipo.
create or replace function pr__tanque_json(p_empresa uuid) returns jsonb
language plpgsql stable security definer as $$
declare
  v_hoy date := pr_hoy();
  v_tipos text[] := array['diesel','gasolina','glp'];
  v_tipo text;
  v_saldo numeric;
  v_umbral numeric;
  v_capacidad numeric;
  v_consumo numeric;
  v_resultado jsonb := '[]'::jsonb;
begin
  foreach v_tipo in array v_tipos loop
    v_saldo := pr__saldo_tanque(p_empresa, v_tipo);
    v_umbral := pr__umbral_tanque(p_empresa, v_tipo);
    v_capacidad := pr__capacidad_tanque(p_empresa, v_tipo);
    v_consumo := coalesce((
      select sum(galones) from despachos_combustible
      where empresa_id = p_empresa and tipo_combustible = v_tipo
        and fecha >= v_hoy - 13 and fecha <= v_hoy
    ), 0) / 14.0;
    v_resultado := v_resultado || jsonb_build_object(
      'tipo', v_tipo,
      'saldo', v_saldo,
      'umbral', v_umbral,
      'capacidad', v_capacidad,
      'configurado', exists (
        select 1 from tanque_umbrales
        where empresa_id = p_empresa and tipo_combustible = v_tipo),
      'porcentaje', case when v_capacidad is not null and v_capacidad > 0
                         then round(v_saldo / v_capacidad * 100, 1) end,
      'alerta', v_saldo <= v_umbral,
      'consumoPromedioDiario', round(v_consumo, 2),
      'diasEstimados', case when v_consumo > 0
                            then round(v_saldo / v_consumo, 1) end,
      'ultimasRecepciones', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', r.id, 'galones', r.galones, 'tipo', r.tipo_combustible,
          'costoUnitario', r.costo_galon, 'total', r.total,
          'proveedor', r.proveedor, 'nota', r.nota,
          'fecha', r.fecha, 'creadaEn', r.creada_en,
          'recibidoPor', r.recibido_por,
          'recibidoPorNombre', (select nombre from usuarios where id = r.recibido_por)
        ) order by r.creada_en desc)
        from (select * from recepciones_combustible
              where empresa_id = p_empresa and tipo_combustible = v_tipo
              order by creada_en desc limit 5) r
      ), '[]'::jsonb)
    );
  end loop;
  return v_resultado;
end;
$$;

-- ================================================================
-- REGISTRAR RECEPCIÓN (app; rol combustible o admin).
-- Suma al saldo del tanque del tipo. Galones > 0 obligatorio.
-- ================================================================
create or replace function pr_registrar_recepcion(p_empresa uuid, p_tipo text,
                                                  p_galones numeric, p_costo_galon numeric,
                                                  p_proveedor text default null,
                                                  p_nota text default null,
                                                  p_quien uuid default null,
                                                  p_token text default null)
returns recepciones_combustible language plpgsql security definer as $$
declare
  q usuarios;
  r recepciones_combustible;
  v_capacidad numeric;
  v_saldo numeric;
begin
  perform pr__exigir_combustible_activo(p_empresa);
  q := pr_actor_con_rol(p_empresa, p_quien, p_token, array['combustible','admin']);
  if p_tipo not in ('diesel','gasolina','glp') then
    raise exception 'Tipo de combustible no válido: % (usa diesel, gasolina o glp)', p_tipo;
  end if;
  if p_galones is null or p_galones <= 0 then
    raise exception 'La cantidad de galones recibida debe ser mayor que cero';
  end if;
  if p_costo_galon is null or p_costo_galon < 0 then
    raise exception 'El costo por galón no puede ser negativo';
  end if;
  -- Regla física: a un tanque no le cabe más de su capacidad (solo
  -- si está configurada; sin capacidad fijada no hay límite).
  v_capacidad := pr__capacidad_tanque(p_empresa, p_tipo);
  if v_capacidad is not null then
    v_saldo := pr__saldo_tanque(p_empresa, p_tipo);
    if v_saldo + p_galones > v_capacidad then
      raise exception 'El tanque de % es de % gal y tiene %: no caben % más',
        pr__tipo_combustible_etiqueta(p_tipo), trim_scale(v_capacidad),
        trim_scale(v_saldo), trim_scale(p_galones);
    end if;
  end if;
  insert into recepciones_combustible
    (empresa_id, recibido_por, fecha, galones, tipo_combustible,
     costo_galon, total, proveedor, nota)
  values
    (p_empresa, q.id, pr_hoy(), p_galones, p_tipo,
     p_costo_galon, round(p_galones * p_costo_galon, 2),
     nullif(trim(coalesce(p_proveedor, '')), ''),
     nullif(trim(coalesce(p_nota, '')), ''))
  returning * into r;
  perform pr_registrar_accion(p_empresa, q.id, 'recepcion_combustible',
    format('Recibió %s galones de %s en el tanque (saldo: %s gal)',
           trim_scale(p_galones), pr__tipo_combustible_etiqueta(p_tipo),
           trim_scale(pr__saldo_tanque(p_empresa, p_tipo))));
  return r;
end;
$$;

-- ================================================================
-- FIJAR EL UMBRAL DE «POCO COMBUSTIBLE» (solo administración).
-- ================================================================
create or replace function pr_fijar_umbral_tanque(p_empresa uuid, p_tipo text,
                                                  p_umbral numeric,
                                                  p_quien uuid default null,
                                                  p_token text default null)
returns void language plpgsql security definer as $$
declare
  q usuarios;
begin
  perform pr__exigir_combustible_activo(p_empresa);
  q := pr_actor_con_rol(p_empresa, p_quien, p_token, array['admin']);
  if p_tipo not in ('diesel','gasolina','glp') then
    raise exception 'Tipo de combustible no válido: % (usa diesel, gasolina o glp)', p_tipo;
  end if;
  if p_umbral is null or p_umbral < 0 then
    raise exception 'El umbral de poco combustible no puede ser negativo';
  end if;
  insert into tanque_umbrales (empresa_id, tipo_combustible, umbral)
  values (p_empresa, p_tipo, p_umbral)
  on conflict (empresa_id, tipo_combustible)
  do update set umbral = excluded.umbral;
  perform pr_registrar_accion(p_empresa, q.id, 'umbral_tanque',
    format('Fijó el umbral de poco combustible de %s en %s galones',
           pr__tipo_combustible_etiqueta(p_tipo), trim_scale(p_umbral)));
end;
$$;

-- ================================================================
-- CONFIGURAR EL TANQUE (solo administración): umbral de «poco
-- combustible» Y capacidad física de un tipo en una sola llamada
-- (el formulario del panel edita los dos juntos). p_capacidad
-- NULL = sin capacidad configurada (sin límite y sin porcentaje);
-- si viene, debe ser > 0.
-- ================================================================
create or replace function pr_configurar_tanque(p_empresa uuid, p_tipo text,
                                                p_umbral numeric, p_capacidad numeric,
                                                p_quien uuid default null,
                                                p_token text default null)
returns void language plpgsql security definer as $$
declare
  q usuarios;
begin
  perform pr__exigir_combustible_activo(p_empresa);
  q := pr_actor_con_rol(p_empresa, p_quien, p_token, array['admin']);
  if p_tipo not in ('diesel','gasolina','glp') then
    raise exception 'Tipo de combustible no válido: % (usa diesel, gasolina o glp)', p_tipo;
  end if;
  if p_umbral is null or p_umbral < 0 then
    raise exception 'El umbral de poco combustible no puede ser negativo';
  end if;
  if p_capacidad is not null and p_capacidad <= 0 then
    raise exception 'La capacidad del tanque debe ser mayor que cero (o déjala vacía para no fijarla)';
  end if;
  insert into tanque_umbrales (empresa_id, tipo_combustible, umbral, capacidad)
  values (p_empresa, p_tipo, p_umbral, p_capacidad)
  on conflict (empresa_id, tipo_combustible)
  do update set umbral = excluded.umbral, capacidad = excluded.capacidad;
  perform pr_registrar_accion(p_empresa, q.id, 'configurar_tanque',
    format('Configuró el tanque de %s: umbral de alerta %s gal, capacidad %s',
           pr__tipo_combustible_etiqueta(p_tipo), trim_scale(p_umbral),
           case when p_capacidad is null then 'sin fijar'
                else trim_scale(p_capacidad) || ' gal' end));
end;
$$;

-- ================================================================
-- REGISTRAR DESPACHO — versión con TANQUE (reemplaza la de
-- combustible.sql conservando TODAS sus reglas y añadiendo una:
-- el despacho descuenta del saldo del tipo y se rechaza si el
-- saldo no alcanza).
-- ================================================================
create or replace function pr_registrar_despacho(p_empresa uuid, p_vehiculo uuid,
                                                 p_galones numeric, p_tipo text,
                                                 p_odometro numeric, p_costo_galon numeric,
                                                 p_quien uuid default null,
                                                 p_token text default null)
returns despachos_combustible language plpgsql security definer as $$
declare
  q usuarios;
  v vehiculos;
  d despachos_combustible;
  v_ultimo numeric;
  v_saldo numeric;
begin
  perform pr__exigir_combustible_activo(p_empresa);
  q := pr_actor_con_rol(p_empresa, p_quien, p_token, array['combustible','admin']);
  if p_vehiculo is null then
    raise exception 'Todo despacho debe decir el vehículo';
  end if;
  select * into v from vehiculos where id = p_vehiculo and empresa_id = p_empresa;
  if v.id is null then raise exception 'Vehículo no encontrado en esta empresa'; end if;
  if not v.activo then raise exception 'El vehículo % está inactivo', v.codigo; end if;
  if p_galones is null or p_galones <= 0 then
    raise exception 'La cantidad de galones debe ser mayor que cero';
  end if;
  if p_tipo not in ('diesel','gasolina','glp') then
    raise exception 'Tipo de combustible no válido: % (usa diesel, gasolina o glp)', p_tipo;
  end if;
  if p_odometro is null or p_odometro < 0 then
    raise exception 'El odómetro es obligatorio y no puede ser negativo';
  end if;
  if p_costo_galon is null or p_costo_galon < 0 then
    raise exception 'El costo por galón no puede ser negativo';
  end if;
  -- Regla de integridad: el odómetro nunca baja.
  v_ultimo := pr__ultimo_odometro(p_empresa, v.id);
  if v_ultimo is not null and p_odometro < v_ultimo then
    raise exception 'El odómetro (%) es menor que el último registrado (%) para el vehículo %: revísalo',
      p_odometro, v_ultimo, v.codigo;
  end if;
  -- Regla del tanque: no se despacha lo que el tanque no tiene.
  v_saldo := pr__saldo_tanque(p_empresa, p_tipo);
  if v_saldo < p_galones then
    raise exception 'Tanque de % sin suficiente combustible: quedan % gal',
      pr__tipo_combustible_etiqueta(p_tipo), trim_scale(v_saldo);
  end if;
  insert into despachos_combustible
    (empresa_id, vehiculo_id, despachador_id, fecha, galones,
     tipo_combustible, odometro, costo_galon, total)
  values
    (p_empresa, v.id, q.id, pr_hoy(), p_galones,
     p_tipo, p_odometro, p_costo_galon, round(p_galones * p_costo_galon, 2))
  returning * into d;
  perform pr_registrar_accion(p_empresa, q.id, 'despacho_combustible',
    format('Despachó %s galones de %s al vehículo %s (odómetro %s, total %s)',
           p_galones, p_tipo, v.codigo, p_odometro, d.total));
  return d;
end;
$$;

-- ================================================================
-- DATOS DE COMBUSTIBLE (app) — versión con el bloque `tanque`:
-- saldo por tipo con alerta y días estimados, para que el
-- despachador vea cuánto queda sin salir de su pantalla.
-- ================================================================
create or replace function pr_datos_combustible(p_quien uuid default null,
                                                p_token text default null)
returns jsonb language plpgsql security definer as $$
declare
  u usuarios;
  q usuarios;
  e empresas;
  v_hoy date := pr_hoy();
begin
  select * into u from usuarios where id = p_quien and activo;
  if u.id is null then raise exception 'Usuario no válido'; end if;
  if u.empresa_id is null then
    raise exception 'Esta cuenta no es de una empresa';
  end if;
  q := pr_actor_con_rol(u.empresa_id, p_quien, p_token, array['combustible','admin']);
  perform pr__exigir_combustible_activo(q.empresa_id);
  select * into e from empresas where id = q.empresa_id;

  return jsonb_build_object(
    'usuario', jsonb_build_object(
      'id', q.id, 'nombre', q.nombre, 'codigo', q.codigo, 'rol', q.rol),
    'empresa', jsonb_build_object(
      'id', e.id, 'nombre', e.nombre, 'combustibleActivo', e.combustible_activo),
    'fecha', v_hoy,
    'unidad', 'km/gal',
    'tipos', pr__precios_combustible(),
    'tanque', pr__tanque_json(q.empresa_id),
    'vehiculos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', v.id, 'codigo', v.codigo, 'placa', v.placa, 'marca', v.marca,
        'modelo', v.modelo, 'anio', v.anio, 'estado', v.estado, 'activo', v.activo,
        'ultimoOdometro', pr__ultimo_odometro(q.empresa_id, v.id)
      ) order by v.codigo)
      from vehiculos v
      where v.empresa_id = q.empresa_id and v.activo
    ), '[]'::jsonb),
    'despachosHoy', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', d.id, 'vehiculoId', d.vehiculo_id,
        'vehiculoCodigo', v.codigo, 'vehiculoPlaca', v.placa,
        'galones', d.galones, 'tipo', d.tipo_combustible,
        'odometro', d.odometro, 'costoUnitario', d.costo_galon,
        'total', d.total, 'creadaEn', d.creada_en,
        'despachadorId', d.despachador_id,
        'despachadorNombre', (select nombre from usuarios where id = d.despachador_id)
      ) order by d.creada_en desc)
      from despachos_combustible d
      join vehiculos v on v.id = d.vehiculo_id
      where d.empresa_id = q.empresa_id and d.fecha = v_hoy
    ), '[]'::jsonb),
    'totalGalonesHoy', coalesce((
      select sum(galones) from despachos_combustible
      where empresa_id = q.empresa_id and fecha = v_hoy
    ), 0),
    'totalCostoHoy', coalesce((
      select sum(total) from despachos_combustible
      where empresa_id = q.empresa_id and fecha = v_hoy
    ), 0)
  );
end;
$$;

-- ================================================================
-- RESUMEN DE COMBUSTIBLE (panel) — versión con el bloque `tanque`
-- (saldo, umbral, alerta y días estimados por tipo).
-- ================================================================
create or replace function pr_resumen_combustible(p_empresa uuid, p_desde date, p_hasta date,
                                                  p_quien uuid default null,
                                                  p_token text default null)
returns jsonb language plpgsql security definer as $$
declare
  q usuarios;
begin
  perform pr__exigir_combustible_activo(p_empresa);
  q := pr_actor_con_rol(p_empresa, p_quien, p_token, array['admin','almacen']);
  if p_desde is null or p_hasta is null or p_hasta < p_desde then
    raise exception 'Rango de fechas no válido para el resumen de combustible';
  end if;
  return jsonb_build_object(
    'desde', p_desde,
    'hasta', p_hasta,
    'unidad', 'km/gal',
    'tanque', pr__tanque_json(p_empresa),
    'porVehiculo', coalesce((
      select jsonb_agg(jsonb_build_object(
        'vehiculoId', r.vehiculo_id,
        'vehiculoCodigo', r.codigo,
        'galones', r.galones,
        'costoTotal', r.costo_total,
        'despachos', r.despachos,
        'distancia', r.distancia,
        'rendimiento', r.rendimiento
      ) order by r.rendimiento asc nulls last, r.galones desc)
      from (
        select v.id as vehiculo_id, v.codigo,
               coalesce(sum(d.galones), 0) as galones,
               coalesce(sum(d.total), 0) as costo_total,
               count(d.id) as despachos,
               case when count(d.id) >= 2
                    then max(d.odometro) - min(d.odometro) end as distancia,
               case when count(d.id) >= 2 and sum(d.galones) > 0
                     and (max(d.odometro) - min(d.odometro)) > 0
                    then round((max(d.odometro) - min(d.odometro)) / sum(d.galones), 2)
               end as rendimiento
        from vehiculos v
        left join despachos_combustible d
          on d.vehiculo_id = v.id and d.empresa_id = p_empresa
         and d.fecha between p_desde and p_hasta
        where v.empresa_id = p_empresa and v.activo
        group by v.id, v.codigo
      ) r
    ), '[]'::jsonb),
    'porDia', coalesce((
      select jsonb_agg(jsonb_build_object(
        'fecha', s.fecha, 'galones', s.galones,
        'costoTotal', s.costo_total, 'despachos', s.despachos
      ) order by s.fecha desc)
      from (
        select fecha, sum(galones) as galones, sum(total) as costo_total,
               count(*) as despachos
        from despachos_combustible
        where empresa_id = p_empresa and fecha between p_desde and p_hasta
        group by fecha
      ) s
    ), '[]'::jsonb),
    'totalGeneral', (
      select jsonb_build_object(
        'galones', coalesce(sum(galones), 0),
        'costoTotal', coalesce(sum(total), 0),
        'despachos', count(*)
      )
      from despachos_combustible
      where empresa_id = p_empresa and fecha between p_desde and p_hasta
    )
  );
end;
$$;

-- ================================================================
-- SNAPSHOT: se vuelve a reemplazar (versión de combustible.sql)
-- para añadir el bloque `tanque` y las `recepcionesCombustible`
-- recientes: el panel pinta el inventario del tanque de aquí.
-- TODAS las claves anteriores se conservan.
-- ================================================================
create or replace function pr_snapshot(p_empresa uuid default null,
                                       p_quien uuid default null,
                                       p_token text default null)
returns jsonb language plpgsql security definer as $$
declare
  q usuarios;
  e empresas;
  lic licencias;
  v_empresa uuid;
  v_mes date := date_trunc('month', pr_hoy())::date;
begin
  q := pr_actor_empresa(p_empresa, p_quien, p_token);
  v_empresa := coalesce(p_empresa, q.empresa_id);
  if v_empresa is null then
    raise exception 'Indica qué empresa quieres ver';
  end if;
  if q.rol <> 'superadmin' and v_empresa is distinct from q.empresa_id then
    raise exception 'No tienes permiso para ver esta empresa';
  end if;

  select * into e from empresas where id = v_empresa;
  if e.id is null then raise exception 'Empresa no encontrada'; end if;
  select * into lic from licencias where empresa_id = v_empresa order by creada_en desc limit 1;

  return jsonb_build_object(
    'empresa', jsonb_build_object(
      'id', e.id, 'nombre', e.nombre, 'activa', e.activa,
      'lavadoActivo', e.lavado_activo,
      'combustibleActivo', e.combustible_activo),
    'licencia', case when lic.id is null then null else jsonb_build_object(
      'estado', lic.estado, 'vence', lic.vence, 'maxVehiculos', lic.max_vehiculos,
      'diasRestantes', case when lic.vence is null then null else lic.vence - pr_hoy() end,
      'porVencer', case when lic.vence is null then false
                        else (lic.vence - pr_hoy()) between 0 and 30 end
    ) end,
    'usuarios', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', u.id, 'rol', u.rol, 'nombre', u.nombre, 'codigo', u.codigo, 'activo', u.activo,
        'modoPago', u.modo_pago, 'sueldoMonto', u.sueldo_monto
      ) order by u.codigo)
      from usuarios u where u.empresa_id = v_empresa
    ), '[]'::jsonb),
    'vehiculos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', v.id, 'codigo', v.codigo, 'placa', v.placa, 'marca', v.marca,
        'modelo', v.modelo, 'anio', v.anio, 'estado', v.estado, 'activo', v.activo
      ) order by v.codigo)
      from vehiculos v where v.empresa_id = v_empresa
    ), '[]'::jsonb),
    'piezas', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id, 'codigo', p.codigo, 'nombre', p.nombre, 'ubicacion', p.ubicacion,
        'costo', p.costo, 'stock', p.stock, 'stockMinimo', p.stock_minimo, 'activa', p.activa
      ) order by p.codigo)
      from piezas p where p.empresa_id = v_empresa
    ), '[]'::jsonb),
    'movimientos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', m.id, 'tipo', m.tipo, 'piezaId', m.pieza_id, 'cantidad', m.cantidad,
        'costoUnitario', m.costo_unitario, 'vehiculoId', m.vehiculo_id,
        'usuarioId', m.usuario_id, 'nota', m.nota, 'fecha', m.fecha,
        'creadaEn', m.creada_en
      ) order by m.creada_en desc)
      from (select * from movimientos where empresa_id = v_empresa
            order by creada_en desc limit 300) m
    ), '[]'::jsonb),
    'herramientas', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', h.id, 'codigo', h.codigo, 'nombre', h.nombre, 'estado', h.estado, 'activa', h.activa
      ) order by h.codigo)
      from herramientas h where h.empresa_id = v_empresa
    ), '[]'::jsonb),
    'prestamos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', pr.id, 'herramientaId', pr.herramienta_id, 'responsableId', pr.responsable_id,
        'fechaSalida', pr.fecha_salida, 'fechaDevolucion', pr.fecha_devolucion
      ) order by pr.fecha_salida desc)
      from (select * from prestamos where empresa_id = v_empresa
            order by fecha_salida desc limit 200) pr
    ), '[]'::jsonb),
    'costos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'vehiculoId', c.vehiculo_id,
        'costoMes', c.costo_mes,
        'costoTotal', c.costo_total,
        'numSalidas', c.num_salidas
      ))
      from (
        select v.id as vehiculo_id,
               coalesce(sum(case when m.fecha >= v_mes
                                 then m.cantidad * m.costo_unitario end), 0) as costo_mes,
               coalesce(sum(m.cantidad * m.costo_unitario), 0) as costo_total,
               count(m.id) as num_salidas
        from vehiculos v
        left join movimientos m
          on m.vehiculo_id = v.id and m.tipo = 'salida' and m.empresa_id = v_empresa
        where v.empresa_id = v_empresa
        group by v.id
      ) c
    ), '[]'::jsonb),
    'tiposTrabajo', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', t.id, 'codigo', t.codigo, 'nombre', t.nombre,
        'precioManoObra', t.precio_mano_obra, 'activo', t.activo
      ) order by t.codigo)
      from tipos_trabajo t where t.empresa_id = v_empresa
    ), '[]'::jsonb),
    'trabajos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', t.id, 'mecanicoId', t.mecanico_id, 'vehiculoId', t.vehiculo_id,
        'tipoTrabajoId', t.tipo_trabajo_id, 'tipoNombre', tt.nombre,
        'descripcion', t.descripcion, 'precio', t.precio_snapshot,
        'estado', t.estado, 'fecha', t.fecha,
        'validadoPor', t.validado_por, 'notaAdmin', t.nota_admin,
        'creadaEn', t.creada_en,
        'piezas', coalesce((
          select jsonb_agg(jsonb_build_object('piezaId', tp.pieza_id, 'cantidad', tp.cantidad))
          from trabajo_piezas tp where tp.trabajo_id = t.id
        ), '[]'::jsonb)
      ) order by t.creada_en desc)
      from (select * from trabajos where empresa_id = v_empresa
            order by creada_en desc limit 300) t
      join tipos_trabajo tt on tt.id = t.tipo_trabajo_id
    ), '[]'::jsonb),
    'pagosMes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'mecanicoId', r.mecanico_id,
        'modoPago', r.modo_pago,
        'sueldoMonto', r.sueldo_monto,
        'validados', r.validados,
        'pendientes', r.pendientes,
        'rechazados', r.rechazados,
        'totalPagar', r.total_pagar
      ) order by r.total_pagar desc)
      from (
        select u.id as mecanico_id, u.modo_pago, u.sueldo_monto,
               count(t.id) filter (where t.estado = 'validada') as validados,
               count(t.id) filter (where t.estado = 'pendiente') as pendientes,
               count(t.id) filter (where t.estado = 'rechazada') as rechazados,
               case when u.modo_pago = 'sueldo'
                    then coalesce(u.sueldo_monto, 0)
                    else coalesce(sum(t.precio_snapshot) filter (where t.estado = 'validada'), 0)
               end as total_pagar
        from usuarios u
        left join trabajos t
          on t.mecanico_id = u.id and t.empresa_id = v_empresa and t.fecha >= v_mes
        where u.empresa_id = v_empresa and u.rol = 'mecanico'
        group by u.id, u.modo_pago, u.sueldo_monto
      ) r
    ), '[]'::jsonb),
    'lavados', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', l.id, 'vehiculoId', l.vehiculo_id, 'fecha', l.fecha,
        'activa', l.activa, 'marcadaEn', l.marcada_en,
        'marcadaPor', l.marcada_por, 'desmarcadaEn', l.desmarcada_en,
        'desmarcadaPor', l.desmarcada_por
      ) order by l.fecha desc, l.marcada_en desc)
      from (select * from lavados where empresa_id = v_empresa
            order by fecha desc, marcada_en desc limit 300) l
    ), '[]'::jsonb),
    'despachosCombustible', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', d.id, 'vehiculoId', d.vehiculo_id, 'despachadorId', d.despachador_id,
        'fecha', d.fecha, 'galones', d.galones, 'tipo', d.tipo_combustible,
        'odometro', d.odometro, 'costoUnitario', d.costo_galon,
        'total', d.total, 'creadaEn', d.creada_en
      ) order by d.creada_en desc)
      from (select * from despachos_combustible where empresa_id = v_empresa
            order by creada_en desc limit 300) d
    ), '[]'::jsonb),
    -- ===== Extensión tanque (este archivo) =====
    'tanque', pr__tanque_json(v_empresa),
    'recepcionesCombustible', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id, 'tipo', r.tipo_combustible, 'galones', r.galones,
        'costoUnitario', r.costo_galon, 'total', r.total,
        'proveedor', r.proveedor, 'nota', r.nota,
        'fecha', r.fecha, 'creadaEn', r.creada_en,
        'recibidoPor', r.recibido_por
      ) order by r.creada_en desc)
      from (select * from recepciones_combustible where empresa_id = v_empresa
            order by creada_en desc limit 100) r
    ), '[]'::jsonb)
  );
end;
$$;


-- === archivo: solicitudes.sql ===
-- TallerNeto · Extensión: SOLICITUDES DE PIEZAS del mecánico
-- Se aplica DESPUÉS de servidor/tanque.sql (y, para la demo, los
-- datos van en servidor/datos-solicitudes-demo.sql, después de
-- datos-tanque-demo.sql). NO modifica los archivos anteriores:
-- todo es idempotente y las funciones que cambian se REEMPLAZAN
-- conservando su firma y sus reglas.
--
-- Pedido de Miguel (2026-11-20): el mecánico, desde la app, puede
-- PEDIR una pieza que no está en stock (o que no existe en el
-- catálogo); administración la gestiona y, cuando llega, el stock
-- entra solo al inventario.
--
-- Diseño:
--  - El mecánico pide: pieza del catálogo (pieza_id) o TEXTO LIBRE
--    (nombre_pieza), cantidad, vehículo opcional, urgencia
--    (normal|urgente) y nota. Solo puede pedir A SU NOMBRE
--    (pr_solicitar_pieza exige rol mecanico y el actor es el dueño).
--  - Flujo de estados: pendiente → pedida (administración ya la
--    encargó) → recibida / rechazada.
--  - RECHAZAR exige nota del admin (el mecánico ve el motivo).
--  - RECIBIR (pr_recibir_solicitud): administración indica cantidad
--    recibida y costo unitario; el sistema genera la ENTRADA de
--    inventario reutilizando pr_registrar_movimiento: si la pieza
--    existe, suma su stock (y su costo pasa a ser el de la compra);
--    si era texto libre, CREA la pieza en el catálogo con el primer
--    código P-NN libre y entra el stock ahí.
--  - pr_datos_mecanico trae las solicitudes DEL mecánico (las suyas,
--    nunca las de otro) y pr_snapshot trae `solicitudesPiezas` para
--    la sección Solicitudes del panel y la alerta del Resumen.

-- ============ SOLICITUDES DE PIEZAS ============
create table if not exists solicitudes_piezas (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references empresas(id) on delete cascade,
  mecanico_id uuid not null references usuarios(id),
  -- Pieza del catálogo si se eligió una; null si es texto libre.
  pieza_id uuid references piezas(id),
  -- Nombre pedido (copia del nombre del catálogo al pedir, o el
  -- texto libre del mecánico): el historial no cambia si la pieza
  -- se renombra después.
  nombre_pieza text not null,
  cantidad int not null check (cantidad > 0),
  vehiculo_id uuid references vehiculos(id),
  urgencia text not null default 'normal' check (urgencia in ('normal','urgente')),
  nota text,
  estado text not null default 'pendiente'
    check (estado in ('pendiente','pedida','recibida','rechazada')),
  -- Respuesta de administración.
  respondida_por uuid references usuarios(id),
  respondida_en timestamptz,
  nota_admin text,
  -- Recepción: qué pieza quedó en el inventario y con qué datos.
  pieza_resultante_id uuid references piezas(id),
  cantidad_recibida int check (cantidad_recibida is null or cantidad_recibida > 0),
  costo_recibido numeric(12,2) check (costo_recibido is null or costo_recibido >= 0),
  fecha date not null default (now() at time zone 'America/Santo_Domingo')::date,
  creada_en timestamptz not null default now()
);
create index if not exists idx_solicitudes_empresa_estado
  on solicitudes_piezas(empresa_id, estado, creada_en desc);
create index if not exists idx_solicitudes_mecanico
  on solicitudes_piezas(empresa_id, mecanico_id, creada_en desc);

alter table solicitudes_piezas enable row level security;

-- Forma JSON de una solicitud (la comparten datos y snapshot).
create or replace function pr__solicitud_json(s solicitudes_piezas) returns jsonb
language sql stable as $$
  select jsonb_build_object(
    'id', s.id, 'mecanicoId', s.mecanico_id,
    'piezaId', s.pieza_id, 'nombrePieza', s.nombre_pieza,
    'cantidad', s.cantidad, 'vehiculoId', s.vehiculo_id,
    'urgencia', s.urgencia, 'nota', s.nota,
    'estado', s.estado,
    'respondidaPor', s.respondida_por, 'respondidaEn', s.respondida_en,
    'notaAdmin', s.nota_admin,
    'piezaResultanteId', s.pieza_resultante_id,
    'cantidadRecibida', s.cantidad_recibida,
    'costoRecibido', s.costo_recibido,
    'fecha', s.fecha, 'creadaEn', s.creada_en
  );
$$;

-- ================================================================
-- SOLICITAR PIEZA (app; SOLO rol mecanico, siempre a su nombre).
-- ================================================================
create or replace function pr_solicitar_pieza(p_empresa uuid, p_nombre text default null,
                                              p_cantidad int default 1,
                                              p_pieza uuid default null,
                                              p_vehiculo uuid default null,
                                              p_urgencia text default 'normal',
                                              p_nota text default null,
                                              p_quien uuid default null,
                                              p_token text default null)
returns solicitudes_piezas language plpgsql security definer as $$
declare
  q usuarios;
  p piezas;
  v vehiculos;
  s solicitudes_piezas;
  v_nombre text;
begin
  q := pr_actor_con_rol(p_empresa, p_quien, p_token, array['mecanico']);
  if p_cantidad is null or p_cantidad <= 0 then
    raise exception 'La cantidad debe ser mayor que cero';
  end if;
  if p_urgencia not in ('normal','urgente') then
    raise exception 'Urgencia no válida: % (usa normal o urgente)', p_urgencia;
  end if;
  if p_pieza is not null then
    select * into p from piezas where id = p_pieza and empresa_id = p_empresa;
    if p.id is null then raise exception 'Pieza no encontrada en esta empresa'; end if;
    v_nombre := p.nombre;
  else
    v_nombre := nullif(trim(coalesce(p_nombre, '')), '');
    if v_nombre is null then
      raise exception 'Escribe el nombre de la pieza que necesitas';
    end if;
  end if;
  if p_vehiculo is not null then
    select * into v from vehiculos where id = p_vehiculo and empresa_id = p_empresa;
    if v.id is null then raise exception 'Vehículo no encontrado en esta empresa'; end if;
  end if;
  insert into solicitudes_piezas
    (empresa_id, mecanico_id, pieza_id, nombre_pieza, cantidad,
     vehiculo_id, urgencia, nota, fecha)
  values
    (p_empresa, q.id, p_pieza, v_nombre, p_cantidad,
     p_vehiculo, p_urgencia, nullif(trim(coalesce(p_nota, '')), ''), pr_hoy())
  returning * into s;
  perform pr_registrar_accion(p_empresa, q.id, 'solicitud_pieza',
    format('Pidió la pieza «%s» × %s%s', v_nombre, p_cantidad,
           case when p_urgencia = 'urgente' then ' (URGENTE)' else '' end));
  return s;
end;
$$;

-- ================================================================
-- RESPONDER SOLICITUD (panel; admin o almacén):
--  - 'pedida':    pendiente → pedida (ya se encargó).
--  - 'rechazada': pendiente|pedida → rechazada, con nota
--                 OBLIGATORIA (el mecánico ve el motivo).
-- ================================================================
create or replace function pr_responder_solicitud(p_solicitud uuid, p_accion text,
                                                  p_nota text default null,
                                                  p_quien uuid default null,
                                                  p_token text default null)
returns solicitudes_piezas language plpgsql security definer as $$
declare
  s solicitudes_piezas;
  q usuarios;
  v_nota text := nullif(trim(coalesce(p_nota, '')), '');
begin
  select * into s from solicitudes_piezas where id = p_solicitud;
  if s.id is null then raise exception 'Solicitud no encontrada'; end if;
  q := pr_actor_con_rol(s.empresa_id, p_quien, p_token, array['admin','almacen']);
  if p_accion = 'pedida' then
    if s.estado <> 'pendiente' then
      raise exception 'Solo se puede marcar «pedida» una solicitud pendiente (está %)', s.estado;
    end if;
    update solicitudes_piezas
    set estado = 'pedida', respondida_por = q.id, respondida_en = now(),
        nota_admin = coalesce(v_nota, nota_admin)
    where id = s.id returning * into s;
  elsif p_accion = 'rechazada' then
    if s.estado not in ('pendiente','pedida') then
      raise exception 'Esta solicitud ya está %: no se puede rechazar', s.estado;
    end if;
    if v_nota is null then
      raise exception 'Para rechazar hay que escribir el motivo: el mecánico lo va a ver';
    end if;
    update solicitudes_piezas
    set estado = 'rechazada', respondida_por = q.id, respondida_en = now(),
        nota_admin = v_nota
    where id = s.id returning * into s;
  else
    raise exception 'Acción no válida: % (usa pedida o rechazada)', p_accion;
  end if;
  perform pr_registrar_accion(s.empresa_id, q.id,
    case when p_accion = 'pedida' then 'solicitud_pedida' else 'solicitud_rechazada' end,
    format('Solicitud de «%s» × %s de %s: %s',
           s.nombre_pieza, s.cantidad,
           (select codigo from usuarios where id = s.mecanico_id), p_accion));
  return s;
end;
$$;

-- ================================================================
-- RECIBIR SOLICITUD (panel; admin o almacén): llegó la pieza.
-- Genera la ENTRADA de inventario con pr_registrar_movimiento:
--  - Pieza del catálogo: suma stock; su costo pasa a ser el costo
--    de esta compra (la entrada lo guarda como foto del momento).
--  - Texto libre: crea la pieza en el catálogo (primer código
--    P-NN libre) con ese costo y le entra el stock.
-- ================================================================
create or replace function pr_recibir_solicitud(p_solicitud uuid, p_cantidad_recibida int,
                                                p_costo_unitario numeric,
                                                p_quien uuid default null,
                                                p_token text default null)
returns solicitudes_piezas language plpgsql security definer as $$
declare
  s solicitudes_piezas;
  q usuarios;
  p piezas;
  v_codigo text;
  v_num int;
begin
  select * into s from solicitudes_piezas where id = p_solicitud;
  if s.id is null then raise exception 'Solicitud no encontrada'; end if;
  q := pr_actor_con_rol(s.empresa_id, p_quien, p_token, array['admin','almacen']);
  if s.estado not in ('pendiente','pedida') then
    raise exception 'Esta solicitud ya está %: no se puede recibir', s.estado;
  end if;
  if p_cantidad_recibida is null or p_cantidad_recibida <= 0 then
    raise exception 'La cantidad recibida debe ser mayor que cero';
  end if;
  if p_costo_unitario is null or p_costo_unitario < 0 then
    raise exception 'El costo unitario de la pieza recibida no puede ser negativo';
  end if;

  if s.pieza_id is not null then
    select * into p from piezas where id = s.pieza_id and empresa_id = s.empresa_id;
    if p.id is null then raise exception 'La pieza pedida ya no existe en el catálogo'; end if;
    -- El costo vigente pasa a ser el de esta compra: la entrada
    -- que genera pr_registrar_movimiento lo guarda como foto.
    update piezas set costo = p_costo_unitario where id = p.id;
  else
    -- Pieza nueva: primer código P-NN libre de la empresa.
    v_num := 1;
    loop
      v_codigo := 'P-' || lpad(v_num::text, 2, '0');
      exit when not exists (select 1 from piezas
                            where empresa_id = s.empresa_id and codigo = v_codigo);
      v_num := v_num + 1;
    end loop;
    insert into piezas (empresa_id, codigo, nombre, ubicacion, costo, stock, stock_minimo)
    values (s.empresa_id, v_codigo, s.nombre_pieza, null, p_costo_unitario, 0, 0)
    returning * into p;
  end if;

  perform pr_registrar_movimiento(
    s.empresa_id, 'entrada', p.id, p_cantidad_recibida, null,
    format('Recibida por solicitud de %s', (select codigo from usuarios where id = s.mecanico_id)),
    p_quien, p_token);

  update solicitudes_piezas
  set estado = 'recibida', respondida_por = q.id, respondida_en = now(),
      pieza_resultante_id = p.id,
      cantidad_recibida = p_cantidad_recibida,
      costo_recibido = p_costo_unitario
  where id = s.id returning * into s;
  perform pr_registrar_accion(s.empresa_id, q.id, 'solicitud_recibida',
    format('Se recibió «%s» × %s (solicitud de %s): entró al inventario como %s',
           s.nombre_pieza, p_cantidad_recibida,
           (select codigo from usuarios where id = s.mecanico_id), p.codigo));
  return s;
end;
$$;

-- ================================================================
-- DATOS DEL MECÁNICO (app) — versión con `solicitudes`: SOLO las
-- del propio mecánico (la consulta filtra por mecanico_id = actor;
-- un mecánico nunca ve las solicitudes de otro).
-- ================================================================
create or replace function pr_datos_mecanico(p_quien uuid default null,
                                             p_token text default null)
returns jsonb language plpgsql security definer as $$
declare
  u usuarios;
  q usuarios;
  e empresas;
  v_mes date := date_trunc('month', pr_hoy())::date;
  v_total_validado numeric;
  v_total_pendiente numeric;
begin
  select * into u from usuarios where id = p_quien and activo;
  if u.id is null then raise exception 'Usuario no válido'; end if;
  if u.empresa_id is null then
    raise exception 'Esta cuenta no es de un mecánico de empresa';
  end if;
  q := pr_actor_con_rol(u.empresa_id, p_quien, p_token, array['mecanico']);
  select * into e from empresas where id = q.empresa_id;

  select coalesce(sum(precio_snapshot), 0) into v_total_validado
  from trabajos
  where empresa_id = q.empresa_id and mecanico_id = q.id
    and estado = 'validada' and fecha >= v_mes;
  select coalesce(sum(precio_snapshot), 0) into v_total_pendiente
  from trabajos
  where empresa_id = q.empresa_id and mecanico_id = q.id
    and estado = 'pendiente' and fecha >= v_mes;

  return jsonb_build_object(
    'mecanico', jsonb_build_object(
      'id', q.id, 'nombre', q.nombre, 'codigo', q.codigo, 'rol', q.rol,
      'modoPago', q.modo_pago, 'sueldoMonto', q.sueldo_monto),
    'empresa', jsonb_build_object('id', e.id, 'nombre', e.nombre),
    'desdeMes', v_mes,
    'totalValidadoMes', v_total_validado,
    'totalPendienteMes', v_total_pendiente,
    'tiposTrabajo', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', t.id, 'codigo', t.codigo, 'nombre', t.nombre,
        'precioManoObra', t.precio_mano_obra, 'activo', t.activo
      ) order by t.codigo)
      from tipos_trabajo t
      where t.empresa_id = q.empresa_id and t.activo
    ), '[]'::jsonb),
    'vehiculos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', v.id, 'codigo', v.codigo, 'placa', v.placa, 'marca', v.marca,
        'modelo', v.modelo, 'anio', v.anio, 'estado', v.estado, 'activo', v.activo
      ) order by v.codigo)
      from vehiculos v where v.empresa_id = q.empresa_id and v.activo
    ), '[]'::jsonb),
    'piezas', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id, 'codigo', p.codigo, 'nombre', p.nombre, 'ubicacion', p.ubicacion,
        'costo', p.costo, 'stock', p.stock, 'stockMinimo', p.stock_minimo, 'activa', p.activa
      ) order by p.codigo)
      from piezas p where p.empresa_id = q.empresa_id and p.activa
    ), '[]'::jsonb),
    'trabajos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', t.id, 'mecanicoId', t.mecanico_id, 'vehiculoId', t.vehiculo_id,
        'tipoTrabajoId', t.tipo_trabajo_id, 'tipoNombre', tt.nombre,
        'descripcion', t.descripcion, 'precio', t.precio_snapshot,
        'estado', t.estado, 'fecha', t.fecha, 'notaAdmin', t.nota_admin,
        'creadaEn', t.creada_en,
        'piezas', coalesce((
          select jsonb_agg(jsonb_build_object('piezaId', tp.pieza_id, 'cantidad', tp.cantidad))
          from trabajo_piezas tp where tp.trabajo_id = t.id
        ), '[]'::jsonb)
      ) order by t.creada_en desc)
      from (select * from trabajos
            where empresa_id = q.empresa_id and mecanico_id = q.id
            order by creada_en desc limit 200) t
      join tipos_trabajo tt on tt.id = t.tipo_trabajo_id
    ), '[]'::jsonb),
    -- ===== Extensión solicitudes (este archivo) =====
    'solicitudes', coalesce((
      select jsonb_agg(pr__solicitud_json(x) order by x.creada_en desc)
      from (select * from solicitudes_piezas
            where empresa_id = q.empresa_id and mecanico_id = q.id
            order by creada_en desc limit 100) x
    ), '[]'::jsonb)
  );
end;
$$;

-- ================================================================
-- SNAPSHOT: se vuelve a reemplazar (versión de tanque.sql) para
-- añadir `solicitudesPiezas`: el panel pinta la sección
-- Solicitudes y la alerta del Resumen de aquí.
-- TODAS las claves anteriores se conservan.
-- ================================================================
create or replace function pr_snapshot(p_empresa uuid default null,
                                       p_quien uuid default null,
                                       p_token text default null)
returns jsonb language plpgsql security definer as $$
declare
  q usuarios;
  e empresas;
  lic licencias;
  v_empresa uuid;
  v_mes date := date_trunc('month', pr_hoy())::date;
begin
  q := pr_actor_empresa(p_empresa, p_quien, p_token);
  v_empresa := coalesce(p_empresa, q.empresa_id);
  if v_empresa is null then
    raise exception 'Indica qué empresa quieres ver';
  end if;
  if q.rol <> 'superadmin' and v_empresa is distinct from q.empresa_id then
    raise exception 'No tienes permiso para ver esta empresa';
  end if;

  select * into e from empresas where id = v_empresa;
  if e.id is null then raise exception 'Empresa no encontrada'; end if;
  select * into lic from licencias where empresa_id = v_empresa order by creada_en desc limit 1;

  return jsonb_build_object(
    'empresa', jsonb_build_object(
      'id', e.id, 'nombre', e.nombre, 'activa', e.activa,
      'lavadoActivo', e.lavado_activo,
      'combustibleActivo', e.combustible_activo),
    'licencia', case when lic.id is null then null else jsonb_build_object(
      'estado', lic.estado, 'vence', lic.vence, 'maxVehiculos', lic.max_vehiculos,
      'diasRestantes', case when lic.vence is null then null else lic.vence - pr_hoy() end,
      'porVencer', case when lic.vence is null then false
                        else (lic.vence - pr_hoy()) between 0 and 30 end
    ) end,
    'usuarios', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', u.id, 'rol', u.rol, 'nombre', u.nombre, 'codigo', u.codigo, 'activo', u.activo,
        'modoPago', u.modo_pago, 'sueldoMonto', u.sueldo_monto
      ) order by u.codigo)
      from usuarios u where u.empresa_id = v_empresa
    ), '[]'::jsonb),
    'vehiculos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', v.id, 'codigo', v.codigo, 'placa', v.placa, 'marca', v.marca,
        'modelo', v.modelo, 'anio', v.anio, 'estado', v.estado, 'activo', v.activo
      ) order by v.codigo)
      from vehiculos v where v.empresa_id = v_empresa
    ), '[]'::jsonb),
    'piezas', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id, 'codigo', p.codigo, 'nombre', p.nombre, 'ubicacion', p.ubicacion,
        'costo', p.costo, 'stock', p.stock, 'stockMinimo', p.stock_minimo, 'activa', p.activa
      ) order by p.codigo)
      from piezas p where p.empresa_id = v_empresa
    ), '[]'::jsonb),
    'movimientos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', m.id, 'tipo', m.tipo, 'piezaId', m.pieza_id, 'cantidad', m.cantidad,
        'costoUnitario', m.costo_unitario, 'vehiculoId', m.vehiculo_id,
        'usuarioId', m.usuario_id, 'nota', m.nota, 'fecha', m.fecha,
        'creadaEn', m.creada_en
      ) order by m.creada_en desc)
      from (select * from movimientos where empresa_id = v_empresa
            order by creada_en desc limit 300) m
    ), '[]'::jsonb),
    'herramientas', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', h.id, 'codigo', h.codigo, 'nombre', h.nombre, 'estado', h.estado, 'activa', h.activa
      ) order by h.codigo)
      from herramientas h where h.empresa_id = v_empresa
    ), '[]'::jsonb),
    'prestamos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', pr.id, 'herramientaId', pr.herramienta_id, 'responsableId', pr.responsable_id,
        'fechaSalida', pr.fecha_salida, 'fechaDevolucion', pr.fecha_devolucion
      ) order by pr.fecha_salida desc)
      from (select * from prestamos where empresa_id = v_empresa
            order by fecha_salida desc limit 200) pr
    ), '[]'::jsonb),
    'costos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'vehiculoId', c.vehiculo_id,
        'costoMes', c.costo_mes,
        'costoTotal', c.costo_total,
        'numSalidas', c.num_salidas
      ))
      from (
        select v.id as vehiculo_id,
               coalesce(sum(case when m.fecha >= v_mes
                                 then m.cantidad * m.costo_unitario end), 0) as costo_mes,
               coalesce(sum(m.cantidad * m.costo_unitario), 0) as costo_total,
               count(m.id) as num_salidas
        from vehiculos v
        left join movimientos m
          on m.vehiculo_id = v.id and m.tipo = 'salida' and m.empresa_id = v_empresa
        where v.empresa_id = v_empresa
        group by v.id
      ) c
    ), '[]'::jsonb),
    'tiposTrabajo', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', t.id, 'codigo', t.codigo, 'nombre', t.nombre,
        'precioManoObra', t.precio_mano_obra, 'activo', t.activo
      ) order by t.codigo)
      from tipos_trabajo t where t.empresa_id = v_empresa
    ), '[]'::jsonb),
    'trabajos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', t.id, 'mecanicoId', t.mecanico_id, 'vehiculoId', t.vehiculo_id,
        'tipoTrabajoId', t.tipo_trabajo_id, 'tipoNombre', tt.nombre,
        'descripcion', t.descripcion, 'precio', t.precio_snapshot,
        'estado', t.estado, 'fecha', t.fecha,
        'validadoPor', t.validado_por, 'notaAdmin', t.nota_admin,
        'creadaEn', t.creada_en,
        'piezas', coalesce((
          select jsonb_agg(jsonb_build_object('piezaId', tp.pieza_id, 'cantidad', tp.cantidad))
          from trabajo_piezas tp where tp.trabajo_id = t.id
        ), '[]'::jsonb)
      ) order by t.creada_en desc)
      from (select * from trabajos where empresa_id = v_empresa
            order by creada_en desc limit 300) t
      join tipos_trabajo tt on tt.id = t.tipo_trabajo_id
    ), '[]'::jsonb),
    'pagosMes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'mecanicoId', r.mecanico_id,
        'modoPago', r.modo_pago,
        'sueldoMonto', r.sueldo_monto,
        'validados', r.validados,
        'pendientes', r.pendientes,
        'rechazados', r.rechazados,
        'totalPagar', r.total_pagar
      ) order by r.total_pagar desc)
      from (
        select u.id as mecanico_id, u.modo_pago, u.sueldo_monto,
               count(t.id) filter (where t.estado = 'validada') as validados,
               count(t.id) filter (where t.estado = 'pendiente') as pendientes,
               count(t.id) filter (where t.estado = 'rechazada') as rechazados,
               case when u.modo_pago = 'sueldo'
                    then coalesce(u.sueldo_monto, 0)
                    else coalesce(sum(t.precio_snapshot) filter (where t.estado = 'validada'), 0)
               end as total_pagar
        from usuarios u
        left join trabajos t
          on t.mecanico_id = u.id and t.empresa_id = v_empresa and t.fecha >= v_mes
        where u.empresa_id = v_empresa and u.rol = 'mecanico'
        group by u.id, u.modo_pago, u.sueldo_monto
      ) r
    ), '[]'::jsonb),
    'lavados', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', l.id, 'vehiculoId', l.vehiculo_id, 'fecha', l.fecha,
        'activa', l.activa, 'marcadaEn', l.marcada_en,
        'marcadaPor', l.marcada_por, 'desmarcadaEn', l.desmarcada_en,
        'desmarcadaPor', l.desmarcada_por
      ) order by l.fecha desc, l.marcada_en desc)
      from (select * from lavados where empresa_id = v_empresa
            order by fecha desc, marcada_en desc limit 300) l
    ), '[]'::jsonb),
    'despachosCombustible', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', d.id, 'vehiculoId', d.vehiculo_id, 'despachadorId', d.despachador_id,
        'fecha', d.fecha, 'galones', d.galones, 'tipo', d.tipo_combustible,
        'odometro', d.odometro, 'costoUnitario', d.costo_galon,
        'total', d.total, 'creadaEn', d.creada_en
      ) order by d.creada_en desc)
      from (select * from despachos_combustible where empresa_id = v_empresa
            order by creada_en desc limit 300) d
    ), '[]'::jsonb),
    'tanque', pr__tanque_json(v_empresa),
    'recepcionesCombustible', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id, 'tipo', r.tipo_combustible, 'galones', r.galones,
        'costoUnitario', r.costo_galon, 'total', r.total,
        'proveedor', r.proveedor, 'nota', r.nota,
        'fecha', r.fecha, 'creadaEn', r.creada_en,
        'recibidoPor', r.recibido_por
      ) order by r.creada_en desc)
      from (select * from recepciones_combustible where empresa_id = v_empresa
            order by creada_en desc limit 100) r
    ), '[]'::jsonb),
    -- ===== Extensión solicitudes (este archivo) =====
    'solicitudesPiezas', coalesce((
      select jsonb_agg(pr__solicitud_json(x) order by x.creada_en desc)
      from (select * from solicitudes_piezas where empresa_id = v_empresa
            order by creada_en desc limit 300) x
    ), '[]'::jsonb)
  );
end;
$$;


-- === archivo: roles.sql ===
-- TallerNeto · Extensión: ROL ADICIONAL OPCIONAL por usuario.
-- Se aplica DESPUÉS de servidor/solicitudes.sql (es la última
-- extensión). NO modifica los archivos anteriores: todo es
-- idempotente (columna nueva + create or replace).
--
-- Pedido de Miguel: «el de almacén puede ser un mismo mecánico» —
-- una persona puede tener, además de su rol principal, UN rol
-- adicional opcional (ej.: mecánico que también atiende el almacén).
--
-- MODELO ELEGIDO (el más simple y seguro con los patrones pr_*):
--  - Columna `usuarios.rol_adicional` (nullable, mismo dominio de
--    roles de empresa: admin/almacen/mecanico/lavado/combustible;
--    nunca 'superadmin' y nunca igual al rol principal).
--  - TODAS las comprobaciones de rol del sistema pasan por el
--    candado central `pr_actor_con_rol`: basta ampliarlo para que
--    acepte al actor si el rol pedido está en su rol principal O
--    en el adicional. Ninguna función de negocio se toca.
--  - El login (pr_iniciar_sesion) devuelve también `rolAdicional`
--    y el snapshot lo incluye por usuario, para que panel y app
--    pinten los dos roles y ofrezcan las pantallas que tocan.
--  - Fijarlo/quitarlo es solo de administración:
--    pr_fijar_rol_adicional (como pr_fijar_modo_pago).
--
-- REGLA DE INTEGRIDAD NUEVA (necesaria justo por el rol doble):
-- nadie puede VALIDAR ni RECHAZAR su PROPIO trabajo. Un mecánico
-- que también es almacén valida los trabajos de los DEMÁS, nunca
-- los suyos: pr_validar_trabajo y pr_rechazar_trabajo se
-- reemplazan aquí con esa comprobación añadida (copia fiel de
-- trabajos.sql + el candado de autoría).

-- ============ COLUMNA Y CANDADOS DE DOMINIO ============
alter table usuarios add column if not exists rol_adicional text;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'usuarios_rol_adicional_check') then
    alter table usuarios add constraint usuarios_rol_adicional_check
      check (rol_adicional is null
             or rol_adicional in ('admin','almacen','mecanico','lavado','combustible'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'usuarios_rol_adicional_distinto') then
    alter table usuarios add constraint usuarios_rol_adicional_distinto
      check (rol_adicional is null or rol_adicional <> rol);
  end if;
end $$;

-- ============ EL CANDADO CENTRAL ACEPTA EL ROL ADICIONAL ============
-- Copia de esquema.sql con UNA línea ampliada: el actor pasa si el
-- rol pedido es su rol principal O su rol adicional.
create or replace function pr_actor_con_rol(p_empresa uuid, p_quien uuid, p_token text,
                                           p_roles text[])
returns usuarios language plpgsql security definer as $$
declare q usuarios;
begin
  q := pr_actor_empresa(p_empresa, p_quien, p_token);
  if q.rol = 'superadmin' then
    raise exception 'El administrador de TallerNeto no opera dentro de las empresas: entra como consulta';
  end if;
  -- OJO con el NULL: si rol_adicional es NULL, «NULL = any(...)»
  -- vale NULL y «false or NULL» también; sin el coalesce el IF no
  -- dispararía y pasaría cualquiera. Comparación segura:
  if not (q.rol = any (p_roles)
          or coalesce(q.rol_adicional, '') = any (p_roles)) then
    raise exception 'Tu rol (%) no puede hacer esta operación', q.rol;
  end if;
  return q;
end;
$$;

-- ============ FIJAR / QUITAR EL ROL ADICIONAL (solo admin) ============
create or replace function pr_fijar_rol_adicional(p_usuario uuid,
                                                  p_rol_adicional text default null,
                                                  p_quien uuid default null,
                                                  p_token text default null)
returns usuarios language plpgsql security definer as $$
declare
  u usuarios;
  q usuarios;
  v_rol text := nullif(trim(lower(coalesce(p_rol_adicional, ''))), '');
begin
  select * into u from usuarios where id = p_usuario;
  if u.id is null then raise exception 'Usuario no encontrado'; end if;
  if u.empresa_id is null then
    raise exception 'El dueño del sistema no lleva rol adicional';
  end if;
  q := pr_actor_con_rol(u.empresa_id, p_quien, p_token, array['admin']);
  if v_rol is not null then
    if v_rol not in ('admin','almacen','mecanico','lavado','combustible') then
      raise exception 'Rol adicional no válido: %', p_rol_adicional;
    end if;
    if v_rol = u.rol then
      raise exception 'El rol adicional no puede ser el mismo que el rol principal (%)', u.rol;
    end if;
  end if;
  update usuarios set rol_adicional = v_rol where id = u.id
  returning * into u;
  perform pr_registrar_accion(u.empresa_id, q.id, 'usuario_editado',
    format('Rol adicional de %s (%s): %s', u.codigo, u.nombre,
           coalesce(v_rol, 'ninguno')));
  return u;
end;
$$;

-- ============ LOGIN: devuelve también el rol adicional ============
-- (Copia fiel de pr_iniciar_sesion de esquema.sql generada por
-- script, con 'rolAdicional' añadido a los dos objetos `usuario`.)
create or replace function pr_iniciar_sesion(p_codigo text, p_pin text, p_contexto text default null)
returns jsonb language plpgsql security definer as $$
declare
  candidatos int := 0;
  u usuarios;
  e empresas;
  lic licencias;
  v_token text;
  v_expira timestamptz;
begin
  select count(*) into candidatos
  from usuarios x
  where x.activo and upper(x.codigo) = upper(trim(p_codigo))
    and pr_verificar_pin(p_pin, x.pin_hash);

  if candidatos = 0 then
    raise exception 'Código o PIN incorrecto';
  end if;
  if candidatos > 1 then
    raise exception 'Ese código existe en más de una empresa. Pide ayuda a TallerNeto para entrar.';
  end if;

  select * into u from usuarios x
  where x.activo and upper(x.codigo) = upper(trim(p_codigo))
    and pr_verificar_pin(p_pin, x.pin_hash);

  -- Superadmin (dueño del sistema): sin empresa ni licencia.
  if u.empresa_id is null then
    if p_contexto = 'panel' and u.rol <> 'superadmin' then
      raise exception 'Esta cuenta no entra por el panel de empresa';
    end if;
    v_token := pr_gen_token();
    v_expira := now() + interval '12 hours';
    insert into sesiones (usuario_id, empresa_id, contexto, token_hash, expira_en)
    values (u.id, null, p_contexto, pr_hash_token(v_token), v_expira);
    return jsonb_build_object(
      'usuario', jsonb_build_object('id', u.id, 'nombre', u.nombre, 'codigo', u.codigo, 'rol', u.rol, 'rolAdicional', u.rol_adicional),
      'empresa', null,
      'licencia', null,
      'sesion', jsonb_build_object('token', v_token, 'expiraEn', v_expira)
    );
  end if;

  select * into e from empresas where id = u.empresa_id;
  if e.id is null or not e.activa then
    raise exception 'Tu empresa está inactiva. Contacta a TallerNeto.';
  end if;

  select * into lic from licencias where empresa_id = e.id order by creada_en desc limit 1;
  if lic.id is null then
    raise exception 'Tu empresa todavía no tiene licencia. Contacta a TallerNeto.';
  end if;
  if lic.estado = 'suspendida' then
    raise exception 'La licencia de tu empresa está suspendida. Contacta a TallerNeto.';
  end if;
  if lic.estado = 'vencida' or (lic.vence is not null and lic.vence < pr_hoy()) then
    raise exception 'La licencia de tu empresa está vencida. Contacta a TallerNeto para renovarla.';
  end if;

  perform pr_registrar_accion(u.empresa_id, u.id, 'inicio_sesion',
    case p_contexto when 'panel' then 'Inició sesión por el panel'
                    else 'Inició sesión' end);

  v_token := pr_gen_token();
  v_expira := now() + interval '12 hours';
  insert into sesiones (usuario_id, empresa_id, contexto, token_hash, expira_en)
  values (u.id, u.empresa_id, p_contexto, pr_hash_token(v_token), v_expira);

  return jsonb_build_object(
    'usuario', jsonb_build_object('id', u.id, 'nombre', u.nombre, 'codigo', u.codigo, 'rol', u.rol, 'rolAdicional', u.rol_adicional),
    'empresa', jsonb_build_object('id', e.id, 'nombre', e.nombre),
    'licencia', jsonb_build_object(
      'estado', lic.estado,
      'vence', lic.vence,
      'maxVehiculos', lic.max_vehiculos,
      'diasRestantes', case when lic.vence is null then null else lic.vence - pr_hoy() end,
      'porVencer', case when lic.vence is null then false
                        else (lic.vence - pr_hoy()) between 0 and 30 end
    ),
    'sesion', jsonb_build_object('token', v_token, 'expiraEn', v_expira)
  );
end;
$$;

-- ============ VALIDAR: nadie valida su PROPIO trabajo ============
-- Copia fiel de trabajos.sql + el candado de autoría tras el
-- candado de rol/estado: el autor del trabajo no puede validarlo
-- aunque tenga rol de almacén o administración por su rol doble.
create or replace function pr_validar_trabajo(p_trabajo uuid,
                                              p_quien uuid default null,
                                              p_token text default null)
returns trabajos language plpgsql security definer as $$
declare
  tr trabajos;
  q usuarios;
  tp trabajo_piezas;
  pz piezas;
  t tipos_trabajo;
  v vehiculos;
  resultado trabajos;
begin
  select * into tr from trabajos where id = p_trabajo;
  if tr.id is null then raise exception 'Trabajo no encontrado'; end if;
  q := pr_actor_con_rol(tr.empresa_id, p_quien, p_token, array['admin','almacen']);
  if tr.estado <> 'pendiente' then
    raise exception 'Este trabajo ya fue %: no se puede validar de nuevo', tr.estado;
  end if;
  if tr.mecanico_id = q.id then
    raise exception 'No puedes validar tu propio trabajo: lo valida otra persona de administración o almacén';
  end if;

  select * into t from tipos_trabajo where id = tr.tipo_trabajo_id;
  select * into v from vehiculos where id = tr.vehiculo_id;

  -- Primero se revisa TODO el stock; si falta algo, la validación
  -- falla con error claro y no se mueve ni una pieza.
  for tp in select * from trabajo_piezas where trabajo_id = tr.id loop
    select * into pz from piezas where id = tp.pieza_id;
    if pz.stock < tp.cantidad then
      raise exception 'No se puede validar: stock insuficiente de % (%): quedan % y el trabajo usa %',
        pz.nombre, pz.codigo, pz.stock, tp.cantidad;
    end if;
  end loop;

  -- Stock bien: salen las piezas, amarradas al vehículo del trabajo.
  for tp in select * from trabajo_piezas where trabajo_id = tr.id loop
    perform pr__salida_por_trabajo(tr.empresa_id, tp.pieza_id, tp.cantidad,
      tr.vehiculo_id, tr.mecanico_id,
      format('Trabajo validado: %s en %s (%s)', t.nombre, v.codigo, v.placa));
  end loop;

  update trabajos
  set estado = 'validada', validado_por = q.id, validado_en = now()
  where id = tr.id
  returning * into resultado;

  perform pr_registrar_accion(tr.empresa_id, q.id, 'trabajo_validado',
    format('Validó el trabajo %s de %s en el vehículo %s: RD$%s a pagar',
           t.nombre, (select nombre from usuarios where id = tr.mecanico_id),
           v.codigo, tr.precio_snapshot));
  return resultado;
end;
$$;

-- ============ RECHAZAR: tampoco el propio trabajo ============
create or replace function pr_rechazar_trabajo(p_trabajo uuid, p_nota text default null,
                                               p_quien uuid default null,
                                               p_token text default null)
returns trabajos language plpgsql security definer as $$
declare
  tr trabajos;
  q usuarios;
  resultado trabajos;
begin
  select * into tr from trabajos where id = p_trabajo;
  if tr.id is null then raise exception 'Trabajo no encontrado'; end if;
  q := pr_actor_con_rol(tr.empresa_id, p_quien, p_token, array['admin','almacen']);
  if tr.estado <> 'pendiente' then
    raise exception 'Este trabajo ya fue %: no se puede rechazar', tr.estado;
  end if;
  if tr.mecanico_id = q.id then
    raise exception 'No puedes rechazar tu propio trabajo: lo resuelve otra persona de administración o almacén';
  end if;
  update trabajos
  set estado = 'rechazada', validado_por = q.id, validado_en = now(),
      nota_admin = nullif(trim(p_nota), '')
  where id = tr.id
  returning * into resultado;
  perform pr_registrar_accion(tr.empresa_id, q.id, 'trabajo_rechazado',
    format('Rechazó un trabajo de %s (%s)',
           (select nombre from usuarios where id = tr.mecanico_id),
           coalesce(nullif(trim(p_nota), ''), 'sin nota')));
  return resultado;
end;
$$;

-- ============ SNAPSHOT: cada usuario trae su rol adicional ============
-- (Copia fiel del pr_snapshot vigente — el de solicitudes.sql —
-- generada por script, con 'rolAdicional' en el bloque `usuarios`.)
create or replace function pr_snapshot(p_empresa uuid default null,
                                       p_quien uuid default null,
                                       p_token text default null)
returns jsonb language plpgsql security definer as $$
declare
  q usuarios;
  e empresas;
  lic licencias;
  v_empresa uuid;
  v_mes date := date_trunc('month', pr_hoy())::date;
begin
  q := pr_actor_empresa(p_empresa, p_quien, p_token);
  v_empresa := coalesce(p_empresa, q.empresa_id);
  if v_empresa is null then
    raise exception 'Indica qué empresa quieres ver';
  end if;
  if q.rol <> 'superadmin' and v_empresa is distinct from q.empresa_id then
    raise exception 'No tienes permiso para ver esta empresa';
  end if;

  select * into e from empresas where id = v_empresa;
  if e.id is null then raise exception 'Empresa no encontrada'; end if;
  select * into lic from licencias where empresa_id = v_empresa order by creada_en desc limit 1;

  return jsonb_build_object(
    'empresa', jsonb_build_object(
      'id', e.id, 'nombre', e.nombre, 'activa', e.activa,
      'lavadoActivo', e.lavado_activo,
      'combustibleActivo', e.combustible_activo),
    'licencia', case when lic.id is null then null else jsonb_build_object(
      'estado', lic.estado, 'vence', lic.vence, 'maxVehiculos', lic.max_vehiculos,
      'diasRestantes', case when lic.vence is null then null else lic.vence - pr_hoy() end,
      'porVencer', case when lic.vence is null then false
                        else (lic.vence - pr_hoy()) between 0 and 30 end
    ) end,
    'usuarios', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', u.id, 'rol', u.rol, 'rolAdicional', u.rol_adicional, 'nombre', u.nombre, 'codigo', u.codigo, 'activo', u.activo,
        'modoPago', u.modo_pago, 'sueldoMonto', u.sueldo_monto
      ) order by u.codigo)
      from usuarios u where u.empresa_id = v_empresa
    ), '[]'::jsonb),
    'vehiculos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', v.id, 'codigo', v.codigo, 'placa', v.placa, 'marca', v.marca,
        'modelo', v.modelo, 'anio', v.anio, 'estado', v.estado, 'activo', v.activo
      ) order by v.codigo)
      from vehiculos v where v.empresa_id = v_empresa
    ), '[]'::jsonb),
    'piezas', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id, 'codigo', p.codigo, 'nombre', p.nombre, 'ubicacion', p.ubicacion,
        'costo', p.costo, 'stock', p.stock, 'stockMinimo', p.stock_minimo, 'activa', p.activa
      ) order by p.codigo)
      from piezas p where p.empresa_id = v_empresa
    ), '[]'::jsonb),
    'movimientos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', m.id, 'tipo', m.tipo, 'piezaId', m.pieza_id, 'cantidad', m.cantidad,
        'costoUnitario', m.costo_unitario, 'vehiculoId', m.vehiculo_id,
        'usuarioId', m.usuario_id, 'nota', m.nota, 'fecha', m.fecha,
        'creadaEn', m.creada_en
      ) order by m.creada_en desc)
      from (select * from movimientos where empresa_id = v_empresa
            order by creada_en desc limit 300) m
    ), '[]'::jsonb),
    'herramientas', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', h.id, 'codigo', h.codigo, 'nombre', h.nombre, 'estado', h.estado, 'activa', h.activa
      ) order by h.codigo)
      from herramientas h where h.empresa_id = v_empresa
    ), '[]'::jsonb),
    'prestamos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', pr.id, 'herramientaId', pr.herramienta_id, 'responsableId', pr.responsable_id,
        'fechaSalida', pr.fecha_salida, 'fechaDevolucion', pr.fecha_devolucion
      ) order by pr.fecha_salida desc)
      from (select * from prestamos where empresa_id = v_empresa
            order by fecha_salida desc limit 200) pr
    ), '[]'::jsonb),
    'costos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'vehiculoId', c.vehiculo_id,
        'costoMes', c.costo_mes,
        'costoTotal', c.costo_total,
        'numSalidas', c.num_salidas
      ))
      from (
        select v.id as vehiculo_id,
               coalesce(sum(case when m.fecha >= v_mes
                                 then m.cantidad * m.costo_unitario end), 0) as costo_mes,
               coalesce(sum(m.cantidad * m.costo_unitario), 0) as costo_total,
               count(m.id) as num_salidas
        from vehiculos v
        left join movimientos m
          on m.vehiculo_id = v.id and m.tipo = 'salida' and m.empresa_id = v_empresa
        where v.empresa_id = v_empresa
        group by v.id
      ) c
    ), '[]'::jsonb),
    'tiposTrabajo', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', t.id, 'codigo', t.codigo, 'nombre', t.nombre,
        'precioManoObra', t.precio_mano_obra, 'activo', t.activo
      ) order by t.codigo)
      from tipos_trabajo t where t.empresa_id = v_empresa
    ), '[]'::jsonb),
    'trabajos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', t.id, 'mecanicoId', t.mecanico_id, 'vehiculoId', t.vehiculo_id,
        'tipoTrabajoId', t.tipo_trabajo_id, 'tipoNombre', tt.nombre,
        'descripcion', t.descripcion, 'precio', t.precio_snapshot,
        'estado', t.estado, 'fecha', t.fecha,
        'validadoPor', t.validado_por, 'notaAdmin', t.nota_admin,
        'creadaEn', t.creada_en,
        'piezas', coalesce((
          select jsonb_agg(jsonb_build_object('piezaId', tp.pieza_id, 'cantidad', tp.cantidad))
          from trabajo_piezas tp where tp.trabajo_id = t.id
        ), '[]'::jsonb)
      ) order by t.creada_en desc)
      from (select * from trabajos where empresa_id = v_empresa
            order by creada_en desc limit 300) t
      join tipos_trabajo tt on tt.id = t.tipo_trabajo_id
    ), '[]'::jsonb),
    'pagosMes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'mecanicoId', r.mecanico_id,
        'modoPago', r.modo_pago,
        'sueldoMonto', r.sueldo_monto,
        'validados', r.validados,
        'pendientes', r.pendientes,
        'rechazados', r.rechazados,
        'totalPagar', r.total_pagar
      ) order by r.total_pagar desc)
      from (
        select u.id as mecanico_id, u.modo_pago, u.sueldo_monto,
               count(t.id) filter (where t.estado = 'validada') as validados,
               count(t.id) filter (where t.estado = 'pendiente') as pendientes,
               count(t.id) filter (where t.estado = 'rechazada') as rechazados,
               case when u.modo_pago = 'sueldo'
                    then coalesce(u.sueldo_monto, 0)
                    else coalesce(sum(t.precio_snapshot) filter (where t.estado = 'validada'), 0)
               end as total_pagar
        from usuarios u
        left join trabajos t
          on t.mecanico_id = u.id and t.empresa_id = v_empresa and t.fecha >= v_mes
        where u.empresa_id = v_empresa and u.rol = 'mecanico'
        group by u.id, u.modo_pago, u.sueldo_monto
      ) r
    ), '[]'::jsonb),
    'lavados', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', l.id, 'vehiculoId', l.vehiculo_id, 'fecha', l.fecha,
        'activa', l.activa, 'marcadaEn', l.marcada_en,
        'marcadaPor', l.marcada_por, 'desmarcadaEn', l.desmarcada_en,
        'desmarcadaPor', l.desmarcada_por
      ) order by l.fecha desc, l.marcada_en desc)
      from (select * from lavados where empresa_id = v_empresa
            order by fecha desc, marcada_en desc limit 300) l
    ), '[]'::jsonb),
    'despachosCombustible', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', d.id, 'vehiculoId', d.vehiculo_id, 'despachadorId', d.despachador_id,
        'fecha', d.fecha, 'galones', d.galones, 'tipo', d.tipo_combustible,
        'odometro', d.odometro, 'costoUnitario', d.costo_galon,
        'total', d.total, 'creadaEn', d.creada_en
      ) order by d.creada_en desc)
      from (select * from despachos_combustible where empresa_id = v_empresa
            order by creada_en desc limit 300) d
    ), '[]'::jsonb),
    'tanque', pr__tanque_json(v_empresa),
    'recepcionesCombustible', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id, 'tipo', r.tipo_combustible, 'galones', r.galones,
        'costoUnitario', r.costo_galon, 'total', r.total,
        'proveedor', r.proveedor, 'nota', r.nota,
        'fecha', r.fecha, 'creadaEn', r.creada_en,
        'recibidoPor', r.recibido_por
      ) order by r.creada_en desc)
      from (select * from recepciones_combustible where empresa_id = v_empresa
            order by creada_en desc limit 100) r
    ), '[]'::jsonb),
    -- ===== Extensión solicitudes (este archivo) =====
    'solicitudesPiezas', coalesce((
      select jsonb_agg(pr__solicitud_json(x) order by x.creada_en desc)
      from (select * from solicitudes_piezas where empresa_id = v_empresa
            order by creada_en desc limit 300) x
    ), '[]'::jsonb)
  );
end;
$$;


-- === archivo: config-ampliada.sql ===
-- ================================================================
-- TallerNeto · CONFIGURACIÓN AMPLIADA por empresa (extensión).
-- Se aplica DESPUÉS de roles.sql (es el último archivo del orden).
--
-- Tres pedidos de Miguel (2026-11-21):
--  1. TIPOS DE COMBUSTIBLE ACTIVABLES por empresa: no todas las
--     compañías trabajan con diésel, gasolina y GLP. Interruptores
--     por tipo en los ajustes del panel; un tipo apagado no sale
--     en la app (selectores, tarjetas de tanque ni formularios) y
--     el SERVIDOR rechaza despachos/recepciones de ese tipo.
--  2. PRECIOS OPCIONALES en la app (`empresas.precios_en_app`):
--     muchas veces los precios los maneja administración y el
--     despachador ni se entera. Apagado: la app no muestra campos
--     de costo y el servidor usa el PRECIO VIGENTE por tipo que
--     administración fija en el panel. Encendido: como siempre
--     (el despachador escribe el costo de cada registro).
--  3. MODO TUTORIAL activable por empresa
--     (`empresas.tutorial_activo`, nace encendido): el panel
--     ofrece el recorrido guiado a cada usuario; administración
--     lo apaga desde sus ajustes y ya no se ofrece.
--
-- La configuración de tipos vive en su propia tabla
-- `combustible_config` (empresa × tipo): activo + precio vigente.
-- Sin fila para un tipo valen los defaults históricos: ACTIVO y
-- precio 250/290/145 (los sugeridos de siempre) — las empresas
-- que ya operan no notan cambio alguno hasta que administración
-- toque los ajustes.
-- ================================================================

-- ---------- Interruptores simples en la empresa ----------
alter table empresas
  add column if not exists precios_en_app boolean not null default true;
alter table empresas
  add column if not exists tutorial_activo boolean not null default true;

-- ---------- Configuración por tipo de combustible ----------
create table if not exists combustible_config (
  empresa_id uuid not null references empresas(id) on delete cascade,
  tipo_combustible text not null
    check (tipo_combustible in ('diesel','gasolina','glp')),
  activo boolean not null default true,
  -- Precio vigente por galón (RD$) que fija administración: se
  -- usa en los despachos/recepciones cuando la empresa apaga los
  -- precios en la app. NULL = el default del tipo.
  precio_vigente numeric(10,2)
    check (precio_vigente is null or precio_vigente >= 0),
  primary key (empresa_id, tipo_combustible)
);
alter table combustible_config enable row level security;

-- ---------- Ayudantes de lectura (con defaults) ----------

-- ¿La empresa trabaja con este tipo de combustible?
create or replace function pr__tipo_combustible_activo(p_empresa uuid, p_tipo text)
returns boolean language sql stable security definer as $$
  select coalesce(
    (select activo from combustible_config
     where empresa_id = p_empresa and tipo_combustible = p_tipo),
    true);
$$;

-- ¿El despachador ve y escribe precios en la app?
create or replace function pr__precios_en_app(p_empresa uuid)
returns boolean language sql stable security definer as $$
  select coalesce(
    (select precios_en_app from empresas where id = p_empresa), true);
$$;

-- Precio vigente de un tipo: el de administración o el default.
create or replace function pr__precio_vigente(p_empresa uuid, p_tipo text)
returns numeric language sql stable security definer as $$
  select coalesce(
    (select precio_vigente from combustible_config
     where empresa_id = p_empresa and tipo_combustible = p_tipo),
    case p_tipo when 'diesel' then 250 when 'gasolina' then 290 else 145 end
  );
$$;

-- Tipos ACTIVOS de la empresa con su precio (para la app: la
-- lista de tipos que el despachador puede elegir, con el precio
-- precargado). Reemplaza en los datos de la app a la lista fija
-- de pr__precios_combustible() sin argumentos, que se conserva.
create or replace function pr__precios_combustible(p_empresa uuid)
returns jsonb language sql stable security definer as $$
  select coalesce(jsonb_agg(s.x order by s.orden), '[]'::jsonb)
  from (
    select jsonb_build_object(
             'tipo', t.tipo,
             'precioSugerido', pr__precio_vigente(p_empresa, t.tipo)) as x,
           t.orden
    from (values ('diesel', 1), ('gasolina', 2), ('glp', 3)) as t(tipo, orden)
    where pr__tipo_combustible_activo(p_empresa, t.tipo)
  ) s;
$$;

-- ================================================================
-- CONFIGURAR COMBUSTIBLE AMPLIADO (solo administración):
-- interruptores por tipo + precios en la app + precio vigente
-- por tipo, todo en una sola llamada (el formulario de ajustes
-- del panel guarda junto). Un precio NULL deja el vigente que
-- hubiera (o el default); para volver al default no hay botón:
-- el precio vigente ES el número que administración escriba.
-- ================================================================
create or replace function pr_configurar_combustible_ampliado(
    p_empresa uuid,
    p_diesel_activo boolean, p_gasolina_activo boolean, p_glp_activo boolean,
    p_precios_en_app boolean,
    p_precio_diesel numeric, p_precio_gasolina numeric, p_precio_glp numeric,
    p_quien uuid default null, p_token text default null)
returns void language plpgsql security definer as $$
declare
  q usuarios;
begin
  perform pr__exigir_combustible_activo(p_empresa);
  q := pr_actor_con_rol(p_empresa, p_quien, p_token, array['admin']);
  if p_precio_diesel is not null and p_precio_diesel < 0 then
    raise exception 'El precio vigente del diésel no puede ser negativo';
  end if;
  if p_precio_gasolina is not null and p_precio_gasolina < 0 then
    raise exception 'El precio vigente de la gasolina no puede ser negativo';
  end if;
  if p_precio_glp is not null and p_precio_glp < 0 then
    raise exception 'El precio vigente del GLP no puede ser negativo';
  end if;
  insert into combustible_config (empresa_id, tipo_combustible, activo, precio_vigente)
  values
    (p_empresa, 'diesel',   coalesce(p_diesel_activo, true),   p_precio_diesel),
    (p_empresa, 'gasolina', coalesce(p_gasolina_activo, true), p_precio_gasolina),
    (p_empresa, 'glp',      coalesce(p_glp_activo, true),      p_precio_glp)
  on conflict (empresa_id, tipo_combustible)
  do update set activo = excluded.activo,
                precio_vigente = coalesce(excluded.precio_vigente,
                                          combustible_config.precio_vigente);
  update empresas set precios_en_app = coalesce(p_precios_en_app, true)
  where id = p_empresa;
  perform pr_registrar_accion(p_empresa, q.id, 'configurar_combustible',
    format('Ajustes de combustible: diésel %s, gasolina %s, GLP %s; precios en la app %s',
           case when coalesce(p_diesel_activo, true) then 'activo' else 'apagado' end,
           case when coalesce(p_gasolina_activo, true) then 'activo' else 'apagado' end,
           case when coalesce(p_glp_activo, true) then 'activo' else 'apagado' end,
           case when coalesce(p_precios_en_app, true) then 'visibles' else 'ocultos' end));
end;
$$;

-- ================================================================
-- MODO TUTORIAL por empresa (solo administración lo enciende o
-- apaga; nace encendido). El panel lo lee del snapshot y ofrece
-- el recorrido guiado solo si está activo.
-- ================================================================
create or replace function pr_configurar_tutorial(
    p_empresa uuid, p_activo boolean,
    p_quien uuid default null, p_token text default null)
returns void language plpgsql security definer as $$
declare
  q usuarios;
begin
  q := pr_actor_con_rol(p_empresa, p_quien, p_token, array['admin']);
  update empresas set tutorial_activo = coalesce(p_activo, true)
  where id = p_empresa;
  perform pr_registrar_accion(p_empresa, q.id, 'configurar_tutorial',
    format('Modo tutorial %s',
           case when coalesce(p_activo, true) then 'activado' else 'desactivado' end));
end;
$$;

-- ================================================================
-- TANQUE (versión filtrada): el bloque `tanque` solo trae los
-- tipos ACTIVOS de la empresa — un tipo apagado no aparece ni
-- en el panel ni en la app. Copia de tanque.sql + el filtro.
-- ================================================================
create or replace function pr__tanque_json(p_empresa uuid) returns jsonb
language plpgsql stable security definer as $$
declare
  v_hoy date := pr_hoy();
  v_tipos text[] := array['diesel','gasolina','glp'];
  v_tipo text;
  v_saldo numeric;
  v_umbral numeric;
  v_capacidad numeric;
  v_consumo numeric;
  v_resultado jsonb := '[]'::jsonb;
begin
  foreach v_tipo in array v_tipos loop
    -- Configuración ampliada: los tipos apagados no existen
    -- para la empresa (ni tarjeta, ni selector, ni formulario).
    if not pr__tipo_combustible_activo(p_empresa, v_tipo) then
      continue;
    end if;
    v_saldo := pr__saldo_tanque(p_empresa, v_tipo);
    v_umbral := pr__umbral_tanque(p_empresa, v_tipo);
    v_capacidad := pr__capacidad_tanque(p_empresa, v_tipo);
    v_consumo := coalesce((
      select sum(galones) from despachos_combustible
      where empresa_id = p_empresa and tipo_combustible = v_tipo
        and fecha >= v_hoy - 13 and fecha <= v_hoy
    ), 0) / 14.0;
    v_resultado := v_resultado || jsonb_build_object(
      'tipo', v_tipo,
      'saldo', v_saldo,
      'umbral', v_umbral,
      'capacidad', v_capacidad,
      'configurado', exists (
        select 1 from tanque_umbrales
        where empresa_id = p_empresa and tipo_combustible = v_tipo),
      'porcentaje', case when v_capacidad is not null and v_capacidad > 0
                         then round(v_saldo / v_capacidad * 100, 1) end,
      'alerta', v_saldo <= v_umbral,
      'consumoPromedioDiario', round(v_consumo, 2),
      'diasEstimados', case when v_consumo > 0
                            then round(v_saldo / v_consumo, 1) end,
      'ultimasRecepciones', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', r.id, 'galones', r.galones, 'tipo', r.tipo_combustible,
          'costoUnitario', r.costo_galon, 'total', r.total,
          'proveedor', r.proveedor, 'nota', r.nota,
          'fecha', r.fecha, 'creadaEn', r.creada_en,
          'recibidoPor', r.recibido_por,
          'recibidoPorNombre', (select nombre from usuarios where id = r.recibido_por)
        ) order by r.creada_en desc)
        from (select * from recepciones_combustible
              where empresa_id = p_empresa and tipo_combustible = v_tipo
              order by creada_en desc limit 5) r
      ), '[]'::jsonb)
    );
  end loop;
  return v_resultado;
end;
$$;

-- ================================================================
-- REGISTRAR RECEPCIÓN — copia de tanque.sql + dos reglas nuevas:
-- el tipo debe estar ACTIVO en la empresa, y si los precios en
-- la app están apagados el costo lo pone el precio vigente de
-- administración (se ignora el que mande la app).
-- ================================================================
create or replace function pr_registrar_recepcion(p_empresa uuid, p_tipo text,
                                                  p_galones numeric, p_costo_galon numeric,
                                                  p_proveedor text default null,
                                                  p_nota text default null,
                                                  p_quien uuid default null,
                                                  p_token text default null)
returns recepciones_combustible language plpgsql security definer as $$
declare
  q usuarios;
  r recepciones_combustible;
  v_capacidad numeric;
  v_saldo numeric;
begin
  perform pr__exigir_combustible_activo(p_empresa);
  q := pr_actor_con_rol(p_empresa, p_quien, p_token, array['combustible','admin']);
  if p_tipo not in ('diesel','gasolina','glp') then
    raise exception 'Tipo de combustible no válido: % (usa diesel, gasolina o glp)', p_tipo;
  end if;
  if not pr__tipo_combustible_activo(p_empresa, p_tipo) then
    raise exception 'El combustible % no está activo en esta empresa: actívalo en los ajustes del panel',
      pr__tipo_combustible_etiqueta(p_tipo);
  end if;
  if p_galones is null or p_galones <= 0 then
    raise exception 'La cantidad de galones recibida debe ser mayor que cero';
  end if;
  -- Precios opcionales: apagados en la app, manda el vigente.
  if not pr__precios_en_app(p_empresa) then
    p_costo_galon := pr__precio_vigente(p_empresa, p_tipo);
  end if;
  if p_costo_galon is null or p_costo_galon < 0 then
    raise exception 'El costo por galón no puede ser negativo';
  end if;
  -- Regla física: a un tanque no le cabe más de su capacidad (solo
  -- si está configurada; sin capacidad fijada no hay límite).
  v_capacidad := pr__capacidad_tanque(p_empresa, p_tipo);
  if v_capacidad is not null then
    v_saldo := pr__saldo_tanque(p_empresa, p_tipo);
    if v_saldo + p_galones > v_capacidad then
      raise exception 'El tanque de % es de % gal y tiene %: no caben % más',
        pr__tipo_combustible_etiqueta(p_tipo), trim_scale(v_capacidad),
        trim_scale(v_saldo), trim_scale(p_galones);
    end if;
  end if;
  insert into recepciones_combustible
    (empresa_id, recibido_por, fecha, galones, tipo_combustible,
     costo_galon, total, proveedor, nota)
  values
    (p_empresa, q.id, pr_hoy(), p_galones, p_tipo,
     p_costo_galon, round(p_galones * p_costo_galon, 2),
     nullif(trim(coalesce(p_proveedor, '')), ''),
     nullif(trim(coalesce(p_nota, '')), ''))
  returning * into r;
  perform pr_registrar_accion(p_empresa, q.id, 'recepcion_combustible',
    format('Recibió %s galones de %s en el tanque (saldo: %s gal)',
           trim_scale(p_galones), pr__tipo_combustible_etiqueta(p_tipo),
           trim_scale(pr__saldo_tanque(p_empresa, p_tipo))));
  return r;
end;
$$;

-- ================================================================
-- REGISTRAR DESPACHO — copia de tanque.sql + las mismas dos
-- reglas nuevas (tipo activo; precio vigente si la app no
-- maneja precios).
-- ================================================================
create or replace function pr_registrar_despacho(p_empresa uuid, p_vehiculo uuid,
                                                 p_galones numeric, p_tipo text,
                                                 p_odometro numeric, p_costo_galon numeric,
                                                 p_quien uuid default null,
                                                 p_token text default null)
returns despachos_combustible language plpgsql security definer as $$
declare
  q usuarios;
  v vehiculos;
  d despachos_combustible;
  v_ultimo numeric;
  v_saldo numeric;
begin
  perform pr__exigir_combustible_activo(p_empresa);
  q := pr_actor_con_rol(p_empresa, p_quien, p_token, array['combustible','admin']);
  if p_vehiculo is null then
    raise exception 'Todo despacho debe decir el vehículo';
  end if;
  select * into v from vehiculos where id = p_vehiculo and empresa_id = p_empresa;
  if v.id is null then raise exception 'Vehículo no encontrado en esta empresa'; end if;
  if not v.activo then raise exception 'El vehículo % está inactivo', v.codigo; end if;
  if p_galones is null or p_galones <= 0 then
    raise exception 'La cantidad de galones debe ser mayor que cero';
  end if;
  if p_tipo not in ('diesel','gasolina','glp') then
    raise exception 'Tipo de combustible no válido: % (usa diesel, gasolina o glp)', p_tipo;
  end if;
  if not pr__tipo_combustible_activo(p_empresa, p_tipo) then
    raise exception 'El combustible % no está activo en esta empresa: actívalo en los ajustes del panel',
      pr__tipo_combustible_etiqueta(p_tipo);
  end if;
  if p_odometro is null or p_odometro < 0 then
    raise exception 'El odómetro es obligatorio y no puede ser negativo';
  end if;
  -- Precios opcionales: apagados en la app, manda el vigente.
  if not pr__precios_en_app(p_empresa) then
    p_costo_galon := pr__precio_vigente(p_empresa, p_tipo);
  end if;
  if p_costo_galon is null or p_costo_galon < 0 then
    raise exception 'El costo por galón no puede ser negativo';
  end if;
  -- Regla de integridad: el odómetro nunca baja.
  v_ultimo := pr__ultimo_odometro(p_empresa, v.id);
  if v_ultimo is not null and p_odometro < v_ultimo then
    raise exception 'El odómetro (%) es menor que el último registrado (%) para el vehículo %: revísalo',
      p_odometro, v_ultimo, v.codigo;
  end if;
  -- Regla del tanque: no se despacha lo que el tanque no tiene.
  v_saldo := pr__saldo_tanque(p_empresa, p_tipo);
  if v_saldo < p_galones then
    raise exception 'Tanque de % sin suficiente combustible: quedan % gal',
      pr__tipo_combustible_etiqueta(p_tipo), trim_scale(v_saldo);
  end if;
  insert into despachos_combustible
    (empresa_id, vehiculo_id, despachador_id, fecha, galones,
     tipo_combustible, odometro, costo_galon, total)
  values
    (p_empresa, v.id, q.id, pr_hoy(), p_galones,
     p_tipo, p_odometro, p_costo_galon, round(p_galones * p_costo_galon, 2))
  returning * into d;
  perform pr_registrar_accion(p_empresa, q.id, 'despacho_combustible',
    format('Despachó %s galones de %s al vehículo %s (odómetro %s, total %s)',
           p_galones, p_tipo, v.codigo, p_odometro, d.total));
  return d;
end;
$$;

-- ================================================================
-- DATOS DE COMBUSTIBLE (app) — copia de tanque.sql + la
-- configuración ampliada: la empresa trae `preciosEnApp` y
-- `tutorialActivo`, y `tipos`/`tanque` solo traen los tipos
-- ACTIVOS (con el precio vigente precargado).
-- ================================================================
create or replace function pr_datos_combustible(p_quien uuid default null,
                                                p_token text default null)
returns jsonb language plpgsql security definer as $$
declare
  u usuarios;
  q usuarios;
  e empresas;
  v_hoy date := pr_hoy();
begin
  select * into u from usuarios where id = p_quien and activo;
  if u.id is null then raise exception 'Usuario no válido'; end if;
  if u.empresa_id is null then
    raise exception 'Esta cuenta no es de una empresa';
  end if;
  q := pr_actor_con_rol(u.empresa_id, p_quien, p_token, array['combustible','admin']);
  perform pr__exigir_combustible_activo(q.empresa_id);
  select * into e from empresas where id = q.empresa_id;

  return jsonb_build_object(
    'usuario', jsonb_build_object(
      'id', q.id, 'nombre', q.nombre, 'codigo', q.codigo, 'rol', q.rol),
    'empresa', jsonb_build_object(
      'id', e.id, 'nombre', e.nombre, 'combustibleActivo', e.combustible_activo,
      'preciosEnApp', e.precios_en_app,
      'tutorialActivo', e.tutorial_activo),
    'fecha', v_hoy,
    'unidad', 'km/gal',
    'tipos', pr__precios_combustible(q.empresa_id),
    'tanque', pr__tanque_json(q.empresa_id),
    'vehiculos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', v.id, 'codigo', v.codigo, 'placa', v.placa, 'marca', v.marca,
        'modelo', v.modelo, 'anio', v.anio, 'estado', v.estado, 'activo', v.activo,
        'ultimoOdometro', pr__ultimo_odometro(q.empresa_id, v.id)
      ) order by v.codigo)
      from vehiculos v
      where v.empresa_id = q.empresa_id and v.activo
    ), '[]'::jsonb),
    'despachosHoy', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', d.id, 'vehiculoId', d.vehiculo_id,
        'vehiculoCodigo', v.codigo, 'vehiculoPlaca', v.placa,
        'galones', d.galones, 'tipo', d.tipo_combustible,
        'odometro', d.odometro, 'costoUnitario', d.costo_galon,
        'total', d.total, 'creadaEn', d.creada_en,
        'despachadorId', d.despachador_id,
        'despachadorNombre', (select nombre from usuarios where id = d.despachador_id)
      ) order by d.creada_en desc)
      from despachos_combustible d
      join vehiculos v on v.id = d.vehiculo_id
      where d.empresa_id = q.empresa_id and d.fecha = v_hoy
    ), '[]'::jsonb),
    'totalGalonesHoy', coalesce((
      select sum(galones) from despachos_combustible
      where empresa_id = q.empresa_id and fecha = v_hoy
    ), 0),
    'totalCostoHoy', coalesce((
      select sum(total) from despachos_combustible
      where empresa_id = q.empresa_id and fecha = v_hoy
    ), 0)
  );
end;
$$;

-- ================================================================
-- SNAPSHOT (panel) — copia fiel del de roles.sql + la
-- configuración ampliada: la empresa trae `preciosEnApp` y
-- `tutorialActivo`, y el bloque `configCombustible` trae por
-- tipo su interruptor y su precio vigente (sin filas, el panel
-- usa los defaults: todo activo, precios 250/290/145).
-- ================================================================
create or replace function pr_snapshot(p_empresa uuid default null,
                                       p_quien uuid default null,
                                       p_token text default null)
returns jsonb language plpgsql security definer as $$
declare
  q usuarios;
  e empresas;
  lic licencias;
  v_empresa uuid;
  v_mes date := date_trunc('month', pr_hoy())::date;
begin
  q := pr_actor_empresa(p_empresa, p_quien, p_token);
  v_empresa := coalesce(p_empresa, q.empresa_id);
  if v_empresa is null then
    raise exception 'Indica qué empresa quieres ver';
  end if;
  if q.rol <> 'superadmin' and v_empresa is distinct from q.empresa_id then
    raise exception 'No tienes permiso para ver esta empresa';
  end if;

  select * into e from empresas where id = v_empresa;
  if e.id is null then raise exception 'Empresa no encontrada'; end if;
  select * into lic from licencias where empresa_id = v_empresa order by creada_en desc limit 1;

  return jsonb_build_object(
    'empresa', jsonb_build_object(
      'id', e.id, 'nombre', e.nombre, 'activa', e.activa,
      'lavadoActivo', e.lavado_activo,
      'combustibleActivo', e.combustible_activo,
      'preciosEnApp', e.precios_en_app,
      'tutorialActivo', e.tutorial_activo),
    'configCombustible', coalesce((
      select jsonb_agg(jsonb_build_object(
        'tipo', c.tipo_combustible, 'activo', c.activo,
        'precioVigente', c.precio_vigente
      ) order by c.tipo_combustible)
      from combustible_config c where c.empresa_id = v_empresa
    ), '[]'::jsonb),
    'licencia', case when lic.id is null then null else jsonb_build_object(
      'estado', lic.estado, 'vence', lic.vence, 'maxVehiculos', lic.max_vehiculos,
      'diasRestantes', case when lic.vence is null then null else lic.vence - pr_hoy() end,
      'porVencer', case when lic.vence is null then false
                        else (lic.vence - pr_hoy()) between 0 and 30 end
    ) end,
    'usuarios', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', u.id, 'rol', u.rol, 'rolAdicional', u.rol_adicional, 'nombre', u.nombre, 'codigo', u.codigo, 'activo', u.activo,
        'modoPago', u.modo_pago, 'sueldoMonto', u.sueldo_monto
      ) order by u.codigo)
      from usuarios u where u.empresa_id = v_empresa
    ), '[]'::jsonb),
    'vehiculos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', v.id, 'codigo', v.codigo, 'placa', v.placa, 'marca', v.marca,
        'modelo', v.modelo, 'anio', v.anio, 'estado', v.estado, 'activo', v.activo
      ) order by v.codigo)
      from vehiculos v where v.empresa_id = v_empresa
    ), '[]'::jsonb),
    'piezas', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id, 'codigo', p.codigo, 'nombre', p.nombre, 'ubicacion', p.ubicacion,
        'costo', p.costo, 'stock', p.stock, 'stockMinimo', p.stock_minimo, 'activa', p.activa
      ) order by p.codigo)
      from piezas p where p.empresa_id = v_empresa
    ), '[]'::jsonb),
    'movimientos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', m.id, 'tipo', m.tipo, 'piezaId', m.pieza_id, 'cantidad', m.cantidad,
        'costoUnitario', m.costo_unitario, 'vehiculoId', m.vehiculo_id,
        'usuarioId', m.usuario_id, 'nota', m.nota, 'fecha', m.fecha,
        'creadaEn', m.creada_en
      ) order by m.creada_en desc)
      from (select * from movimientos where empresa_id = v_empresa
            order by creada_en desc limit 300) m
    ), '[]'::jsonb),
    'herramientas', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', h.id, 'codigo', h.codigo, 'nombre', h.nombre, 'estado', h.estado, 'activa', h.activa
      ) order by h.codigo)
      from herramientas h where h.empresa_id = v_empresa
    ), '[]'::jsonb),
    'prestamos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', pr.id, 'herramientaId', pr.herramienta_id, 'responsableId', pr.responsable_id,
        'fechaSalida', pr.fecha_salida, 'fechaDevolucion', pr.fecha_devolucion
      ) order by pr.fecha_salida desc)
      from (select * from prestamos where empresa_id = v_empresa
            order by fecha_salida desc limit 200) pr
    ), '[]'::jsonb),
    'costos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'vehiculoId', c.vehiculo_id,
        'costoMes', c.costo_mes,
        'costoTotal', c.costo_total,
        'numSalidas', c.num_salidas
      ))
      from (
        select v.id as vehiculo_id,
               coalesce(sum(case when m.fecha >= v_mes
                                 then m.cantidad * m.costo_unitario end), 0) as costo_mes,
               coalesce(sum(m.cantidad * m.costo_unitario), 0) as costo_total,
               count(m.id) as num_salidas
        from vehiculos v
        left join movimientos m
          on m.vehiculo_id = v.id and m.tipo = 'salida' and m.empresa_id = v_empresa
        where v.empresa_id = v_empresa
        group by v.id
      ) c
    ), '[]'::jsonb),
    'tiposTrabajo', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', t.id, 'codigo', t.codigo, 'nombre', t.nombre,
        'precioManoObra', t.precio_mano_obra, 'activo', t.activo
      ) order by t.codigo)
      from tipos_trabajo t where t.empresa_id = v_empresa
    ), '[]'::jsonb),
    'trabajos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', t.id, 'mecanicoId', t.mecanico_id, 'vehiculoId', t.vehiculo_id,
        'tipoTrabajoId', t.tipo_trabajo_id, 'tipoNombre', tt.nombre,
        'descripcion', t.descripcion, 'precio', t.precio_snapshot,
        'estado', t.estado, 'fecha', t.fecha,
        'validadoPor', t.validado_por, 'notaAdmin', t.nota_admin,
        'creadaEn', t.creada_en,
        'piezas', coalesce((
          select jsonb_agg(jsonb_build_object('piezaId', tp.pieza_id, 'cantidad', tp.cantidad))
          from trabajo_piezas tp where tp.trabajo_id = t.id
        ), '[]'::jsonb)
      ) order by t.creada_en desc)
      from (select * from trabajos where empresa_id = v_empresa
            order by creada_en desc limit 300) t
      join tipos_trabajo tt on tt.id = t.tipo_trabajo_id
    ), '[]'::jsonb),
    'pagosMes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'mecanicoId', r.mecanico_id,
        'modoPago', r.modo_pago,
        'sueldoMonto', r.sueldo_monto,
        'validados', r.validados,
        'pendientes', r.pendientes,
        'rechazados', r.rechazados,
        'totalPagar', r.total_pagar
      ) order by r.total_pagar desc)
      from (
        select u.id as mecanico_id, u.modo_pago, u.sueldo_monto,
               count(t.id) filter (where t.estado = 'validada') as validados,
               count(t.id) filter (where t.estado = 'pendiente') as pendientes,
               count(t.id) filter (where t.estado = 'rechazada') as rechazados,
               case when u.modo_pago = 'sueldo'
                    then coalesce(u.sueldo_monto, 0)
                    else coalesce(sum(t.precio_snapshot) filter (where t.estado = 'validada'), 0)
               end as total_pagar
        from usuarios u
        left join trabajos t
          on t.mecanico_id = u.id and t.empresa_id = v_empresa and t.fecha >= v_mes
        where u.empresa_id = v_empresa and u.rol = 'mecanico'
        group by u.id, u.modo_pago, u.sueldo_monto
      ) r
    ), '[]'::jsonb),
    'lavados', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', l.id, 'vehiculoId', l.vehiculo_id, 'fecha', l.fecha,
        'activa', l.activa, 'marcadaEn', l.marcada_en,
        'marcadaPor', l.marcada_por, 'desmarcadaEn', l.desmarcada_en,
        'desmarcadaPor', l.desmarcada_por
      ) order by l.fecha desc, l.marcada_en desc)
      from (select * from lavados where empresa_id = v_empresa
            order by fecha desc, marcada_en desc limit 300) l
    ), '[]'::jsonb),
    'despachosCombustible', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', d.id, 'vehiculoId', d.vehiculo_id, 'despachadorId', d.despachador_id,
        'fecha', d.fecha, 'galones', d.galones, 'tipo', d.tipo_combustible,
        'odometro', d.odometro, 'costoUnitario', d.costo_galon,
        'total', d.total, 'creadaEn', d.creada_en
      ) order by d.creada_en desc)
      from (select * from despachos_combustible where empresa_id = v_empresa
            order by creada_en desc limit 300) d
    ), '[]'::jsonb),
    'tanque', pr__tanque_json(v_empresa),
    'recepcionesCombustible', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id, 'tipo', r.tipo_combustible, 'galones', r.galones,
        'costoUnitario', r.costo_galon, 'total', r.total,
        'proveedor', r.proveedor, 'nota', r.nota,
        'fecha', r.fecha, 'creadaEn', r.creada_en,
        'recibidoPor', r.recibido_por
      ) order by r.creada_en desc)
      from (select * from recepciones_combustible where empresa_id = v_empresa
            order by creada_en desc limit 100) r
    ), '[]'::jsonb),
    'solicitudesPiezas', coalesce((
      select jsonb_agg(pr__solicitud_json(x) order by x.creada_en desc)
      from (select * from solicitudes_piezas where empresa_id = v_empresa
            order by creada_en desc limit 300) x
    ), '[]'::jsonb)
  );
end;
$$;


-- === archivo: bloqueo-roles-extra.sql ===
-- ================================================================
-- TallerNeto · BLOQUEO DE ROLES DE SERVICIOS EXTRA (2026-11-21)
-- Orden de Miguel: en el panel de una empresa que NO ha contratado
-- los servicios extras (Lavado y Combustible) no se le puede
-- permitir crear el usuario que maneja el combustible ni el del
-- lavado. El uso ya estaba candado (pr__exigir_lavado_activo /
-- pr__exigir_combustible_activo en cada operación); faltaba la
-- CREACIÓN de esos usuarios, que es lo que cierra este archivo.
--
-- Se redefine, con guardas nuevas y el resto copiado fiel:
--   · pr_crear_usuario (versión vigente: combustible.sql) — el rol
--     principal 'lavado' exige empresas.lavado_activo y el rol
--     'combustible' exige empresas.combustible_activo.
--   · pr_fijar_rol_adicional (versión vigente: roles.sql) — la
--     misma exigencia para el rol ADICIONAL: un mecánico no puede
--     recibir el sombrero de lavado/combustible si la empresa no
--     tiene contratado ese extra.
-- Los mensajes están escritos para el administrador de la empresa:
-- le dicen qué pasa y que la activación la pide a su proveedor
-- (la activación sigue siendo solo-superadmin, como siempre).
--
-- Aplicar DESPUÉS de toda la pila (esquema, trabajos, lavado,
-- combustible, tanque, solicitudes, roles, config-ampliada).
-- ================================================================

-- ============ CREAR USUARIO: sin extra contratado, no hay rol ============
create or replace function pr_crear_usuario(p_empresa uuid, p_nombre text, p_codigo text,
                                            p_rol text, p_pin text default null,
                                            p_quien uuid default null,
                                            p_token text default null)
returns usuarios language plpgsql security definer as $$
declare
  nuevo usuarios;
  q usuarios;
begin
  q := pr_actor_con_rol(p_empresa, p_quien, p_token, array['admin']);
  if p_rol not in ('admin','almacen','mecanico','lavado','combustible') then
    raise exception 'Rol no válido: %', p_rol;
  end if;
  -- NUEVO (bloqueo-roles-extra): los roles de los servicios extra
  -- solo existen si la empresa tiene ese extra contratado/activo.
  if p_rol = 'lavado' and not pr__lavado_activo(p_empresa) then
    raise exception 'No puedes crear un usuario de Lavado: esta empresa no tiene contratado el servicio extra de Lavado. Pide su activación a tu proveedor.';
  end if;
  if p_rol = 'combustible' and not pr__combustible_activo(p_empresa) then
    raise exception 'No puedes crear un usuario de Combustible: esta empresa no tiene contratado el servicio extra de Combustible. Pide su activación a tu proveedor.';
  end if;
  if p_pin is null or length(trim(p_pin)) = 0 then
    raise exception 'El PIN es obligatorio: indica un PIN de 4 a 6 dígitos para el usuario nuevo';
  end if;
  if trim(p_pin) !~ '^[0-9]{4,6}$' then
    raise exception 'El PIN debe tener de 4 a 6 dígitos';
  end if;
  if trim(p_pin) = '1234' then
    raise exception 'El PIN 1234 está prohibido por seguridad: elige otro PIN';
  end if;
  if exists (select 1 from usuarios
             where empresa_id = p_empresa and upper(codigo) = upper(trim(p_codigo))) then
    raise exception 'Ya existe un usuario con el código %', p_codigo;
  end if;
  insert into usuarios (empresa_id, rol, nombre, codigo, pin_hash)
  values (p_empresa, p_rol, trim(p_nombre), trim(p_codigo), pr_hash_pin(trim(p_pin)))
  returning * into nuevo;
  perform pr_registrar_accion(p_empresa, q.id, 'usuario_creado',
    format('Se creó el usuario %s (%s, %s)', nuevo.codigo, nuevo.nombre, nuevo.rol));
  return nuevo;
end;
$$;

-- ============ ROL ADICIONAL: la misma exigencia ============
create or replace function pr_fijar_rol_adicional(p_usuario uuid,
                                                  p_rol_adicional text default null,
                                                  p_quien uuid default null,
                                                  p_token text default null)
returns usuarios language plpgsql security definer as $$
declare
  u usuarios;
  q usuarios;
  v_rol text := nullif(trim(lower(coalesce(p_rol_adicional, ''))), '');
begin
  select * into u from usuarios where id = p_usuario;
  if u.id is null then raise exception 'Usuario no encontrado'; end if;
  if u.empresa_id is null then
    raise exception 'El dueño del sistema no lleva rol adicional';
  end if;
  q := pr_actor_con_rol(u.empresa_id, p_quien, p_token, array['admin']);
  if v_rol is not null then
    if v_rol not in ('admin','almacen','mecanico','lavado','combustible') then
      raise exception 'Rol adicional no válido: %', p_rol_adicional;
    end if;
    if v_rol = u.rol then
      raise exception 'El rol adicional no puede ser el mismo que el rol principal (%)', u.rol;
    end if;
    -- NUEVO (bloqueo-roles-extra): el sombrero de un servicio extra
    -- exige que la empresa tenga ese extra contratado/activo.
    if v_rol = 'lavado' and not pr__lavado_activo(u.empresa_id) then
      raise exception 'No puedes dar el rol adicional de Lavado: esta empresa no tiene contratado el servicio extra de Lavado. Pide su activación a tu proveedor.';
    end if;
    if v_rol = 'combustible' and not pr__combustible_activo(u.empresa_id) then
      raise exception 'No puedes dar el rol adicional de Combustible: esta empresa no tiene contratado el servicio extra de Combustible. Pide su activación a tu proveedor.';
    end if;
  end if;
  update usuarios set rol_adicional = v_rol where id = u.id
  returning * into u;
  perform pr_registrar_accion(u.empresa_id, q.id, 'usuario_editado',
    format('Rol adicional de %s (%s): %s', u.codigo, u.nombre,
           coalesce(v_rol, 'ninguno')));
  return u;
end;
$$;


-- === archivo: lavado-fuera-servicio.sql ===
-- ================================================================
-- TallerNeto · LAVADO: LOS FUERA DE SERVICIO NO CUENTAN (2026-11-21)
-- Observación de Miguel: «si un vehículo lo colocan fuera de
-- servicio, no desaparece de la lista de no lavados, y eso no
-- debería ser así». Tiene razón: la parrilla del día y el cálculo
-- de «sin lavar» filtraban solo por vehiculos.activo (la baja
-- lógica), pero un vehículo con estado 'fuera_servicio' sigue
-- activo=true y aparecía como pendiente de lavado para siempre.
--
-- Corrección (copias fieles de lavado.sql con el filtro nuevo
-- `v.estado <> 'fuera_servicio'`):
--   · pr_datos_lavado — la parrilla del día (app y panel) ya no
--     trae los vehículos fuera de servicio.
--   · pr_resumen_lavado — «porVehiculo» (último lavado / días sin
--     lavar) ya no los cuenta como atrasados. El historial NO se
--     toca: lo que se lavó, se lavó.
--   · pr_marcar_lavado — marcar un vehículo fuera de servicio se
--     rechaza con mensaje claro, igual que ya se rechazaba el
--     inactivo.
-- Los vehículos 'en_taller' SÍ siguen en la parrilla (no lo pidió
-- Miguel: un vehículo en el taller puede lavarse al salir).
--
-- Aplicar DESPUÉS de lavado.sql (y del resto de la pila).
-- ================================================================

-- ============ MARCAR LAVADO: fuera de servicio no se marca ============
create or replace function pr_marcar_lavado(p_empresa uuid, p_vehiculo uuid,
                                            p_quien uuid default null,
                                            p_token text default null)
returns lavados language plpgsql security definer as $$
declare
  q usuarios;
  v vehiculos;
  l lavados;
  v_hoy date := pr_hoy();
begin
  perform pr__exigir_lavado_activo(p_empresa);
  q := pr_actor_con_rol(p_empresa, p_quien, p_token, array['lavado','admin','almacen']);
  select * into v from vehiculos where id = p_vehiculo and empresa_id = p_empresa;
  if v.id is null then raise exception 'Vehículo no encontrado en esta empresa'; end if;
  if not v.activo then raise exception 'El vehículo % está inactivo', v.codigo; end if;
  -- NUEVO (lavado-fuera-servicio): fuera de servicio no se lava.
  if v.estado = 'fuera_servicio' then
    raise exception 'El vehículo % está fuera de servicio: no se marca lavado', v.codigo;
  end if;

  select * into l from lavados
  where empresa_id = p_empresa and vehiculo_id = v.id and fecha = v_hoy;
  if l.id is not null and l.activa then
    raise exception 'El vehículo % ya está marcado como lavado hoy', v.codigo;
  end if;
  if l.id is not null then
    -- Estaba desmarcado: se reactiva con auditoría nueva de marcado.
    update lavados
    set activa = true, marcada_por = q.id, marcada_en = now(),
        desmarcada_por = null, desmarcada_en = null
    where id = l.id
    returning * into l;
  else
    insert into lavados (empresa_id, vehiculo_id, fecha, activa, marcada_por, marcada_en)
    values (p_empresa, v.id, v_hoy, true, q.id, now())
    returning * into l;
  end if;
  perform pr_registrar_accion(p_empresa, q.id, 'lavado_marcado',
    format('Marcó lavado el vehículo %s (%s)', v.codigo, v.placa));
  return l;
end;
$$;

-- ============ DATOS DE LAVADO (app): sin fuera de servicio ============
create or replace function pr_datos_lavado(p_quien uuid default null,
                                           p_token text default null)
returns jsonb language plpgsql security definer as $$
declare
  u usuarios;
  q usuarios;
  e empresas;
  v_hoy date := pr_hoy();
begin
  select * into u from usuarios where id = p_quien and activo;
  if u.id is null then raise exception 'Usuario no válido'; end if;
  if u.empresa_id is null then
    raise exception 'Esta cuenta no es de una empresa';
  end if;
  q := pr_actor_con_rol(u.empresa_id, p_quien, p_token, array['lavado','admin']);
  perform pr__exigir_lavado_activo(q.empresa_id);
  select * into e from empresas where id = q.empresa_id;

  return jsonb_build_object(
    'usuario', jsonb_build_object(
      'id', q.id, 'nombre', q.nombre, 'codigo', q.codigo, 'rol', q.rol),
    'empresa', jsonb_build_object(
      'id', e.id, 'nombre', e.nombre, 'lavadoActivo', e.lavado_activo),
    'fecha', v_hoy,
    'vehiculos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', v.id, 'codigo', v.codigo, 'placa', v.placa, 'marca', v.marca,
        'modelo', v.modelo, 'anio', v.anio, 'estado', v.estado, 'activo', v.activo,
        'lavadoHoy', coalesce(l.activa, false),
        'marcadaEn', case when l.activa then l.marcada_en else null end,
        'marcadaPor', case when l.activa then l.marcada_por else null end,
        'marcadaPorNombre', case when l.activa
          then (select nombre from usuarios where id = l.marcada_por) else null end
      ) order by v.codigo)
      from vehiculos v
      left join lavados l
        on l.vehiculo_id = v.id and l.empresa_id = q.empresa_id and l.fecha = v_hoy
      -- NUEVO (lavado-fuera-servicio): los fuera de servicio no
      -- salen en la parrilla del día.
      where v.empresa_id = q.empresa_id and v.activo
        and v.estado <> 'fuera_servicio'
    ), '[]'::jsonb)
  );
end;
$$;

-- ============ RESUMEN DE LAVADO (panel): «sin lavar» sin fuera de servicio ============
create or replace function pr_resumen_lavado(p_empresa uuid,
                                             p_quien uuid default null,
                                             p_token text default null)
returns jsonb language plpgsql security definer as $$
declare
  q usuarios;
  v_hoy date := pr_hoy();
begin
  perform pr__exigir_lavado_activo(p_empresa);
  q := pr_actor_con_rol(p_empresa, p_quien, p_token, array['admin','almacen']);
  return jsonb_build_object(
    'fecha', v_hoy,
    'hoy', coalesce((
      select jsonb_agg(jsonb_build_object(
        'vehiculoId', l.vehiculo_id,
        'vehiculoCodigo', v.codigo,
        'vehiculoPlaca', v.placa,
        'hora', l.marcada_en,
        'responsableId', l.marcada_por,
        'responsableNombre', (select nombre from usuarios where id = l.marcada_por)
      ) order by l.marcada_en)
      from lavados l
      join vehiculos v on v.id = l.vehiculo_id
      where l.empresa_id = p_empresa and l.fecha = v_hoy and l.activa
    ), '[]'::jsonb),
    'historial', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', l.id, 'vehiculoId', l.vehiculo_id, 'fecha', l.fecha,
        'activa', l.activa, 'marcadaEn', l.marcada_en,
        'marcadaPor', l.marcada_por, 'desmarcadaEn', l.desmarcada_en,
        'desmarcadaPor', l.desmarcada_por
      ) order by l.fecha desc, l.marcada_en desc)
      from (select * from lavados where empresa_id = p_empresa
            order by fecha desc, marcada_en desc limit 300) l
    ), '[]'::jsonb),
    'porVehiculo', coalesce((
      select jsonb_agg(jsonb_build_object(
        'vehiculoId', r.vehiculo_id,
        'ultimoLavado', r.ultimo_lavado,
        'diasSinLavar', case when r.ultimo_lavado is null then null
                             else v_hoy - r.ultimo_lavado end
      ) order by r.ultimo_lavado asc nulls first)
      from (
        select v.id as vehiculo_id,
               (select max(l.fecha) from lavados l
                 where l.vehiculo_id = v.id and l.empresa_id = p_empresa
                   and l.activa) as ultimo_lavado
        from vehiculos v
        -- NUEVO (lavado-fuera-servicio): los fuera de servicio no
        -- cuentan como atrasados de lavado.
        where v.empresa_id = p_empresa and v.activo
          and v.estado <> 'fuera_servicio'
      ) r
    ), '[]'::jsonb)
  );
end;
$$;


-- === archivo: extras-contratacion.sql ===
-- ================================================================
-- TallerNeto · CONTRATACIÓN DE EXTRAS CON SOLICITUD (2026-11-21)
-- Orden de Miguel: «Lavado y Combustible quítalo del panel y
-- ponlo en Administración como extras; cuando se despliegue le
-- informa que tiene un precio extra esas funciones, le das la
-- opción de activar y que me llegue la notificación a mí de
-- activarla para aprobarla».
--
-- Cómo queda el flujo:
--   1. Los módulos salen del menú principal del panel cuando NO
--      están activos; su contratación vive en Administración →
--      Servicios extra, donde la empresa ve qué hace cada módulo,
--      su PRECIO (el aprobado: Lavado US$10/mes, Combustible
--      US$15/mes, ambos US$19/mes) y el botón «Solicitar
--      activación».
--   2. pr_solicitar_extra: solo el admin de la empresa; crea la
--      solicitud (tabla solicitudes_extras, una sola pendiente por
--      módulo) y queda en el registro de la empresa. ESA es la
--      notificación al dueño: su bandeja es
--      pr_admin_solicitudes_extras.
--   3. pr_admin_resolver_extra: solo el superadmin (Miguel). Al
--      APROBAR, el módulo se activa de verdad (pr_configurar_
--      lavado / pr_configurar_combustible, las de siempre) y la
--      solicitud queda aprobada; al rechazar, queda rechazada con
--      su nota y la empresa puede volver a pedirla.
-- La activación directa del dueño (sin solicitud) no cambia.
--
-- Precios: viven en la tabla `configuracion` (claves
-- precio_extra_lavado / precio_extra_combustible /
-- precio_extras_ambos), sembrados aquí sin pisar ajustes.
--
-- Aplicar DESPUÉS de toda la pila (lavado y combustible incluidos).
-- ================================================================

-- ============ PRECIOS DE LOS EXTRAS (configuración global) ============
insert into configuracion (clave, valor, descripcion) values
  ('precio_extra_lavado', '10', 'Precio mensual del extra de Lavado (US$)'),
  ('precio_extra_combustible', '15', 'Precio mensual del extra de Combustible (US$)'),
  ('precio_extras_ambos', '19', 'Precio mensual de Lavado + Combustible juntos (US$)')
on conflict (clave) do nothing;

create or replace function pr__precio_extra(p_clave text) returns numeric
language sql stable security definer as $$
  select coalesce((select valor::numeric from configuracion where clave = p_clave), 0);
$$;

-- ============ SOLICITUDES DE ACTIVACIÓN ============
create table if not exists solicitudes_extras (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references empresas(id) on delete cascade,
  modulo text not null check (modulo in ('lavado','combustible')),
  estado text not null default 'pendiente'
    check (estado in ('pendiente','aprobada','rechazada')),
  solicitada_por uuid not null references usuarios(id),
  creada_en timestamptz not null default now(),
  resuelta_por uuid references usuarios(id),
  resuelta_en timestamptz,
  nota text
);
alter table solicitudes_extras enable row level security;

-- Una sola solicitud pendiente por empresa y módulo.
create unique index if not exists solicitudes_extras_una_pendiente
  on solicitudes_extras (empresa_id, modulo) where estado = 'pendiente';

-- ============ LA EMPRESA PIDE LA ACTIVACIÓN (solo su admin) ============
create or replace function pr_solicitar_extra(p_modulo text,
                                              p_quien uuid default null,
                                              p_token text default null)
returns solicitudes_extras language plpgsql security definer as $$
declare
  u usuarios;
  q usuarios;
  s solicitudes_extras;
  v_modulo text := lower(trim(coalesce(p_modulo, '')));
begin
  select * into u from usuarios where id = p_quien and activo;
  if u.id is null then raise exception 'Usuario no válido'; end if;
  if u.empresa_id is null then
    raise exception 'Esta cuenta no es de una empresa';
  end if;
  q := pr_actor_con_rol(u.empresa_id, p_quien, p_token, array['admin']);
  if v_modulo not in ('lavado','combustible') then
    raise exception 'Módulo no válido: %', p_modulo;
  end if;
  if (v_modulo = 'lavado' and pr__lavado_activo(q.empresa_id))
     or (v_modulo = 'combustible' and pr__combustible_activo(q.empresa_id)) then
    raise exception 'El módulo de % ya está activo en tu empresa', v_modulo;
  end if;
  if exists (select 1 from solicitudes_extras
             where empresa_id = q.empresa_id and modulo = v_modulo
               and estado = 'pendiente') then
    raise exception 'Ya tienes una solicitud de activación pendiente para el módulo de %: tu proveedor ya la recibió', v_modulo;
  end if;
  insert into solicitudes_extras (empresa_id, modulo, solicitada_por)
  values (q.empresa_id, v_modulo, q.id)
  returning * into s;
  perform pr_registrar_accion(q.empresa_id, q.id, 'extra_solicitado',
    format('La empresa solicitó la activación del servicio extra de %s (US$%s/mes)',
           v_modulo,
           pr__precio_extra(case when v_modulo = 'lavado'
                                 then 'precio_extra_lavado'
                                 else 'precio_extra_combustible' end)));
  return s;
end;
$$;

-- ============ ESTADO DE LOS EXTRAS PARA EL PANEL (Administración) ============
create or replace function pr_datos_extras(p_quien uuid default null,
                                           p_token text default null)
returns jsonb language plpgsql security definer as $$
declare
  u usuarios;
  q usuarios;
begin
  select * into u from usuarios where id = p_quien and activo;
  if u.id is null then raise exception 'Usuario no válido'; end if;
  if u.empresa_id is null then
    raise exception 'Esta cuenta no es de una empresa';
  end if;
  q := pr_actor_con_rol(u.empresa_id, p_quien, p_token, array['admin']);
  return jsonb_build_object(
    'lavado', jsonb_build_object(
      'activo', pr__lavado_activo(q.empresa_id),
      'precioMes', pr__precio_extra('precio_extra_lavado'),
      'pendiente', exists (select 1 from solicitudes_extras
                           where empresa_id = q.empresa_id and modulo = 'lavado'
                             and estado = 'pendiente')),
    'combustible', jsonb_build_object(
      'activo', pr__combustible_activo(q.empresa_id),
      'precioMes', pr__precio_extra('precio_extra_combustible'),
      'pendiente', exists (select 1 from solicitudes_extras
                           where empresa_id = q.empresa_id and modulo = 'combustible'
                             and estado = 'pendiente')),
    'precioAmbos', pr__precio_extra('precio_extras_ambos'));
end;
$$;

-- ============ LA BANDEJA DEL DUEÑO: SOLICITUDES POR APROBAR ============
create or replace function pr_admin_solicitudes_extras(p_quien uuid)
returns jsonb language plpgsql security definer as $$
begin
  perform pr_exigir_superadmin(p_quien);
  return jsonb_build_object('solicitudes', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', s.id,
      'empresaId', s.empresa_id,
      'empresaNombre', e.nombre,
      'modulo', s.modulo,
      'estado', s.estado,
      'solicitadaPorNombre', su.nombre,
      'solicitadaPorCodigo', su.codigo,
      'creadaEn', s.creada_en,
      'resueltaEn', s.resuelta_en,
      'nota', s.nota
    ) order by case when s.estado = 'pendiente' then 0 else 1 end, s.creada_en desc)
    from solicitudes_extras s
    join empresas e on e.id = s.empresa_id
    join usuarios su on su.id = s.solicitada_por
  ), '[]'::jsonb));
end;
$$;

-- ============ EL DUEÑO APRUEBA O RECHAZA (aprobar = activar) ============
create or replace function pr_admin_resolver_extra(p_quien uuid, p_solicitud uuid,
                                                   p_aprobar boolean,
                                                   p_nota text default null)
returns solicitudes_extras language plpgsql security definer as $$
declare
  s solicitudes_extras;
begin
  perform pr_exigir_superadmin(p_quien);
  select * into s from solicitudes_extras where id = p_solicitud;
  if s.id is null then raise exception 'Solicitud no encontrada'; end if;
  if s.estado <> 'pendiente' then
    raise exception 'Esta solicitud ya fue resuelta (%): no se puede resolver dos veces', s.estado;
  end if;

  if p_aprobar then
    -- Activar el módulo de verdad, por la vía de siempre.
    if s.modulo = 'lavado' then
      perform pr_configurar_lavado(s.empresa_id, true, p_quien);
    else
      perform pr_configurar_combustible(s.empresa_id, true, p_quien);
    end if;
  end if;

  update solicitudes_extras
  set estado = case when p_aprobar then 'aprobada' else 'rechazada' end,
      resuelta_por = p_quien,
      resuelta_en = now(),
      nota = nullif(trim(coalesce(p_nota, '')), '')
  where id = s.id
  returning * into s;

  perform pr_registrar_accion(s.empresa_id, p_quien,
    case when p_aprobar then 'extra_aprobado' else 'extra_rechazado' end,
    format(case when p_aprobar
                then 'Se aprobó la solicitud y se ACTIVÓ el servicio extra de %s'
                else 'Se rechazó la solicitud del servicio extra de %s%s' end,
           s.modulo,
           case when p_aprobar then ''
                else coalesce(': ' || s.nota, '') end));
  return s;
end;
$$;


