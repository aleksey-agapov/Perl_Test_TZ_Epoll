#!/bin/bash
for i in {1..50}
do
   echo "Welcome $i times"
    (cat msg/638_1.msg; cat msg/638_2.msg; cat msg/638_3.msg ) | nc -w 1 localhost 1212 

done
echo "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"