➤ cat mssql.conf 
[memory]
memorylimitmb = 2047⏎ 


kubectl create secret generic -n demo ms-custom-config --from-file=./mssql.conf
secret/ms-custom-config created


➤ kubectl view-secret -n demo ms-custom-config -a
mssql.conf='[memory]
memorylimitmb = 2047'

set 
```
  configuration:
    secretName: ms-custom-config
    inline:
      mssql.conf: |-
        [memory]
        memorylimitmb = 2048
```    
kubectl apply -f standalone.yaml 
mssqlserver.kubedb.com/standalone created






full config:
➤ kubectl view-secret -n demo standalone-8003bf -a
mssql.conf='[language]
lcid = 1033
[memory]
memorylimitmb = 2048
'


Test All 7 options:
If RemoveCustomConfig is false:
1 - [OK] Nothing given: Rejected by validator
2 - [OK-not-ready!] Only applyConfig is given: keep the previous custom config if it exists. Merge the applyConfig with the previous config if it exists. Otherwise, just use the given applyConfig.
3 - [OK] Only configSecret is given: Using the newly given configSecret as the custom config secret. 
4 - [OK] config + apply: allowed (merge both, gives priority to applyconfig)


if RemoveCustomConfig is true:
5 - [OK] No applyConfig and ConfigSecret: Just remove the previous custom configurations.  
6 - [OK]Only applyConfig is given: Allowed. Remove previously given custom configs, use the custom configuration given in the applyConfig.
7 - [OK]configSecret is given: Not allowed. Not needed, as giving configSecret already removes the previous config by using the newly given configSecret. Rejected by validator.


➤ kubectl apply -f reconfigure-1.yaml 
The MSSQLServerOpsRequest "msops-reconfigure-nothing" is invalid: spec.configuration: Invalid value: "msops-reconfigure-nothing": `spec.configuration` nil not supported in Reconfigure type


➤ kubectl apply -f reconfigure-2.yaml
mssqlserveropsrequest.ops.kubedb.com/reconfigure-2-only-apply created


➤ kubectl view-secret -n demo standalone-8003bf -a
mssql.conf='[language]
lcid = 1033
[memory]
memorylimitmb = 2048
[network]
tcpport = 1433
'



➤ cat mssql.conf
[sqlagent]
enabled = true⏎     

kubectl create secret generic -n demo ms-new-custom-config --from-file=./mssql.conf

➤ kubectl view-secret -n demo ms-new-custom-config -a
mssql.conf='[sqlagent]
enabled = true'


neaj@neaj-pc:~/g/s/g/N/n/m/o/reconfigure-test|main⚡*?
➤ kubectl apply -f reconfigure-3.yaml


➤ kubectl view-secret -n demo standalone-8003bf -a
mssql.conf='[language]
lcid = 1033
[memory]
memorylimitmb = 2048
[network]
tcpport = 1433
[sqlagent]
enabled = true
'





➤ cat mssql.conf
[sqlagent]
enabled = false

[memory]
memorylimitmb = 2056⏎    


➤ kubectl view-secret -n demo ms-new-custom-config2 -a
mssql.conf='[sqlagent]
enabled = false

[memory]
memorylimitmb = 2056'


➤ kubectl apply -f reconfigure-4.yaml
mssqlserveropsrequest.ops.kubedb.com/reconfigure-4-config-and-apply created


➤ kubectl view-secret -n demo standalone-8003bf -a
mssql.conf='[language]
lcid = 1033
[memory]
memorylimitmb = 4096
[network]
tcpport = 1433
[sqlagent]
enabled = false
'




remove = true: 

➤ kubectl apply -f reconfigure-5.yaml
mssqlserveropsrequest.ops.kubedb.com/reconfigure-5-remove-and-nothing created

configSecret = nil and just default config remains.

➤ kubectl view-secret -n demo standalone-config -a
mssql.conf='[language]
lcid = 1033
'



➤ kubectl apply -f reconfigure-6.yaml
mssqlserveropsrequest.ops.kubedb.com/reconfigure-6-remove-apply created

➤ kubectl view-secret -n demo standalone-config -a
mssql.conf='[language]
lcid = 1033
[memory]
memorylimitmb = 4096
'


➤ kubectl apply -f reconfigure-7.yaml
The MSSQLServerOpsRequest "reconfigure-7-remove-and-config" is invalid: spec.configuration: Invalid value: "reconfigure-7-remove-and-config": `spec.configuration.removeCustomConfig` and `spec.configuration.configSecret` is not supported together

