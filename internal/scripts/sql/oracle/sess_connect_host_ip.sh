#!/bin/sh
echo "please enter the SID"
read s 
echo "select spid from v\$process where addr=(select paddr from v\$session where sid=$s);"|su - oracle -c 'sqlplus "/as sysdba"' | grep '^[0-9]*[0-9]$'| read c 
netstat -Aan | grep 1521 | awk '{print $6}'>a 
netstat -Aan | grep 1521 | awk '{print $1}'|xargs -I{} rmsock {} tcpcb 'echo{}'| awk '{print $9}'>b
paste a  b >e
cat e |grep $c |read f
echo "the host ip is $f"
