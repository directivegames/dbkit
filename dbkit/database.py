import pytds

from util import print_split, pad_str, dbcursor_admin


def list(server, login, password, tier):

    cursor = dbcursor_admin(server, login, password, tier)

    cursor.execute("SELECT server, [database] FROM admin.databases ORDER BY [database]")
    print_split(112)
    print pad_str("SERVER", 60) + "  " + pad_str("DATABASE", 50)
    print_split(112)
    for r in cursor.fetchall():
        print pad_str(r.server, 60) + "  " + pad_str(r.database, 50)
    print_split(112)
