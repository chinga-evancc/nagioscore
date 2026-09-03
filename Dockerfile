# Nagios Core built from this source tree, served by Apache + PHP.
#
# Build:  docker build -t nagioscore:local .
# Run:    docker run -d --name nagios -p 8080:80 nagioscore:local
# Web UI: http://localhost:8080/nagios  (default login: nagiosadmin / nagiosadmin)
#
# This is a Linux (Debian-based) image; on Windows it runs under Docker Desktop
# with the WSL 2 or Hyper-V backend (Linux containers mode).

ARG DEBIAN_VERSION=bookworm

# ---------------------------------------------------------------------------
# Stage 1: compile Nagios Core
# ---------------------------------------------------------------------------
FROM debian:${DEBIAN_VERSION}-slim AS build

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential autoconf automake gcc libc6-dev make \
        libgd-dev libssl-dev zlib1g-dev libpng-dev libjpeg-dev \
        unzip wget ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd -r nagios \
    && useradd -r -g nagios -d /usr/local/nagios -s /usr/sbin/nologin nagios \
    && groupadd -r nagcmd \
    && usermod -a -G nagcmd nagios

WORKDIR /src
COPY . .

# A checkout made on Windows may have CRLF line endings and no exec bits,
# which breaks every shell script ("./configure: not found"). Normalise the
# tree before building so the image builds identically on any host OS.
RUN grep -rlI --exclude-dir=images "$(printf '\r')" . | xargs -r sed -i 's/\r$//' \
    && chmod +x configure config.guess config.sub install-sh tap/install-sh \
        autoconf-macros/* indent.sh indent-all.sh update-version make-tarball mkpackage

RUN mkdir -p /etc/apache2/sites-available /etc/apache2/sites-enabled \
    && sh ./configure \
        --prefix=/usr/local/nagios \
        --with-nagios-user=nagios \
        --with-nagios-group=nagios \
        --with-command-user=nagios \
        --with-command-group=nagcmd \
        --with-httpd-conf=/etc/apache2/sites-available \
    && make -j"$(nproc)" all \
    && make install \
    && make install-commandmode \
    && make install-config \
    && make install-webconf

# ---------------------------------------------------------------------------
# Stage 2: runtime image
# ---------------------------------------------------------------------------
FROM debian:${DEBIAN_VERSION}-slim AS runtime

LABEL org.opencontainers.image.title="Nagios Core" \
      org.opencontainers.image.source="https://github.com/chinga-evancc/nagioscore" \
      org.opencontainers.image.licenses="GPL-2.0"

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        apache2 libapache2-mod-php php php-gd apache2-utils \
        libgd3 libssl3 zlib1g \
        monitoring-plugins-basic monitoring-plugins-standard \
        iputils-ping procps tini \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd -r nagios \
    && useradd -r -g nagios -d /usr/local/nagios -s /usr/sbin/nologin nagios \
    && groupadd -r nagcmd \
    && usermod -a -G nagcmd nagios \
    && usermod -a -G nagcmd www-data \
    && a2enmod cgi rewrite \
    && a2dissite 000-default \
    && ln -sf /dev/stdout /var/log/apache2/access.log \
    && ln -sf /dev/stderr /var/log/apache2/error.log

COPY --from=build /usr/local/nagios /usr/local/nagios
COPY --from=build /etc/apache2/sites-available/nagios.conf /etc/apache2/sites-available/nagios.conf
# Debian ships the plugins in /usr/lib/nagios/plugins; the sample config
# expects $USER1$ = /usr/local/nagios/libexec.
RUN rmdir /usr/local/nagios/libexec \
    && ln -s /usr/lib/nagios/plugins /usr/local/nagios/libexec \
    && a2ensite nagios \
    # Keep a pristine copy of the default config so the entrypoint can seed an
    # empty /usr/local/nagios/etc volume on first start.
    && cp -a /usr/local/nagios/etc /usr/local/nagios/etc.default \
    && chown -R nagios:nagios /usr/local/nagios \
    && chown -R nagios:nagcmd /usr/local/nagios/var/rw \
    && chmod 2775 /usr/local/nagios/var/rw

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN sed -i 's/\r$//' /usr/local/bin/entrypoint.sh && chmod +x /usr/local/bin/entrypoint.sh

ENV NAGIOS_ADMIN_USER=nagiosadmin \
    NAGIOS_ADMIN_PASSWORD=nagiosadmin \
    APACHE_RUN_USER=www-data \
    APACHE_RUN_GROUP=www-data \
    APACHE_PID_FILE=/var/run/apache2/apache2.pid \
    APACHE_RUN_DIR=/var/run/apache2 \
    APACHE_LOCK_DIR=/var/lock/apache2 \
    APACHE_LOG_DIR=/var/log/apache2

VOLUME ["/usr/local/nagios/etc", "/usr/local/nagios/var"]
EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD /usr/local/nagios/bin/nagios -v /usr/local/nagios/etc/nagios.cfg >/dev/null 2>&1 \
        && pgrep -x nagios >/dev/null || exit 1

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
