-- ================================================================
-- TallerNeto · EL DUEÑO CREA EMPRESAS DESDE EL SISTEMA
-- (admin-crear-empresa.sql)
--
-- Hasta hoy las empresas solo nacían por script SQL pegado en el
-- editor de Supabase (semilla-demo-staffride.sql y crear-empresa-
-- prueba-produccion.sql), porque el bundle NO traía ninguna
-- función para crearlas y las tablas tienen RLS sin políticas
-- (la API REST rechaza inserts directos). Miguel pidió arreglar
-- eso (2026-11-22): el dueño crea las empresas desde el panel,
-- como en RutaNeto (pr_admin_crear_empresa de pago-rutas).
--
-- Archivo NUEVO, independiente, aditivo e idempotente (create or
-- replace): se aplica DESPUÉS de toda la pila vigente (esquema +
-- extensiones). NO toca ninguna función existente.
--
-- Qué trae:
--  - pr_admin_crear_empresa: SOLO el superadmin (dueño), con su
--    sesión token validada como en el resto del sistema
--    (pr_validar_token + pr_exigir_superadmin). El dueño NO opera
--    dentro de la empresa: solo la crea y crea a su primer
--    administrador, y la acción queda en la auditoría
--    (registro_actividad, acción 'empresa_creada').
--  - pr_admin_empresas: el listado de empresas del dueño para
--    la sección «Empresas» del panel (antes no existía ningún
--    listado del dueño dentro de TallerNeto: el snapshot exige
--    empresa y el Súper Panel lee el estado por otra vía).
--
-- Reglas que replica de la casa:
--  - Licencia activa desde el día uno: vence = pr_hoy() + meses.
--  - PIN del administrador con la MISMA regla de pr_crear_usuario:
--    obligatorio, de 4 a 6 dígitos y NUNCA '1234'; se guarda solo
--    su hash bcrypt (pr_hash_pin) y NUNCA se devuelve.
--  - El código del administrador debe ser único en TODO el
--    sistema (no solo en su empresa): la entrada es por código
--    sin elegir empresa (pr_iniciar_sesion busca por código en
--    todas las empresas y rechaza si el mismo código+PIN existe
--    en más de una), así que un código repetido dejaría al admin
--    nuevo sin poder entrar sin ambigüedad.
--  - La plantilla base del Inventario por unidad (9 artículos)
--    se siembra al crear la empresa si el módulo está aplicado
--    (en el sistema vigente se siembra perezosa al primer acceso
--    con pr__inv_asegurar_plantilla; aquí se llama a la misma
--    función, protegida por si el módulo no estuviera).
-- ================================================================

-- ============ LISTADO DE EMPRESAS DEL DUEÑO ============
create or replace function pr_admin_empresas(p_quien uuid, p_token text)
returns jsonb language plpgsql security definer as $$
declare
  q usuarios;
begin
  perform pr_validar_token(p_quien, p_token);
  q := pr_exigir_superadmin(p_quien);
  return jsonb_build_object('empresas', coalesce((
    select jsonb_agg(fila order by nombre)
    from (
      select jsonb_build_object(
        'id', e.id,
        'nombre', e.nombre,
        'activa', e.activa,
        'creadaEn', e.creada_en,
        'licencia', case when lic.id is null then null else jsonb_build_object(
          'estado', lic.estado,
          'vence', lic.vence,
          'maxVehiculos', lic.max_vehiculos,
          'diasRestantes', case when lic.vence is null then null
                                else lic.vence - pr_hoy() end
        ) end,
        'usuarios', (select count(*) from usuarios u where u.empresa_id = e.id),
        'vehiculos', (select count(*) from vehiculos v where v.empresa_id = e.id)
      ) as fila, e.nombre as nombre
      from empresas e
      left join lateral (
        select l.* from licencias l
        where l.empresa_id = e.id
        order by l.creada_en desc limit 1
      ) lic on true
    ) t
  ), '[]'::jsonb));
end;
$$;

-- ============ CREAR EMPRESA (+ SU PRIMER ADMINISTRADOR) ============
create or replace function pr_admin_crear_empresa(p_quien uuid, p_token text,
                                                  p_nombre text,
                                                  p_admin_codigo text,
                                                  p_admin_nombre text,
                                                  p_admin_pin text,
                                                  p_meses int default 12,
                                                  p_max_vehiculos int default 25)
returns jsonb language plpgsql security definer as $$
declare
  q usuarios;
  e empresas;
  lic licencias;
  adm usuarios;
  v_nombre text := trim(coalesce(p_nombre, ''));
  v_codigo text := trim(coalesce(p_admin_codigo, ''));
  v_adm_nombre text := trim(coalesce(p_admin_nombre, ''));
  v_pin text := trim(coalesce(p_admin_pin, ''));
  v_meses int := coalesce(p_meses, 12);
  v_max int := coalesce(p_max_vehiculos, 25);
begin
  -- Solo el dueño, con su sesión viva (el mismo candado del
  -- resto del sistema: token válido + rol superadmin).
  perform pr_validar_token(p_quien, p_token);
  q := pr_exigir_superadmin(p_quien);

  -- ---- Validaciones (mensajes claros, antes de tocar nada) ----
  if v_nombre = '' then
    raise exception 'El nombre de la empresa no puede estar vacío';
  end if;
  if length(v_nombre) > 120 then
    raise exception 'El nombre de la empresa es demasiado largo (máximo 120 caracteres)';
  end if;
  if exists (select 1 from empresas where lower(nombre) = lower(v_nombre)) then
    raise exception 'Ya existe una empresa con el nombre %', v_nombre;
  end if;
  if v_meses <= 0 then
    raise exception 'La licencia debe durar al menos 1 mes: indica los meses de licencia';
  end if;
  if v_meses > 120 then
    raise exception 'La licencia no puede durar más de 120 meses';
  end if;
  if v_max <= 0 then
    raise exception 'El máximo de vehículos debe ser mayor que cero';
  end if;
  if v_codigo = '' then
    raise exception 'El código del administrador no puede estar vacío';
  end if;
  if exists (select 1 from usuarios where upper(codigo) = upper(v_codigo)) then
    raise exception 'Ya existe un usuario con el código % en el sistema: elige otro código (el código de entrada es único en todo TallerNeto)', v_codigo;
  end if;
  if v_adm_nombre = '' then
    raise exception 'El nombre del administrador no puede estar vacío';
  end if;
  if v_pin = '' then
    raise exception 'El PIN es obligatorio: indica un PIN de 4 a 6 dígitos para el administrador';
  end if;
  if v_pin !~ '^[0-9]{4,6}$' then
    raise exception 'El PIN debe tener de 4 a 6 dígitos';
  end if;
  if v_pin = '1234' then
    raise exception 'El PIN 1234 está prohibido por seguridad: elige otro PIN';
  end if;

  -- ---- Creación: empresa + licencia activa + primer admin ----
  insert into empresas (nombre) values (v_nombre) returning * into e;
  insert into licencias (empresa_id, estado, vence, max_vehiculos)
  values (e.id, 'activa', (pr_hoy() + (v_meses || ' months')::interval)::date, v_max)
  returning * into lic;
  insert into usuarios (empresa_id, rol, nombre, codigo, pin_hash)
  values (e.id, 'admin', v_adm_nombre, v_codigo, pr_hash_pin(v_pin))
  returning * into adm;

  -- Plantilla base del Inventario por unidad (9 artículos): en el
  -- sistema se siembra perezosa al primer acceso; aquí se siembra
  -- al crear, con la misma función, si el módulo está aplicado.
  begin
    perform pr__inv_asegurar_plantilla(e.id);
  exception when undefined_function then
    null; -- el módulo de inventario por unidad aún no está aplicado
  end;

  perform pr_registrar_accion(e.id, q.id, 'empresa_creada',
    format('Creó la empresa «%s» (licencia activa hasta el %s, máx. %s vehículos) y su administrador %s (%s)',
           e.nombre, to_char(lic.vence, 'DD/MM/YYYY'), lic.max_vehiculos,
           adm.codigo, adm.nombre));

  -- Se devuelve la empresa y el admin — NUNCA el PIN.
  return jsonb_build_object(
    'empresa', jsonb_build_object('id', e.id, 'nombre', e.nombre, 'activa', e.activa),
    'licencia', jsonb_build_object('estado', lic.estado, 'vence', lic.vence,
                                   'maxVehiculos', lic.max_vehiculos),
    'admin', jsonb_build_object('id', adm.id, 'codigo', adm.codigo,
                                'nombre', adm.nombre, 'rol', adm.rol)
  );
end;
$$;
