#!/bin/bash
mv "/etc/ilogtail/$REGION/ilogtail_config.json" "/etc/ilogtail"
tee "/etc/ilogtail/user_defined_id" <<< "$USERID"
ilogtail
