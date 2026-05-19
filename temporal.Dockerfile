# ABOUTME: Temporal dev server image with the temporal-ts-net CLI extension baked in.
# Exposes the dev server on the local Docker network and on the configured Tailnet.

FROM temporalio/temporal:latest

USER root
RUN apk add --no-cache curl \
    && curl -sSfL https://raw.githubusercontent.com/temporal-community/temporal-ts-net/main/install.sh | sh

VOLUME ["/data", "/var/lib/tailscale"]
ENTRYPOINT ["temporal", "ts-net"]
CMD ["--ip", "0.0.0.0", "--db-filename", "/data/temporal.db"]
