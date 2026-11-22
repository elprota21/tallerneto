-- ================================================================
-- TallerNeto · PRIMERA EMPRESA (de prueba) para PRODUCCIÓN
-- Proyecto Supabase «staffride» (cuenta ml).
--
-- Aprobada por Miguel el 2026-11-22 con estos datos exactos:
--   Empresa:  «Transportes Prueba», licencia activa 12 meses,
--             plan base (max_vehiculos = 25, el mismo tope de la
--             semilla demo sembrada en este proyecto).
--   Admin:    ADM-01 «Admin Prueba»,    PIN 2468 (provisional).
--   Mecánico: MEC-01 «Mecánico Prueba», PIN 2468 (provisional),
--             modo_pago = destajo (es el default de la tabla).
--   Unidad:   V-01 de prueba, para que el Inventario por unidad
--             tenga algo que mostrar.
--
-- POR QUÉ UN SCRIPT: TallerNeto NO tiene función RPC para crear
-- empresas (se revisaron las 77 funciones pr_* del bundle de
-- producción: ninguna crea empresas) y las tablas tienen RLS sin
-- políticas (la API REST rechaza inserts directos, verificado:
-- 401 «new row violates row-level security policy»). Las empresas
-- se crean por SQL, igual que se sembró la demo (semilla-demo-
-- staffride.sql) y el dueño (crear-dueno-produccion.sql).
--
-- Aplicar DESPUÉS de produccion-staffride.sql e inventario-
-- unidad.sql (ambos ya aplicados en producción). Idempotente:
-- si la empresa ya existe (por id o por nombre), no hace nada.
-- ================================================================

do $$
declare
  v_emp uuid := 'c0000000-0000-0000-0000-000000000001';
  v_adm uuid; v_mec uuid; v_v1 uuid;
  v_hoy date := pr_hoy();
begin
  if exists (select 1 from empresas where id = v_emp)
     or exists (select 1 from empresas where nombre = 'Transportes Prueba') then
    raise notice 'La empresa de prueba ya existe: no se crea de nuevo.';
    return;
  end if;

  insert into empresas (id, nombre) values (v_emp, 'Transportes Prueba');
  insert into licencias (empresa_id, estado, vence, max_vehiculos)
  values (v_emp, 'activa', (v_hoy + interval '1 year')::date, 25);

  insert into usuarios (empresa_id, rol, nombre, codigo, pin_hash) values
    (v_emp, 'admin',    'Admin Prueba',    'ADM-01', pr_hash_pin('2468')) returning id into v_adm;
  insert into usuarios (empresa_id, rol, nombre, codigo, pin_hash) values
    (v_emp, 'mecanico', 'Mecánico Prueba', 'MEC-01', pr_hash_pin('2468')) returning id into v_mec;

  insert into vehiculos (empresa_id, codigo, placa, marca, modelo, anio, estado) values
    (v_emp, 'V-01', 'A-000001', 'Hyundai', 'County', 2020, 'activo') returning id into v_v1;

  raise notice 'Empresa de prueba creada: empresa %, admin %, mecanico %, vehiculo %',
    v_emp, v_adm, v_mec, v_v1;
end;
$$;
