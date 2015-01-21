import pytds

from getpass import getuser
from datetime import datetime
import os

import create

from util import print_split, pad_str, dbconn_admin, dbcursor_admin


def list(server, login, password, tier):
    cursor = dbcursor_admin(server, login, password, tier)
    cursor.execute("SELECT tenant, useSingleDb FROM admin.tenants ORDER BY tenant")
    print_split(70)
    print pad_str("TENANT", 50) + "  " + pad_str("USE-SINGLE-DB", 20)
    print_split(70)
    for r in cursor.fetchall():
        useSingleDb = ""
        if r.useSingleDb:
            useSingleDb = "SINGLE-DB"
        print pad_str(r.tenant, 50) + "  " + pad_str(useSingleDb, 20)
    print_split(70)


def add(server, login, password, tier, tenant):
    cursor = dbcursor_admin(server, login, password, tier)
    cursor.callproc("admin.Tenants_Insert", (tenant, ))
    print "Tenant %s added" % tenant


def edit(server, login, password, tier, tenant, column, value):

    column = column.lower()
    if value.upper() == "NULL" or value.lower() == "none":
        value = None

    cursor = dbcursor_admin(server, login, password, tier)
    cursor.callproc("admin.Tenants_Select", (tenant, ))
    r = cursor.fetchone()
    if r is None:
        raise RuntimeError("Tenant not found")
    description = r.description
    dbServer = r.dbServer
    useSingleDb = r.useSingleDb
    spColor = r.spColor

    if column == "description":
        description = value
    elif column == "dbserver":
        dbServer = value
    elif column == "usesingledb":
        if value not in ("0", "1"):
            raise RuntimeError("Value not valid, needs to be 0 or 1")
        useSingleDb = value
    elif column == "spcolor":
        spColor = value
    else:
        raise RuntimeError("Column not valid, only description, dbServer, useSingleDb and spColor supported")

    cursor.callproc("admin.Tenants_Update", (tenant, description, dbServer, useSingleDb, spColor))

    print "Tenant %s updated (%s = %s)" % (tenant, column, value)


def remove(server, login, password, tier, tenant):
    cursor = dbcursor_admin(server, login, password, tier)
    cursor.callproc("admin.Tenants_Delete", (tenant, ))
    print "Tenant %s removed" % tenant


def create_db_for_tenant_service(server, login, password, tier, tenant, service):

    print "Creating DB for tenant '%s' and service '%s'" % (tenant, service)

    conn_admin = dbconn_admin(server, login, password, tier)
    cursor_admin = conn_admin.cursor()

    # check service
    cursor_admin.execute("SELECT multitenant, dbFolder FROM admin.services WHERE service = '%s'" % service)
    r = cursor_admin.fetchone()
    if r is None:
        raise RuntimeError("Service not registered in admin.services")
    if r.multitenant == 0:
        raise RuntimeError("Service not registered as multitenant in admin.services")
    folder = os.path.join("..", (r.dbFolder if r.dbFolder else ("sk-%s\db" % service)))
    developer = "SK-" + service.upper()

    # check tenant
    cursor_admin.execute("SELECT dbServer, useSingleDb FROM admin.tenants WHERE tenant = '%s'" % tenant)
    r = cursor_admin.fetchone()
    if r is None:
        raise RuntimeError("Tenant not registered in admin.tenants")
    server_tenant = r.dbServer if r.dbServer else server
    if r.useSingleDb:
        database = "vk_%s_%s_ALL" % (tier, tenant)
    else:
        database = "vk_%s_%s_%s" % (tier, tenant, service)

    # check database in admin.databases
    c = cursor_admin.execute_scalar("SELECT COUNT(*) FROM admin.databases WHERE service = '%s' AND tenant = '%s'" % (service, tenant))
    if c > 0:
        raise RuntimeError("Service %s and tenant %s already registered in admin.databases" % (service, tenant))

    # check if core part exists
    core_part_exists = False
    if server_tenant == server:
        conn_tenant = conn_admin
    else:
        conn_tenant = pytds.connect(
            server=server_tenant,
            user=login,
            password=password,
            autocommit=True,
            appname="dbkit",
            row_strategy=pytds.namedtuple_row_strategy,
        )
    cursor_tenant = conn_tenant.cursor()
    c = cursor_tenant.execute_scalar("SELECT COUNT(*) FROM sys.databases WHERE name = '%s'" % database)
    if c > 0:
        conn_tenant = pytds.connect(
            server=server_tenant,
            database=database,
            user=login,
            password=password,
            autocommit=True,
            appname="dbkit",
            row_strategy=pytds.namedtuple_row_strategy,
        )
        cursor_tenant = conn_tenant.cursor()

        c = cursor_tenant.execute_scalar("SELECT OBJECT_ID('zsystem.versions')")
        if c > 0:
            core_part_exists = True

    # create db, skipping core part if it already exists
    user = getuser()

    start_time = datetime.now()

    print ""
    print "CREATING DATABASE %s (SERVICE %s)" % (database, service)

    print ""
    print "CREATING CORE PART"

    if core_part_exists:
        print "CORE PART ALREADY EXISTS, SKIPPING!"
    else:
        create.create_db(server_tenant, login, password, database, os.path.join("sql-core"), "CORE")

    print ""
    print "CREATING %s PART" % developer

    create.create_db(server_tenant, login, password, database, folder, developer)

    stop_time = datetime.now()
    elapsed = stop_time - start_time

    cursor_admin.execute(
        "INSERT INTO admin.databases (service, tenant, server, [database], login, userName, duration) VALUES ('%s', '%s', '%s', '%s', '%s', '%s', %d)" % (
            service,
            tenant,
            server_tenant,
            database,
            "zzp_user_" + service,
            user,
            elapsed.total_seconds(),
        )
    )


def create_db(server, login, password, tier, tenant, service=None):

    if not tenant:
        raise RuntimeError("Missing parameter for tenant in createdb")

    if service:
        create_db_for_tenant_service(server, login, password, tier, tenant, service)
    else:
        cursor = dbcursor_admin(server, login, password, tier)

        cursor.execute("SELECT service FROM admin.services WHERE multitenant = 1 ORDER BY service")
        for r in cursor.fetchall():
            create_db_for_tenant_service(server, login, password, tier, tenant, r.service)


def drop_db_for_tenant_service(server, login, password, tier, tenant, service):

    conn_admin = dbconn_admin(server, login, password, tier)
    cursor_admin = conn_admin.cursor()

    # check service
    cursor_admin.execute("SELECT multitenant FROM admin.services WHERE service = '%s'" % service)
    r = cursor_admin.fetchone()
    if r is None:
        raise RuntimeError("Service not registered in admin.services")
    if r.multitenant == 0:
        raise RuntimeError("Service not registered as multitenant in admin.services")

    # check tenant
    cursor_admin.execute("SELECT dbServer, useSingleDb, locked FROM admin.tenants WHERE tenant = '%s'" % tenant)
    r = cursor_admin.fetchone()
    if r is None:
        raise RuntimeError("Tenant not registered in admin.tenants")
    if r.locked:
        raise RuntimeError("Tenant is locked, dbkit dropdb not allowed")
    server_tenant = r.dbServer if r.dbServer else server
    useSingleDb = r.useSingleDb
    if useSingleDb:
        database = "vk_%s_%s_ALL" % (tier, tenant)
    else:
        database = "vk_%s_%s_%s" % (tier, tenant, service)

    # check database in admin.databases
    c = cursor_admin.execute_scalar("SELECT COUNT(*) FROM admin.databases WHERE service = '%s' AND tenant = '%s'" % (service, tenant))
    if c == 0:
        raise RuntimeError("Service %s and tenant %s not registered in admin.databases" % (service, tenant))

    # drop db
    print ""
    print "DROPPING DATABASE %s (SERVICE %s)" % (database, service)
    if server_tenant == server:
        conn_tenant = conn_admin
    else:
        conn_tenant = pytds.connect(
            server=server_tenant,
            user=login,
            password=password,
            autocommit=True,
            appname="dbkit",
            row_strategy=pytds.namedtuple_row_strategy,
        )
    cursor_tenant = conn_tenant.cursor()
    c = cursor_tenant.execute_scalar("SELECT COUNT(*) FROM sys.databases WHERE name = '%s'" % database)
    if useSingleDb:
        if c == 0:
            print "DATABASE %s HAS ALREADY BEEN DROPPED, SKIPPING!" % database
        else:
            cursor_tenant.execute("ALTER DATABASE %s SET SINGLE_USER WITH ROLLBACK IMMEDIATE" % database)
            cursor_tenant.execute("DROP DATABASE %s" % database)
    else:
        if c == 0:
            raise RuntimeError("Database %s not found" % database)
        cursor_tenant.execute("ALTER DATABASE %s SET SINGLE_USER WITH ROLLBACK IMMEDIATE" % database)
        cursor_tenant.execute("DROP DATABASE %s" % database)
    cursor_admin.execute("DELETE FROM admin.databases WHERE service = '%s' AND tenant = '%s'" % (service, tenant))


def drop_db(server, login, password, tier, tenant, service=None):

    if not tenant:
        raise RuntimeError("Missing parameter for tenant in dropdb")

    if service:
        drop_db_for_tenant_service(server, login, password, tier, tenant, service)
    else:
        cursor = dbcursor_admin(server, login, password, tier)

        cursor.execute("SELECT service FROM admin.services WHERE multitenant = 1 ORDER BY service")
        for r in cursor.fetchall():
            drop_db_for_tenant_service(server, login, password, tier, tenant, r.service)
