# PGTool

PGTool is a modular Bash toolkit for PostgreSQL management. The project provides a lightweight plugin-based framework to handle backups, monitoring and administration tasks without external dependencies.

## Directory structure

```
pgtool/
├── bin/              # entrypoints
│   └── pgtool.sh     # main launcher and menu
├── lib/              # reusable libraries
├── modules/          # grouped functionality (backup, monitoring...)
├── plugins/          # optional extensions loaded at startup
├── etc/              # user configuration files
├── backups/          # default backup location
└── logs/             # unified logs
```

See `modules/` and `plugins/` for examples of how to extend the tool. Each plugin defines a `plugin_register` function that returns its metadata and callback.

## Usage

After cloning the repository simply run:

```bash
./bin/pgtool.sh
```

The launcher discovers plugins in the `plugins/` directory and adds them to the menu automatically.

Configuration for backups can be stored in `etc/connections.json` and is parsed by `lib/config.sh` without requiring `jq`.

## Status

This repository contains an initial skeleton. More modules will be added over time for monitoring, user management and maintenance. Contributions are welcome.
