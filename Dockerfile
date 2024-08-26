FROM node:18-alpine
WORKDIR /usr/src/app
COPY package*.json ./
RUN npm install --production
COPY . .
ENV NODE_ENV=production
EXPOSE 8000
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser
CMD ["node", "index.js"]
