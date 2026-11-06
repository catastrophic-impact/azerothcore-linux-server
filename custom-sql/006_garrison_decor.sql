-- Garrison decor: many placed instances per account/location (unlike dc_garrison_object, which is one row per kind).
-- Ids are assigned by the script (MAX(id)+1 at load), so placing never has to wait for the database.
USE acore_characters;
CREATE TABLE IF NOT EXISTS dc_garrison_decor (
  id       INT UNSIGNED NOT NULL,
  account  INT UNSIGNED NOT NULL,
  location INT UNSIGNED NOT NULL,
  kind     VARCHAR(32)  NOT NULL,
  x FLOAT NOT NULL, y FLOAT NOT NULL, z FLOAT NOT NULL, o FLOAT NOT NULL,
  PRIMARY KEY (id),
  KEY idx_owner (account, location)
) ENGINE=InnoDB;
