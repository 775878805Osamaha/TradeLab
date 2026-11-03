FROM node:22-alpine
WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev --ignore-scripts --no-audit --no-fund && npm cache clean --force
COPY security.mjs ctrader.mjs server.mjs ./
ENV NODE_ENV=production
EXPOSE 8080
USER node
CMD ["node", "server.mjs"]
