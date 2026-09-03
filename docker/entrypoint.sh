#!/bin/sh
# Starts Apache (web UI/CGIs) and the Nagios daemon in the foreground.
set -eu

NAGIOS_HOME=/usr/local/nagios
ETC="$NAGIOS_HOME/etc"
VAR="$NAGIOS_HOME/var"

# Seed the config volume on first start (an empty bind mount / named volume).
if [ ! -f "$ETC/nagios.cfg" ]; then
    echo "[entrypoint] seeding default configuration into $ETC"
    cp -a "$NAGIOS_HOME/etc.default/." "$ETC/"
fi

mkdir -p "$VAR/rw" "$VAR/archives" "$VAR/spool/checkresults"
chown -R nagios:nagios "$ETC" "$VAR"
chown nagios:nagcmd "$VAR/rw"
chmod 2775 "$VAR/rw"

# Create/refresh the web UI user unless an htpasswd file is already managed by the user.
if [ ! -f "$ETC/htpasswd.users" ] || [ "${NAGIOS_RESET_ADMIN_PASSWORD:-false}" = "true" ]; then
    echo "[entrypoint] creating web user '$NAGIOS_ADMIN_USER'"
    htpasswd -cbB "$ETC/htpasswd.users" "$NAGIOS_ADMIN_USER" "$NAGIOS_ADMIN_PASSWORD"
    chown nagios:nagios "$ETC/htpasswd.users"
fi

# Nagios runs as 'nagios' but writes to the CGI-facing command pipe/status
# files; make sure the sample config grants the configured admin user access.
if [ "$NAGIOS_ADMIN_USER" != "nagiosadmin" ] && grep -q "nagiosadmin" "$ETC/cgi.cfg"; then
    sed -i "s/nagiosadmin/$NAGIOS_ADMIN_USER/g" "$ETC/cgi.cfg"
    sed -i "s/nagiosadmin/$NAGIOS_ADMIN_USER/g" "$ETC/objects/contacts.cfg"
fi

echo "[entrypoint] verifying configuration"
"$NAGIOS_HOME/bin/nagios" -v "$ETC/nagios.cfg"

rm -f "$APACHE_PID_FILE" "$VAR/nagios.lock"
mkdir -p "$APACHE_RUN_DIR" "$APACHE_LOCK_DIR"

term() {
    echo "[entrypoint] shutting down"
    kill -TERM "$NAGIOS_PID" 2>/dev/null || true
    apache2ctl -k graceful-stop 2>/dev/null || true
    wait "$NAGIOS_PID" 2>/dev/null || true
    exit 0
}
trap term TERM INT

echo "[entrypoint] starting apache"
apache2ctl -DFOREGROUND &
APACHE_PID=$!

echo "[entrypoint] starting nagios"
"$NAGIOS_HOME/bin/nagios" "$ETC/nagios.cfg" &
NAGIOS_PID=$!

# Exit if either process dies so the container restarts.
while kill -0 "$APACHE_PID" 2>/dev/null && kill -0 "$NAGIOS_PID" 2>/dev/null; do
    sleep 5
done
echo "[entrypoint] a service exited; stopping container"
term
