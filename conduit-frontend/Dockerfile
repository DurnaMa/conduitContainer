FROM node:26.6.0-alpine3.24 AS bilder
WORKDIR /app
COPY ./package.json ./package-lock.json /app/
RUN npm install
COPY . /app/

ARG API_URL=http://localhost:8283/api
RUN echo "export const environment = { apiUrl: '${API_URL}' };" > src/environments/environment.ts

RUN npm run build

FROM nginx:1.31.3-alpine
COPY --from=bilder /app/dist/angular-conduit /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80
