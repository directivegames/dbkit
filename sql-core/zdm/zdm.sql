
--
-- SCHEMA
--

IF SCHEMA_ID('zdm') IS NULL
  EXEC sp_executesql N'CREATE SCHEMA zdm'
GO
