
EXEC zsystem.Versions_Start 'CORE', 0002, 'jorundur'
GO



---------------------------------------------------------------------------------------------------------------------------------


IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'zzp_server')
  CREATE ROLE zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF SCHEMA_ID('zutil') IS NULL
  EXEC sp_executesql N'CREATE SCHEMA zutil'
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zutil.DateDay') IS NOT NULL
  DROP FUNCTION zutil.DateDay
GO
CREATE FUNCTION zutil.DateDay(@dt datetime2(0))
RETURNS date
BEGIN
  RETURN CONVERT(date, @dt)
END
GO
GRANT EXEC ON zutil.DateDay TO public
GRANT EXEC ON zutil.DateDay TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zutil.DateWeek') IS NOT NULL
  DROP FUNCTION zutil.DateWeek
GO
CREATE FUNCTION zutil.DateWeek(@dt datetime2(0))
RETURNS date
BEGIN
  -- SQL Server says sunday is the first day of the week but the CCP week starts on monday
  SET @dt = CONVERT(date, @dt)
  DECLARE @weekday int = DATEPART(weekday, @dt)
  IF @weekday = 1
    SET @dt = DATEADD(day, -6, @dt)
  ELSE IF @weekday > 2
    SET @dt = DATEADD(day, -(@weekday - 2), @dt)
  RETURN @dt
END
GO
GRANT EXEC ON zutil.DateWeek TO public
GRANT EXEC ON zutil.DateWeek TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zutil.DateMonth') IS NOT NULL
  DROP FUNCTION zutil.DateMonth
GO
CREATE FUNCTION zutil.DateMonth(@dt datetime2(0))
RETURNS date
BEGIN
  SET @dt = CONVERT(date, @dt)
  RETURN DATEADD(day, 1 - DATEPART(day, @dt), @dt)
END
GO
GRANT EXEC ON zutil.DateMonth TO public
GRANT EXEC ON zutil.DateMonth TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zutil.DateYear') IS NOT NULL
  DROP FUNCTION zutil.DateYear
GO
CREATE FUNCTION zutil.DateYear(@dt datetime2(0))
RETURNS date
BEGIN
  SET @dt = CONVERT(date, @dt)
  RETURN DATEADD(day, 1 - DATEPART(dayofyear, @dt), @dt)
END
GO
GRANT EXEC ON zutil.DateYear TO public
GRANT EXEC ON zutil.DateYear TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.texts') IS NULL
BEGIN
  CREATE TABLE zsystem.texts
  (
    textID  int                                          NOT NULL  IDENTITY(1, 1),
    [text]  nvarchar(450)  COLLATE Latin1_General_CI_AI  NOT NULL,
    --
    CONSTRAINT texts_PK PRIMARY KEY CLUSTERED (textID)
  )

  CREATE UNIQUE NONCLUSTERED INDEX texts_IX_Text ON zsystem.texts ([text])
END
GRANT SELECT ON zsystem.texts TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.Texts_ID') IS NOT NULL
  DROP PROCEDURE zsystem.Texts_ID
GO
CREATE PROCEDURE zsystem.Texts_ID
  @text  nvarchar(450)
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  IF @text IS NULL
    RETURN 0

  DECLARE @textID int
  SELECT @textID = textID FROM zsystem.texts WHERE [text] = @text
  IF @textID IS NULL
  BEGIN
    INSERT INTO zsystem.texts ([text]) VALUES (@text)
    SET @textID = SCOPE_IDENTITY()
  END
  RETURN @textID
GO
GRANT EXEC ON zsystem.Texts_ID TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


-- *** lookupTableID from 2000000000 and up is reserved for CORE ***

IF OBJECT_ID('zsystem.lookupTables') IS NULL
BEGIN
  CREATE TABLE zsystem.lookupTables
  (
    lookupTableID             int                                          NOT NULL,
    lookupTableName           nvarchar(200)                                NOT NULL,
    [description]             nvarchar(max)                                NULL,
    --
    schemaID                  int                                          NULL, -- Link lookup table to a schema, just info
    tableID                   int                                          NULL, -- Link lookup table to a table, just info
    [source]                  nvarchar(200)                                NULL, -- Description of data source, f.e. table name
    lookupID                  nvarchar(200)                                NULL, -- Description of lookupID column
    parentID                  nvarchar(200)                                NULL, -- Description of parentID column
    parentLookupTableID       int                                          NULL,
    link                      nvarchar(500)                                NULL, -- If a link to a web page is needed
    lookupTableIdentifier     varchar(500)   COLLATE Latin1_General_CI_AI  NOT NULL, -- Identifier to use in code to make it readable and usable in other Metrics webs
    hidden                    bit                                          NOT NULL  DEFAULT 0,
    obsolete                  bit                                          NOT NULL  DEFAULT 0,
    sourceForID               varchar(20)                                  NULL, -- EXTERNAL/TEXT/MAX
    label                     nvarchar(200)                                NULL, -- If a label is needed instead of lookup text
    --
    CONSTRAINT lookupTables_PK PRIMARY KEY CLUSTERED (lookupTableID)
  )

  CREATE UNIQUE NONCLUSTERED INDEX lookupTables_UQ_Identifier ON zsystem.lookupTables (lookupTableIdentifier)
END
GRANT SELECT ON zsystem.lookupTables TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.lookupValues') IS NULL
BEGIN
  CREATE TABLE zsystem.lookupValues
  (
    lookupTableID  int                                           NOT NULL,
    lookupID       int                                           NOT NULL,
    lookupText     nvarchar(1000)  COLLATE Latin1_General_CI_AI  NOT NULL,
    [description]  nvarchar(max)                                 NULL,
    parentID       int                                           NULL,
    [fullText]     nvarchar(1000)  COLLATE Latin1_General_CI_AI  NULL,
    --
    CONSTRAINT lookupValues_PK PRIMARY KEY CLUSTERED (lookupTableID, lookupID)
  )
END
GRANT SELECT ON zsystem.lookupValues TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.lookupValuesEx') IS NOT NULL
  DROP VIEW zsystem.lookupValuesEx
GO
CREATE VIEW zsystem.lookupValuesEx
AS
  SELECT V.lookupTableID, T.lookupTableName, V.lookupID, V.lookupText, V.[fullText], V.parentID, V.[description]
    FROM zsystem.lookupValues V
      LEFT JOIN zsystem.lookupTables T ON T.lookupTableID = V.lookupTableID
GO
GRANT SELECT ON zsystem.lookupValuesEx TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.LookupTables_ID') IS NOT NULL
  DROP FUNCTION zsystem.LookupTables_ID
GO
CREATE FUNCTION zsystem.LookupTables_ID(@lookupTableIdentifier varchar(500))
RETURNS int
BEGIN
  DECLARE @lookupTableID int
  SELECT @lookupTableID = lookupTableID FROM zsystem.lookupTables WHERE lookupTableIdentifier = @lookupTableIdentifier
  RETURN @lookupTableID
END
GO
GRANT EXEC ON zsystem.LookupTables_ID TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.LookupTables_Insert') IS NOT NULL
  DROP PROCEDURE zsystem.LookupTables_Insert
GO
CREATE PROCEDURE zsystem.LookupTables_Insert
  @lookupTableID          int = NULL,            -- NULL means MAX-UNDER-2000000000 + 1
  @lookupTableName        nvarchar(200),
  @description            nvarchar(max) = NULL,
  @schemaID               int = NULL,            -- Link lookup table to a schema, just info
  @tableID                int = NULL,            -- Link lookup table to a table, just info
  @source                 nvarchar(200) = NULL,  -- Description of data source, f.e. table name
  @lookupID               nvarchar(200) = NULL,  -- Description of lookupID column
  @parentID               nvarchar(200) = NULL,  -- Description of parentID column
  @parentLookupTableID    int = NULL,
  @link                   nvarchar(500) = NULL,  -- If a link to a web page is needed
  @lookupTableIdentifier  varchar(500) = NULL,
  @sourceForID            varchar(20) = NULL,    -- EXTERNAL/TEXT/MAX
  @label                  nvarchar(200) = NULL   -- If a label is needed instead of lookup text
AS
  SET NOCOUNT ON

  IF @lookupTableID IS NULL
    SELECT @lookupTableID = MAX(lookupTableID) + 1 FROM zsystem.lookupTables WHERE lookupTableID < 2000000000
  IF @lookupTableID IS NULL SET @lookupTableID = 1

  IF @lookupTableIdentifier IS NULL SET @lookupTableIdentifier = @lookupTableID

  INSERT INTO zsystem.lookupTables
              (lookupTableID, lookupTableName, [description], schemaID, tableID, [source], lookupID, parentID, parentLookupTableID,
               link, lookupTableIdentifier, sourceForID, label)
       VALUES (@lookupTableID, @lookupTableName, @description, @schemaID, @tableID, @source, @lookupID, @parentID, @parentLookupTableID,
               @link, @lookupTableIdentifier, @sourceForID, @label)

  SELECT lookupTableID = @lookupTableID
GO
GRANT EXEC ON zsystem.LookupTables_Insert TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zsystem.LookupValues_Update') IS NOT NULL
  DROP PROCEDURE zsystem.LookupValues_Update
GO
CREATE PROCEDURE zsystem.LookupValues_Update
  @lookupTableID  int,
  @lookupID       int, -- If NULL then zsystem.Texts_ID is used
  @lookupText     nvarchar(1000)
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  BEGIN TRY
    IF @lookupID IS NULL
    BEGIN
      IF LEN(@lookupText) > 450
        RAISERROR ('@lookupText must not be over 450 characters if zsystem.Texts_ID is used', 16, 1)
      EXEC @lookupID = zsystem.Texts_ID @lookupText
    END

    IF EXISTS(SELECT * FROM zsystem.lookupValues WHERE lookupTableID = @lookupTableID AND lookupID = @lookupID)
      UPDATE zsystem.lookupValues SET lookupText = @lookupText WHERE lookupTableID = @lookupTableID AND lookupID = @lookupID AND lookupText != @lookupText
    ELSE
      INSERT INTO zsystem.lookupValues (lookupTableID, lookupID, lookupText) VALUES (@lookupTableID, @lookupID, @lookupText)

    RETURN @lookupID
  END TRY
  BEGIN CATCH
    EXEC zsystem.CatchError 'zsystem.LookupValues_Update'
    RETURN -1
  END CATCH
GO
GRANT EXEC ON zsystem.LookupValues_Update TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF SCHEMA_ID('zmetric') IS NULL
  EXEC sp_executesql N'CREATE SCHEMA zmetric'
GO


---------------------------------------------------------------------------------------------------------------------------------


-- Settings
IF NOT EXISTS(SELECT * FROM zsystem.settings WHERE [group] = 'zmetric' AND [key] = 'Recipients-IndexStats')
  INSERT INTO zsystem.settings ([group], [key], value, [description])
       VALUES ('zmetric', 'Recipients-IndexStats', '', 'Mail recipients for Index Stats notifications')
IF NOT EXISTS(SELECT * FROM zsystem.settings WHERE [group] = 'zmetric' AND [key] = 'SaveIndexStats')
  INSERT INTO zsystem.settings ([group], [key], value, defaultValue, [description])
       VALUES ('zmetric', 'SaveIndexStats', '0', '0', 'Save index stats daily to zmetric.keyCounters (set to "1" to activate).')
IF NOT EXISTS(SELECT * FROM zsystem.settings WHERE [group] = 'zmetric' AND [key] = 'SaveFileStats')
  INSERT INTO zsystem.settings ([group], [key], value, defaultValue, [description])
       VALUES ('zmetric', 'SaveFileStats', '0', '0', 'Save file stats daily to zmetric.keyCounters (set to "1" to activate).  Note that file stats are saved for server so only one database needs to save file stats.')
IF NOT EXISTS(SELECT * FROM zsystem.settings WHERE [group] = 'zmetric' AND [key] = 'SaveWaitStats')
  INSERT INTO zsystem.settings ([group], [key], value, defaultValue, [description])
       VALUES ('zmetric', 'SaveWaitStats', '0', '0', 'Save wait stats daily to zmetric.keyCounters (set to "1" to activate).  Note that waits stats are saved for server so only one database needs to save wait stats.')
IF NOT EXISTS(SELECT * FROM zsystem.settings WHERE [group] = 'zmetric' AND [key] = 'SaveProcStats')
  INSERT INTO zsystem.settings ([group], [key], value, defaultValue, [description])
       VALUES ('zmetric', 'SaveProcStats', '0', '0', 'Save proc stats daily to zmetric.keyCounters (set to "1" to activate).')
IF NOT EXISTS(SELECT * FROM zsystem.settings WHERE [group] = 'zmetric' AND [key] = 'SavePerfCountersTotal')
  INSERT INTO zsystem.settings ([group], [key], value, defaultValue, [description])
       VALUES ('zmetric', 'SavePerfCountersTotal', '0', '0', 'Save total performance counters daily to zmetric.keyCounters (set to "1" to activate).')
IF NOT EXISTS(SELECT * FROM zsystem.settings WHERE [group] = 'zmetric' AND [key] = 'SavePerfCountersInstance')
  INSERT INTO zsystem.settings ([group], [key], value, defaultValue, [description])
       VALUES ('zmetric', 'SavePerfCountersInstance', '0', '0', 'Save instance performance counters daily to zmetric.keyCounters (set to "1" to activate).')
IF NOT EXISTS(SELECT * FROM zsystem.settings WHERE [group] = 'zmetric' AND [key] = 'AutoDeleteMaxRows')
  INSERT INTO zsystem.settings ([group], [key], value, defaultValue, [description])
       VALUES ('zmetric', 'AutoDeleteMaxRows', '50000', '50000', 'Max rows to delete when zmetric.counters.autoDeleteMaxDays (set to "0" to disable).  See proc zmetric.Counters_SaveStats.')
GO

-- Lookup tables
IF NOT EXISTS(SELECT * FROM zsystem.lookupTables WHERE lookupTableID = 2000000001)
  INSERT INTO zsystem.lookupTables (lookupTableID, lookupTableIdentifier, lookupTableName)
       VALUES (2000000001, 'core.db.procs', 'DB - Procs')
IF NOT EXISTS(SELECT * FROM zsystem.lookupTables WHERE lookupTableID = 2000000005)
  INSERT INTO zsystem.lookupTables (lookupTableID, lookupTableIdentifier, lookupTableName)
       VALUES (2000000005, 'core.db.indexes', 'DB - Indexes')
IF NOT EXISTS(SELECT * FROM zsystem.lookupTables WHERE lookupTableID = 2000000006)
  INSERT INTO zsystem.lookupTables (lookupTableID, lookupTableIdentifier, lookupTableName)
       VALUES (2000000006, 'core.db.tables', 'DB - Tables')
IF NOT EXISTS(SELECT * FROM zsystem.lookupTables WHERE lookupTableID = 2000000007)
  INSERT INTO zsystem.lookupTables (lookupTableID, lookupTableIdentifier, lookupTableName)
       VALUES (2000000007, 'core.db.filegroups', 'DB - Filegroups')
IF NOT EXISTS(SELECT * FROM zsystem.lookupTables WHERE lookupTableID = 2000000008)
  INSERT INTO zsystem.lookupTables (lookupTableID, lookupTableIdentifier, lookupTableName)
       VALUES (2000000008, 'core.db.waitTypes', 'DB - Wait types')
IF NOT EXISTS(SELECT * FROM zsystem.lookupTables WHERE lookupTableID = 2000000009)
  INSERT INTO zsystem.lookupTables (lookupTableID, lookupTableIdentifier, lookupTableName)
       VALUES (2000000009, 'core.db.perfCounters', 'DB - Performance counters')
GO


---------------------------------------------------------------------------------------------------------------------------------


-- *** groupID from 30000 and up is reserved for CORE ***

IF OBJECT_ID('zmetric.groups') IS NULL
BEGIN
  CREATE TABLE zmetric.groups
  (
    groupID        smallint                                     NOT NULL,
    groupName      nvarchar(200)  COLLATE Latin1_General_CI_AI  NOT NULL,
    [description]  nvarchar(max)                                NULL,
    [order]        smallint                                     NOT NULL  DEFAULT 0,
    parentGroupID  smallint                                     NULL,
    --
    CONSTRAINT groups_PK PRIMARY KEY CLUSTERED (groupID)
  )
END
GRANT SELECT ON zmetric.groups TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


-- *** counterID from 30000 and up is reserved for CORE ***

IF OBJECT_ID('zmetric.counters') IS NULL
BEGIN
  CREATE TABLE zmetric.counters
  (
    counterID             smallint                                     NOT NULL,
    counterName           nvarchar(200)  COLLATE Latin1_General_CI_AI  NOT NULL,
    groupID               smallint                                     NULL,
    [description]         nvarchar(max)                                NULL,
    subjectLookupTableID  int                                          NULL, -- Lookup table for subjectID, pointing to zsystem.lookupTables/Values
    keyLookupTableID      int                                          NULL, -- Lookup table for keyID, pointing to zsystem.lookupTables/Values
    [source]              nvarchar(200)                                NULL, -- Description of data source, f.e. table name
    subjectID             nvarchar(200)                                NULL, -- Description of subjectID column
    keyID                 nvarchar(200)                                NULL, -- Description of keyID column
    absoluteValue         bit                                          NOT NULL  DEFAULT 0, -- If set counter stores absolute value
    shortName             nvarchar(50)                                 NULL,
    [order]               smallint                                     NOT NULL  DEFAULT 0,
    procedureName         nvarchar(500)                                NULL, -- Procedure called to get data for the counter
    procedureOrder        tinyint                                      NOT NULL  DEFAULT 200,
    parentCounterID       smallint                                     NULL,
    createDate            datetime2(0)                                 NOT NULL  DEFAULT GETUTCDATE(),
    baseCounterID         smallint                                     NULL,

    -- *** deprecated column ***
    counterType           char(1)                                      NOT NULL  DEFAULT 'D', -- C:Column, D:Date, S:Simple, T:Time

    obsolete              bit                                          NOT NULL  DEFAULT 0,
    counterIdentifier     varchar(500)   COLLATE Latin1_General_CI_AI  NOT NULL, -- Identifier to use in code to make it readable and usable in other Metrics webs
    hidden                bit                                          NOT NULL  DEFAULT 0,
    published             bit                                          NOT NULL  DEFAULT 1,
    sourceType            varchar(20)                                  NULL, -- Used f.e. on EVE Metrics to say if counter comes from DB or DOOBJOB
    units                 varchar(20)                                  NULL, -- zmetric.columns.units overrides value set here
    counterTable          nvarchar(256)                                NULL, -- Stating in what table the counter data is stored
    userName              varchar(200)                                 NULL,
    config                varchar(max)                                 NULL,
    modifyDate            datetime2(0)                                 NOT NULL  DEFAULT GETUTCDATE(),
    autoDeleteMaxDays     smallint                                     NULL, -- If set then old counter data is automatically deleted at midnight
    --
    CONSTRAINT counters_PK PRIMARY KEY CLUSTERED (counterID)
  )

  CREATE NONCLUSTERED INDEX counters_IX_ParentCounter ON zmetric.counters (parentCounterID)

  CREATE UNIQUE NONCLUSTERED INDEX counters_UQ_Identifier ON zmetric.counters (counterIdentifier)
END
GRANT SELECT ON zmetric.counters TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zmetric.columns') IS NULL
BEGIN
  CREATE TABLE zmetric.columns
  (
    counterID          smallint                                     NOT NULL,
    columnID           tinyint                                      NOT NULL,
    columnName         nvarchar(200)  COLLATE Latin1_General_CI_AI  NOT NULL,
    [description]      nvarchar(max)                                NULL,
    [order]            smallint                                     NOT NULL  DEFAULT 0,
    units              varchar(20)                                  NULL, -- If set here it overrides value in zmetric.counters.units
    counterTable       nvarchar(256)                                NULL, -- If set here it overrides value in zmetric.counters.counterTable
    --
    CONSTRAINT columns_PK PRIMARY KEY CLUSTERED (counterID, columnID)
  )
END
GRANT SELECT ON zmetric.columns TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


-- This table is intended for normal key counters
--
-- Normal key counters are key counters where you need to get top x records ordered by value (f.e. leaderboards)

IF OBJECT_ID('zmetric.keyCounters') IS NULL
BEGIN
  CREATE TABLE zmetric.keyCounters
  (
    counterID    smallint  NOT NULL,  -- Counter, poining to zmetric.counters
    counterDate  date      NOT NULL,  -- Date
    columnID     tinyint   NOT NULL,  -- Column if used, pointing to zmetric.columns, 0 if not used
    keyID        int       NOT NULL,  -- Key if used, f.e. if counting by country, 0 if not used
    value        float     NOT NULL,  -- Value
    --
    CONSTRAINT keyCounters_PK PRIMARY KEY CLUSTERED (counterID, columnID, keyID, counterDate)
  )

  CREATE NONCLUSTERED INDEX keyCounters_IX_CounterDate ON zmetric.keyCounters (counterID, counterDate, columnID, value)
END
GRANT SELECT ON zmetric.keyCounters TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


-- COUNTERS
IF NOT EXISTS(SELECT * FROM zmetric.counters WHERE counterID = 30007)
  INSERT INTO zmetric.counters (counterID, counterTable, counterIdentifier, counterName, [description], keyLookupTableID, autoDeleteMaxDays)
       VALUES (30007, 'zmetric.keyCounters', 'core.db.indexStats', 'DB - Index statistics', 'Index statistics saved daily by job (see proc zmetric.KeyCounters_SaveIndexStats). Note that user columns contain accumulated counts.', 2000000005, 500)
IF NOT EXISTS(SELECT * FROM zmetric.counters WHERE counterID = 30008)
  INSERT INTO zmetric.counters (counterID, counterTable, counterIdentifier, counterName, [description], keyLookupTableID, autoDeleteMaxDays)
       VALUES (30008, 'zmetric.keyCounters', 'core.db.tableStats', 'DB - Table statistics', 'Table statistics saved daily by job (see proc zmetric.KeyCounters_SaveIndexStats). Note that user columns contain accumulated counts.', 2000000006, 500)
IF NOT EXISTS(SELECT * FROM zmetric.counters WHERE counterID = 30009)
  INSERT INTO zmetric.counters (counterID, counterTable, counterIdentifier, counterName, [description], keyLookupTableID, autoDeleteMaxDays)
       VALUES (30009, 'zmetric.keyCounters', 'core.db.fileStats', 'DB - File statistics', 'File statistics saved daily by job (see proc zmetric.KeyCounters_SaveFileStats). Note that all columns except size_kb contain accumulated counts.', 2000000007, 500)
IF NOT EXISTS(SELECT * FROM zmetric.counters WHERE counterID = 30025)
  INSERT INTO zmetric.counters (counterID, counterTable, counterIdentifier, counterName, [description], keyLookupTableID, autoDeleteMaxDays)
       VALUES (30025, 'zmetric.keyCounters', 'core.db.waitStats', 'DB - Wait statistics', 'Wait statistics saved daily by job (see proc zmetric.KeyCounters_SaveWaitStats). Note that all columns contain accumulated counts.', 2000000008, 500)
IF NOT EXISTS(SELECT * FROM zmetric.counters WHERE counterID = 30026)
  INSERT INTO zmetric.counters (counterID, counterTable, counterIdentifier, counterName, [description], keyLookupTableID, autoDeleteMaxDays)
       VALUES (30026, 'zmetric.keyCounters', 'core.db.procStats', 'DB - Proc statistics', 'Proc statistics saved daily by job (see proc zmetric.KeyCounters_SaveProcStats). Note that all columns contain accumulated counts.', 2000000001, 500)
IF NOT EXISTS(SELECT * FROM zmetric.counters WHERE counterID = 30027)
  INSERT INTO zmetric.counters (counterID, counterTable, counterIdentifier, counterName, [description], keyLookupTableID, autoDeleteMaxDays)
       VALUES (30027, 'zmetric.keyCounters', 'core.db.perfCountersTotal', 'DB - Performance counters - Total', 'Total performance counters saved daily by job (see proc zmetric.KeyCounters_SavePerfCounters). Note that value saved is accumulated count.', 2000000009, 500)
IF NOT EXISTS(SELECT * FROM zmetric.counters WHERE counterID = 30028)
  INSERT INTO zmetric.counters (counterID, counterTable, counterIdentifier, counterName, [description], keyLookupTableID, autoDeleteMaxDays)
       VALUES (30028, 'zmetric.keyCounters', 'core.db.perfCountersInstance', 'DB - Performance counters - Instance', 'Instance performance counters saved daily by job (see proc zmetric.KeyCounters_SavePerfCounters). Note that value saved is accumulated count.', 2000000009, 500)
GO

-- COLUMNS
-- core.db.indexStats
IF NOT EXISTS(SELECT * FROM zmetric.columns WHERE counterID = 30007)
BEGIN
  INSERT INTO zmetric.columns (counterID, columnID, columnName)
       VALUES (30007, 1, 'rows'), (30007, 2, 'total_kb'), (30007, 3, 'used_kb'), (30007, 4, 'data_kb')
  INSERT INTO zmetric.columns (counterID, columnID, columnName, [description])
       VALUES (30007, 5, 'user_seeks', 'Accumulated count'), (30007, 6, 'user_scans', 'Accumulated count'), (30007, 7, 'user_lookups', 'Accumulated count'), (30007, 8, 'user_updates', 'Accumulated count')
END
-- core.db.tableStats
IF NOT EXISTS(SELECT * FROM zmetric.columns WHERE counterID = 30008)
BEGIN
  INSERT INTO zmetric.columns (counterID, columnID, columnName)
       VALUES (30008, 1, 'rows'), (30008, 2, 'total_kb'), (30008, 3, 'used_kb'), (30008, 4, 'data_kb')
  INSERT INTO zmetric.columns (counterID, columnID, columnName, [description])
       VALUES (30008, 5, 'user_seeks', 'Accumulated count'), (30008, 6, 'user_scans', 'Accumulated count'), (30008, 7, 'user_lookups', 'Accumulated count'), (30008, 8, 'user_updates', 'Accumulated count')
END
-- core.db.fileStats
IF NOT EXISTS(SELECT * FROM zmetric.columns WHERE counterID = 30009)
  INSERT INTO zmetric.columns (counterID, columnID, columnName, [description])
       VALUES (30009, 1, 'reads', 'Accumulated count'), (30009, 2, 'reads_kb', 'Accumulated count'), (30009, 3, 'io_stall_read', 'Accumulated count'), (30009, 4, 'writes', 'Accumulated count'),
              (30009, 5, 'writes_kb', 'Accumulated count'), (30009, 6, 'io_stall_write', 'Accumulated count'), (30009, 7, 'size_kb', NULL)
-- core.db.waitStats
IF NOT EXISTS(SELECT * FROM zmetric.columns WHERE counterID = 30025)
  INSERT INTO zmetric.columns (counterID, columnID, columnName, [description])
       VALUES (30025, 1, 'waiting_tasks_count', 'Accumulated count'), (30025, 2, 'wait_time_ms', 'Accumulated count'), (30025, 3, 'signal_wait_time_ms', 'Accumulated count')
-- core.db.procStats
IF NOT EXISTS(SELECT * FROM zmetric.columns WHERE counterID = 30026)
  INSERT INTO zmetric.columns (counterID, columnID, columnName, [description])
       VALUES (30026, 1, 'execution_count', 'Accumulated count'), (30026, 2, 'total_logical_reads', 'Accumulated count'), (30026, 3, 'total_logical_writes', 'Accumulated count'),
              (30026, 4, 'total_worker_time', 'Accumulated count'), (30026, 5, 'total_elapsed_time', 'Accumulated count')
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zmetric.groupsEx') IS NOT NULL
  DROP VIEW zmetric.groupsEx
GO
CREATE VIEW zmetric.groupsEx
AS
  WITH CTE ([level], fullName, parentGroupID, groupID, groupName, [description], [order]) AS
  (
      SELECT [level] = 1, fullName = CONVERT(nvarchar(4000), groupName),
             parentGroupID, groupID, groupName, [description], [order]
        FROM zmetric.groups G
       WHERE parentGroupID IS NULL
      UNION ALL
      SELECT CTE.[level] + 1, CTE.fullName + N', ' + CONVERT(nvarchar(4000), X.groupName),
             X.parentGroupID, X.groupID, X.groupName,  X.[description], X.[order]
        FROM CTE
          INNER JOIN zmetric.groups X ON X.parentGroupID = CTE.groupID
  )
  SELECT [level], fullName, parentGroupID, groupID, groupName, [description], [order]
    FROM CTE
GO
GRANT SELECT ON zmetric.groupsEx TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zmetric.countersEx') IS NOT NULL
  DROP VIEW zmetric.countersEx
GO
CREATE VIEW zmetric.countersEx
AS
  SELECT C.groupID, G.groupName, C.counterID, C.counterName, C.counterType, C.counterTable, C.counterIdentifier, C.[description],
         C.subjectLookupTableID, subjectLookupTableIdentifier = LS.lookupTableIdentifier, subjectLookupTableName = LS.lookupTableName,
         C.keyLookupTableID, keyLookupTableIdentifier = LK.lookupTableIdentifier, keyLookupTableName = LK.lookupTableName,
         C.sourceType, C.[source], C.subjectID, C.keyID, C.absoluteValue, C.shortName,
         groupOrder = G.[order], C.[order], C.procedureName, C.procedureOrder, C.parentCounterID, C.createDate, C.modifyDate, C.userName,
         C.baseCounterID, C.hidden, C.published, C.units, C.obsolete
    FROM zmetric.counters C
      LEFT JOIN zmetric.groups G ON G.groupID = C.groupID
      LEFT JOIN zsystem.lookupTables LS ON LS.lookupTableID = C.subjectLookupTableID
      LEFT JOIN zsystem.lookupTables LK ON LK.lookupTableID = C.keyLookupTableID
GO
GRANT SELECT ON zmetric.countersEx TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zmetric.columnsEx') IS NOT NULL
  DROP VIEW zmetric.columnsEx
GO
CREATE VIEW zmetric.columnsEx
AS
  SELECT C.groupID, G.groupName, O.counterID, C.counterName, O.columnID, O.columnName, O.[description], O.units, O.counterTable, O.[order]
    FROM zmetric.columns O
      LEFT JOIN zmetric.counters C ON C.counterID = O.counterID
        LEFT JOIN zmetric.groups G ON G.groupID = C.groupID
GO
GRANT SELECT ON zmetric.columnsEx TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zmetric.keyCountersEx') IS NOT NULL
  DROP VIEW zmetric.keyCountersEx
GO
CREATE VIEW zmetric.keyCountersEx
AS
  SELECT C.groupID, G.groupName, K.counterID, C.counterName, K.counterDate, K.columnID, O.columnName,
         K.keyID, keyText = ISNULL(L.[fullText], L.lookupText), K.[value]
    FROM zmetric.keyCounters K
      LEFT JOIN zmetric.counters C ON C.counterID = K.counterID
        LEFT JOIN zmetric.groups G ON G.groupID = C.groupID
        LEFT JOIN zsystem.lookupValues L ON L.lookupTableID = C.keyLookupTableID AND L.lookupID = K.keyID
      LEFT JOIN zmetric.columns O ON O.counterID = K.counterID AND O.columnID = K.columnID
GO
GRANT SELECT ON zmetric.keyCountersEx TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zmetric.Counters_ID') IS NOT NULL
  DROP FUNCTION zmetric.Counters_ID
GO
CREATE FUNCTION zmetric.Counters_ID(@counterIdentifier varchar(500))
RETURNS smallint
BEGIN
  DECLARE @counterID int
  SELECT @counterID = counterID FROM zmetric.counters WHERE counterIdentifier = @counterIdentifier
  RETURN @counterID
END
GO
GRANT EXEC ON zmetric.Counters_ID TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zmetric.Counters_Insert') IS NOT NULL
  DROP PROCEDURE zmetric.Counters_Insert
GO
CREATE PROCEDURE zmetric.Counters_Insert
  @counterType           char(1) = 'D',         -- C:Column, D:Date, S:Simple, T:Time
  @counterID             smallint = NULL,       -- NULL means MAX-UNDER-30000 + 1
  @counterName           nvarchar(200),
  @groupID               smallint = NULL,
  @description           nvarchar(max) = NULL,
  @subjectLookupTableID  int = NULL,            -- Lookup table for subjectID, pointing to zsystem.lookupTables/Values
  @keyLookupTableID      int = NULL,            -- Lookup table for keyID, pointing to zsystem.lookupTables/Values
  @source                nvarchar(200) = NULL,  -- Description of data source, f.e. table name
  @subjectID             nvarchar(200) = NULL,  -- Description of subjectID column
  @keyID                 nvarchar(200) = NULL,  -- Description of keyID column
  @absoluteValue         bit = 0,               -- If set counter stores absolute value
  @shortName             nvarchar(50) = NULL,
  @order                 smallint = 0,
  @procedureName         nvarchar(500) = NULL,  -- Procedure called to get data for the counter
  @procedureOrder        tinyint = 255,
  @parentCounterID       smallint = NULL,
  @baseCounterID         smallint = NULL,
  @counterIdentifier     varchar(500) = NULL,
  @published             bit = 1,
  @sourceType            varchar(20) = NULL,    -- Used f.e. on EVE Metrics to say if counter comes from DB or DOOBJOB
  @units                 varchar(20) = NULL,
  @counterTable          nvarchar(256) = NULL,
  @userName              varchar(200) = NULL
AS
  SET NOCOUNT ON

  IF @counterID IS NULL
    SELECT @counterID = MAX(counterID) + 1 FROM zmetric.counters WHERE counterID < 30000
  IF @counterID IS NULL SET @counterID = 1

  IF @counterIdentifier IS NULL SET @counterIdentifier = @counterID

  INSERT INTO zmetric.counters
              (counterID, counterName, groupID, [description], subjectLookupTableID, keyLookupTableID, [source], subjectID, keyID,
               absoluteValue, shortName, [order], procedureName, procedureOrder, parentCounterID, baseCounterID, counterType,
               counterIdentifier, published, sourceType, units, counterTable, userName)
       VALUES (@counterID, @counterName, @groupID, @description, @subjectLookupTableID, @keyLookupTableID, @source, @subjectID, @keyID,
               @absoluteValue, @shortName, @order, @procedureName, @procedureOrder, @parentCounterID, @baseCounterID, @counterType,
               @counterIdentifier, @published, @sourceType, @units, @counterTable, @userName)

  SELECT counterID = @counterID
GO
GRANT EXEC ON zmetric.Counters_Insert TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zmetric.KeyCounters_Insert') IS NOT NULL
  DROP PROCEDURE zmetric.KeyCounters_Insert
GO
CREATE PROCEDURE zmetric.KeyCounters_Insert
  @counterID    smallint,
  @columnID     tinyint = 0,
  @keyID        int = 0,
  @value        float,
  @interval     char(1) = 'D', -- D:Day, W:Week, M:Month, Y:Year
  @counterDate  date = NULL
AS
  SET NOCOUNT ON

  IF @counterDate IS NULL SET @counterDate = GETUTCDATE()

  IF @interval = 'W' SET @counterDate = zutil.DateWeek(@counterDate)
  ELSE IF @interval = 'M' SET @counterDate = zutil.DateMonth(@counterDate)
  ELSE IF @interval = 'Y' SET @counterDate = zutil.DateYear(@counterDate)

  INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value)
       VALUES (@counterID, @counterDate, @columnID, @keyID, @value)
GO
GRANT EXEC ON zmetric.KeyCounters_Insert TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zmetric.KeyCounters_Update') IS NOT NULL
  DROP PROCEDURE zmetric.KeyCounters_Update
GO
CREATE PROCEDURE zmetric.KeyCounters_Update
  @counterID    smallint,
  @columnID     tinyint = 0,
  @keyID        int = 0,
  @value        float,
  @interval     char(1) = 'D', -- D:Day, W:Week, M:Month, Y:Year
  @counterDate  date = NULL
AS
  SET NOCOUNT ON

  IF @counterDate IS NULL SET @counterDate = GETUTCDATE()

  IF @interval = 'W' SET @counterDate = zutil.DateWeek(@counterDate)
  ELSE IF @interval = 'M' SET @counterDate = zutil.DateMonth(@counterDate)
  ELSE IF @interval = 'Y' SET @counterDate = zutil.DateYear(@counterDate)

  UPDATE zmetric.keyCounters
      SET value = value + @value
    WHERE counterID = @counterID AND columnID = @columnID AND keyID = @keyID AND counterDate = @counterDate
  IF @@ROWCOUNT = 0
  BEGIN TRY
    INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value)
          VALUES (@counterID, @counterDate, @columnID, @keyID, @value)
  END TRY
  BEGIN CATCH
    IF ERROR_NUMBER() = 2627 -- Violation of PRIMARY KEY constraint
    BEGIN
      UPDATE zmetric.keyCounters
         SET value = value + @value
       WHERE counterID = @counterID AND columnID = @columnID AND keyID = @keyID AND counterDate = @counterDate
    END
    ELSE
    BEGIN
      EXEC zsystem.CatchError 'zmetric.KeyCounters_Update'
      RETURN -1
    END
  END CATCH
GO
GRANT EXEC ON zmetric.KeyCounters_Update TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zmetric.KeyCounters_InsertMulti') IS NOT NULL
  DROP PROCEDURE zmetric.KeyCounters_InsertMulti
GO
CREATE PROCEDURE zmetric.KeyCounters_InsertMulti
  @counterID      smallint,
  @interval       char(1) = 'D',  -- D:Day, W:Week, M:Month, Y:Year
  @counterDate    date = NULL,
  @lookupTableID  int,
  @keyID          int = NULL,     -- If NULL then zsystem.Texts_ID is used
  @keyText        nvarchar(450),
  @value1         float = NULL,
  @value2         float = NULL,
  @value3         float = NULL,
  @value4         float = NULL,
  @value5         float = NULL,
  @value6         float = NULL,
  @value7         float = NULL,
  @value8         float = NULL,
  @value9         float = NULL,
  @value10        float = NULL
AS
  -- Set values for multiple columns
  -- @value1 goes into columnID = 1, @value2 goes into columnID = 2 and so on
  SET NOCOUNT ON

  IF @counterDate IS NULL SET @counterDate = GETUTCDATE()

  IF @interval = 'W' SET @counterDate = zutil.DateWeek(@counterDate)
  ELSE IF @interval = 'M' SET @counterDate = zutil.DateMonth(@counterDate)
  ELSE IF @interval = 'Y' SET @counterDate = zutil.DateYear(@counterDate)

  IF @keyText IS NOT NULL
    EXEC @keyID = zsystem.LookupValues_Update @lookupTableID, @keyID, @keyText

  IF ISNULL(@value1, 0.0) != 0.0
    INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (@counterID, @counterDate, 1, @keyID, @value1)

  IF ISNULL(@value2, 0.0) != 0.0
    INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (@counterID, @counterDate, 2, @keyID, @value2)

  IF ISNULL(@value3, 0.0) != 0.0
    INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (@counterID, @counterDate, 3, @keyID, @value3)

  IF ISNULL(@value4, 0.0) != 0.0
    INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (@counterID, @counterDate, 4, @keyID, @value4)

  IF ISNULL(@value5, 0.0) != 0.0
    INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (@counterID, @counterDate, 5, @keyID, @value5)

  IF ISNULL(@value6, 0.0) != 0.0
    INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (@counterID, @counterDate, 6, @keyID, @value6)

  IF ISNULL(@value7, 0.0) != 0.0
    INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (@counterID, @counterDate, 7, @keyID, @value7)

  IF ISNULL(@value8, 0.0) != 0.0
    INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (@counterID, @counterDate, 8, @keyID, @value8)

  IF ISNULL(@value9, 0.0) != 0.0
    INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (@counterID, @counterDate, 9, @keyID, @value9)

  IF ISNULL(@value10, 0.0) != 0.0
    INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (@counterID, @counterDate, 10, @keyID, @value10)
GO
GRANT EXEC ON zmetric.KeyCounters_InsertMulti TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zmetric.KeyCounters_UpdateMulti') IS NOT NULL
  DROP PROCEDURE zmetric.KeyCounters_UpdateMulti
GO
CREATE PROCEDURE zmetric.KeyCounters_UpdateMulti
  @counterID      smallint,
  @interval       char(1) = 'D',  -- D:Day, W:Week, M:Month, Y:Year
  @counterDate    date = NULL,
  @lookupTableID  int,
  @keyID          int = NULL,     -- If NULL then zsystem.Texts_ID is used
  @keyText        nvarchar(450),
  @value1         float = NULL,
  @value2         float = NULL,
  @value3         float = NULL,
  @value4         float = NULL,
  @value5         float = NULL,
  @value6         float = NULL,
  @value7         float = NULL,
  @value8         float = NULL,
  @value9         float = NULL,
  @value10        float = NULL
AS
  -- Set values for multiple columns
  -- @value1 goes into columnID = 1, @value2 goes into columnID = 2 and so on
  SET NOCOUNT ON

  IF @counterDate IS NULL SET @counterDate = GETUTCDATE()

  IF @interval = 'W' SET @counterDate = zutil.DateWeek(@counterDate)
  ELSE IF @interval = 'M' SET @counterDate = zutil.DateMonth(@counterDate)
  ELSE IF @interval = 'Y' SET @counterDate = zutil.DateYear(@counterDate)

  IF @keyText IS NOT NULL
    EXEC @keyID = zsystem.LookupValues_Update @lookupTableID, @keyID, @keyText

  IF ISNULL(@value1, 0.0) != 0.0
  BEGIN
    UPDATE zmetric.keyCounters SET value = value + @value1 WHERE counterID = @counterID AND counterDate = @counterDate AND columnID = 1 AND keyID = @keyID
    IF @@ROWCOUNT = 0
      INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (@counterID, @counterDate, 1, @keyID, @value1)
  END

  IF ISNULL(@value2, 0.0) != 0.0
  BEGIN
    UPDATE zmetric.keyCounters SET value = value + @value2 WHERE counterID = @counterID AND counterDate = @counterDate AND columnID = 2 AND keyID = @keyID
    IF @@ROWCOUNT = 0
      INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (@counterID, @counterDate, 2, @keyID, @value2)
  END

  IF ISNULL(@value3, 0.0) != 0.0
  BEGIN
    UPDATE zmetric.keyCounters SET value = value + @value3 WHERE counterID = @counterID AND counterDate = @counterDate AND columnID = 3 AND keyID = @keyID
    IF @@ROWCOUNT = 0
      INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (@counterID, @counterDate, 3, @keyID, @value3)
  END

  IF ISNULL(@value4, 0.0) != 0.0
  BEGIN
    UPDATE zmetric.keyCounters SET value = value + @value4 WHERE counterID = @counterID AND counterDate = @counterDate AND columnID = 4 AND keyID = @keyID
    IF @@ROWCOUNT = 0
      INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (@counterID, @counterDate, 4, @keyID, @value4)
  END

  IF ISNULL(@value5, 0.0) != 0.0
  BEGIN
    UPDATE zmetric.keyCounters SET value = value + @value5 WHERE counterID = @counterID AND counterDate = @counterDate AND columnID = 5 AND keyID = @keyID
    IF @@ROWCOUNT = 0
      INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (@counterID, @counterDate, 5, @keyID, @value5)
  END

  IF ISNULL(@value6, 0.0) != 0.0
  BEGIN
    UPDATE zmetric.keyCounters SET value = value + @value6 WHERE counterID = @counterID AND counterDate = @counterDate AND columnID = 6 AND keyID = @keyID
    IF @@ROWCOUNT = 0
      INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (@counterID, @counterDate, 6, @keyID, @value6)
  END

  IF ISNULL(@value7, 0.0) != 0.0
  BEGIN
    UPDATE zmetric.keyCounters SET value = value + @value7 WHERE counterID = @counterID AND counterDate = @counterDate AND columnID = 7 AND keyID = @keyID
    IF @@ROWCOUNT = 0
      INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (@counterID, @counterDate, 7, @keyID, @value7)
  END

  IF ISNULL(@value8, 0.0) != 0.0
  BEGIN
    UPDATE zmetric.keyCounters SET value = value + @value8 WHERE counterID = @counterID AND counterDate = @counterDate AND columnID = 8 AND keyID = @keyID
    IF @@ROWCOUNT = 0
      INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (@counterID, @counterDate, 8, @keyID, @value8)
  END

  IF ISNULL(@value9, 0.0) != 0.0
  BEGIN
    UPDATE zmetric.keyCounters SET value = value + @value9 WHERE counterID = @counterID AND counterDate = @counterDate AND columnID = 9 AND keyID = @keyID
    IF @@ROWCOUNT = 0
      INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (@counterID, @counterDate, 9, @keyID, @value9)
  END

  IF ISNULL(@value10, 0.0) != 0.0
  BEGIN
    UPDATE zmetric.keyCounters SET value = value + @value10 WHERE counterID = @counterID AND counterDate = @counterDate AND columnID = 10 AND keyID = @keyID
    IF @@ROWCOUNT = 0
      INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (@counterID, @counterDate, 10, @keyID, @value10)
  END
GO
GRANT EXEC ON zmetric.KeyCounters_UpdateMulti TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zmetric.KeyCounters_SaveIndexStats') IS NOT NULL
  DROP PROCEDURE zmetric.KeyCounters_SaveIndexStats
GO
CREATE PROCEDURE zmetric.KeyCounters_SaveIndexStats
  @checkSetting   bit = 1,
  @deleteOldData  bit = 0
AS
  SET NOCOUNT ON
  SET ANSI_WARNINGS OFF
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  BEGIN TRY
    IF @checkSetting = 1 AND zsystem.Settings_Value('zmetric', 'SaveIndexStats') != '1'
      RETURN

    DECLARE @counterDate date = GETDATE()

    IF @deleteOldData = 1
    BEGIN
      DELETE FROM zmetric.keyCounters WHERE counterID = 30007 AND counterDate = @counterDate
      DELETE FROM zmetric.keyCounters WHERE counterID = 30008 AND counterDate = @counterDate
    END
    ELSE
    BEGIN
      IF EXISTS(SELECT * FROM zmetric.keyCounters WHERE counterID = 30007 AND counterDate = @counterDate)
        RAISERROR ('Index stats data exists', 16, 1)
      IF EXISTS(SELECT * FROM zmetric.keyCounters WHERE counterID = 30008 AND counterDate = @counterDate)
        RAISERROR ('Table stats data exists', 16, 1)
    END

    DECLARE @indexStats TABLE
    (
      tableName    nvarchar(450)  NOT NULL,
      indexName    nvarchar(450)  NOT NULL,
      [rows]       bigint         NOT NULL,
      total_kb     bigint         NOT NULL,
      used_kb      bigint         NOT NULL,
      data_kb      bigint         NOT NULL,
      user_seeks   bigint         NULL,
      user_scans   bigint         NULL,
      user_lookups bigint         NULL,
      user_updates bigint         NULL
    )
    INSERT INTO @indexStats (tableName, indexName, [rows], total_kb, used_kb, data_kb, user_seeks, user_scans, user_lookups, user_updates)
         SELECT S.name + '.' + T.name, ISNULL(I.name, 'HEAP'),
                SUM(P.row_count),
                SUM(P.reserved_page_count * 8), SUM(P.used_page_count * 8), SUM(P.in_row_data_page_count * 8),
                MAX(U.user_seeks), MAX(U.user_scans), MAX(U.user_lookups), MAX(U.user_updates)
           FROM sys.tables T
             INNER JOIN sys.schemas S ON S.[schema_id] = T.[schema_id]
             INNER JOIN sys.indexes I ON I.[object_id] = T.[object_id]
               INNER JOIN sys.dm_db_partition_stats P ON P.[object_id] = I.[object_id] AND P.index_id = I.index_id
               LEFT JOIN sys.dm_db_index_usage_stats U ON U.database_id = DB_ID() AND U.[object_id] = I.[object_id] AND U.index_id = I.index_id
          WHERE T.is_ms_shipped != 1
          GROUP BY S.name, T.name, I.name
          ORDER BY S.name, T.name, I.name

    DECLARE @rows bigint, @total_kb bigint, @used_kb bigint, @data_kb bigint,
            @user_seeks bigint, @user_scans bigint, @user_lookups bigint, @user_updates bigint,
            @keyText nvarchar(450), @keyID int

    -- INDEX STATISTICS
    DECLARE @cursor CURSOR
    SET @cursor = CURSOR LOCAL FAST_FORWARD
      FOR SELECT tableName + '.' + indexName, [rows], total_kb, used_kb, data_kb, user_seeks, user_scans, user_lookups, user_updates
            FROM @indexStats
           ORDER BY tableName, indexName
    OPEN @cursor
    FETCH NEXT FROM @cursor INTO @keyText, @rows, @total_kb, @used_kb, @data_kb, @user_seeks, @user_scans, @user_lookups, @user_updates
    WHILE @@FETCH_STATUS = 0
    BEGIN
      EXEC zmetric.KeyCounters_InsertMulti 30007, 'D', @counterDate, 2000000005, NULL, @keyText, @rows, @total_kb, @used_kb, @data_kb, @user_seeks, @user_scans, @user_lookups, @user_updates

      FETCH NEXT FROM @cursor INTO @keyText, @rows, @total_kb, @used_kb, @data_kb, @user_seeks, @user_scans, @user_lookups, @user_updates
    END
    CLOSE @cursor
    DEALLOCATE @cursor

    -- TABLE STATISTICS
    SET @cursor = CURSOR LOCAL FAST_FORWARD
      FOR SELECT tableName, MAX([rows]), SUM(total_kb), SUM(used_kb), SUM(data_kb), MAX(user_seeks), MAX(user_scans), MAX(user_lookups), MAX(user_updates)
            FROM @indexStats
           GROUP BY tableName
           ORDER BY tableName
    OPEN @cursor
    FETCH NEXT FROM @cursor INTO @keyText, @rows, @total_kb, @used_kb, @data_kb, @user_seeks, @user_scans, @user_lookups, @user_updates
    WHILE @@FETCH_STATUS = 0
    BEGIN
      EXEC zmetric.KeyCounters_InsertMulti 30008, 'D', @counterDate, 2000000006, NULL, @keyText, @rows, @total_kb, @used_kb, @data_kb, @user_seeks, @user_scans, @user_lookups, @user_updates

      FETCH NEXT FROM @cursor INTO @keyText, @rows, @total_kb, @used_kb, @data_kb, @user_seeks, @user_scans, @user_lookups, @user_updates
    END
    CLOSE @cursor
    DEALLOCATE @cursor

    -- MAIL
    DECLARE @recipients varchar(max)
    SET @recipients = zsystem.Settings_Value('zmetric', 'Recipients-IndexStats')
    IF @recipients != '' AND zsystem.Settings_Value('zsystem', 'Database') = DB_NAME()
    BEGIN
      DECLARE @subtractDate date
      SET @subtractDate = DATEADD(day, -1, @counterDate)

      -- SEND MAIL...
      DECLARE @subject nvarchar(255)
      SET @subject = HOST_NAME() + '.' + DB_NAME() + ': Index Statistics'

      DECLARE @body nvarchar(MAX)
      SET @body =
        -- rows
          N'<h3><font color=blue>Top 30 rows</font></h3>'
        + N'<table border="1">'
        + N'<tr>'
        + N'<th align="left">table</th><th>rows</th><th>total_MB</th><th>used_MB</th><th>data_MB</th>'
        + N'</tr>'
        + ISNULL(CAST((
        SELECT TOP 30 td = L.lookupText, '',
               [td/@align] = 'right', td = zutil.BigintToNvarchar(C1.value, 1), '',
               [td/@align] = 'right', td = zutil.IntToNvarchar(C2.value / 1024, 1), '',
               [td/@align] = 'right', td = zutil.IntToNvarchar(C3.value / 1024, 1), '',
               [td/@align] = 'right', td = zutil.IntToNvarchar(C4.value / 1024, 1), ''
          FROM zmetric.keyCounters C1
            LEFT JOIN zsystem.lookupValues L ON L.lookupTableID = 2000000006 AND L.lookupID = C1.keyID
            LEFT JOIN zmetric.keyCounters C2 ON C2.counterID = C1.counterID AND C2.counterDate = C1.counterDate AND C2.columnID = 2 AND C2.keyID = C1.keyID
            LEFT JOIN zmetric.keyCounters C3 ON C3.counterID = C1.counterID AND C3.counterDate = C1.counterDate AND C3.columnID = 3 AND C3.keyID = C1.keyID
            LEFT JOIN zmetric.keyCounters C4 ON C4.counterID = C1.counterID AND C4.counterDate = C1.counterDate AND C4.columnID = 4 AND C4.keyID = C1.keyID
         WHERE C1.counterID = 30008 AND C1.counterDate = @counterDate AND C1.columnID = 1
         ORDER BY C1.value DESC
               FOR XML PATH('tr'), TYPE) AS nvarchar(MAX)), '<tr></tr>')
        + N'</table>'

        -- total_MB
        + N'<h3><font color=blue>Top 30 total_MB</font></h3>'
        + N'<table border="1">'
        + N'<tr>'
        + N'<th align="left">table</th><th>total_MB</th><th>used_MB</th><th>data_MB</th><th>rows</th>'
        + N'</tr>'
        + ISNULL(CAST((
        SELECT TOP 30 td = L.lookupText, '',
               [td/@align] = 'right', td = zutil.IntToNvarchar(C2.value / 1024, 1), '',
               [td/@align] = 'right', td = zutil.IntToNvarchar(C3.value / 1024, 1), '',
               [td/@align] = 'right', td = zutil.IntToNvarchar(C4.value / 1024, 1), '',
               [td/@align] = 'right', td = zutil.BigintToNvarchar(C1.value, 1), ''
          FROM zmetric.keyCounters C2
            LEFT JOIN zsystem.lookupValues L ON L.lookupTableID = 2000000006 AND L.lookupID = C2.keyID
            LEFT JOIN zmetric.keyCounters C3 ON C3.counterID = C2.counterID AND C3.counterDate = C2.counterDate AND C3.columnID = 3 AND C3.keyID = C2.keyID
            LEFT JOIN zmetric.keyCounters C4 ON C4.counterID = C2.counterID AND C4.counterDate = C2.counterDate AND C4.columnID = 4 AND C4.keyID = C2.keyID
            LEFT JOIN zmetric.keyCounters C1 ON C1.counterID = C2.counterID AND C1.counterDate = C2.counterDate AND C1.columnID = 1 AND C1.keyID = C2.keyID
         WHERE C2.counterID = 30008 AND C2.counterDate = @counterDate AND C2.columnID = 2
         ORDER BY C2.value DESC
               FOR XML PATH('tr'), TYPE) AS nvarchar(MAX)), '<tr></tr>')
        + N'</table>'

        -- user_seeks (accumulative count, subtracting the value from the day before)
        + N'<h3><font color=blue>Top 30 user_seeks</font></h3>'
        + N'<table border="1">'
        + N'<tr>'
        + N'<th align="left">index</th><th>count</th>'
        + N'</tr>'
        + ISNULL(CAST((
        SELECT TOP 30 td = L.lookupText, '',
               [td/@align] = 'right', td = zutil.BigintToNvarchar(C5.value - ISNULL(C5B.value, 0), 1), ''
          FROM zmetric.keyCounters C5
            LEFT JOIN zsystem.lookupValues L ON L.lookupTableID = 2000000005 AND L.lookupID = C5.keyID
            LEFT JOIN zmetric.keyCounters C5B ON C5B.counterID = C5.counterID AND C5B.counterDate = @subtractDate AND C5B.columnID = C5.columnID AND C5B.keyID = C5.keyID
         WHERE C5.counterID = 30007 AND C5.counterDate = @counterDate AND C5.columnID = 5
         ORDER BY (C5.value - ISNULL(C5B.value, 0)) DESC
               FOR XML PATH('tr'), TYPE) AS nvarchar(MAX)), '<tr></tr>')
        + N'</table>'

        -- user_scans (accumulative count, subtracting the value from the day before)
        + N'<h3><font color=blue>Top 30 user_scans</font></h3>'
        + N'<table border="1">'
        + N'<tr>'
        + N'<th align="left">index</th><th>count</th>'
        + N'</tr>'
        + ISNULL(CAST((
        SELECT TOP 30 td = L.lookupText, '',
               [td/@align] = 'right', td = zutil.BigintToNvarchar(C6.value - ISNULL(C6B.value, 0), 1), ''
          FROM zmetric.keyCounters C6
            LEFT JOIN zsystem.lookupValues L ON L.lookupTableID = 2000000005 AND L.lookupID = C6.keyID
            LEFT JOIN zmetric.keyCounters C6B ON C6B.counterID = C6.counterID AND C6B.counterDate = @subtractDate AND C6B.columnID = C6.columnID AND C6B.keyID = C6.keyID
         WHERE C6.counterID = 30007 AND C6.counterDate = @counterDate AND C6.columnID = 6
         ORDER BY (C6.value - ISNULL(C6B.value, 0)) DESC
               FOR XML PATH('tr'), TYPE) AS nvarchar(MAX)), '<tr></tr>')
        + N'</table>'

        -- user_lookups (accumulative count, subtracting the value from the day before)
        + N'<h3><font color=blue>Top 30 user_lookups</font></h3>'
        + N'<table border="1">'
        + N'<tr>'
        + N'<th align="left">index</th><th>count</th>'
        + N'</tr>'
        + ISNULL(CAST((
        SELECT TOP 30 td = L.lookupText, '',
               [td/@align] = 'right', td = zutil.BigintToNvarchar(C7.value - ISNULL(C7B.value, 0), 1), ''
          FROM zmetric.keyCounters C7
            LEFT JOIN zsystem.lookupValues L ON L.lookupTableID = 2000000005 AND L.lookupID = C7.keyID
            LEFT JOIN zmetric.keyCounters C7B ON C7B.counterID = C7.counterID AND C7B.counterDate = @subtractDate AND C7B.columnID = C7.columnID AND C7B.keyID = C7.keyID
         WHERE C7.counterID = 30007 AND C7.counterDate = @counterDate AND C7.columnID = 7
         ORDER BY (C7.value - ISNULL(C7B.value, 0)) DESC
               FOR XML PATH('tr'), TYPE) AS nvarchar(MAX)), '<tr></tr>')
        + N'</table>'

        -- user_updates (accumulative count, subtracting the value from the day before)
        + N'<h3><font color=blue>Top 30 user_updates</font></h3>'
        + N'<table border="1">'
        + N'<tr>'
        + N'<th align="left">index</th><th>count</th>'
        + N'</tr>'
        + ISNULL(CAST((
        SELECT TOP 30 td = L.lookupText, '',
               [td/@align] = 'right', td = zutil.BigintToNvarchar(C8.value - ISNULL(C8B.value, 0), 1), ''
          FROM zmetric.keyCounters C8
            LEFT JOIN zsystem.lookupValues L ON L.lookupTableID = 2000000005 AND L.lookupID = C8.keyID
            LEFT JOIN zmetric.keyCounters C8B ON C8B.counterID = C8.counterID AND C8B.counterDate = @subtractDate AND C8B.columnID = C8.columnID AND C8B.keyID = C8.keyID
         WHERE C8.counterID = 30007 AND C8.counterDate = @counterDate AND C8.columnID = 8
         ORDER BY (C8.value - ISNULL(C8B.value, 0)) DESC
               FOR XML PATH('tr'), TYPE) AS nvarchar(MAX)), '<tr></tr>')
        + N'</table>'

      EXEC zsystem.SendMail @recipients, @subject, @body, 'HTML'
    END
  END TRY
  BEGIN CATCH
    EXEC zsystem.CatchError 'zmetric.KeyCounters_SaveIndexStats'
    RETURN -1
  END CATCH
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zmetric.KeyCounters_SaveProcStats') IS NOT NULL
  DROP PROCEDURE zmetric.KeyCounters_SaveProcStats
GO
CREATE PROCEDURE zmetric.KeyCounters_SaveProcStats
  @checkSetting   bit = 1,
  @deleteOldData  bit = 0
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  BEGIN TRY
    IF @checkSetting = 1 AND zsystem.Settings_Value('zmetric', 'SaveProcStats') != '1'
      RETURN

    DECLARE @counterDate date = GETDATE()

    IF @deleteOldData = 1
      DELETE FROM zmetric.keyCounters WHERE counterID = 30026 AND counterDate = @counterDate
    ELSE
    BEGIN
      IF EXISTS(SELECT * FROM zmetric.keyCounters WHERE counterID = 30026 AND counterDate = @counterDate)
        RAISERROR ('Proc stats data exists', 16, 1)
    END

    -- PROC STATISTICS
    DECLARE @object_name nvarchar(300), @execution_count bigint, @total_logical_reads bigint, @total_logical_writes bigint, @total_worker_time bigint, @total_elapsed_time bigint

    DECLARE @cursor CURSOR
    SET @cursor = CURSOR LOCAL FAST_FORWARD
      FOR SELECT S.name + '.' + O.name, SUM(P.execution_count), SUM(P.total_logical_reads), SUM(P.total_logical_writes), SUM(P.total_worker_time), SUM(P.total_elapsed_time)
            FROM sys.dm_exec_procedure_stats P
              INNER JOIN sys.objects O ON O.[object_id] = P.[object_id]
                INNER JOIN sys.schemas S ON S.[schema_id] = O.[schema_id]
           WHERE P.database_id = DB_ID()
           GROUP BY S.name + '.' + O.name
           ORDER BY 1
    OPEN @cursor
    FETCH NEXT FROM @cursor INTO @object_name, @execution_count, @total_logical_reads, @total_logical_writes, @total_worker_time, @total_elapsed_time
    WHILE @@FETCH_STATUS = 0
    BEGIN
      -- removing digits at the end of string (max two digits)
      IF CHARINDEX(RIGHT(@object_name, 1), '0123456789') > 0
        SET @object_name = LEFT(@object_name, LEN(@object_name) - 1)
      IF CHARINDEX(RIGHT(@object_name, 1), '0123456789') > 0
        SET @object_name = LEFT(@object_name, LEN(@object_name) - 1)

      EXEC zmetric.KeyCounters_UpdateMulti 30026, 'D', @counterDate, 2000000001, NULL, @object_name, @execution_count, @total_logical_reads, @total_logical_writes, @total_worker_time, @total_elapsed_time

      FETCH NEXT FROM @cursor INTO @object_name, @execution_count, @total_logical_reads, @total_logical_writes, @total_worker_time, @total_elapsed_time
    END
    CLOSE @cursor
    DEALLOCATE @cursor
  END TRY
  BEGIN CATCH
    EXEC zsystem.CatchError 'zmetric.KeyCounters_SaveProcStats'
    RETURN -1
  END CATCH
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zmetric.KeyCounters_SaveFileStats') IS NOT NULL
  DROP PROCEDURE zmetric.KeyCounters_SaveFileStats
GO
CREATE PROCEDURE zmetric.KeyCounters_SaveFileStats
  @checkSetting   bit = 1,
  @deleteOldData  bit = 0
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  BEGIN TRY
    IF @checkSetting = 1 AND zsystem.Settings_Value('zmetric', 'SaveFileStats') != '1'
      RETURN

    DECLARE @counterDate date = GETDATE()

    IF @deleteOldData = 1
      DELETE FROM zmetric.keyCounters WHERE counterID = 30009 AND counterDate = @counterDate
    ELSE
    BEGIN
      IF EXISTS(SELECT * FROM zmetric.keyCounters WHERE counterID = 30009 AND counterDate = @counterDate)
        RAISERROR ('File stats data exists', 16, 1)
    END

    -- FILE STATISTICS
    DECLARE @database_name nvarchar(200), @file_type nvarchar(20), @filegroup_name nvarchar(200),
            @reads bigint, @reads_kb bigint, @io_stall_read bigint, @writes bigint, @writes_kb bigint, @io_stall_write bigint, @size_kb bigint,
            @keyText nvarchar(450)

    DECLARE @cursor CURSOR
    SET @cursor = CURSOR LOCAL FAST_FORWARD
      FOR SELECT database_name = D.name,
                 file_type = CASE WHEN M.type_desc = 'ROWS' THEN 'DATA' ELSE M.type_desc END,
                 [filegroup_name] = F.name,
                 SUM(S.num_of_reads), SUM(S.num_of_bytes_read) / 1024, SUM(S.io_stall_read_ms),
                 SUM(S.num_of_writes), SUM(S.num_of_bytes_written) / 1024, SUM(S.io_stall_write_ms),
                 SUM(S.size_on_disk_bytes) / 1024
            FROM sys.dm_io_virtual_file_stats(NULL, NULL) S
              LEFT JOIN sys.databases D ON D.database_id = S.database_id
              LEFT JOIN sys.master_files M ON M.database_id = S.database_id AND M.[file_id] = S.[file_id]
                LEFT JOIN sys.filegroups F ON S.database_id = DB_ID() AND F.data_space_id = M.data_space_id
           GROUP BY D.name, M.type_desc, F.name
           ORDER BY database_name, M.type_desc DESC
    OPEN @cursor
    FETCH NEXT FROM @cursor INTO @database_name, @file_type, @filegroup_name, @reads, @reads_kb, @io_stall_read, @writes, @writes_kb, @io_stall_write, @size_kb
    WHILE @@FETCH_STATUS = 0
    BEGIN
      SET @keyText = @database_name + ' :: ' + ISNULL(@filegroup_name, @file_type)

      EXEC zmetric.KeyCounters_InsertMulti 30009, 'D', @counterDate, 2000000007, NULL, @keyText,  @reads, @reads_kb, @io_stall_read, @writes, @writes_kb, @io_stall_write, @size_kb

      FETCH NEXT FROM @cursor INTO @database_name, @file_type, @filegroup_name, @reads, @reads_kb, @io_stall_read, @writes, @writes_kb, @io_stall_write, @size_kb
    END
    CLOSE @cursor
    DEALLOCATE @cursor
  END TRY
  BEGIN CATCH
    EXEC zsystem.CatchError 'zmetric.KeyCounters_SaveFileStats'
    RETURN -1
  END CATCH
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zmetric.KeyCounters_SaveWaitStats') IS NOT NULL
  DROP PROCEDURE zmetric.KeyCounters_SaveWaitStats
GO
CREATE PROCEDURE zmetric.KeyCounters_SaveWaitStats
  @checkSetting   bit = 1,
  @deleteOldData  bit = 0
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  BEGIN TRY
    IF @checkSetting = 1 AND zsystem.Settings_Value('zmetric', 'SaveWaitStats') != '1'
      RETURN

    DECLARE @counterDate date = GETDATE()

    IF @deleteOldData = 1
      DELETE FROM zmetric.keyCounters WHERE counterID = 30025 AND counterDate = @counterDate
    ELSE
    BEGIN
      IF EXISTS(SELECT * FROM zmetric.keyCounters WHERE counterID = 30025 AND counterDate = @counterDate)
        RAISERROR ('Wait stats data exists', 16, 1)
    END

    -- WAIT STATISTICS
    DECLARE @wait_type nvarchar(100), @waiting_tasks_count bigint, @wait_time_ms bigint, @signal_wait_time_ms bigint

    DECLARE @cursor CURSOR
    SET @cursor = CURSOR LOCAL FAST_FORWARD
      FOR SELECT wait_type, waiting_tasks_count, wait_time_ms, signal_wait_time_ms FROM sys.dm_os_wait_stats WHERE waiting_tasks_count > 0
    OPEN @cursor
    FETCH NEXT FROM @cursor INTO @wait_type, @waiting_tasks_count, @wait_time_ms, @signal_wait_time_ms
    WHILE @@FETCH_STATUS = 0
    BEGIN
      EXEC zmetric.KeyCounters_InsertMulti 30025, 'D', @counterDate, 2000000008, NULL, @wait_type,  @waiting_tasks_count, @wait_time_ms, @signal_wait_time_ms

      FETCH NEXT FROM @cursor INTO @wait_type, @waiting_tasks_count, @wait_time_ms, @signal_wait_time_ms
    END
    CLOSE @cursor
    DEALLOCATE @cursor
  END TRY
  BEGIN CATCH
    EXEC zsystem.CatchError 'zmetric.KeyCounters_SaveWaitStats'
    RETURN -1
  END CATCH
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zmetric.KeyCounters_SavePerfCountersTotal') IS NOT NULL
  DROP PROCEDURE zmetric.KeyCounters_SavePerfCountersTotal
GO
CREATE PROCEDURE zmetric.KeyCounters_SavePerfCountersTotal
  @checkSetting   bit = 1,
  @deleteOldData  bit = 0
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  BEGIN TRY
    IF @checkSetting = 1 AND zsystem.Settings_Value('zmetric', 'SavePerfCountersTotal') != '1'
      RETURN

    DECLARE @counterDate date = GETDATE()

    IF @deleteOldData = 1
      DELETE FROM zmetric.keyCounters WHERE counterID = 30027 AND counterDate = @counterDate
    ELSE
    BEGIN
      IF EXISTS(SELECT * FROM zmetric.keyCounters WHERE counterID = 30027 AND counterDate = @counterDate)
        RAISERROR ('Performance counters total data exists', 16, 1)
    END

    -- PERFORMANCE COUNTERS TOTAL
    DECLARE @object_name nvarchar(200), @counter_name nvarchar(200), @cntr_value bigint, @keyID int, @keyText nvarchar(450)

    DECLARE @cursor CURSOR
    SET @cursor = CURSOR LOCAL FAST_FORWARD
      FOR SELECT REPLACE(RTRIM([object_name]), 'SQLServer:', ''),
                 CASE WHEN [object_name] = 'SQLServer:SQL Errors' THEN RTRIM(instance_name) ELSE RTRIM(counter_name) END,
                 cntr_value
            FROM sys.dm_os_performance_counters
           WHERE cntr_type = 272696576
             AND cntr_value != 0
             AND (    ([object_name] = 'SQLServer:Access Methods' AND instance_name = '')
                   OR ([object_name] = 'SQLServer:Buffer Manager' AND instance_name = '')
                   OR ([object_name] = 'SQLServer:General Statistics' AND instance_name = '')
                   OR ([object_name] = 'SQLServer:Latches' AND instance_name = '')
                   OR ([object_name] = 'SQLServer:Access Methods' AND instance_name = '')
                   OR ([object_name] = 'SQLServer:SQL Statistics' AND instance_name = '')
                   OR ([object_name] = 'SQLServer:Databases' AND instance_name = '_Total')
                   OR ([object_name] = 'SQLServer:Locks' AND instance_name = '_Total')
                   OR ([object_name] = 'SQLServer:SQL Errors' AND instance_name != '_Total')
                 )
    OPEN @cursor
    FETCH NEXT FROM @cursor INTO @object_name, @counter_name, @cntr_value
    WHILE @@FETCH_STATUS = 0
    BEGIN
      SET @keyText = @object_name + ' :: ' + @counter_name

      EXEC @keyID = zsystem.LookupValues_Update 2000000009, NULL, @keyText

      INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (30027, @counterDate, 0, @keyID, @cntr_value)

      FETCH NEXT FROM @cursor INTO @object_name, @counter_name, @cntr_value
    END
    CLOSE @cursor
    DEALLOCATE @cursor

    -- ADDING A FEW SYSTEM FUNCTIONS TO THE MIX
    -- Azure does not support @@PACK_RECEIVED, @@PACK_SENT, @@PACKET_ERRORS, @@TOTAL_READ, @@TOTAL_WRITE and @@TOTAL_ERRORS
    IF CONVERT(varchar(max), SERVERPROPERTY('edition')) NOT LIKE '%Azure%'
    BEGIN
      DECLARE @pack_received int, @pack_sent int, @packet_errors int, @total_read int, @total_write int, @total_errors int

      EXEC sp_executesql N'
        SELECT @pack_received = @@PACK_RECEIVED, @pack_sent = @@PACK_SENT, @packet_errors = @@PACKET_ERRORS,
               @total_read = @@TOTAL_READ, @total_write = @@TOTAL_WRITE, @total_errors = @@TOTAL_ERRORS',
        N'@pack_received int OUTPUT, @pack_sent int OUTPUT, @packet_errors int OUTPUT, @total_read int OUTPUT, @total_write int OUTPUT, @total_errors int OUTPUT',
        @pack_received OUTPUT, @pack_sent OUTPUT, @packet_errors OUTPUT, @total_read OUTPUT, @total_write OUTPUT, @total_errors OUTPUT

      EXEC @keyID = zsystem.LookupValues_Update 2000000009, NULL, '@@PACK_RECEIVED'
      INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (30027, @counterDate, 0, @keyID, @pack_received)

      EXEC @keyID = zsystem.LookupValues_Update 2000000009, NULL, '@@PACK_SENT'
      INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (30027, @counterDate, 0, @keyID, @pack_sent)

      IF @packet_errors != 0
      BEGIN
        EXEC @keyID = zsystem.LookupValues_Update 2000000009, NULL, '@@PACKET_ERRORS'
        INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (30027, @counterDate, 0, @keyID, @packet_errors)
      END

      EXEC @keyID = zsystem.LookupValues_Update 2000000009, NULL, '@@TOTAL_READ'
      INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (30027, @counterDate, 0, @keyID, @total_read)

      EXEC @keyID = zsystem.LookupValues_Update 2000000009, NULL, '@@TOTAL_WRITE'
      INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (30027, @counterDate, 0, @keyID, @total_write)

      IF @total_errors != 0
      BEGIN
        EXEC @keyID = zsystem.LookupValues_Update 2000000009, NULL, '@@TOTAL_ERRORS'
        INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (30027, @counterDate, 0, @keyID, @total_errors)
      END
    END
  END TRY
  BEGIN CATCH
    EXEC zsystem.CatchError 'zmetric.KeyCounters_SavePerfCountersTotal'
    RETURN -1
  END CATCH
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zmetric.KeyCounters_SavePerfCountersInstance') IS NOT NULL
  DROP PROCEDURE zmetric.KeyCounters_SavePerfCountersInstance
GO
CREATE PROCEDURE zmetric.KeyCounters_SavePerfCountersInstance
  @checkSetting   bit = 1,
  @deleteOldData  bit = 0
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  BEGIN TRY
    IF @checkSetting = 1 AND zsystem.Settings_Value('zmetric', 'SavePerfCountersInstance') != '1'
      RETURN

    DECLARE @counterDate date = GETDATE()

    IF @deleteOldData = 1
      DELETE FROM zmetric.keyCounters WHERE counterID = 30028 AND counterDate = @counterDate
    ELSE
    BEGIN
      IF EXISTS(SELECT * FROM zmetric.keyCounters WHERE counterID = 30028 AND counterDate = @counterDate)
        RAISERROR ('Performance counters instance data exists', 16, 1)
    END

    -- PERFORMANCE COUNTERS INSTANCE
    DECLARE @object_name nvarchar(200), @counter_name nvarchar(200), @cntr_value bigint, @keyID int, @keyText nvarchar(450)

    DECLARE @cursor CURSOR
    SET @cursor = CURSOR LOCAL FAST_FORWARD
      FOR SELECT REPLACE(RTRIM([object_name]), 'SQLServer:', ''), RTRIM(counter_name), cntr_value
            FROM sys.dm_os_performance_counters
           WHERE cntr_type = 272696576 AND cntr_value != 0 AND instance_name = DB_NAME()
    OPEN @cursor
    FETCH NEXT FROM @cursor INTO @object_name, @counter_name, @cntr_value
    WHILE @@FETCH_STATUS = 0
    BEGIN
      SET @keyText = @object_name + ' :: ' + @counter_name

      EXEC @keyID = zsystem.LookupValues_Update 2000000009, NULL, @keyText

      INSERT INTO zmetric.keyCounters (counterID, counterDate, columnID, keyID, value) VALUES (30028, @counterDate, 0, @keyID, @cntr_value)

      FETCH NEXT FROM @cursor INTO @object_name, @counter_name, @cntr_value
    END
    CLOSE @cursor
    DEALLOCATE @cursor
  END TRY
  BEGIN CATCH
    EXEC zsystem.CatchError 'zmetric.KeyCounters_SavePerfCountersInstance'
    RETURN -1
  END CATCH
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zmetric.Counters_SaveStats') IS NOT NULL
  DROP PROCEDURE zmetric.Counters_SaveStats
GO
CREATE PROCEDURE zmetric.Counters_SaveStats
AS
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  EXEC zmetric.KeyCounters_SaveIndexStats
  EXEC zmetric.KeyCounters_SaveProcStats
  EXEC zmetric.KeyCounters_SaveFileStats
  EXEC zmetric.KeyCounters_SaveWaitStats
  EXEC zmetric.KeyCounters_SavePerfCountersTotal
  EXEC zmetric.KeyCounters_SavePerfCountersInstance

  --
  -- Auto delete old data
  --
  DECLARE @autoDeleteMaxRows int = zsystem.Settings_Value('zmetric', 'AutoDeleteMaxRows')
  IF @autoDeleteMaxRows < 1
    RETURN

  DECLARE @counterDate date, @counterDateTime datetime2(0)

  DECLARE @counterID smallint, @counterTable nvarchar(256), @autoDeleteMaxDays smallint

  DECLARE @cursor CURSOR
  SET @cursor = CURSOR LOCAL FAST_FORWARD
    FOR SELECT counterID, counterTable, autoDeleteMaxDays FROM zmetric.counters WHERE autoDeleteMaxDays > 0 ORDER BY counterID
  OPEN @cursor
  FETCH NEXT FROM @cursor INTO @counterID, @counterTable, @autoDeleteMaxDays
  WHILE @@FETCH_STATUS = 0
  BEGIN
    SET @counterDate = DATEADD(day, -@autoDeleteMaxDays, GETDATE())
    SET @counterDateTime = @counterDate

    IF @counterTable = 'zmetric.keyCounters'
    BEGIN
      DELETE TOP (@autoDeleteMaxRows) FROM zmetric.keyCounters WHERE counterID = @counterID AND counterDate < @counterDate
--      DELETE TOP (@autoDeleteMaxRows) FROM zmetric.keyTimeCounters WHERE counterID = @counterID AND counterDate < @counterDateTime
    END
--    ELSE IF @counterTable = 'zmetric.subjectKeyCounters'
--      DELETE TOP (@autoDeleteMaxRows) FROM zmetric.subjectKeyCounters WHERE counterID = @counterID AND counterDate < @counterDate
--    ELSE IF @counterTable = 'zmetric.simpleCounters'
--      DELETE TOP (@autoDeleteMaxRows) FROM zmetric.simpleCounters WHERE counterID = @counterID AND counterDate < @counterDateTime

    FETCH NEXT FROM @cursor INTO @counterID, @counterTable, @autoDeleteMaxDays
  END
  CLOSE @cursor
  DEALLOCATE @cursor
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zmetric.Counters_ReportDates') IS NOT NULL
  DROP PROCEDURE zmetric.Counters_ReportDates
GO
CREATE PROCEDURE zmetric.Counters_ReportDates
  @counterID      smallint,
  @counterDate    date = NULL,
  @seek           char(1) = NULL -- NULL / O:Older / N:Newer
AS
  -- Get date to use for zmetric.Counters_ReportData
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  BEGIN TRY
    IF @counterID IS NULL
      RAISERROR ('@counterID not set', 16, 1)

    IF @seek IS NOT NULL AND @seek NOT IN ('O', 'N')
      RAISERROR ('Only seek types O and N are supported', 16, 1)

    DECLARE @counterTable nvarchar(256), @counterType char(1)
    SELECT @counterTable = counterTable, @counterType = counterType FROM zmetric.counters  WHERE counterID = @counterID
    IF @counterTable IS NULL AND @counterType = 'D'
        SET @counterTable = 'zmetric.dateCounters'
    IF @counterTable IS NULL OR @counterTable NOT IN ('zmetric.keyCounters', 'zmetric.subjectKeyCounters', 'zmetric.dateCounters')
      RAISERROR ('Counter table not supported', 16, 1)

    DECLARE @dateRequested date, @dateReturned date

    IF @counterDate IS NULL
    BEGIN
      SET @dateRequested = DATEADD(day, -1, GETDATE())

      IF @counterTable = 'zmetric.dateCounters'
        SELECT TOP 1 @dateReturned = counterDate FROM zmetric.dateCounters WHERE counterID = @counterID AND counterDate <= @dateRequested ORDER BY counterDate DESC
      ELSE IF @counterTable = 'zmetric.subjectKeyCounters'
        SELECT TOP 1 @dateReturned = counterDate FROM zmetric.subjectKeyCounters WHERE counterID = @counterID AND counterDate <= @dateRequested ORDER BY counterDate DESC
      ELSE
        SELECT TOP 1 @dateReturned = counterDate FROM zmetric.keyCounters WHERE counterID = @counterID AND counterDate <= @dateRequested ORDER BY counterDate DESC
    END
    ELSE
    BEGIN
      SET @dateRequested = @counterDate

      IF @seek IS NULL
        SET @dateReturned = @counterDate
      ELSE
      BEGIN
        IF @counterTable = 'zmetric.dateCounters'
        BEGIN
          IF NOT EXISTS(SELECT * FROM zmetric.dateCounters WHERE counterID = @counterID AND counterDate = @counterDate)
          BEGIN
            IF @seek = 'O'
              SELECT TOP 1 @dateReturned = counterDate FROM zmetric.dateCounters WHERE counterID = @counterID AND counterDate < @counterDate ORDER BY counterDate DESC
            ELSE
              SELECT TOP 1 @dateReturned = counterDate FROM zmetric.dateCounters WHERE counterID = @counterID AND counterDate > @counterDate ORDER BY counterDate
          END
        END
        ELSE IF @counterTable = 'zmetric.subjectKeyCounters'
        BEGIN
          IF NOT EXISTS(SELECT * FROM zmetric.subjectKeyCounters WHERE counterID = @counterID AND counterDate = @counterDate)
          BEGIN
            IF @seek = 'O'
              SELECT TOP 1 @dateReturned = counterDate FROM zmetric.subjectKeyCounters WHERE counterID = @counterID AND counterDate < @counterDate ORDER BY counterDate DESC
            ELSE
              SELECT TOP 1 @dateReturned = counterDate FROM zmetric.subjectKeyCounters WHERE counterID = @counterID AND counterDate > @counterDate ORDER BY counterDate
          END
        END
        ELSE
        BEGIN
          IF NOT EXISTS(SELECT * FROM zmetric.keyCounters WHERE counterID = @counterID AND counterDate = @counterDate)
          BEGIN
            IF @seek = 'O'
              SELECT TOP 1 @dateReturned = counterDate FROM zmetric.keyCounters WHERE counterID = @counterID AND counterDate < @counterDate ORDER BY counterDate DESC
            ELSE
              SELECT TOP 1 @dateReturned = counterDate FROM zmetric.keyCounters WHERE counterID = @counterID AND counterDate > @counterDate ORDER BY counterDate
          END
        END
      END
    END

    IF @dateReturned IS NULL
      SET @dateReturned = @dateRequested

    SELECT dateRequested = @dateRequested, dateReturned = @dateReturned
  END TRY
  BEGIN CATCH
    EXEC zsystem.CatchError 'zmetric.Counters_ReportDates'
    RETURN -1
  END CATCH
GO
GRANT EXEC ON zmetric.Counters_ReportDates TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------


IF OBJECT_ID('zmetric.Counters_ReportData') IS NOT NULL
  DROP PROCEDURE zmetric.Counters_ReportData
GO
CREATE PROCEDURE zmetric.Counters_ReportData
  @counterID      smallint,
  @fromDate       date = NULL,
  @toDate         date = NULL,
  @rows           int = 20,
  @orderColumnID  smallint = NULL,
  @orderDesc      bit = 1,
  @lookupText     nvarchar(1000) = NULL
AS
  -- Create dynamic SQL to return report used on INFO - Metrics
  SET NOCOUNT ON
  SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  BEGIN TRY
    IF @counterID IS NULL
      RAISERROR ('@counterID not set', 16, 1)

    IF @fromDate IS NULL
      RAISERROR ('@fromDate not set', 16, 1)

    IF @rows > 10000
      RAISERROR ('@rows over limit', 16, 1)

    IF @toDate IS NOT NULL AND @toDate = @fromDate
      SET @toDate = NULL

    DECLARE @counterTable nvarchar(256), @counterType char(1), @subjectLookupTableID int, @keyLookupTableID int
    SELECT @counterTable = counterTable, @counterType = counterType, @subjectLookupTableID = subjectLookupTableID, @keyLookupTableID = keyLookupTableID
      FROM zmetric.counters
     WHERE counterID = @counterID
    IF @counterTable IS NULL AND @counterType = 'D'
      SET @counterTable = 'zmetric.dateCounters'
    IF @counterTable IS NULL OR @counterTable NOT IN ('zmetric.keyCounters', 'zmetric.subjectKeyCounters', 'zmetric.dateCounters')
      RAISERROR ('Counter table not supported', 16, 1)
    IF @subjectLookupTableID IS NOT NULL AND @keyLookupTableID IS NULL
      RAISERROR ('Counter is not valid, subject lookup set and key lookup not set', 16, 1)
    IF @counterTable = 'zmetric.keyCounters' AND @subjectLookupTableID IS NOT NULL
      RAISERROR ('Key counter is not valid, subject lookup set', 16, 1)
    IF @counterTable = 'zmetric.subjectKeyCounters' AND (@subjectLookupTableID IS NULL OR @keyLookupTableID IS NULL)
      RAISERROR ('Subject/Key counter is not valid, subject lookup or key lookup not set', 16, 1)

    DECLARE @sql nvarchar(max)

    IF @subjectLookupTableID IS NOT NULL AND @keyLookupTableID IS NOT NULL
    BEGIN
      -- Subject + Key, Single column
      IF @counterType != 'D'
        RAISERROR ('Counter is not valid, subject and key lookup set and counter not of type D', 16, 1)
      SET @sql = 'SELECT TOP (@pRows) C.subjectID, subjectText = ISNULL(S.fullText, S.lookupText), C.keyID, keyText = ISNULL(K.fullText, K.lookupText), '
      IF @toDate IS NULL
        SET @sql = @sql + 'C.value'
      ELSE
        SET @sql = @sql + 'value = SUM(C.value)'
      SET @sql = @sql + CHAR(13) + ' FROM ' + @counterTable + ' C'
      SET @sql = @sql + CHAR(13) + ' LEFT JOIN zsystem.lookupValues S ON S.lookupTableID = @pSubjectLookupTableID AND S.lookupID = C.subjectID'
      SET @sql = @sql + CHAR(13) + ' LEFT JOIN zsystem.lookupValues K ON K.lookupTableID = @pKeyLookupTableID AND K.lookupID = C.keyID'
      SET @sql = @sql + CHAR(13) + ' WHERE C.counterID = @pCounterID AND '
      IF @toDate IS NULL
        SET @sql = @sql + 'C.counterDate = @pFromDate'
      ELSE
        SET @sql = @sql + 'C.counterDate BETWEEN @pFromDate AND @pToDate'

      -- *** *** *** temporarily hard coding columnID = 0 *** *** ***
      IF @counterTable = 'zmetric.subjectKeyCounters'
        SET @sql = @sql + ' AND C.columnID = 0'

      IF @lookupText IS NOT NULL AND @lookupText != ''
        SET @sql = @sql + ' AND (ISNULL(S.fullText, S.lookupText) LIKE ''%'' + @pLookupText + ''%'' OR ISNULL(K.fullText, K.lookupText) LIKE ''%'' + @pLookupText + ''%'')'
      IF @toDate IS NOT NULL
        SET @sql = @sql + CHAR(13) + ' GROUP BY C.subjectID, ISNULL(S.fullText, S.lookupText), C.keyID, ISNULL(K.fullText, K.lookupText)'
      SET @sql = @sql + CHAR(13) + ' ORDER BY 5'
      IF @orderDesc = 1
        SET @sql = @sql + ' DESC'
      EXEC sp_executesql @sql,
                         N'@pRows int, @pCounterID smallint, @pSubjectLookupTableID int, @pKeyLookupTableID int, @pFromDate date, @pToDate date, @pLookupText nvarchar(1000)',
                         @rows, @counterID, @subjectLookupTableID, @keyLookupTableID, @fromDate, @toDate, @lookupText
    END
    ELSE
    BEGIN
      IF EXISTS(SELECT * FROM zmetric.columns WHERE counterID = @counterID)
      BEGIN
        -- Multiple columns (Single value / Multiple key values)
        DECLARE @columnID tinyint, @columnName nvarchar(200), @orderBy nvarchar(200), @sql2 nvarchar(max) = '', @alias nvarchar(10)
        IF @keyLookupTableID IS NULL
          SET @sql = 'SELECT TOP 1 '
        ELSE
          SET @sql = 'SELECT TOP (@pRows) C.keyID, keyText = ISNULL(K.fullText, K.lookupText)'
         SET @sql2 = ' FROM ' + @counterTable + ' C'
        IF @keyLookupTableID IS NOT NULL
          SET @sql2 = @sql2 + CHAR(13) + '    LEFT JOIN zsystem.lookupValues K ON K.lookupTableID = @pKeyLookupTableID AND K.lookupID = C.keyID'
        DECLARE @cursor CURSOR
        SET @cursor = CURSOR LOCAL FAST_FORWARD
          FOR SELECT columnID, columnName FROM zmetric.columns WHERE counterID = @counterID ORDER BY [order], columnID
        OPEN @cursor
        FETCH NEXT FROM @cursor INTO @columnID, @columnName
        WHILE @@FETCH_STATUS = 0
        BEGIN
          IF @orderColumnID IS NULL SET @orderColumnID = @columnID
          IF @columnID = @orderColumnID SET @orderBy = @columnName
          SET @alias = 'C'
          IF @columnID != @orderColumnID
            SET @alias = @alias + CONVERT(nvarchar, @columnID)
          IF @sql != 'SELECT TOP 1 '
            SET @sql = @sql + ',' + CHAR(13) + '       '
          SET @sql = @sql + '[' + @columnName + '] = '
          IF @toDate IS NULL
            SET @sql = @sql + 'ISNULL(' + @alias + '.value, 0)'
          ELSE
            SET @sql = @sql + 'SUM(ISNULL(' + @alias + '.value, 0))'
          IF @columnID = @orderColumnID
            SET @orderBy = '[' + @columnName + ']'
          ELSE
          BEGIN
            SET @sql2 = @sql2 + CHAR(13) + '    LEFT JOIN ' + @counterTable + ' ' + @alias + ' ON ' + @alias + '.counterID = C.counterID'

            IF @counterTable IN ('zmetric.keyCounters', 'zmetric.subjectKeyCounters')
              SET @sql2 = @sql2 + ' AND ' + @alias + '.columnID = ' + CONVERT(nvarchar, @columnID)

            IF @counterTable IN ('zmetric.subjectKeyCounters', 'zmetric.dateCounters')
              SET @sql2 = @sql2 + ' AND ' + @alias + '.subjectID = ' + CONVERT(nvarchar, @columnID)

            SET @sql2 = @sql2 + ' AND ' + @alias + '.counterDate = C.counterDate AND ' + @alias + '.keyID = C.keyID'
          END
          FETCH NEXT FROM @cursor INTO @columnID, @columnName
        END
        CLOSE @cursor
        DEALLOCATE @cursor
        SET @sql = @sql + CHAR(13) + @sql2
        SET @sql = @sql + CHAR(13) + ' WHERE C.counterID = @pCounterID AND '
        IF @toDate IS NULL
          SET @sql = @sql + 'C.counterDate = @pFromDate AND'
        ELSE
          SET @sql = @sql + 'C.counterDate BETWEEN @pFromDate AND @pToDate AND'

        IF @counterTable IN ('zmetric.keyCounters', 'zmetric.subjectKeyCounters')
          SET @sql = @sql + ' C.columnID = ' + CONVERT(nvarchar, @orderColumnID)

        IF @counterTable IN ('zmetric.subjectKeyCounters', 'zmetric.dateCounters')
          SET @sql = @sql + ' C.subjectID = ' + CONVERT(nvarchar, @orderColumnID)

        IF @keyLookupTableID IS NOT NULL
        BEGIN
          IF @lookupText IS NOT NULL AND @lookupText != ''
            SET @sql = @sql + ' AND ISNULL(K.fullText, K.lookupText) LIKE ''%'' + @pLookupText + ''%'''
          IF @toDate IS NOT NULL
            SET @sql = @sql + CHAR(13) + ' GROUP BY C.keyID, ISNULL(K.fullText, K.lookupText)'
          SET @sql = @sql + CHAR(13) + ' ORDER BY ' + @orderBy
          IF @orderDesc = 1
            SET @sql = @sql + ' DESC'
        END
        SET @sql = @sql + CHAR(13) + 'OPTION (FORCE ORDER)'
        EXEC sp_executesql @sql,
                           N'@pRows int, @pCounterID smallint, @pKeyLookupTableID int, @pFromDate date, @pToDate date, @pLookupText nvarchar(1000)',
                           @rows, @counterID, @keyLookupTableID, @fromDate, @toDate, @lookupText
      END
      ELSE
      BEGIN
        -- Single column
        IF @keyLookupTableID IS NULL
        BEGIN
          -- Single value, Single column
          SET @sql = 'SELECT TOP 1 '
          IF @toDate IS NULL
            SET @sql = @sql + 'value'
          ELSE
            SET @sql = @sql + 'value = SUM(value)'
          SET @sql = @sql + ' FROM ' + @counterTable + ' WHERE counterID = @pCounterID AND '
          IF @toDate IS NULL
            SET @sql = @sql + 'counterDate = @pFromDate'
          ELSE
            SET @sql = @sql + 'counterDate BETWEEN @pFromDate AND @pToDate'
          EXEC sp_executesql @sql, N'@pCounterID smallint, @pFromDate date, @pToDate date', @counterID, @fromDate, @toDate
        END
        ELSE
        BEGIN
          -- Multiple key values, Single column (not using WHERE subjectID = 0 as its not in the index, trusting that its always 0)
          SET @sql = 'SELECT TOP (@pRows) C.keyID, keyText = ISNULL(K.fullText, K.lookupText), '
          IF @toDate IS NULL
            SET @sql = @sql + 'C.value'
          ELSE
            SET @sql = @sql + 'value = SUM(C.value)'
          SET @sql = @sql + CHAR(13) + '  FROM ' + @counterTable + ' C'
          SET @sql = @sql + CHAR(13) + '    LEFT JOIN zsystem.lookupValues K ON K.lookupTableID = @pKeyLookupTableID AND K.lookupID = C.keyID'
          SET @sql = @sql + CHAR(13) + ' WHERE C.counterID = @pCounterID AND '
          IF @toDate IS NULL
            SET @sql = @sql + 'C.counterDate = @pFromDate'
          ELSE
            SET @sql = @sql + 'C.counterDate BETWEEN @pFromDate AND @pToDate'
          IF @lookupText IS NOT NULL AND @lookupText != ''
            SET @sql = @sql + ' AND ISNULL(K.fullText, K.lookupText) LIKE ''%'' + @pLookupText + ''%'''
          IF @toDate IS NOT NULL
            SET @sql = @sql + CHAR(13) + ' GROUP BY C.keyID, ISNULL(K.fullText, K.lookupText)'
          SET @sql = @sql + CHAR(13) + ' ORDER BY 3'
          IF @orderDesc = 1
            SET @sql = @sql + ' DESC'
          EXEC sp_executesql @sql,
                             N'@pRows int, @pCounterID smallint, @pKeyLookupTableID int, @pFromDate date, @pToDate date, @pLookupText nvarchar(1000)',
                             @rows, @counterID, @keyLookupTableID, @fromDate, @toDate, @lookupText
        END
      END
    END
  END TRY
  BEGIN CATCH
    EXEC zsystem.CatchError 'zmetric.Counters_ReportData'
    RETURN -1
  END CATCH
GO
GRANT EXEC ON zmetric.Counters_ReportData TO zzp_server
GO


---------------------------------------------------------------------------------------------------------------------------------



GO
EXEC zsystem.Versions_Finish 'CORE', 0002, 'jorundur'
GO
