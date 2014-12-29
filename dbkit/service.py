import pytds

from util import print_split, pad_str, dbcursor_admin


def list(server, login, password, tier):

    cursor = dbcursor_admin(server, login, password, tier)

    cursor.execute("SELECT service FROM admin.services ORDER BY service")
    print_split(50)
    print "SERVICE"
    print_split(50)
    for r in cursor.fetchall():
        print pad_str(r.service, 50)
    print_split(50)
