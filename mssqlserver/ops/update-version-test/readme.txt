
➤ kubectl get msversion
NAME        VERSION   DB_IMAGE                                                DEPRECATED   AGE
2022-cu12   2022      mcr.microsoft.com/mssql/server:2022-CU12-ubuntu-22.04                2d19h
2022-cu14   2022      mcr.microsoft.com/mssql/server:2022-CU14-ubuntu-22.04                2d19h
2022-cu16   2022      mcr.microsoft.com/mssql/server:2022-CU16-ubuntu-22.04                2d19h
2022-cu19   2022      mcr.microsoft.com/mssql/server:2022-CU19-ubuntu-22.04                2d19h
2022-cu22   2022      mcr.microsoft.com/mssql/server:2022-CU22-ubuntu-22.04                2d19h
2025-cu0    2025      mcr.microsoft.com/mssql/server:2025-RTM-ubuntu-22.04                 2d19h



std: 
2022-cu12 -> 2022-cu22 ok 
2022-cu12 -> 2025-cu0
2022-cu22 -> 2025-cu0 ok

ag: 
2022-cu12 -> 2022-cu22 ok 
2022-cu12 -> 2025-cu0
2022-cu22 -> 2025-cu0 ok