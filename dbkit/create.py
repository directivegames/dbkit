# dbk 0.1
#
# Copyright (C) 2014 CCP Games.
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.

#
# LIMITATIONS AND PROBLEMS
#
# GO statements need to be the only thing in a line, in upper case and with no leading or trailing spaces
# All CREATE XXX needs to be in upper case followed by one space
# SELECT and FROM in functions needs to be in upper case where SELECT is followed by one space and FROM is preceded and followed by one space
#
# There is a very weird silent error where a block with many INSERT statements does insert fewer rows than expected
#   This happened for zuser.countries.sql and zuser.videoDevices.sql where both tables ended up with only 159 rows (mega weird)
#   Splitting things into smaller blocks using GO "fixed" the problem
#

import argparse
import os
import os.path
import re
import json
from datetime import datetime

import pytds
from pytds.tds import DatabaseError, OperationalError, ProgrammingError


_print_filename=False

def print_filename(filename):
    if _print_filename:
        if _print_sql:
            print ""
        print "--", filename


_print_sql=False


def print_header(s, split="#"):
    print ""
    print "-- " + split*76
    print "-- >>>"
    print "-- >>> ", s
    print "-- >>>"


def read_files(folder):
    """
    Read all files in folder recursively and organize them into a list of (filename, sql) tuples
    """
    print_header("READING FILES FROM FOLDER (RECURSIVE)", "=")
    files = []
    for dirpath, dirnames, filenames in os.walk(folder):
        if not dirpath.endswith("updates"):
            for filename in filenames:
                root, ext = os.path.splitext(filename)
                if ext.lower() == ".sql":
                    full_path = os.path.join(dirpath, filename)
                    with open(full_path, "r") as f:
                        sql = f.read()
                        sql = sql.decode("latin-1")

                    files.append((filename, sql))
    return files


def read_move_files(folder):
    """
    Read move_files part of dbkit_rules.json file if it exists
    """
    dbCreateFileName = os.path.join(folder, "dbkit_rules.json")
    if os.path.exists(dbCreateFileName):
        print_header("READING MOVE FILES (dbkit_rules.json)", "=")
        with open(dbCreateFileName, "r") as f:
            dbCreate = json.load(f)

        move_files = dbCreate["move_files"]
    else:
        move_files = {}
    return move_files


def files_to_scripts(files, move_files):
    """
    organize files into a scripts dict
    """
    print_header("ORGANIZING FILES TO SCRIPTS DICT", "=")

    scripts = {}
    scripts["schemas"] = []
    scripts["functions 0"] = []
    scripts["functions"] = []
    scripts["types"] = []
    scripts["tables"] = []
    scripts["views 0"] = []
    scripts["views"] = []
    scripts["views 2"] = []
    scripts["views 3"] = []
    scripts["views 4"] = []
    scripts["procs"] = []
    scripts["partition functions"] = []
    scripts["partition schemes"] = []
    scripts["other"] = []

    files.sort()
    for filename, sql in files:

        if sql.endswith("\nGO"):
            sql = sql[:-3]

        t = (filename, sql)

        if filename in move_files:
            move_to = move_files[filename]
            if move_to == "skip":
                print "-- SKIPPING FILE " + filename
            else:
                scripts[move_to].append(t)
        elif filename.endswith("Ex.sql"):
            scripts["views 2"].append(t)
        elif "CREATE SCHEMA " in sql:
            scripts["schemas"].append(t)
        elif "CREATE ROLE " in sql:
            scripts["schemas"].append(t)
        elif "CREATE FUNCTION " in sql:
            scripts["functions"].append(t)
        elif "CREATE VIEW " in sql:
            scripts["views"].append(t)
        elif "CREATE PROCEDURE " in sql:
            scripts["procs"].append(t)
        elif "CREATE TYPE " in sql:
            scripts["types"].append(t)
        elif "CREATE TABLE " in sql:
            scripts["tables"].append(t)
        elif "CREATE PARTITION FUNCTION " in sql:
            scripts["partition functions"].append(t)
        elif "CREATE PARTITION SCHEME " in sql:
            scripts["partition schemes"].append(t)
        else:
            scripts["other"].append(t)

    return scripts


def execute_block(cursor, block, filename):
    if block == "":
        return
    try:
        block = block.replace("\n", "\r\n")
        cursor.execute(block)
    except Exception:
        print "-- " + "*"*76
        print "-- >>>"
        print "-- >>> ERROR IN FILE %s..." % filename
        print "-- >>>"
        print block
        print "-- " + "*"*76
        raise
    # print warnings, skipping proc dependency, partition scheme create and PRINT
    if len(cursor.messages) > 0:
        msgclass, msg = cursor.messages[0]
        if ("depends on the missing object" not in msg.message) and ("is marked as the next used filegroup" not in msg.message) and ("message 0, severity 0, state 1" not in msg.message):
            print "-- >>>"
            print "-- >>> WARNING IN FILE %s..." % filename
            print "-- >>>"
            for msgclass, msg in cursor.messages:
                print "-- " + msg.message
    # print sql if requested
    if _print_sql:
        print "-- " + "-"*76
        print "GO"
        print block
        print "GO"


def execute_scripts_header(scripts, scripts_key, extraInfo=""):
    fileCount = len(scripts[scripts_key])
    if fileCount > 0:
        print_header("EXECUTE SCRIPTS: %s %s (%d files)" % (scripts_key, extraInfo, fileCount))
    return fileCount


def execute_scripts(cursor, scripts, scripts_key):
    if execute_scripts_header(scripts, scripts_key):
        for filename, sql in scripts[scripts_key]:
            print_filename(filename)
            blocks = sql.split("\nGO\n")
            for block in blocks:
                execute_block(cursor, block, filename)


def get_highest_version(folder):
    folder = os.path.join(folder, "updates")
    highest_version = 0
    for dirpath, dirnames, filenames in os.walk(folder):
        for filename in filenames:
            m = re.search(r"(\d+)", filename)
            if m:
                version = int(m.groups()[0])
                if version > highest_version:
                    highest_version = version
        return highest_version
    raise RuntimeError("can't get highest version for %s" % folder)


def create_db(server, login, password, database, root, developer=None, DROPDB=False, FILENAMES=False, SQL=False):

    global _print_filename
    global _print_sql

    _print_filename = FILENAMES
    _print_sql = SQL

    start_time = datetime.now()

    # connect to datbase server, no database selected
    dbconn = pytds.connect(
        server=server,
        user=login,
        password=password,
        autocommit=True,
        appname="dbkit",
        row_strategy=pytds.namedtuple_row_strategy,
    )
    cursor = dbconn.cursor()

    # drop database, if -DROPDB in arguments
    if DROPDB:
        print_header("DROPPING DATABASE %s !!!" % database, "=")
        cursor = dbconn.cursor()
        try:
            cursor.execute("DROP DATABASE {db}".format(db=database))
        except OperationalError:
            print "ERROR IN DROP DATABASE !!!"
            pass  # This usually failes if the database does not exist

    # create database, if it does not exist
    cursor.execute("SELECT database_id FROM sys.databases WHERE name = '%s'" % database)
    r = cursor.fetchone()
    if r is None:
        print_header("DATABASE NOT FOUND, CREATING DATATABASE %s" % database, "=")
        cursor.execute("""
            CREATE DATABASE {db}
            ALTER DATABASE {db} SET RECOVERY SIMPLE
            """.format(db=database)
        )

    # connect to database
    dbconn = pytds.connect(
        server=server,
        database=database,
        user=login,
        password=password,
        autocommit=True,
        appname="dbkit",
        row_strategy=pytds.namedtuple_row_strategy,
    )
    cursor = dbconn.cursor()

    # read files and organize files to scripts
    files = read_files(root)
    move_files = read_move_files(root)
    scripts = files_to_scripts(files, move_files)

    # schemas, pass 1
    if execute_scripts_header(scripts, "schemas", "pass 1"):
        for filename, sql in scripts["schemas"]:
            print_filename(filename)
            blocks = sql.split("\nGO\n")
            for block in blocks:
                if ("CREATE SCHEMA " in block) or ("CREATE ROLE " in block) or ("CREATE TABLE " in block):
                    execute_block(cursor, block, filename)

    # functions 0
    execute_scripts(cursor, scripts, "functions 0")

    # functions, pass 1
    if execute_scripts_header(scripts, "functions", "pass 1"):
        for filename, sql in scripts["functions"]:
            if not(("SELECT " in sql) and (" FROM " in sql)):
                print_filename(filename)
                blocks = sql.split("\nGO\n")
                for block in blocks:
                    execute_block(cursor, block, filename)

    # partition functions
    execute_scripts(cursor, scripts, "partition functions")

    # partition schemes
    execute_scripts(cursor, scripts, "partition schemes")

    # types
    execute_scripts(cursor, scripts, "types")

    # tables, pass 1
    if execute_scripts_header(scripts, "tables", "pass 1"):
        for filename, sql in scripts["tables"]:
            print_filename(filename)
            blocks = sql.split("\nGO\n")
            for block in blocks:
                if "CREATE TABLE " in block:
                    execute_block(cursor, block, filename)

    # functions, pass 2
    if execute_scripts_header(scripts, "functions", "pass 2"):
        for filename, sql in scripts["functions"]:
            if ("SELECT " in sql) and (" FROM " in sql):
                print_filename(filename)
                blocks = sql.split("\nGO\n")
                for block in blocks:
                    execute_block(cursor, block, filename)

    # views 0
    execute_scripts(cursor, scripts, "views 0")

    # views
    execute_scripts(cursor, scripts, "views")

    # views 2
    execute_scripts(cursor, scripts, "views 2")

    # views 3
    execute_scripts(cursor, scripts, "views 3")

    # views 4
    execute_scripts(cursor, scripts, "views 4")

    # procs
    execute_scripts(cursor, scripts, "procs")

    # schemas, pass 2
    if execute_scripts_header(scripts, "schemas", "pass 2"):
        for filename, sql in scripts["schemas"]:
            print_filename(filename)
            blocks = sql.split("\nGO\n")
            for block in blocks:
                if not (("CREATE SCHEMA " in block) or ("CREATE ROLE " in block) or ("CREATE TABLE " in block)):
                    execute_block(cursor, block, filename)

    # tables, pass 2
    if execute_scripts_header(scripts, "tables", "pass 2"):
        for filename, sql in scripts["tables"]:
            print_filename(filename)
            blocks = sql.split("\nGO\n")
            for block in blocks:
                if "CREATE TABLE " not in block:
                    execute_block(cursor, block, filename)

    # other
    # schemas, pass 2
    if execute_scripts_header(scripts, "other"):
        for filename, sql in scripts["other"]:
            print_filename(filename)
            blocks = sql.split("\nGO\n")
            for block in blocks:
                if not "CREATE DATABASE " in block:
                    execute_block(cursor, block, filename)

    # insert version
    if developer:
        version = get_highest_version(root)
        print_header("APPLYING VERSION (%s, %s)" % (developer, version))
        cursor.execute("INSERT INTO zsystem.versions (developer, version, versionDate, userName, loginName, executionCount) VALUES ('%s', %d, GETUTCDATE(), 'dbkit', '%s', 0)" % (developer, version, login))

    stop_time = datetime.now()

    elapsed = stop_time - start_time
    print ""
    print "-- " + "="*76
    print "-- Execution time: %.1f seconds" % elapsed.total_seconds()
    print "-- " + "="*76


if __name__ == "__main__":

    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)

    parser.add_argument('-S', '--server', action='store', nargs='?', required=True, help="Server")

    parser.add_argument('-U', '--login', action='store', nargs='?', required=True, help="Login")

    parser.add_argument('-P', '--password', action='store', nargs='?', required=True, help="Password")

    parser.add_argument('-d', '--database', action='store', nargs='?', required=True, help="Database")

    parser.add_argument('-r', '--root', action='store', nargs='?', default=".", help="File root for SQL scripts.")

    parser.add_argument('-developer', '--developer', action='store', nargs='?', default=None, help="developer in zsystem.versions.")

    parser.add_argument("-DROPDB", action="store_true", help="Starts by dropping the database, CAREFUL!")

    parser.add_argument("-FILENAMES", action="store_true", help="Print filenames.")

    parser.add_argument("-SQL", action="store_true", help="Print SQL.")

    args = parser.parse_args()

    create_db(args.server, args.login, args.password, args.database, args.root, args.developer, args.DROPDB, args.FILENAMES, args.SQL)
