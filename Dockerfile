FROM nginx:1.25-alpine

# Run as non-root user (satisfies OPA security policy)
RUN addgroup -g 1001 appgroup && \
    adduser -u 1001 -G appgroup -s /bin/sh -D appuser && \
    chown -R appuser:appgroup /var/cache/nginx /var/run /var/log/nginx

COPY nginx.conf /etc/nginx/nginx.conf
COPY html/ /usr/share/nginx/html/

USER appuser

EXPOSE 8080

HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost:8080/healthz || exit 1

LABEL org.opencontainers.image.title="web-app" \
      org.opencontainers.image.description="Sample microservice for multi-cluster IDP demo" \
      org.opencontainers.image.source="https://github.com/Dakshayani2005/multi-cluster-platform"
