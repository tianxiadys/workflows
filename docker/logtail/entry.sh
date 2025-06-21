#!/bin/sh
mv "/etc/ilogtail/$REGION/ilogtail_config.json" "/etc/ilogtail"
echo "$USERID" > "/etc/ilogtail/user_defined_id"
ilogtail
