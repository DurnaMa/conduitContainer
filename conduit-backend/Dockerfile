FROM python:3.5.10-slim-buster AS build
WORKDIR /app

ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1

COPY requirements.txt /app/
RUN pip install --prefix=/install -r requirements.txt

FROM python:3.5.10-slim-buster
WORKDIR /app
COPY --from=build /install /usr/local
COPY . /app/
RUN python manage.py collectstatic --noinput

RUN chmod +x /app/entrypoint.sh
ENTRYPOINT ["/app/entrypoint.sh"]

EXPOSE 80