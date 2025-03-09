import gleam/dynamic/decode
import gleam/io
import gleam/option.{type Option}

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
