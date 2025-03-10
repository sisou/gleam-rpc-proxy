FROM ghcr.io/gleam-lang/gleam:v1.9.0-erlang
COPY . /app/
RUN cd /app && gleam build
RUN touch /app/.env
WORKDIR /app
CMD ["gleam", "run"]
