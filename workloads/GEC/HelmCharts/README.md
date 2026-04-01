# ONCITE DPS on fair

## Pull Secret

tu-redhat-fair —> vTID8zi6Pjd91FNadgcUsqUzfasbtJsLPNXBN

## Charts
dps-operators - 26.2.0
oncite-dps - 26.2.6
doctrain - 9.1.0-rc.0
k6doctrain - 9.1.0-rc.2


## INSTALL 

```bash
$ oc new-project oncite-dps
$ helm install dps-operators charts/dps-operators-26.2.0.tgz

!!! SET BASEDOMAIN IN VALUESs
!!! pls. organise a valid certificate for this domain 

$ helm install oncite-dps -f oncite-dps-value-overwrite.yaml charts/oncite-dps-26.2.6.tgz
```

## DOCTRAIN

later...