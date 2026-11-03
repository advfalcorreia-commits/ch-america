/* ─────────────────────────────────────────────────────────────────
   CONFIGURACIÓN DE SUPABASE — un solo sitio para las dos páginas.
   Este fichero lo cargan index.html (web pública) y adm.html (panel).

   Deja los dos valores vacíos y:
     · la web funciona como ahora (precios fijos en el código);
     · el panel de administración entra en modo demostración
       (datos guardados solo en tu navegador, no sirve para producción).

   Para conectarlo de verdad:
     1. supabase.com → tu proyecto → Project Settings → API
     2. Copia "Project URL"  -> url
        Copia la clave "anon public" -> anonKey
     3. Pega los dos valores entre las comillas y guarda.

   La clave "anon" NO es un secreto: está protegida por las reglas RLS
   de supabase/schema.sql. La que nunca debe aparecer aquí es la
   "service_role".
   ───────────────────────────────────────────────────────────────── */
window.CH_SUPABASE = {
  url:     "",
  anonKey: ""
};
