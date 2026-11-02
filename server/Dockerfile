FROM node:22-slim

WORKDIR /app
COPY package.json app.js db.js index.js import-votes.js ./

ENV NODE_ENV=production \
    DB_PATH=/data/votes.db

# O volume nomeado herda o dono desta pasta na primeira criacao.
RUN mkdir -p /data && chown node:node /data
USER node

EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
  CMD node -e "fetch('http://127.0.0.1:3000/api/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["node", "--disable-warning=ExperimentalWarning", "index.js"]
