# PGTool Modular Skeleton

Este repositorio representa el inicio de la migración del script original `pgtool2.sh` hacia una arquitectura modular y extensible.

## 📁 Estructura

- `bin/pgtool.sh` – Punto de entrada principal y cargador del menú.
- `lib/` – Bibliotecas reutilizables:
  - `colors.sh`: estilos y colores para el terminal.
  - `log.sh`: logging uniforme.
  - `utils.sh`: utilidades generales.
  - `pgpass.sh`: gestión de credenciales `.pgpass`.
  - `menu.sh`: sistema de menús interactivos.
  - `config.sh`: (opcional) para leer configuraciones como `etc/connections.json`.
- `plugins/` – Extensiones cargadas dinámicamente. Incluye ejemplos como:
  - `ejemplo_hello.sh`: plugin de ejemplo básico.
  - `pgpass_manage.sh`: gestión de entradas en `.pgpass`.
  - `backup_core.sh`: backups automáticos según `etc/connections.json`.
  - `backup_logical.sh`: módulo de backup lógico con soporte extendido.
  - `legacy_backup.sh`: lanza el antiguo `pgtool2.sh`.

## 🚀 Uso

Ejecuta la herramienta desde la raíz del proyecto:

```bash
./bin/pgtool.sh
