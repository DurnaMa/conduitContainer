FROM node:26.6.0-alpine3.24 as bilder
WORKDIR /app
COPY ./package.json ./package-lock.json /app/
RUN npm install
COPY . /app/

ARG API_URL=http://localhost:8283/api

RUN npm run build

FROM nginx:1.31.3-alpine
COPY --from=bilder /app/dist /usr/share/nginx/html

EXPOSE 80