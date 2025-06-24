# PGTool Modular Skeleton

Este repositorio representa el inicio de la migración del script original `pgtool2.sh` hacia una arquitectura modular, extensible y mantenible para la gestión de PostgreSQL.

## 📁 Estructura del proyecto

```
pgtool/
├── bin/              # Scripts principales
│   └── pgtool.sh     # Lanzador principal y cargador de menú
├── lib/              # Bibliotecas reutilizables (colores, log, utils...)
├── modules/          # Módulos organizados por funcionalidad (backup, monitoreo, etc)
├── plugins/          # Plugins opcionales cargados dinámicamente
├── etc/              # Archivos de configuración
├── backups/          # Ruta por defecto para backups
└── logs/             # Archivos de log centralizados
```

## 🚀 Uso

Ejecuta la herramienta desde la raíz del proyecto:

```bash
./bin/pgtool.sh
```

El menú se genera dinámicamente cargando todos los plugins que contengan una función `plugin_register`.

## 🧩 Plugins incluidos

- `ejemplo_hello.sh`: plugin de ejemplo simple.
- `pgpass_manage.sh`: añade y elimina entradas en `.pgpass`.
- `backup_core.sh`: realiza backups físicos/lógicos definidos en `etc/connections.json`.
- `backup_logical.sh`: permite ejecutar backups lógicos en varios formatos (`custom`, `plain`, `directory`, etc).
- `legacy_backup.sh`: ejecuta el antiguo `pgtool2.sh` para compatibilidad.

## ⚙ Configuración

Algunos plugins utilizan `etc/connections.json` para obtener la lista de servidores y credenciales. Este archivo se puede procesar sin `jq`, gracias a funciones internas en `lib/config.sh`.

### Ejemplo de `connections.json`:

```json
[
  {
    "name": "producción",
    "host": "192.168.1.10",
    "port": 5432,
    "user": "postgres",
    "database": "miapp"
  },
  {
    "name": "test",
    "host": "192.168.1.11",
    "port": 5432,
    "user": "pguser",
    "database": "testdb"
  }
]
```

## 🔧 Objetivo

PGTool proporciona una forma flexible y extensible de gestionar entornos PostgreSQL a través de Bash. Su enfoque modular permite añadir nuevas funcionalidades sin romper la base existente.

Este es un proyecto en evolución. Próximamente se incluirán módulos para monitoreo, mantenimiento, gestión de usuarios, alertas, y más.

¡Contribuciones bienvenidas!
