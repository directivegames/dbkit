sh dbkit.sh -U sa -P themachines -S dbms.dg-api.com tenant dropdb $*
sh dbkit.sh -U sa -P themachines -S dbms.dg-api.com tenant remove $*
sh dbkit.sh -U sa -P themachines -S dbms.dg-api.com tenant add $*
sh dbkit.sh -U sa -P themachines -S dbms.dg-api.com tenant edit $* usesingledb 1
sh dbkit.sh -U sa -P themachines -S dbms.dg-api.com tenant createdb $*
