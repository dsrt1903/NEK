FROM node:24-alpine
WORKDIR /app
COPY --chown=node:node package.json ./
COPY --chown=node:node src/server ./src/server
RUN mkdir /data && chown node:node /data
ENV HOST=0.0.0.0 PORT=8080 DB_PATH=/data/nek.sqlite
USER node
EXPOSE 8080
CMD ["node", "src/server/main.js"]
