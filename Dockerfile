FROM python:3.4.5-alpine
MAINTAINER Triet Truong <mtriet.truong@gmail.com>

# Define build arguments: Taiga version
ARG VERSION=3.3.0rc

# Install necessary packages
RUN apk update &&\
    apk add ca-certificates wget nginx git postgresql-dev musl-dev gcc jpeg-dev zlib-dev libxml2-dev libxslt-dev libffi-dev &&\
    update-ca-certificates

# Download taiga.io backend and frontend
RUN mkdir -p /apps/taiga
WORKDIR /apps/taiga
RUN wget https://github.com/taigaio/taiga-back/archive/$VERSION.tar.gz
RUN tar xzf $VERSION.tar.gz
RUN ln -sf taiga-back-$VERSION taiga-back
RUN rm -f $VERSION.tar.gz
RUN wget https://github.com/taigaio/taiga-front-dist/archive/stable.tar.gz
RUN tar xzf $VERSION-stable.tar.gz
RUN ln -sf taiga-front-dist-$VERSION-stable taiga-front
RUN rm -f $VERSION-stable.tar.gz

# Install all required dependencies of the backend (we will check on container startup whether we need
# to setup the database first)
WORKDIR /apps/taiga/taiga-back-$VERSION
ENV LIBRARY_PATH=/lib:/usr/lib
RUN pip install --no-cache-dir -r requirements.txt
RUN pip install taiga-contrib-ldap-auth
RUN python manage.py collectstatic --noinput

# Setup default environment
ENV TAIGA_SSL "false"
ENV TAIGA_HOSTNAME "localhost"
ENV TAIGA_SECRET_KEY "taiga-secrect@test_by_me"
ENV TAIGA_DB_HOST "localhost"
ENV TAIGA_DB_NAME "postgres"
ENV TAIGA_DB_USER "postgres"
ENV TAIGA_DB_PASSWORD "taiga-db-password@test_by_me"
ENV TAIGA_PUBLIC_REGISTER_ENABLED "false"
ENV TAIGA_BACKEND_DEBUG "false"
ENV TAIGA_FRONTEND_DEBUG "false"
ENV TAIGA_FEEDBACK_ENABLED "false"
ENV TAIGA_DEFAULT_LANGUAGE "en"
ENV TAIGA_DEFAULT_THEME "material-design"
ENV LDAP_ENABLE "false"
ENV LDAP_SERVER ""
ENV LDAP_PORT 389
ENV LDAP_BIND_DN ""
ENV LDAP_BIND_PASSWORD ""
ENV LDAP_SEARCH_BASE ""
ENV LDAP_SEARCH_PROPERTY "sAMAccountName"
ENV LDAP_EMAIL_PROPERTY = 'mail'
ENV LDAP_FULL_NAME_PROPERTY = 'displayName'

RUN mkdir /apps/taiga/presets
COPY local.py /apps/taiga/presets/local.py

# Setup Nginx
COPY nginx.conf /etc/nginx/nginx.conf

# Remove all packages that are not required anymore
RUN apk del gcc wget git musl-dev libxml2-dev
RUN apk add gettext

# Copy files for startup
COPY checkdb.py /apps/taiga/checkdb.py
COPY entrypoint.sh /apps/taiga/entrypoint.sh

# Create a data-directory into which the configuration files will be moved
RUN mkdir /apps/taiga/data

# Startup
WORKDIR /apps/taiga/taiga-back
ENTRYPOINT ["/apps/taiga/entrypoint.sh"]
CMD ["python", "manage.py", "runserver", "127.0.0.1:8000"]
