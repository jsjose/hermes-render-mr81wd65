# Plan de implementación: Hermes Agent en Render + Nous Portal

## Objetivo
Desplegar Hermes Agent (Nous Research) en Render con Render MCP integrado
desde el inicio, conectado a Nous Portal como proveedor de modelo, con el
dashboard protegido y la API key de Render acotada antes de exponer el servicio.

Repo: https://github.com/jsjose/hermes-render-mr81wd65

## Alcance (fase 1 — actualizado)
- Deploy del servicio Docker con disco persistente (5GB) para sesiones/skills/memoria.
- Configuración de Nous Portal como proveedor de LLM.
- Render MCP registrado en `config.yaml` con `RENDER_MCP_API_KEY` (Render no soporta scoping por key; riesgo full-access aceptado, ver Riesgos conocidos).
- Protección de acceso al dashboard (sin auth nativa) — bloqueante antes de usar MCP en producción.
- Verificación end-to-end: chat funcional + al menos una tool MCP probada (ej. `mcp_render_list_services`).

Fuera de alcance (fase 1): gateway a Telegram/Discord/Slack, API server OpenAI-compatible.

## Pasos

### 1. Cuenta y credenciales
- [x] Crear cuenta en portal.nousresearch.com
- [x] Generar API key de Nous Portal
- [x] Guardar la key en un gestor de secretos local (no en el repo)

### 2. Deploy en Render
- [x] Corregir `render.yaml`: `region: frankfurt` (minúsculas), confirmar `plan` deseado — verificado en `render.yaml`; se decide `plan: starter` (más barato, always-on, soporta disco; se puede subir a standard después sin perder el disco)
- [x] Verificar en el `Dockerfile` que `HERMES_HOME=/opt/data` (o que coincide con `disk.mountPath`) — default en `bootstrap.sh` coincide con `disk.mountPath`
- [x] Verificar que `/api/status` existe en la imagen antes de confiar en `healthCheckPath` — confirmado en README (depende de `HERMES_DASHBOARD=1`, ya seteado)
- [x] Generar `RENDER_MCP_API_KEY` — Render no permite scoping de permisos por key (hereda el rol completo del usuario que la genera); se acepta el riesgo de key full-access, mitigado con rotación frecuente y revisión de logs (ver Riesgos conocidos)
- [x] Render Dashboard → Blueprints → New Blueprint Instance → apuntar al repo
- [x] Confirmar deploy (build ~3-5 min por el pull de la imagen base)
- [x] Revisar logs de arranque — warnings de "no messaging platforms/allowlists" son esperados (fuera de alcance fase 1); pendiente confirmar ausencia de `Traceback` o `config patch failed` y estado "Live" en Render

### 3. Configuración del agente
- [x] Abrir dashboard de Hermes (URL del servicio Render)
- [x] Intentar login OAuth a Nous Portal desde tab "Provider Login (OAuth)" → falló: "Hermes Agent session key minting has been retired". Causa: imagen pineada `v2026.5.7` es anterior al flujo "Quick Setup via Nous Portal" (introducido en upstream `v0.17.0` / `2026.6.19`)
- [x] Bump `HERMES_IMAGE` en `Dockerfile` a `v2026.7.1`, commit + push (`e38d4b6`)
- [x] Redeploy → falló: `Refusing to bind dashboard to 0.0.0.0 — the auth gate engages on non-loopback binds, but no auth providers are registered`. Hermes ≥v0.16.0 exige un auth provider (password o OAuth) antes de bindear en no-loopback; sin puerto abierto, Render mata el deploy por timeout.
- [x] Extendido `scripts/patch-config.py` (TDD, `tests/test_patch_config.py`) con `ensure_dashboard_basic_auth()`: si `HERMES_DASHBOARD_BASIC_AUTH_USER` + `HERMES_DASHBOARD_BASIC_AUTH_HASH` están seteados, los inserta en `config.yaml` antes de que arranque el dashboard. Añadidas ambas vars a `render.yaml` (`sync: false`).
- [x] Generar el hash localmente con `sudo docker run --rm --entrypoint python docker.io/nousresearch/hermes-agent:v2026.7.1 -c "from plugins.dashboard_auth.basic import hash_password; print(hash_password('...'))"`
- [x] Env vars `HERMES_DASHBOARD_BASIC_AUTH_USER`/`HASH` guardadas en Render, pero el patch automático no llegó a aplicarse en los redeploys candidatos (config.yaml en disco seguía sin `dashboard:` tras fallar) — causa exacta sin confirmar (posible que el disco persistente no esté disponible/sea el mismo para una instancia candidata mientras la anterior sigue viva reteniéndolo)
- [x] Añadido logging persistente `/opt/data/.render-tools-boot.log` en `bootstrap.sh` para diagnosticar (commit `9c05e1c`) — tampoco se creó en el intento candidato, confirma que el patcher no corrió (o no persistió) en esa ventana
- [x] Workaround aplicado: `dashboard.basic_auth` escrito a mano vía Shell en el disco real (`cat >> /opt/data/config.yaml`) antes del siguiente redeploy — como el patcher es insert-only, no lo pisa
- [x] Redeploy → **éxito**: `Detected service running on port 10000`. Dashboard bindea correctamente con el auth-gate satisfecho.
- [x] Confirmar login con usuario/password en el dashboard → **funciona**, pero hay un bug de Hermes v2026.7.1: la raíz redirige a `/auth/login?provider=basic&next=%2F` (flujo OAuth) y crashea con `NotImplementedError` para proveedores password-only. Workaround: entrar directo a `/login`.
- [x] **Incidente de seguridad:** el hash real de `HERMES_DASHBOARD_BASIC_AUTH_HASH` se commiteó por error en `.env.example` (commit `ce493bc`, ya pusheado a un repo público). Password rotada (nuevo hash generado y actualizado en Render + `config.yaml` a mano vía Shell) e historial de git reescrito (squash de `ce493bc`+`904fcd9`) para retirar el secreto del historial antes de un nuevo push. Repo sin colaboradores, así que el force-push no rompe clones ajenos.
- [x] Tab "Provider Login (OAuth)" seguía roto (`Session token not available`) por el mismo motivo: en modo gated (`auth_required`), `__HERMES_SESSION_TOKEN__` no se inyecta a propósito (la SPA usa cookies) y ese flujo concreto de login de proveedor no contempla ese modo — bug/gap de esta versión, no algo configurable. Workaround: login por CLI vía Shell, que no depende del JS del navegador: `hermes portal login` → device-code flow (URL + código), **login correcto**. Auth guardada en `/opt/data/auth.json`.
- [x] Modelo y proveedor configurados automáticamente por `hermes portal login`: `model.provider=nous`, modelo por defecto `google/gemini-3.5-flash`, Tool Gateway habilitado (web search/Firecrawl, imágenes/FAL, STT/Whisper, TTS/OpenAI, browser automation) — todo vía `config.yaml`
- [x] Tab "Status" → confirmado, muestra la conexión a Nous Portal y el gateway operativo
- [x] Conversación de prueba confirmada por el usuario

### 4. Render MCP
- [x] `RENDER_MCP_API_KEY` generada en dashboard.render.com y pegada en el tab Environment de **Render** (no el de Hermes)
- [x] Restart del gateway tras añadir la key
- [x] Confirmado que el MCP server `render` está registrado y habilitado — el tab "Status"/"MCP" del dashboard no lo mostraba (otro bug de UI de esta versión), pero `hermes mcp list` por CLI confirma `render ... all ... ✓ enabled`. El tab MCP del dashboard sí lo mostró tras un reinicio.
- [ ] Probar una tool de solo lectura primero (ej. `mcp_render_list_services` o `mcp_render_get_metrics`)
- [ ] Revisar qué tools quedan expuestas (no hay filtro `tools.include` por defecto en este template — el agente ve el catálogo completo permitido por la key)

**Incidente de capacidad:** el servicio se reinició por exceder el límite de memoria de `plan: starter` (dashboard + gateway + MCP + Tool Gateway de Nous simultáneos). Se decide subir a `plan: standard` (más RAM) — coste mayor, confirmado explícitamente por el usuario. `render.yaml` actualizado; pendiente commit/push y redeploy.

### 5. Seguridad (bloqueante antes de compartir la URL)
- [ ] Restringir acceso al dashboard: bearer token / IP allowlist / Render private service — **posible que ya quede cubierto** por el auth-gate nativo de Hermes ≥v0.16.0 (`dashboard.basic_auth`, ver punto 3); evaluar si basta o si se quiere una capa adicional
- [ ] Confirmar que las API keys no quedan visibles en logs públicos
- [ ] Documentar en README quién tiene acceso y cómo rotar credenciales
- [ ] `RENDER_MCP_API_KEY` es full-access (riesgo aceptado); confirmar rotación periódica programada y acceso a logs para detectar uso anómalo

### 6. Validación final
- [ ] Reinicio del servicio → confirmar que sesión/memoria persiste (disco persistente)
- [ ] Confirmar que el modelo configurado responde tras un redeploy
- [ ] Confirmar que una tool MCP sigue funcionando tras el redeploy

## Fase futura (no ahora)
- Evaluar Tool Gateway de Nous (web search, imágenes, TTS) si el caso de uso lo requiere.
- Evaluar gateway a Telegram/Discord/Slack.

## Riesgos conocidos
- Dashboard sin autenticación propia → mitigar en paso 5 antes de cualquier uso real.
- MCP sin filtro de tools → el agente puede ejecutar cualquier acción que la key permita.
- `RENDER_MCP_API_KEY` full-access (Render no soporta API keys con permisos acotados; scoping solo sería posible generando la key desde una cuenta colaboradora con rol limitado, opción descartada por ahora) → riesgo aceptado explícitamente; mitigar con rotación periódica de la key y revisión de logs de uso, no con filtrado de tools en el agente.
- Cold start / sleep en tier gratuito de Render puede afectar disponibilidad del agente (no aplica con `plan: starter` o superior — solo el tier free duerme por inactividad).
