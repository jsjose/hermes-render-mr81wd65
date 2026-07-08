# Acceso y rotación de credenciales

## Quién tiene acceso

- Operador único: Chema (josem.sanjose@gmail.com). Sin colaboradores en el
  repo de GitHub (`jsjose/hermes-render-mr81wd65`, público) ni en el
  workspace de Render.
- Acceso al dashboard de Hermes: protegido con `basic_auth` nativo
  (usuario + password, hash scrypt) desde Hermes ≥v0.16.0. Sin esa
  credencial no se puede ni ver el login — no hay bind público sin auth.
- Acceso a Render: cuenta owner de Chema. `RENDER_MCP_API_KEY` se generó
  desde esa misma cuenta (full-access; ver "Riesgos conocidos" en
  `hermes-deployment-plan.md` — Render no soporta API keys con permisos
  acotados salvo generándolas desde un usuario colaborador con rol
  limitado, opción descartada por ahora al ser un proyecto de una sola
  persona).

## Rotación: password del dashboard (`basic_auth`)

1. Generar un hash nuevo (requiere Docker local; en esta máquina hace
   falta `sudo`):
   ```bash
   sudo docker run --rm --entrypoint python docker.io/nousresearch/hermes-agent:<tag> \
     -c "from plugins.dashboard_auth.basic import hash_password; print(hash_password('NUEVA_PASSWORD'))"
   ```
   `<tag>` debe coincidir con el `HERMES_IMAGE` pineado en el `Dockerfile`.
2. Actualizar `HERMES_DASHBOARD_BASIC_AUTH_HASH` en Render → tab
   Environment del servicio `hermes`.
3. El patcher de arranque (`scripts/patch-config.py`) es *insert-only*:
   si `dashboard.basic_auth` ya existe en `config.yaml`, no lo toca. Hay
   que editar el hash a mano en el disco vía Shell de Render:
   ```bash
   read -r NEWHASH
   sed -i "s#password_hash:.*#password_hash: '${NEWHASH}'#" /opt/data/config.yaml
   ```
   (ejecutar como el usuario `hermes`, no como root — ver
   `CLAUDE.md` § Operación vía Shell de Render).
4. Reiniciar el gateway (Status tab → Restart, o redeploy) para que
   recargue `config.yaml`.
5. Entrar por `<url>/login` (no la raíz — bug conocido de esta versión,
   ver `hermes-deployment-plan.md` punto 3) y confirmar el login nuevo.

## Rotación: `RENDER_MCP_API_KEY`

1. Generar una key nueva en `dashboard.render.com/u/*/settings#api-keys`.
2. Actualizar `RENDER_MCP_API_KEY` en Render → tab Environment del
   servicio `hermes` (no en el tab "API Keys" del dashboard de Hermes —
   `config.yaml` la lee del entorno del proceso gateway).
3. Restart del gateway (Status tab) para que la tome.
4. Revocar/eliminar la key vieja en Render una vez confirmado que la
   nueva funciona (`hermes mcp list` debe mostrar `render ... enabled`).
5. **Cadencia recomendada:** cada 90 días, o inmediatamente si se
   sospecha exposición (p. ej. un commit accidental — ver el incidente
   ya ocurrido con el hash de `basic_auth` en `hermes-deployment-plan.md`
   punto 3).

## Rotación: autenticación de Nous Portal

1. Por Shell, como usuario `hermes` (no root):
   ```bash
   su hermes -c "/opt/hermes/.venv/bin/hermes auth logout nous"
   su hermes -c "/opt/hermes/.venv/bin/hermes portal login"
   ```
2. Seguir el flujo device-code (URL + código) igual que el login inicial.

## Revisión de logs

- Hermes redacta secretos por defecto (`security.redact_secrets: true`
  es el default aunque aparezca comentado en `config.yaml`) — strings
  con pinta de API key/token/password se enmascaran en logs, salida de
  tools y respuestas del chat.
- Aun así, revisar periódicamente los logs de Render (tab Logs) por:
  - Intentos de login fallidos repetidos en el dashboard.
  - Llamadas a tools MCP de Render inesperadas (la key es full-access;
    cualquier tool que la key permita es invocable por el agente).
- No se ha detectado ningún secreto en texto plano en los logs
  revisados durante el despliegue inicial.
