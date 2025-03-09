-- SETUP

CREATE TABLE IF NOT EXISTS autoinc(
    num INTEGER
);

SELECT count(*) FROM autoinc;

INSERT INTO autoinc(num) VALUES(0);

CREATE TABLE IF NOT EXISTS logs(
    timestamp INTEGER NOT NULL,
    autoid INTEGER NOT NULL,
    method TEXT NOT NULL,
    duration INTEGER NOT NULL,
    byte_size INTEGER NOT NULL,
    tokens INTEGER NOT NULL,
    error TEXT,
    PRIMARY KEY(timestamp, autoid)
) WITHOUT ROWID;

CREATE TRIGGER insert_trigger BEFORE INSERT ON logs BEGIN
    UPDATE autoinc SET num = num + 1;
END;

-- INSERT

INSERT INTO logs(timestamp, autoid, method, ...) VALUES (UNIXEPOCH(), (SELECT num FROM autoinc), ?, ...);
