ARG UBUNTU_CODENAME=jammy
ARG UBUNTU_VERSION=20240111

FROM ubuntu:${UBUNTU_CODENAME}-${UBUNTU_VERSION} AS base

ARG DEBIAN_FRONTEND=noninteractive

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN set -x \
		&& apt-get update && apt-get install -y \
			libcjose0 \
			libcurl4 \
			libev4 \
			libjansson4 \
			libhttp-parser2.9 \
			libnl-route-3-200 \
			liboath0 \
			libprotobuf-c1 \
			libradcli4 \
			libreadline8 \
			libtalloc2 \
			libwrap0 \
		&& rm -rf /var/lib/apt/lists/*

#############################################################

FROM base AS builder-sources

RUN set -x \
		&& apt-get update && apt-get install -y \
			curl \
		&& rm -rf /var/lib/apt/lists/*

ARG OCS_VERSION=1.2.4

RUN set -x \
		&& cd /tmp \
		&& curl -SL --connect-timeout 8 --max-time 120 --retry 128 --retry-delay 5 "https://gitlab.com/openconnect/ocserv/-/archive/$OCS_VERSION/ocserv-$OCS_VERSION.tar.gz" -o ocserv.tar.gz \
		&& mkdir -p /usr/src/ocserv \
		&& tar -xf ocserv.tar.gz -C /usr/src/ocserv --strip-components=1 \
		&& rm -rf /tmp/*

#############################################################

FROM base AS builder-dependencies

RUN set -x \
		&& apt-get update && apt-get install -y \
			autoconf \
			automake \
			build-essential \
			cscope \
			curl \
			gperf \
			libcjose-dev \
			libcurl4-openssl-dev \
			libev-dev \
			# libgeoip-dev \
			libgnutls28-dev \
			libhttp-parser-dev \
			libjansson-dev \
			libkrb5-dev \
			liblz4-dev \
			# libmaxminddb-dev \
			libnl-3-dev \
			libnl-route-3-dev \
			libnss-wrapper \
			liboath-dev \
			# libpam-dev \
			# libpam-wrapper \
			libpcl1-dev \
			libprotobuf-c-dev \
			libradcli-dev \
			libreadline-dev \
			libseccomp-dev \
			libsocket-wrapper \
			libssl-dev \
			libtalloc-dev \
			libuid-wrapper \
			libwrap0-dev \
			m4 \
			pkg-config \
			protobuf-c-compiler \
			ronn \
			universal-ctags \
		&& rm -rf /var/lib/apt/lists/*

#############################################################

FROM builder-dependencies AS builder

COPY --from=builder-sources /usr/src/ocserv/ /usr/src/ocserv/

RUN set -x \
		&& cd /usr/src/ocserv \
		&& autoreconf -fvi \
		&& ./configure --enable-oidc-auth \
		&& make \
		&& make install \
		&& mkdir -p /usr/local/share/ocserv \
		&& cp /usr/src/ocserv/doc/sample.config /usr/local/share/ocserv/sample.config \
		&& cd / \
		&& rm -rf /usr/src/ocserv

#############################################################

FROM base AS config

COPY --from=builder /usr/local/share/ocserv/sample.config /tmp/ocserv.conf.template

RUN set -x \
		&& sed -i 's/\.\/sample\.passwd/\/etc\/ocserv\/ocpasswd/'																			/tmp/ocserv.conf.template \
		&& sed -i 's/\(max-same-clients = \)2/\110/' 																									/tmp/ocserv.conf.template \
		&& sed -i 's/\.\.\/tests/\/etc\/ocserv/'																											/tmp/ocserv.conf.template \
		&& sed -i 's/#\(compression.*\)/\1/'																													/tmp/ocserv.conf.template \
		&& sed -i 's/^route/#route/'																																	/tmp/ocserv.conf.template \
		&& sed -i 's/^no-route/#no-route/'																														/tmp/ocserv.conf.template \
		&& sed -i '/\[vhost:www.example.com\]/,$d'																										/tmp/ocserv.conf.template \
		&& sed -i '/^cookie-timeout = /{s/300/3600/}'																									/tmp/ocserv.conf.template \
		&& sed -i '/^pid-file = /{s/\/var\/run\/ocserv\.pid/\/run\/ocserv\.pid/}'											/tmp/ocserv.conf.template \
		&& sed -i '/^socket-file = /{s/\/var\/run\/ocserv-socket/\/run\/ocserv\.socket/}'							/tmp/ocserv.conf.template \
		&& sed -i '/^isolate-workers = /{s/true/\$\{OCS_ISOLATE_WORKERS\}/}'													/tmp/ocserv.conf.template \
		&& sed -i '/^ipv4-network = /{s/192.168.1.0/\$\{OCS_NETWORK\}/}'															/tmp/ocserv.conf.template \
		&& sed -i '/^ipv4-netmask = /{s/255.255.255.0/\$\{OCS_NETMASK\}/}'														/tmp/ocserv.conf.template \
		&& sed -i '/^dns = /{s/192.168.1.2/\$\{OCS_DNS\}/}'																						/tmp/ocserv.conf.template \
		&& sed -i '/^camouflage = /{s/false/\$\{OCS_CAMOUFLAGE\}/}'																		/tmp/ocserv.conf.template \
		&& sed -i '/^camouflage_realm = /{s/\"Restricted\ Content\"/\"\$\{OCS_CAMOUFLAGE_REALM\}\"/}'	/tmp/ocserv.conf.template \
		&& sed -i '/^camouflage_secret = /{s/\"mysecretkey\"/\"\$\{OCS_CAMOUFLAGE_SECRET\}\"/}'				/tmp/ocserv.conf.template \
		&& sed -i '/^default-domain = /{s/example\.com/\$\{OCS_DEFAULT_DOMAIN\}/}'										/tmp/ocserv.conf.template \
		&& sed -i '/^auth = /{s/\"plain\[passwd=\/etc\/ocserv\/ocpasswd\]\"/\"\$\{OCS_AUTH\}\"/}'			/tmp/ocserv.conf.template \
		&& mkdir -p /usr/local/share/ocserv \
		&& cat /tmp/ocserv.conf.template | grep -v '^#' | grep -v '^$' | sort -u > /usr/local/share/ocserv/ocserv.conf.envsubst \
		&& rm -rf /tmp/*

############################################################

FROM base AS runtime-dependencies

RUN set -x \
		&& apt-get update && apt-get install -y \
			iptables \
			gettext-base \
			gnutls-bin \
		&& rm -rf /var/lib/apt/lists/* \
		&& rm -rf /usr/local/*

COPY docker-entrypoint.sh /entrypoint.sh
RUN set -x \
		&& chmod a+x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]

############################################################

FROM runtime-dependencies AS runtime

WORKDIR /etc/ocserv

COPY --from=builder /usr/local/ /usr/local/

COPY --from=config /usr/local/share/ocserv/ocserv.conf.envsubst /usr/local/share/ocserv/ocserv.conf.envsubst

CMD ["ocserv", "-c", "/etc/ocserv/ocserv.conf", "-f"]

EXPOSE 443

LABEL org.opencontainers.image.description "OpenConnect server automated build"
