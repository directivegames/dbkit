import argparse

import service
import tenant
import database



def command_service(args):
    if args.command == "list":
        service.list(args.server, args.login, args.password, args.tier)
    else:
        raise RuntimeError("Command %s is not supported for service" % args.command)


def command_tenant(args):
    if args.command == "list":
        tenant.list(args.server, args.login, args.password, args.tier)
    elif args.command == "add":
        tenant.add(args.server, args.login, args.password, args.tier, tenant=args.subcommand)
    elif args.command == "edit":
        tenant.edit(args.server, args.login, args.password, args.tier, tenant=args.subcommand, column=args.subcommand2, value=args.subcommand3)
    elif args.command == "remove":
        tenant.remove(args.server, args.login, args.password, args.tier, tenant=args.subcommand)
    elif args.command == "createdb":
        tenant.create_db(args.server, args.login, args.password, args.tier, tenant=args.subcommand, service=args.subcommand2)
    elif args.command == "dropdb":
        tenant.drop_db(args.server, args.login, args.password, args.tier, tenant=args.subcommand, service=args.subcommand2)
    else:
        raise RuntimeError("Command %s is not supported for tenant" % args.command)


def command_database(args):
    if args.command == "list":
        database.list(args.server, args.login, args.password, args.tier)
    else:
        raise RuntimeError("Command %s is not supported for database" % args.command)


if __name__ == "__main__":

    # create parse object
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)

    # non-command arguments
    parser.add_argument("-T", "--tier", action="store", nargs="?", help="Tier")
    parser.add_argument("-S", "--server", action="store", nargs="?", required=True, help="Server")
    parser.add_argument("-U", "--login", action="store", nargs="?", required=True, help="Login")
    parser.add_argument("-P", "--password", action="store", nargs="?", required=True, help="Password")

    # subparser for commands
    subparsers = parser.add_subparsers(help="sub-command help")

    # command service
    parser_database = subparsers.add_parser("service", help="Service")
    parser_database.add_argument("command", help="Command, f.e. list")
    parser_database.set_defaults(func=command_service)

    # command tenant
    parser_database = subparsers.add_parser("tenant", help="Tenant")
    parser_database.add_argument("command", help="Command, f.e. list or add")
    parser_database.add_argument("subcommand", help="Subcommand, f.e. name of tenant when command is createdb", nargs="?", default=None)
    parser_database.add_argument("subcommand2", help="Subcommand2, f.e. name of service when command is createdb", nargs="?", default=None)
    parser_database.add_argument("subcommand3", help="Subcommand3, f.e. value of column when command is edit", nargs="?", default=None)
    parser_database.set_defaults(func=command_tenant)

    # command database
    parser_database = subparsers.add_parser("database", help="Database")
    parser_database.add_argument("command", help="Command, f.e. list")
    parser_database.set_defaults(func=command_database)

    # initialize args object
    args = parser.parse_args()

    # set default values
    if args.tier is None:
        args.tier = "DEV"
    elif args.tier != "DEV":
        raise RuntimeError("Currently only tier DEV is supported")

    # call requested command function
    args.func(args)
