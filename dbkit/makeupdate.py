import sys
import subprocess

from getpass import getuser


#
# OS
#

def run_cmd(cmd, cmd_input = None, mode=""):
    """
        Run a cmd command, raise any errors, otherwise return the results as string
    """
    p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    stdout, stderr = p.communicate(cmd_input)
    if p.returncode:
        raise subprocess.CalledProcessError(p.returncode, stderr)
    if "b" not in mode:
        stdout = stdout.replace("\r\n", "\n")
    return stdout           


#
# P4
#

def p4_changelist_info(client, changelist):
    """
        Extract information from a specified changelist. Returns a dict with the following keys:
         - subject: first line in changelist description (Change xxxxx by xxxxx....)
         - description: The changelist description (what the user typed in)
         - files: for each file in the changelist, a dict containing the following keys:
                  - path: depot file path
                  - revision: number of the current revision (1 for files opened for add)
                  - action: change action
         - num: changelist
         - user: user
    """
    ret = {}
    command = "p4 -Q none -C none -c %s -s describe %s" % (client, changelist)
    po = run_cmd(command)

    #data types
    TEXT        = "text: "
    INFO        = "info1: "
    LINEEND     = "\n"
    DESCRIPTION = "\t"
    SPACE       = " "
    DELETE      = ""
    UNUSEDLINES = ["Affected files ...\n", "\t\n", "exit: 0\n"]

    text = []
    info = []

    for line in po.splitlines():
        if line == LINEEND or line in UNUSEDLINES:
            continue
        
        if line.startswith(TEXT):
            text.append(line[len(TEXT):])
        elif line.startswith(INFO):
            info.append(line[len(INFO):])

    try:
        subject = text[0].split(SPACE)
        ret["subject"]  = SPACE.join(subject)
        ret["num"] = subject[1]
        ret["user"] = subject[3].split("@")[0]
    except Exception, ex:
        raise RuntimeError("Error encountered while parsing change:\n%s" % ex.message) 

    descr = ""
    for line in text:
        if line.startswith(DESCRIPTION):
            descr += line.replace(DESCRIPTION, DELETE)
    ret["description"] = descr

    #File List Fields
    PATH        = 0
    REVISION    = 1
    CHANGETYPE  = 2

    filelist = []
    for line in info:
        splitline = line.replace("#", SPACE).replace(LINEEND, DELETE).split(SPACE)
        fileinfo = {}
        fileinfo["path"] = splitline[PATH]
        if fileinfo["path"].endswith(".sql"):
            fileinfo["revision"] = splitline[REVISION] 
            fileinfo["action"] = splitline[CHANGETYPE]
            if fileinfo["action"] not in ["add", "edit", "move/add", "delete", "move/delete"]:
                raise RuntimeError("Action '%s' not supported" % fileinfo["action"])
            filelist.append(fileinfo)
        
    ret["files"] = filelist
    
    return ret


def p4_os_folder_for_depot_file(client, depot_folder_file):
    """
        For a specified depot path and filename (for reference because there
        are no folders in Perforce) get the folder path on disk
    """
    command = "p4 -Q none -C none -c %s fstat %s" % (client, depot_folder_file)
    po = run_cmd(command)

    filePath = None
    for line in po.splitlines():
        if line.startswith("... clientFile"):
            filePath = line.split()[2]
            # remove the last part, there are probably better ways to do this but this works
    if filePath is None:
        raise RuntimeError("Please make sure folder is included in your clientspec (%s)" % depot_folder_file)
        
    return "\\".join(filePath.split("\\")[:-1])


def p4_os_file_content(client, depot_folder_file):
    """
        Find a local version of file specifed by Perforce depot path, 
        verify the contents, then return as list
    """
    # Use fstat to find the file on disk
    command = "p4 -Q none -C none -c %s -s fstat %s" % (client, depot_folder_file)
    po = run_cmd(command)

    localpath = None
    for line in po.splitlines():
        parts = line.split(" ")
        if parts > 2 and parts[1] == "clientFile":
            localpath = parts[2].strip()
            break

    if localpath is None:
        raise RuntimeError("Failed to find file %s" % depot_folder_file)
        
    file = open(localpath)
    ret = []
    
    line = file.readline()
    linecount = 1
    while line != "":
        if line.find("\t") > -1:
            raise RuntimeError("There is a tab in line %s in \n%s\nPlease replace with spaces." % (linecount, depot_folder_file))
        ret.append(line)
        line = file.readline()
        linecount = linecount + 1
    file.close()
    
    return ret


def p4_add_file_to_changelist(client, changelist, os_folder_file):
    """
        add file to changelist
    """
    command = "p4 -Q none -C none -c %s add -c %s %s" % (client, changelist, os_folder_file)
    run_cmd(command)


#
# OTHER SHARED FUNCTIONS
#

def update_folder_service_from_change(change):

    # Determine update folder
    update_folder = ""
    update_service = ""

    for file in change["files"]:
        filename = file["path"]

        if filename.startswith("//valkyrieBackend/dbUpdateTemp"):
            continue

        folder = ""
        if "/vk-dbcore/" in filename:
            i = filename.find("/vk-dbcore/")
            i = i + 10
            folder = filename[:i]
        elif "/db/" in filename:
            i = filename.find("/db/")
            i = i + 3
            folder = filename[:i]

        if folder == "":
            raise RuntimeError("Folder not correct for file %s" % filename)

        if update_folder == "":
            update_folder = folder
        elif folder != update_folder:
            raise RuntimeError("Multiple folders found (%s and %s)" % (update_folder, folder))

        service = ""
        if folder.endswith("/vk-dbcore"):
            service = "core"
        elif folder.endswith("/db"):
            l = folder.split("/")
            before_db = l[len(l) - 2]
            if before_db.startswith("vk-"):
                service = before_db[3:]
            elif before_db.startswith("vk"):
                service = before_db[2:]
            else:
                service = before_db

        if service == "":
            raise RuntimeError("Not able to determine service for file %s" % filename)

        if update_service == "":
            update_service = service
        elif service != update_service:
            raise RuntimeError("Multiple services found (%s and %s)" % (update_service, service))

    return update_folder, update_service


#
# GENERATE
#

def get_update(client, path, action):
    """
        Get update text for the specified file and action. For functions, views
        and procs, this means simply copying the content for either add or edit.
        For a table we must distinguish between add and edit, edit is not 
        automatic at this stage.
    """
    file_content = p4_os_file_content(client, path)
    # Check for tabs in all files
    
    TABLE_MARKER = "CREATE TABLE "

    UPDATE_TABLE = """
-- ###
-- ### TABLE %s WAS CHANGED, REPLACE THIS COMMENT WITH AN ALTER SCRIPT
-- ###
"""
    if action == "edit":
        for line in file_content:
                pos = line.find(TABLE_MARKER)
                if pos > -1:
                    pos = pos + len(TABLE_MARKER)
                    #If the table name starts with "#" then this is a temporary table created inside a proc
                    if line[pos] == "#":
                        continue
                    parts = line[pos:].split()
                    return [UPDATE_TABLE % parts[0]]
    return file_content


def generate_db_update(client, changelist):
    print "VK DB UPDATE GENERATE..."

    change = p4_changelist_info(client, changelist)

    updates = {}
    deletes = {}
    update_filename = "dbUpdateTemp%s.sql" % changelist

    for file in change["files"]:
        if file["path"].find(update_filename) > 0:
            raise RuntimeError("There is already a generated update %s in this changelist, revert it if you want to generate a new one" % update_filename)

        if file["path"].endswith(".sql") and file["path"].find("/updates/") < 0:
            if file["path"].find("UpdateLater") < 0:
                if file["action"] in ["delete", "move/delete"]:
                    deletes[file["path"]] = file["action"]
                else:
                    updates[file["path"]] = file["action"]

    # just used for checking, exception raised if not ok
    update_folder, update_service = update_folder_service_from_change(change)

    UPDATE_HEADER = """
-- ###
-- ### THIS IS AN AUTOMATICALLY CREATED DATABASE UPDATE
-- ###
-- ### THE SCRIPT NEEDS TO BE VERIFIED AND TESTED BEFORE CHECKIN
-- ### ONCE THAT IS DONE PROPERLY, DELETE THIS COMMENT
-- ###
"""
    UPDATE_SEPARATOR = "\n\n" + "-"*130 + "\n\n"

    UPDATE_DELETES = """
-- ###
-- ### SQL FILES HAVE BEEN DELETED, MAKE SURE TO ADD THEM TO THE "UPDATE LATER" SCRIPT
-- ### ONCE THAT IS DONE PROPERLY, DELETE THIS COMMENT
-- ###
"""
    update_path = "%s\\%s" % (p4_os_folder_for_depot_file(client, "//valkyrieBackend/README.txt"), update_filename)

    update_file = open(update_path, "w")

    update_file.write(UPDATE_HEADER)
    update_file.write(UPDATE_SEPARATOR)

    if len(deletes) > 0:
        update_file.write(UPDATE_DELETES)
        l = deletes.keys()
        l.sort()
        for path in l:
            update_file.write("-- ###   %s\n" % path)
        update_file.write("-- ###\n")
        update_file.write(UPDATE_SEPARATOR)

    updates_functions = []
    updates_tables = []
    updates_views = []
    updates_procedures = []
    updates_other = []

    l = updates.keys()
    l.sort()
    for path in l:
        handled = 0
        content = get_update(client, path, updates[path])
        for line in content:
            if line.find("CREATE PROCEDURE") >= 0:
                updates_procedures.append(path)
                handled = 1
                break
            if line.find("CREATE TABLE") >= 0:
                updates_tables.append(path)
                handled = 1
                break
            if line.find("CREATE VIEW") >= 0:
                updates_views.append(path)
                handled = 1
                break
            if line.find("CREATE FUNCTION") >= 0:
                updates_functions.append(path)
                handled = 1
                break
        if handled == 0:
            updates_other.append(path)

    # 1. Other
    for x in updates_other:
        content = get_update(client, x, updates[x])
        for line in content:
            update_file.write(line)
        update_file.write(UPDATE_SEPARATOR)
    # 2. Functions
    for x in updates_functions:
        content = get_update(client, x, updates[x])
        for line in content:
            update_file.write(line)
        update_file.write(UPDATE_SEPARATOR)
    # 3. Tables
    for x in updates_tables:
        content = get_update(client, x, updates[x])
        for line in content:
            update_file.write(line)
        update_file.write(UPDATE_SEPARATOR)
    # 3. Views
    for x in updates_views:
        content = get_update(client, x, updates[x])
        for line in content:
            update_file.write(line)
        update_file.write(UPDATE_SEPARATOR)
    # 4. Procedures
    for x in updates_procedures:
        content = get_update(client, x, updates[x])
        for line in content:
            update_file.write(line)
        update_file.write(UPDATE_SEPARATOR)

    update_file.close()

    p4_add_file_to_changelist(client, changelist, update_path)

    # end with a nice message
    print "%s was successfully generated and added to your changelist" % update_filename
    print "Please review and update, then use wrap tool to prepare your final update"


#
# WRAP
#

def wrap_db_update(client, changelist):

    print "DB UPDATE WRAP..."

    change = p4_changelist_info(client, changelist)

    # check if temp file exists
    temp_path = "//valkyrieBackend/dbUpdateTemp%s.sql" % changelist
    temp_file_found = 0
    for file in change["files"]:
        if file["path"] == temp_path:
            temp_file_found = 1
            break
    if not temp_file_found:
        raise RuntimeError("Temp file %s not found in changelist" % temp_path)

    # get update_folder/service
    update_folder, update_service = update_folder_service_from_change(change)

    # get the most recent addition to the updates folder (hence the #1 specification)
    command = "p4 -Q none -C none -c %s changes -m 1 %s...#1" % (client, update_folder + "/updates/")
    po = run_cmd(command)
    if not po.startswith("Change "):
        raise RuntimeError("Unexpected response from p4 changes: %s" % po)
    last_changelist = po.split(" ")[1]

    # get the update file from the change
    command = "p4 -Q none -C none -c %s files %s...@%s,%s" % (client, update_folder + "/updates/", last_changelist, last_changelist)
    po = run_cmd(command)

    # get last/next version from last update file
    i = po.find(".sql#")
    last_update_file = po[:i+4]
    max_version = po[i-4:i]
    next_version = ("0000" + str(int(max_version) + 1))[-4:]

    # create next update file from temp update file
    os_folder = p4_os_folder_for_depot_file(client, last_update_file)
    if update_service == "core":
        next_update_file = os_folder + "\\vkCoreUpdate" + next_version + ".sql"
        update_developer = "VK-CORE"
    else:
        next_update_file = os_folder + "\\" + update_service.lower() + "Update" + next_version + ".sql"
        update_developer = update_service.upper()
    the_file = open(next_update_file, "w")
    content = p4_os_file_content(client, temp_path)
    the_file.write("""
EXEC zsystem.Versions_Start '%s', %s, '%s'
GO

""" % (update_developer, next_version, getuser()))
    for line in content:
        for marker in ["DELETE THIS COMMENT", "REPLACE THIS COMMENT"]:
            if line.find(marker) > -1:
                raise Exception("Automatically generated comment found in update, please review and clean up before wrapping")
        the_file.write(line)
    the_file.write("""

GO
EXEC zsystem.Versions_Finish '%s', %s, '%s'
GO
""" % (update_developer, next_version, getuser()))

    the_file.close()

    # add the wrapped update to the changelist and revert the temporary one
    po = run_cmd("p4 -Q none -C none -c %s add -c %s %s" % (client, changelist, next_update_file))
    if po.find("can't add") > -1:
        raise RuntimeError(po)
    run_cmd("p4 -Q none -C none -c %s revert %s" % (client, temp_path))

    # end with a nice message
    print "Successfully created %s and added to your changelist" % next_update_file


#
# MAIN
#

if __name__ == "__main__":
    updateFile = None
    try:
        if len(sys.argv) < 4:
            raise RuntimeError("""
                Usage: %s changelist client
                - changelist is the number of a pending changelist
                - client is the name of a Perforce workspace
                - ACTION is either GENERATE or WRAP""" % sys.argv[0])

        changelist = sys.argv[1]
        client = sys.argv[2]
        action = sys.argv[3]

        if changelist == "default":
            raise RuntimeError("Please move your change to a saved changelist before wrapping update")
        
        if action == "GENERATE":
            generate_db_update(client, changelist)
        elif action == "WRAP":
            wrap_db_update(client, changelist)
        else:
            raise RuntimeError("ACTION not valid, needs to be GENERATE or WRAP")

    except Exception, e:
        print "!!! ERROR : ", e
    finally:
        if updateFile is not None:
            updateFile.close()
