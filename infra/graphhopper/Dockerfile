FROM eclipse-temurin:21-jre
ARG GH_VERSION=11.0
ARG GH_SHA1=4cba3d3bbdc8572f7bc6ecd6ffebf8ff6d394ce4
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl \
 && rm -rf /var/lib/apt/lists/* \
 && curl -fsSL -o /opt/graphhopper.jar \
    "https://repo1.maven.org/maven2/com/graphhopper/graphhopper-web/${GH_VERSION}/graphhopper-web-${GH_VERSION}.jar" \
 && echo "${GH_SHA1}  /opt/graphhopper.jar" | sha1sum -c -
COPY config.yml /opt/graphhopper/config.yml
COPY custom_models /opt/graphhopper/custom_models
WORKDIR /opt/graphhopper
EXPOSE 8989 8990
# `server` imports the OSM file on first start when no graph exists yet.
ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /opt/graphhopper.jar server /opt/graphhopper/config.yml"]
