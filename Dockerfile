FROM --platform=linux/amd64 ubuntu:24.04

LABEL architecture="amd64" \
      maintainer="github.com/miniradius" \
      desc="RADIUS CLI utilities from FreeRADIUS (eapol_test, radclient, radcrypt, radeapclient, radlast, radperf, radsecret, radsniff, radsqlrelay, radtest, radwho, radzap)"

ARG DEBIAN_FRONTEND=noninteractive
ARG DEBCONF_NOWARNINGS=yes
ARG WPA_SUPPLICANT_VERSION=2.11

# Init bind9-utils, dpkg, freeradius-comon (dictionary) freeradius-utils (tools) and others
RUN apt-get update -y && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
    --no-install-recommends ca-certificates bind9-utils curl freeradius-common freeradius-utils gettext git \
    build-essential pkg-config libssl-dev libnl-3-dev libnl-genl-3-dev && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install eapol_test
RUN git clone --depth 1 --single-branch --branch v3.2.x https://github.com/FreeRADIUS/freeradius-server.git && \
    /freeradius-server/scripts/ci/eapol_test-build.sh && \
    cp /freeradius-server/scripts/ci/eapol_test/eapol_test /usr/bin/ && \
    rm -rf /freeradius-server

# Install extra utils
RUN apt-get update && \
    apt-get install -y unzip && \
    apt-get install -y less && \
    apt-get install -y jq && \
    apt-get autoremove -y && \
    ln -s /usr/share/freeradius/* /usr/share

# Install capacity testing tools
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive \
    apt-get install -y vim default-jdk wget && \
    wget https://dlcdn.apache.org//jmeter/binaries/apache-jmeter-5.6.3.tgz && \
    tar xzvf apache-jmeter-5.6.3.tgz -C /opt && \
    ln -s /opt/apache-jmeter-5.6.3/bin/jmeter /usr/local/bin/jmeter

RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o \
    "awscliv2.zip" && \
    unzip awscliv2.zip && \ 
    ./aws/install && \ 
    rm -rf aws awscliv2.zip

# Make a new directories for capacity testing files
RUN mkdir /capacity_tests

# CSV (user,password pairs) for radperf
COPY ./accounts-10.csv ./accounts-100.csv ./accounts-1000.csv /accounts/

# Copy eapol testing scripts and supporting files
COPY  ./capacity_tests /capacity_tests/

# Change permissions so scripts are able to run
RUN chmod u+x /capacity_tests/scripts/*.sh

# Make a dummy pem file for certificate testing
RUN echo "This is a broken cert" > /etc/freeradius/3.0/certs/broken_cert.pem

CMD aws ssm get-parameter --name "/govwifi/capacity_testing/cert_pub" --with-decryption --region eu-west-2 --query 'Parameter.Value' --output text > /capacity_tests/pub.pem && \
    aws ssm get-parameter --name "/govwifi/capacity_testing/cert_key" --with-decryption --region eu-west-2 --query 'Parameter.Value' --output text > /capacity_tests/client.key && \
    aws ssm get-parameter --name "/govwifi/capacity_testing/govwifi_cert" --with-decryption --region eu-west-2 --query 'Parameter.Value' --output text > /etc/freeradius/3.0/certs/govwifi_ca.pem && \
    envsubst < /capacity_tests/eap_peap.conf.template > /capacity_tests/eap_peap.conf && \
    envsubst < /capacity_tests/broken_cert_tls.conf.template > /capacity_tests/broken_cert_tls.conf && \
    envsubst < /capacity_tests/broken_eap_peap.conf.template > /capacity_tests/broken_eap_peap.conf && \
    envsubst < /capacity_tests/eap_tls.conf.template > /capacity_tests/eap_tls.conf && \
    envsubst < /capacity_tests/eap_peap_missmatch.conf.template > /capacity_tests/eap_peap_missmatch.conf && \
    envsubst < /capacity_tests/eap_tls_missmatch.conf.template > /capacity_tests/eap_tls_missmatch.conf && \
    export WORKER_IPS=$( /capacity_tests/scripts/get_worker_ips.sh) && \
    jmeter -s -Jserver.rmi.ssl.disable=true && \
    tail -f /dev/null