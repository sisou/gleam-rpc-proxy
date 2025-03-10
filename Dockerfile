FROM erlang:27 AS build
COPY --from=ghcr.io/gleam-lang/gleam:v1.9.0-erlang-alpine /bin/gleam /bin/gleam
COPY . /app/
RUN cd /app && gleam export erlang-shipment

FROM erlang:27-alpine
RUN \
  addgroup --system webapp && \
  adduser --system webapp -g webapp
COPY --from=build /app/build/erlang-shipment /app
RUN touch /app/.env
WORKDIR /app
ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["run"]
