#!/bin/sh

#Logging
LOGFILE=/opt/couchbase/var/lib/couchbase/logs/container-startup.log
exec 3>&1 1>>${LOGFILE} 2>&1


CONFIG_DONE_FILE=/opt/couchbase/var/lib/couchbase/container-configured


config_done() {
  touch ${CONFIG_DONE_FILE}
  echo "Couchbase Admin UI: http://localhost:8091" \
     "\nLogin credentials: Administrator / password" | tee /dev/fd/3
  echo "Stopping config-couchbase service"
  sv stop /etc/service/config-couchbase
}


if [ -e ${CONFIG_DONE_FILE} ]; then
  echo "Container previously configured." | tee /dev/fd/3
  config_done
else
  echo "Configuring Couchbase Server.  Please wait (~60 sec)..." | tee /dev/fd/3
fi

export PATH=/opt/couchbase/bin:${PATH}

wait_for_uri() {
  expected=$1
  shift
  uri=$1
  echo "Waiting for $uri to be available..."
  while true; do
    status=$(curl -s -w "%{http_code}" -o /dev/null $*)
    if [ "x$status" = "x$expected" ]; then
      break
    fi
    echo "$uri not up yet, waiting 2 seconds..."
    sleep 2
  done
  echo "$uri ready, continuing"
}

panic() {
  cat <<EOF 1>&3

@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
Error during initial configuration - aborting container
Here's the log of the configuration attempt:
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
EOF
  cat $LOGFILE 1>&3
  echo 1>&3
  kill -HUP 1
  exit
}

couchbase_cli_check() {
  couchbase-cli $* || {
    echo Previous couchbase-cli command returned error code $?
    panic
  }
}

curl_check() {
  status=$(curl -sS -w "%{http_code}" -o /tmp/curl.txt $*)
  cat /tmp/curl.txt
  rm /tmp/curl.txt
  if [ "$status" -lt 200 -o "$status" -ge 300 ]; then
    echo
    echo Previous curl command returned HTTP status $status
    panic
  fi
}


echo "- Waiting for couchbase server.." | tee /dev/fd/3
wait_for_uri 200 http://127.0.0.1:8091/ui/index.html
echo

echo "- Setting up memory quota" | tee /dev/fd/3
curl_check http://127.0.0.1:8091/pools/default -d memoryQuota=256 -d indexMemoryQuota=256 -d ftsMemoryQuota=256

echo "- Configuring services" | tee /dev/fd/3
curl_check http://127.0.0.1:8091/node/controller/setupServices -d services=kv%2Cn1ql%2Cindex%2Cfts%2Ceventing
echo

echo "- Setting base URL with a specific password and username" | tee /dev/fd/3
curl_check http://127.0.0.1:8091/settings/web -d port=8091 -d username=Administrator -d password=password
echo

echo "- Creating the World bucket" | tee /dev/fd/3
curl_check -X POST -u Administrator:password http://127.0.0.1:8091/pools/default/buckets -d name=World  -d bucketType=ephemeral  -d ramQuotaMB=100 -d indexMemoryQuota=100 -d ftsMemoryQuota=100 -d eventingMemoryQuota=100
echo

echo "- Setting index settings"| tee /dev/fd/3
curl  -u Administrator:password http://localhost:8091/settings/indexes -d indexerThreads=0 -d logLevel=info -d maxRollbackPoints=5 -d memorySnapshotInterval=200 -d stableSnapshotInterval=5000 -d storageMode=memory_optimized
echo

echo "waiting for the settings"| tee /dev/fd/3
sleep 4

echo "- Creating indexes on world" | tee /dev/fd/3
curl_check -u Administrator:password http://127.0.0.1:8093/query/service -d statement=CREATE%20PRIMARY%20INDEX%20primary_index%20ON%20World
echo

echo "Configuration completed!" | tee /dev/fd/3

config_done
