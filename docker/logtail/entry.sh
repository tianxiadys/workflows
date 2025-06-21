#!/bin/sh
/app/bin/ilogtail \
-https_ca_cert "/app/resources/ca-bundle.crt" \
-ilogtail_config "/app/conf/$REGION/ilogtail_config.json" \
-ilogtail_daemon_flag "false" \
-ilogtail_user_defined_id_env_name "$USERID"
