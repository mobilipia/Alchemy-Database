#!/bin/bash

DIRS="1 2 3 4"
PORTS="8080 8081 8082 8083"
B_PORTS="9999"
B_DIRS="1"

echo killall ./alchemy-cli
killall ./alchemy-cli
echo sleep 1
sleep 1

if [ "$1" == "clean" ]; then
  echo killall -9 alchemy-server
  killall -9 alchemy-server
  for d in $DIRS; do (cd SERVERS/$d; rm dump.rdb); done
else
  for p in $PORTS; do 
    echo ./alchemy-cli -p $p SAVE
    ./alchemy-cli -p $p SAVE
    echo ./alchemy-cli -p $p SHUTDOWN
    ./alchemy-cli -p $p SHUTDOWN
  done
  for p in $B_PORTS; do 
    echo ./alchemy-cli -p $p SAVE
    ./alchemy-cli -p $p SAVE
    echo ./alchemy-cli -p $p SHUTDOWN
    ./alchemy-cli -p $p SHUTDOWN
  done
  if [ "$1" == "shutdown" ]; then
    exit 0;
  fi
fi

# TODO check that all are dead
echo sleep 2
sleep 2

for d in $DIRS; do
  (cd SERVERS/$d
    echo "(cd SERVERS/$d; ./alchemy-server redis.conf >> OUTPUT & </dev/null)"
    ./alchemy-server redis.conf >> OUTPUT & </dev/null
  )
done
for d in $B_DIRS; do
(cd SERVERS/BRIDGE/$d;
  echo "(cd SERVERS/BRIDGE/$d; ./alchemy-server redis.conf >> OUTPUT & </dev/null)"
  ./alchemy-server redis.conf >> OUTPUT & </dev/null
)
done

echo sleep 2
sleep 2
for p in $PORTS; do 
  echo ./alchemy-cli -p $p -ph 127.0.0.1 -pp $p SUBPIPE
  ./alchemy-cli -p $p -ph 127.0.0.1 -pp $p SUBPIPE "echo" & < /dev/null
done