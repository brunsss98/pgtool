# PGTool Modular Skeleton

This repository starts the migration of the original `pgtool2.sh` script into a modular architecture.

## Structure

- `bin/pgtool.sh` – main entry point and menu loader.
- `lib/` – reusable libraries (`colors.sh`, `log.sh`, `utils.sh`, `pgpass.sh`,
  `menu.sh`).
- `plugins/` – dynamically loaded extensions. Includes a sample `ejemplo_hello.sh`
  and a `.pgpass` management plugin. The `backup_core` plugin runs backups based
  on `etc/connections.json`.

## Usage

Run the tool via:

```bash
./bin/pgtool.sh
```

Plugins placed under `plugins/` with a `plugin_register` function are loaded automatically. Sample plugins are provided in `plugins/ejemplo_hello.sh` and `plugins/pgpass_manage.sh`.

Backups can be triggered from the `backup_core` plugin, which reads connection
information from `etc/connections.json` using `lib/config.sh`.

An additional plugin `plugins/backup_logical.sh` demonstrates how to call the
new logical backup module under `modules/backup/`.

A legacy backup menu is available via the `legacy_backup` plugin, which simply runs the original `pgtool2.sh` script. Place `pgtool2.sh` at the project root (already provided) and choose **Legacy Backup Menu** from the main launcher.
