import argparse
import pytds


def execute_block(cursor, block):
    if block == "":
        return
    try:
        block = block.replace("\n", "\r\n")
        cursor.execute(block)
    except Exception:
        print "-- " + "*"*76
        print "-- >>>"
        print "-- >>> ERROR..."
        print "-- >>>"
        print block
        print "-- " + "*"*76
        raise
    # print warnings, skipping proc dependency, partition scheme create and PRINT
    if len(cursor.messages) > 0:
        msgclass, msg = cursor.messages[0]
        if "message 0, severity 0, state 1" not in msg.message:
            print "-- >>>"
            print "-- >>> WARNING..."
            print "-- >>>"
            for msgclass, msg in cursor.messages:
                print "-- " + msg.message


if __name__ == "__main__":

    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)

    parser.add_argument("-S", "--server", action="store", nargs="?", required=True, help="Server")

    parser.add_argument('-U', '--login', action='store', nargs='?', required=True, help="Login")

    parser.add_argument('-P', '--password', action='store', nargs='?', required=True, help="Password")

    parser.add_argument('-s', '--service', action='store', nargs='?', required=True, help="Service")

    parser.add_argument('-v', '--version', action='store', nargs='?', required=True, help="Version number of DB update")

    parser.add_argument("-OLDUPDATE", action="store_true", help="Allow spamming an old update")

    args = parser.parse_args()

    # connect to admin db
    dbconn_admin = pytds.connect(
        server=args.server,
        database="DEV_admin",
        user=args.login,
        password=args.password,
        autocommit=True,
        appname="dbkit",
        row_strategy=pytds.namedtuple_row_strategy,
    )
    cursor_admin = dbconn_admin.cursor()

    # check service
    service = ""
    folder = ""
    if args.service in ["core", "dbcore", "coredb"]:
        service = "core"
        folder = "dbcore"
    else:
        cursor_admin.execute("SELECT service, dbFolder FROM admin.services WHERE service = '%s'" % args.service)
        r = cursor_admin.fetchone()
        if r:
            service = r.service
            if r.dbFolder is None:
                folder = "%s\db" % service
            else:
                folder = r.dbFolder
    if service == "":
        raise RuntimeError("Service not found")

    # set path to db update file
    update_path = "..\\" + folder
    update_path += "\\updates\\"
    if service == "core":
        update_path += "core"
    else:
        update_path += args.service.lower()
    update_path += "Update"
    update_path += ("0000" + str(int(args.version)))[-4:]
    update_path += ".sql"

    # read from db update file
    with open(update_path, "r") as f:
        sql = f.read()
        sql = sql.decode("latin-1")
    blocks = sql.split("\nGO\n")

    # loop over databases and execute db update for each database
    if service == "core":
        developer = "CORE"
    else:
        developer = service.upper()
    first_database = ""
    if service == "core":
        cursor_admin.execute("SELECT [server], [database] FROM admin.databases")
    else:
        cursor_admin.execute("SELECT [server], [database] FROM admin.databases WHERE [service] = '%s'" % service)
    print ""
    for r in cursor_admin.fetchall():

        dbconn = pytds.connect(
            server = r.server,
            database = r.database,
            user = args.login,
            password = args.password,
            autocommit = True,
            appname = "dbkit",
            row_strategy = pytds.namedtuple_row_strategy,
        )
        cursor = dbconn.cursor()

        if first_database == "":
            first_database = r.database
            cursor.execute("SELECT maxVersion = MAX(version) FROM zsystem.versions WHERE developer = '%s'" % developer)
            max_version = cursor.fetchone().maxVersion
            if max_version > int(args.version):
                if args.OLDUPDATE:
                    print "#"
                    print "# Old update!  Spamming version %s when max version is %s!" % (args.version, max_version)
                    print "#"
                    print ""
                else:
                    raise RuntimeError("Trying to spam version %s when max version is %s, parameter -OLDUPDATE is needed for spamming old updates!" % (args.version, max_version))

        print "UPDATING DATABASE %s" % r.database
        print ""

        for block in blocks:
            execute_block(cursor, block)
