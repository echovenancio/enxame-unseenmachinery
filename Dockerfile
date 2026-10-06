FROM docker.io/library/python:3.13-slim-bookworm AS godot

ENV GODOT_SILENCE_ROOT_WARNING=1
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl unzip libfontconfig1 libx11-6 libxcursor1 libxinerama1 libgl1 libxi6 libxrandr2 \
    && rm -rf /var/lib/apt/lists/*
COPY tools/install_godot.sh /tmp/install_godot.sh
RUN sh /tmp/install_godot.sh && rm /tmp/install_godot.sh

FROM godot AS project
WORKDIR /app
COPY . .
RUN godot --headless --editor --path godot --import

FROM project AS tests
RUN set -eu; for test in simulation ui animation feedback; do \
        godot --headless --path godot --script "res://tests/test_${test}.gd"; \
    done

FROM project AS builder
RUN python3 tools/build.py --engine godot

FROM docker.io/nginxinc/nginx-unprivileged:stable-alpine@sha256:15c994d10d6d78658721c3bcafff14cb281fba2a4bdf9d5ba92c416a472516e3 AS runtime
COPY deploy/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /app/dist/ /usr/share/nginx/html/
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -q -O /dev/null http://127.0.0.1:8080/healthz || exit 1
