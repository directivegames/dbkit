import pytds


def print_split(len, chr="-"):
    print "-"*len


def pad_str(str, len, chr=" "):
    return (str + chr*len)[:len]


def dbconn_admin(server, login, password, tier):

    database = "vk_%s_admin" % tier

    return pytds.connect(
        server=server,
        database=database,
        user=login,
        password=password,
        autocommit=True,
        appname="dbkit",
        row_strategy=pytds.namedtuple_row_strategy,
    )


def dbcursor_admin(server, login, password, tier):

    database = "vk_%s_admin" % tier

    dbconn = pytds.connect(
        server=server,
        database=database,
        user=login,
        password=password,
        autocommit=True,
        appname="dbkit",
        row_strategy=pytds.namedtuple_row_strategy,
    )

    return dbconn.cursor()
