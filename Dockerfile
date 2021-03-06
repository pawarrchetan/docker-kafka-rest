FROM openjdk:8u121-jre-alpine

ENV MAVEN_MAJOR=3 \
    MAVEN_VERSION=3.3.9 \
    KAFKA_REST_VERSION=3.2.0 \
		KAFKA_REST_HOME=/kafka-rest \
    REST_UTILS_VERSION=3.2.0 \
    COMMON_VERSION=3.2.0

ARG MAVEN_OPTIONS="-DskipTests"

# Install required packages
RUN apk add --no-cache \
		bash

# Download and build Schema Registry
RUN log () { echo -e "\033[01;95m$@\033[0m"; } && \

	apk add --no-cache --virtual .fetch-deps \
		ca-certificates \
		libressl \
		tar && \

	apk add --no-cache --virtual .build-deps \
		openjdk8="$JAVA_ALPINE_VERSION" \
		rsync && \

	BUILD_DIR="$(mktemp -d)" && \

	log "Download and unpack Apache Maven" && \
	wget -O $BUILD_DIR/apache-maven-bin.tar.gz "https://www.apache.org/dist/maven/maven-$MAVEN_MAJOR/$MAVEN_VERSION/binaries/apache-maven-$MAVEN_VERSION-bin.tar.gz" && \
	wget -O $BUILD_DIR/apache-maven-bin.tar.gz.sha1 "https://www.apache.org/dist/maven/maven-$MAVEN_MAJOR/$MAVEN_VERSION/binaries/apache-maven-$MAVEN_VERSION-bin.tar.gz.sha1" && \
	echo "$(cat $BUILD_DIR/apache-maven-bin.tar.gz.sha1) *$BUILD_DIR/apache-maven-bin.tar.gz" | sha1sum -c - && \
	tar -xzf $BUILD_DIR/apache-maven-bin.tar.gz --directory=$BUILD_DIR && \

	log "Download, unpack, and build confluentinc/kafka-rest" && \
	wget -O $BUILD_DIR/kafka-rest.tar.gz "https://github.com/confluentinc/kafka-rest/archive/v$KAFKA_REST_VERSION.tar.gz" && \
	tar -xzf $BUILD_DIR/kafka-rest.tar.gz --directory=$BUILD_DIR && \
	cd $BUILD_DIR/kafka-rest-$KAFKA_REST_VERSION && \
	$BUILD_DIR/apache-maven-$MAVEN_VERSION/bin/mvn $MAVEN_OPTIONS --file=$BUILD_DIR/kafka-rest-$KAFKA_REST_VERSION/pom.xml package && \

	log "Download, unpack, and build confluentinc/rest-utils" && \
	wget -O $BUILD_DIR/rest-utils.tar.gz "https://github.com/confluentinc/rest-utils/archive/v$REST_UTILS_VERSION.tar.gz" && \
	tar -xzf $BUILD_DIR/rest-utils.tar.gz --directory=$BUILD_DIR && \
	cd $BUILD_DIR/rest-utils-$REST_UTILS_VERSION && \
	$BUILD_DIR/apache-maven-$MAVEN_VERSION/bin/mvn $MAVEN_OPTIONS --file=$BUILD_DIR/rest-utils-$REST_UTILS_VERSION/pom.xml package && \

	log "Download, unpack, and build confluentinc/common" && \
	wget -O $BUILD_DIR/common.tar.gz "https://github.com/confluentinc/common/archive/v$COMMON_VERSION.tar.gz" && \
	tar -xzf $BUILD_DIR/common.tar.gz --directory=$BUILD_DIR && \
	cd $BUILD_DIR/common-$COMMON_VERSION && \
	$BUILD_DIR/apache-maven-$MAVEN_VERSION/bin/mvn $MAVEN_OPTIONS --file=$BUILD_DIR/common-$COMMON_VERSION/pom.xml package && \

	log "Install the build packages" && \
	cp -r $BUILD_DIR/kafka-rest-$KAFKA_REST_VERSION/target/kafka-rest-$KAFKA_REST_VERSION-package $KAFKA_REST_HOME && \
	rsync -a $BUILD_DIR/rest-utils-$REST_UTILS_VERSION/package/target/rest-utils-package-$REST_UTILS_VERSION-package/ $KAFKA_REST_HOME && \
	rsync -a $BUILD_DIR/common-$COMMON_VERSION/package/target/common-package-$COMMON_VERSION-package/ $KAFKA_REST_HOME && \

	log "Clean up" && \
	rm -r "$BUILD_DIR" && \
	apk del .fetch-deps .build-deps

# Adjust the default kafka-rest properties to connect to Zookeeper at zookeeper:2181
# and Schema Registry at http://schema-registry:8081
ENV ZOOKEEPER_HOST=zookeeper \
    ZOOKEEPER_PORT=2181 \
    KAFKA_HOST=kafka \
    KAFKA_PORT=9092 \
    SCHEMA_REGISTRY_URL=http://schema-registry:8081
RUN sed -i "s/#zookeeper.connect=.*/zookeeper.connect=$ZOOKEEPER_HOST:$ZOOKEEPER_PORT/g" $KAFKA_REST_HOME/etc/kafka-rest/kafka-rest.properties && \
    sed -i "s|#schema.registry.url=.*|schema.registry.url=$SCHEMA_REGISTRY_URL|g" $KAFKA_REST_HOME/etc/kafka-rest/kafka-rest.properties

# Add wait-for-it script, for use in waiting for Zookeeper
ADD https://raw.githubusercontent.com/ucalgary/wait-for-it/master/wait-for-it.sh /usr/local/bin/wait-for-it
RUN chmod 755 /usr/local/bin/wait-for-it

# Copy custom schema-registry-start script
COPY bin/kafka-rest-docker-start $KAFKA_REST_HOME/bin/kafka-rest-docker-start

WORKDIR $KAFKA_REST_HOME

ENV PATH=$PATH:$KAFKA_REST_HOME/bin

EXPOSE 8081

CMD ["kafka-rest-docker-start", "/kafka-rest/etc/kafka-rest/kafka-rest.properties"]

LABEL maintainer="King Chung Huang <kchuang@ucalgary.ca>"
