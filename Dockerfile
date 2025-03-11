FROM ghcr.io/gleam-lang/gleam:v1.9.0-erlang
RUN apt-get update && \
    apt-get --no-install-recommends -y install sqlite3 && \
    rm -rf /var/lib/apt/lists/*
COPY . /app/
RUN cd /app && gleam build
RUN touch /app/.env
WORKDIR /app
CMD ["gleam", "run"]
