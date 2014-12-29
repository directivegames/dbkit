
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


-- Data
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
