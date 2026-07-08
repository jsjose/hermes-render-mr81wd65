# Backup y recuperación ante desastres

## Qué cubre Render automáticamente

Render toma un snapshot del disco persistente **cada 24h**, retenido
**7 días**, restaurable desde el Dashboard → servicio `hermes` → tab
Disks. Cubre un borrado accidental del disco o corrupción, siempre que
se detecte dentro de esa ventana de una semana. No requiere ninguna
acción nuestra.

Lo que Render **no** cubre: recuperación más allá de 7 días, o una
copia fuera de la cuenta de Render (por si hay un problema a nivel de
cuenta, no solo del disco).

## Backup manual (procedimiento actual)

Para tener una copia fuera del disco de vez en cuando (tras cambios de
configuración importantes, o periódicamente si te acuerdas):

1. Por Shell, como usuario `hermes`:
   ```bash
   su hermes -c "/opt/hermes/.venv/bin/hermes backup -q -o /tmp/hermes-backup.zip"
   ```
   `-q` (quick) incluye solo el estado crítico: config, `state.db`,
   `.env`, auth, cron. Se guarda en `/tmp` a propósito, para no dejarlo
   dentro del disco persistente que estamos intentando respaldar.

2. Sacar el zip del contenedor a tu máquina. Dos opciones:

   **Opción A — SSH real + scp** (más cómodo, sin confirmar si Render
   permite `scp` sobre su SSH; si falla, usar la opción B):
   ```bash
   # una vez, en tu máquina:
   ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519
   # pega la pública en Render → Account Settings → SSH Public Keys
   scp -i ~/.ssh/id_ed25519 srv-xxxxx@ssh-<region>.render.com:/tmp/hermes-backup.zip .
   ```
   (sacar el host/usuario exacto del dropdown "Connect" del servicio en
   Render).

   **Opción B — base64 a través de la Shell web** (garantizado,
   funciona siempre, incómodo para archivos grandes):
   ```bash
   base64 /tmp/hermes-backup.zip
   ```
   Copiar la salida completa y, en tu máquina:
   ```bash
   pbpaste | base64 -d > hermes-backup.zip   # macOS
   # o pegar en un archivo y: base64 -d archivo.b64 > hermes-backup.zip
   ```

3. Borrar el zip temporal del contenedor: `rm /tmp/hermes-backup.zip`.

## Restaurar

```bash
su hermes -c "/opt/hermes/.venv/bin/hermes import --force /ruta/al/hermes-backup.zip"
```

## Pendiente (fase futura)

Automatizar esto (cron dentro de Hermes + subida a un storage externo,
p. ej. S3 o el propio Render object storage si lo hay) — no se hace
ahora por ser un proyecto de un solo operador; se prioriza simplicidad.
Tarea de seguimiento anotada en el kanban de Hermes.
