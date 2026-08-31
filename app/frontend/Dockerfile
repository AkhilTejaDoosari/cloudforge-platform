# Single stage: the frontend has no build step (no npm/bundler), so a
# multi-stage build wouldn't discard anything — it would just add complexity.
# nginx-unprivileged (vs. plain nginx) runs as a non-root user out of the box
# and listens on port 8080 instead of 80, which requires no capability grant.
FROM nginxinc/nginx-unprivileged:1.27-alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY index.html style.css app.js /usr/share/nginx/html/
# Overwrite the local-dev config.js with the Docker-networking variant.
COPY config.docker.js /usr/share/nginx/html/config.js

EXPOSE 8080

# nginx:alpine's busybox provides wget; no need to install curl.
# Use 127.0.0.1, not localhost: this image only binds IPv4, but /etc/hosts
# resolves "localhost" to ::1 first and busybox wget won't fall back to IPv4.
HEALTHCHECK --interval=10s --timeout=5s --start-period=5s --retries=5 \
    CMD wget --spider -q http://127.0.0.1:8080/ || exit 1
