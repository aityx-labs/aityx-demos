# The multyx index: bin/server.mjs, plain Node with no packages, serving
# www/ (the page) and /api/. Built by k8s/build.sh from the multyx-index/
# folder; multyx-index.Dockerfile.dockerignore lets in only bin/ and www/.
# The image has no other folders beside this one, so on Kubernetes
# INDEX_DEMOS names the demos /api/demos checks, and the *_PORT settings
# say where a browser reaches each one (see k8s/deployment.yaml).
FROM node:22-alpine

WORKDIR /app
# Owned by root and only read: the server writes nothing.
COPY bin/ bin/
COPY www/ www/

# Every interface, so the Service reaches it; the port is the usual one.
ENV INDEX_BIND_HOST=0.0.0.0 \
    INDEX_PORT=9700
EXPOSE 9700
# The node user of the image (uid 1000), not root.
USER node
CMD ["node", "bin/server.mjs"]
