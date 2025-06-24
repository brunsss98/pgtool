# PGTool Modular Skeleton

This repository starts the migration of the original `pgtool2.sh` script into a
modular architecture.

## Structure

- `bin/pgtool.sh` – main entry point and menu loader.
- `lib/` – reusable libraries (`colors.sh`, `log.sh`, `utils.sh`).
- `plugins/` – dynamically loaded extensions.

## Usage

Run the tool via:

```bash
./bin/pgtool.sh
```

Plugins placed under `plugins/` with a `plugin_register` function are loaded
automatically. An example plugin is provided in `plugins/ejemplo_hello.sh`.
