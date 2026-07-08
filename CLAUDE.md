# CLAUDE.md — Convenciones del proyecto

## Contexto

Proyecto de infraestructura: despliegue de Hermes Agent (Nous Research) en
Render, conectado a Nous Portal, con Render MCP integrado desde fase 1.
Repo: hermes-render-mr81wd65 (fork de render-examples/hermes-render).

## Archivos y formatos

- Planes de implementación: `plans/*.md` (uno por hito/fase, nombre descriptivo en kebab-case).
- Configuración de Hermes: `config.yaml` (no versionar credenciales; usar env vars).
- Infra as code: `render.yaml` en la raíz del repo.
- Documentación operativa (runbooks, rotación de credenciales, accesos): `docs/`.
- Secretos: nunca en el repo. Solo en el tab "Environment" de Render o en un gestor de secretos local.

## Lenguaje por defecto

- Python para cualquier script auxiliar (health checks, utilidades de deploy, validaciones).
- Go o C++ solo si hay una razón explícita de rendimiento o si el componente ya está en ese lenguaje.

## Convenciones de código

- Scripts Python: tipado (`typing`), `black` + `ruff` para formato/lint, sin dependencias innecesarias.
- Nombres de variables de entorno: `MAYUSCULAS_CON_GUION_BAJO`, prefijadas por servicio si aplica (`HERMES_`, `RENDER_`, `NOUS_`).
- Commits: mensajes en imperativo, un cambio lógico por commit.

## TDD

- Todo script o utilidad con lógica no trivial (parsing, validación de config, health checks) se desarrolla test-first:
  1. Escribir el test que falla.
  2. Implementar lo mínimo para pasarlo.
  3. Refactorizar.
- Framework: `pytest`.
- Los tests de infraestructura (¿responde el dashboard?, ¿persiste el disco?) se documentan como checklist manual en `plans/` hasta que existan health checks automatizados; entonces migran a `tests/`.

## Seguridad (no negociable)

- El dashboard de Hermes no tiene autenticación propia → siempre debe ir detrás de un control de acceso (bearer token / IP allowlist / private service) antes de cualquier uso más allá de pruebas locales del propio equipo.
- Ninguna API key (Nous, Render, etc.) se comitea ni se pega en texto plano en documentación compartida.
- `RENDER_MCP_API_KEY` es full-access: Render no soporta API keys con permisos acotados (la key hereda el rol completo del usuario que la genera; el único scoping real posible sería generarla desde una cuenta colaboradora con rol limitado, descartado por ahora). Riesgo aceptado explícitamente — mitigar con rotación periódica y revisión de logs, no asumir que la key está acotada. El template tampoco filtra qué tools MCP puede usar el agente.
- Toda tool MCP nueva se prueba primero en modo lectura (list/get) antes de habilitar acciones destructivas o de escritura.

## Operación vía Shell de Render

- Render conecta la Shell como `root`. Cualquier comando `hermes ...` ejecutado a mano ahí debe correr como el usuario `hermes` (`su hermes -c "hermes ..."` o equivalente), nunca directamente como root — si no, deja archivos root-owned en `/opt/data` (disco persistente) que el proceso del gateway (que sí corre como `hermes`) no puede leer/escribir, y el agente falla al arrancar con `Permission denied`. Ya pasó con `/opt/data/shared/` tras un `hermes portal login` corrido como root.
- Tras cualquier intervención manual en el disco vía Shell, verificar dueño/permisos con `ls -la` antes de dar por bueno un redeploy.

## render.yaml

- `region` siempre en minúsculas (`frankfurt`, `oregon`, etc.) — el schema de Render lo exige.
- Cualquier cambio de `plan` (coste) se documenta en el PR y se confirma explícitamente, no se asume.
- Antes de fijar `healthCheckPath` o `disk.mountPath`, verificar contra el `Dockerfile` que el endpoint/env var (`HERMES_HOME`) coinciden realmente.

## Estado del proyecto

- Fase 1 (actual): deploy con Render MCP integrado desde el inicio. Ver `plans/hermes-deployment-plan.md`.
- Fase futura: evaluar Tool Gateway de Nous (web search, imágenes, TTS) y gateways de chat (Telegram/Discord/Slack).
