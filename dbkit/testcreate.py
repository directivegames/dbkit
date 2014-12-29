import argparse
import pytds

from datetime import datetime

import tenant


if __name__ == "__main__":

    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)

    parser.add_argument("-S", "--server", action="store", nargs="?", required=True, help="Server")
    parser.add_argument("-U", "--login", action="store", nargs="?", required=True, help="Login")
    parser.add_argument("-P", "--password", action="store", nargs="?", required=True, help="Password")

    parser.add_argument("-t", "--tenant", action="store", nargs="?", default=None, help="Tenant, if not set testYYYYMMDD will be used")

    parser.add_argument("-USESINGLEDB", action="store_true", help="Direct all service databases to a single database")

    parser.add_argument("-DBSERVER", action="store", nargs="?", default=None, help="Direct all service databases to a different server")

    args = parser.parse_args()

    tier = "DEV"

    server = args.server

    if not args.tenant:
        now = datetime.now()
        args.tenant = "test%d%d%d" % (now.year, now.month, now.day)

    print ""
    print ">>> TEST CREATE CLEANUP FOR TENANT", args.tenant

    print ""
    tenant.add(server, args.login, args.password, tier, args.tenant)

    if args.DBSERVER:
        print ""
        tenant.edit(server, args.login, args.password, tier, args.tenant, "dbServer", args.DBSERVER)

    if args.USESINGLEDB:
        print ""
        tenant.edit(server, args.login, args.password, tier, args.tenant, "useSingleDb", "1")

    tenant.create_db(server, args.login, args.password, tier, args.tenant)

    print ""
    print ">>> TEST CREATE DONE FOR TENANT", args.tenant
