#!/bin/bash

# set project Kiwix name
sed -i "s/CHAOSS/Kiwix/g" /project.cfg

# set Github token and enable cocom
{ \
  echo "[github]" ; \
  echo "api-token = $GITHUB_TOKEN" ; 
} > /override.cfg

# Start Elasticsearch
echo "Starting Elasticsearch"
chown -R elasticsearch.elasticsearch /var/lib/elasticsearch
/etc/init.d/elasticsearch start

# Start MariaDB
echo "Starting MariaDB"
/etc/init.d/mysql start

# Start Kibana
echo "Starting Kibiter"
${KB_DIR}/bin/kibana > kibana.log 2>&1 &

# Disable dev tool
sed -e s/\'devTools\'\,//g  -i ${KB_DIR}/src/core_plugins/kibana/index.js

if [ "$PROJECT_NAME" != "" ]; then
  sed -e "s/title: 'Kibana',$/title: '$PROJECT_NAME',/" -i ${KB_DIR}/src/core_plugins/kibana/index.js
  sed -e "s|__PROJECT__|$PROJECT_NAME|g" -i ${KB_DIR}/src/ui/views/chrome.jade
  sed -e "s/title GrimoireLab Analytics/title $PROJECT_NAME/" -i ${KB_DIR}/src/ui/views/chrome.jade
fi

echo -n "Waiting for Kibiter to start..."
until $(curl --output /dev/null --silent --head --fail http://127.0.0.1:5601); do
    printf '.'
    sleep 2
done

# Allow kibana setting writting for initialization
curl -X PUT "http://localhost:9200/.kibana/_settings" -H'Content-Type: application/json' -d '{ "index.blocks.read_only" : false }'

echo ""
echo "Import dashboard"
kidash --import /dashboard_overview.json --dashboard Overview 

echo ""
echo "Settings Kibana"
curl -XPOST -H "Content-Type: application/json" -H "kbn-xsrf: true" localhost:5601/api/kibana/settings/histogram:barTarget -d '{"value": "20"}'
curl -XPOST -H "Content-Type: application/json" -H "kbn-xsrf: true" localhost:5601/api/kibana/settings/defaultIndex -d '{"value":"26d36150-0f7c-11ea-ae8c-d9e77f11fa16"}'

# Put Index kibana setting in read only
curl -X PUT "http://localhost:9200/.kibana/_settings" -H'Content-Type: application/json' -d '{ "index.blocks.read_only" : true }'

if [[ $RUN_MORDRED ]] && [[ $RUN_MORDRED = "NO" ]]; then
  echo
  echo "All services up, not running SirMordred because RUN_MORDRED = NO"
  echo "Get a shell running docker exec, for example:"
  echo "docker exec -it" $(hostname) "env TERM=xterm /bin/bash"
else
  sleep 1
  # Start SirMordred
  echo "Starting SirMordred to build a GrimoireLab dashboard"
  echo "This will usually take a while..."
  /usr/local/bin/sirmordred $*
  status=$?
  if [ $status -ne 0 ]; then
    echo "Failed to start SirMordred: $status"
    exit $status
  fi
  echo
  echo "SirMordred done, dashboard produced, check http://localhost:5601"
  echo
  echo "To make this shell finish, type <CTRL> C"
  echo "but the container will still run services in the background,"
  echo "including Kibiter and Elasticsearch, so you can still operate the dashboard."
fi
echo
echo "To make the whole container finish, type 'docker kill " $(hostname) "'"
sleep 5000d
