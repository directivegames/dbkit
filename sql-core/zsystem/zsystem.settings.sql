
-- *** group starting with "z" is reserved for CORE ***

IF OBJECT_ID('zsystem.settings') IS NULL
BEGIN
  CREATE TABLE zsystem.settings
  (
    [group]        varchar(200)   NOT NULL,
    [key]          varchar(200)   NOT NULL,
    [value]        nvarchar(max)  NOT NULL,
    [description]  nvarchar(max)  NOT NULL,
    defaultValue   nvarchar(max)  NULL,
    critical       bit            NOT NULL  DEFAULT 0,
    allowUpdate    bit            NOT NULL  DEFAULT 0,
    orderID        int            NOT NULL  DEFAULT 0,
    --
    CONSTRAINT settings_PK PRIMARY KEY CLUSTERED ([group], [key])
  )
END
GRANT SELECT ON zsystem.settings TO zzp_server
GO



-- Data
IF NOT EXISTS(SELECT * FROM zsystem.settings WHERE [group] = 'zsystem' AND [key] = 'Product')
  INSERT INTO zsystem.settings ([group], [key], [value], [description], defaultValue, critical)
       VALUES ('zsystem', 'Product', 'CORE', 'The product being developed (CORE, EVE, WOD, ...)', 'CORE', 1)
IF NOT EXISTS(SELECT * FROM zsystem.settings WHERE [group] = 'zsystem' AND [key] = 'Recipients-Updates')
  INSERT INTO zsystem.settings ([group], [key], [value], [description])
       VALUES ('zsystem', 'Recipients-Updates', '', 'Mail recipients for DB update notifications')
IF NOT EXISTS(SELECT * FROM zsystem.settings WHERE [group] = 'zsystem' AND [key] = 'Database')
  INSERT INTO zsystem.settings ([group], [key], [value], [description])
       VALUES ('zsystem', 'Database', '', 'The database being used.  Often useful to know when working on a restored database with a different name.)')
GO
