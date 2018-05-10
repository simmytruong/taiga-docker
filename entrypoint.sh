#!/bin/sh

# If a backend configuration file is present in /apps/taiga/data, delete the default one
# from inside of the docker image, and create a symlink. Otherwise move the default one
# into /apps/taiga/data and symlink to it as well.
if [ -f /apps/taiga/data/local.py ]; then

  # Case 1: there is already preconfiguration in the volume directory, so let's delete
  #         the local.py in the settings/ folder (if present)
  rm -f /apps/taiga/taiga-back/settings/local.py
  mv /apps/taiga/taiga-back/settings/local.py.example /apps/taiga/taiga-back/settings/original.py

elif [ -f /apps/taiga/taiga-back/settings/local.py.example ]; then

  # Case 2: there is only the example configuration file by the distribution. We rename it to
  #         original.py and move the local.py preset of this Docker image to the volume
  #         directory (which will import the example configuration and configure DB and Hosts/URLs)
  mv /apps/taiga/taiga-back/settings/local.py.example /apps/taiga/taiga-back/settings/original.py
  mv /apps/taiga/presets/local.py /apps/taiga/data/local.py

fi

# Finally, create a symlink from the local.py in the volume directory to the settings/ directory.
ln -sf /apps/taiga/data/local.py /apps/taiga/taiga-back/settings/local.py

# If a frontend configuration file is present in /apps/taiga/data, delete the default one
# from inside of the docker image, and create a symlink. Otherwise move the default one
# into /apps/taiga/data and symlink to it as well.
if [ -f /apps/taiga/data/conf.json ]; then

  # Case 1: there is already pre-configuration in the volume directory, so let's delete
  #         the local conf.js in the dist/ folder (if present)
  rm -f /apps/taiga/taiga-front/dist/conf.json

elif [ -f /apps/taiga/taiga-front/dist/conf.example.json ]; then

  # Case 2: there is only the example configuration file by the distribution. We move it to the
  #         volume directory and replace the values according to the given environment parameters.
  mv /apps/taiga/taiga-front/dist/conf.example.json /apps/taiga/data/conf.json

  # Adjust attributes: debug, debugInfo, defaultLanguage, publicRegisterEnabled and feedbackEnabled
  sed -i "s/\"debug\":.*,/\"debug\": $TAIGA_FRONTEND_DEBUG,/g" /apps/taiga/data/conf.json
  sed -i "s/\"debugInfo\":.*,/\"debugInfo\": $TAIGA_FRONTEND_DEBUG,/g" /apps/taiga/data/conf.json
  sed -i "s/\"defaultLanguage\":.*,/\"defaultLanguage\": \"$TAIGA_DEFAULT_LANGUAGE\",/g" /apps/taiga/data/conf.json
  sed -i "s/\"publicRegisterEnabled\":.*,/\"publicRegisterEnabled\": $TAIGA_PUBLIC_REGISTER_ENABLED,/g" /apps/taiga/data/conf.json
  sed -i "s/\"feedbackEnabled\":.*,/\"feedbackEnabled\": $TAIGA_FEEDBACK_ENABLED,/g" /apps/taiga/data/conf.json

  # Set API according to SSL parameter
  export TAIGA_SSL_LOWERCASE=$(echo "$TAIGA_SSL" | tr '[:upper:]' '[:lower:]')
  if [ "$TAIGA_SSL_LOWERCASE" = "true" ]; then
    sed -i "s/\"api\":.*,/\"api\": \"https:\/\/$TAIGA_HOSTNAME\/api\/v1\/\",/g" /apps/taiga/data/conf.json
  else
    sed -i "s/\"api\":.*,/\"api\": \"http:\/\/$TAIGA_HOSTNAME\/api\/v1\/\",/g" /apps/taiga/data/conf.json
  fi

  # Adjust also the list of available themes...
  sed -i "s/\"themes\":.*,/\"themes\": \[\"taiga\", \"material-design\"\],/g" /apps/taiga/data/conf.json
  # ...as well as the default one
  sed -i "s/\"defaultTheme\":.*,/\"defaultTheme\": \"$TAIGA_DEFAULT_THEME\",/g" /apps/taiga/data/conf.json

  # Enable LDAP if enabled
  export LDAP_ENABLE_LOWERCASE=$(echo "$LDAP_ENABLE" | tr '[:upper:]' '[:lower:]')
  if [ "$LDAP_ENABLE_LOWERCASE" = "true" ]; then
    sed -i "s/\"tribeHost\": null/\"tribeHost\": null, \"loginFormType\": \"ldap\"/g" /apps/taiga/data/conf.json
  fi

fi

# Finally, create a symlink from conf.json in the volume directory to the dist/ directory.
ln -sf /apps/taiga/data/conf.json /apps/taiga/taiga-front/dist/conf.json

# Setup database automatically if needed
if [ -z "$TAIGA_SKIP_DB_CHECK" ]; then

  # Try to connect 6 times, always waiting 10 seconds in between. This is to make sure
  # that the database has enough time to initialize upon first startup.
  python /apps/taiga/checkdb.py
  DB_CHECK_STATUS=$?
  TRIALS=0
  while [ $DB_CHECK_STATUS == 1 -a $TRIALS -lt 6 ]
  do
    echo "Could not connect to PostgreSQL database, will try again in 10 seconds..."
    sleep 10
    python /apps/taiga/checkdb.py
    DB_CHECK_STATUS=$?
    TRIALS=`expr $TRIALS + 1`
  done

  if [ $DB_CHECK_STATUS -eq 1 ]; then
    echo "Failed to connect to database server."
    exit 1
  elif [ $DB_CHECK_STATUS -eq 2 ]; then
    echo "Configuring initial database"
    python manage.py migrate --noinput
    python manage.py loaddata initial_user
    python manage.py loaddata initial_project_templates
    python manage.py loaddata initial_role
    python manage.py compilemessages
  fi
fi

# Start nginx service (need to start it as background process)
echo "Starting Nginx Webserver in background..."
nginx

# Start Taiga backend Django server
echo "Starting Taiga backend server..."
exec "$@"
