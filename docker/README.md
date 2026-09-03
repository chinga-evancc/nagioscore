Running Nagios Core in Docker
=============================

The `Dockerfile` at the repository root builds Nagios Core from this source
tree and packages it with Apache + PHP (for the web UI/CGIs) and the Debian
`monitoring-plugins` (so the sample config's `check_ping`, `check_http`, etc.
work out of the box).

It is a **Linux** image. On Windows it runs under Docker Desktop with the
WSL 2 (recommended) or Hyper-V backend in *Linux containers* mode, which is
the default.

Build
-----

From the repository root (PowerShell, cmd or a WSL shell):

    docker build -t nagioscore:local .

Run
---

    docker run -d --name nagios -p 8080:80 nagioscore:local

Then open http://localhost:8080/nagios and log in with
`nagiosadmin` / `nagiosadmin`.

Or with Compose (persists config and state in named volumes):

    docker compose up -d --build

Configuration
-------------

| Environment variable           | Default       | Purpose                                              |
|--------------------------------|---------------|------------------------------------------------------|
| `NAGIOS_ADMIN_USER`            | `nagiosadmin` | Web UI user created in `htpasswd.users`              |
| `NAGIOS_ADMIN_PASSWORD`        | `nagiosadmin` | Password for that user                               |
| `NAGIOS_RESET_ADMIN_PASSWORD`  | `false`       | Set to `true` to overwrite an existing htpasswd file |

Volumes:

* `/usr/local/nagios/etc` – configuration (`nagios.cfg`, `objects/*.cfg`, ...).
  Seeded with the sample config on first start if empty.
* `/usr/local/nagios/var` – status, logs, archives, command pipe.

Example with a bind-mounted config directory on Windows:

    docker run -d --name nagios -p 8080:80 `
      -e NAGIOS_ADMIN_PASSWORD=changeme `
      -v C:\nagios\etc:/usr/local/nagios/etc `
      nagioscore:local

Custom plugins can be dropped into `/usr/lib/nagios/plugins` (also reachable
as `/usr/local/nagios/libexec`, which is what `$USER1$` points to).

Useful commands
---------------

    docker logs -f nagios                                   # apache + nagios logs
    docker exec nagios /usr/local/nagios/bin/nagios -v /usr/local/nagios/etc/nagios.cfg
    docker restart nagios                                   # apply config edits

Notes
-----

* Checks such as `check_ping` run inside the container, so "localhost" in the
  sample config refers to the container itself.
* The `HEALTHCHECK` reports healthy once the config validates and the
  `nagios` daemon is running.
