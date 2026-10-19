FROM node:24.21.0-alpine3.23

WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

COPY server.mjs ipv4-dns.cjs ./
ENV PORT=8080
EXPOSE 8080
USER node
CMD ["node", "server.mjs"]
