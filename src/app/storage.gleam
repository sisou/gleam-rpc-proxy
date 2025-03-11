import gleam/dynamic/decode
import gleam/io
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option}
import gleam/pair
import gleam/time/timestamp

import app/config.{type SqliteConfig}

import sqlight

pub fn start(opts: SqliteConfig) -> sqlight.Connection {
  let assert Ok(conn) = sqlight.open(opts.path)

  // Create autoinc table
  let assert Ok(Nil) =
    "CREATE TABLE IF NOT EXISTS autoinc(
      num INTEGER
    );"
    |> sqlight.exec(conn)

  // Check if table is empty
  let assert Ok(count) =
    "SELECT count(*) FROM autoinc;"
    |> sqlight.query(conn, [], {
      use count <- decode.field(0, decode.int)
      decode.success(count)
    })

  // Continue setup only if autoinc table is empty
  case count == [0] {
    True -> {
      io.println("Setting up database tables")

      let assert Ok(Nil) =
        "INSERT INTO autoinc(num) VALUES(1);"
        |> sqlight.exec(conn)

      // Create optimized logs table
      let assert Ok(Nil) =
        "CREATE TABLE IF NOT EXISTS logs(
          timestamp INTEGER NOT NULL,
          autoid INTEGER NOT NULL,
          method TEXT NOT NULL,
          duration INTEGER NOT NULL,
          byte_size INTEGER NOT NULL,
          tokens INTEGER NOT NULL,
          error TEXT,
          PRIMARY KEY(timestamp, autoid)
        ) WITHOUT ROWID;"
        |> sqlight.exec(conn)

      // Create autoinc trigger
      let assert Ok(Nil) =
        "CREATE TRIGGER insert_trigger BEFORE INSERT ON logs BEGIN
          UPDATE autoinc SET num = num + 1;
        END;"
        |> sqlight.exec(conn)
      Nil
    }
    _ -> {
      io.println("Database tables already set up")
      Nil
    }
  }

  conn
}

pub fn insert_log(
  conn conn: sqlight.Connection,
  method method: String,
  duration duration: Int,
  byte_size byte_size: Int,
  tokens tokens: Int,
  error error: Option(String),
) {
  let assert Ok(_) =
    "INSERT INTO logs(timestamp, autoid, method, duration, byte_size, tokens, error)
    VALUES(UNIXEPOCH(), (SELECT num FROM autoinc), ?, ?, ?, ?, ?);"
    |> sqlight.query(
      conn,
      [
        method |> sqlight.text(),
        duration |> sqlight.int(),
        byte_size |> sqlight.int(),
        tokens |> sqlight.int(),
        error |> option.map(sqlight.text) |> option.unwrap(sqlight.null()),
      ],
      decode.dynamic,
    )
  Nil
}

pub fn print_stats(conn conn: sqlight.Connection, hours hours: Int) -> Json {
  let now =
    timestamp.system_time()
    |> timestamp.to_unix_seconds_and_nanoseconds()
    |> pair.first()
  let start = now - { hours * 60 * 60 }

  let assert Ok(rows) =
    "SELECT
      strftime('%F %R:00', timestamp, 'unixepoch') as minute,
      count(*),
      avg(duration), min(duration), max(duration),
      avg(byte_size), min(byte_size), max(byte_size),
      sum(tokens)
    FROM logs
    WHERE timestamp > ?
    GROUP BY minute;"
    |> sqlight.query(conn, [sqlight.int(start)], {
      use time <- decode.field(0, decode.string)
      use count <- decode.field(1, decode.int)
      use avg_duration <- decode.field(2, decode.float)
      use min_duration <- decode.field(3, decode.int)
      use max_duration <- decode.field(4, decode.int)
      use avg_byte_size <- decode.field(5, decode.float)
      use min_byte_size <- decode.field(6, decode.int)
      use max_byte_size <- decode.field(7, decode.int)
      use sum_tokens <- decode.field(8, decode.int)
      decode.success(#(
        time,
        count,
        avg_duration,
        min_duration,
        max_duration,
        avg_byte_size,
        min_byte_size,
        max_byte_size,
        sum_tokens,
      ))
    })

  json.object([
    #("time", json.array(rows |> list.map(fn(row) { row.0 }), json.string)),
    #("count", json.array(rows |> list.map(fn(row) { row.1 }), json.int)),
    #(
      "avg_duration",
      json.array(rows |> list.map(fn(row) { row.2 }), json.float),
    ),
    #("min_duration", json.array(rows |> list.map(fn(row) { row.3 }), json.int)),
    #("max_duration", json.array(rows |> list.map(fn(row) { row.4 }), json.int)),
    #(
      "avg_byte_size",
      json.array(rows |> list.map(fn(row) { row.5 }), json.float),
    ),
    #(
      "min_byte_size",
      json.array(rows |> list.map(fn(row) { row.6 }), json.int),
    ),
    #(
      "max_byte_size",
      json.array(rows |> list.map(fn(row) { row.7 }), json.int),
    ),
    #("sum_tokens", json.array(rows |> list.map(fn(row) { row.8 }), json.int)),
  ])
}
