#!/bin/bash

(cat  msg/902.msg ) | gzip -nc | nc -w 2 localhost 1212 | gzip -dc
#(cat  msg/638_3.msg ) | gzip -nc | nc -w 1 localhost 1212 | gzip -dc
echo "==========================================================\n"
