FROM eclipse-temurin:25-jre@sha256:dbb43d81099eec91e0800226ed2296d03146ee7857165b95112372ad0d67e87f
ARG GH_VERSION=11.0
ARG GH_SHA1=4cba3d3bbdc8572f7bc6ecd6ffebf8ff6d394ce4
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl \
 && rm -rf /var/lib/apt/lists/* \
 && curl -fsSL -o /opt/graphhopper.jar \
    "https://repo1.maven.org/maven2/com/graphhopper/graphhopper-web/${GH_VERSION}/graphhopper-web-${GH_VERSION}.jar" \
 && echo "${GH_SHA1}  /opt/graphhopper.jar" | sha1sum -c -
# OpenTelemetry agent: GraphHopper itself times nothing per request. Off
# unless JAVA_OPTS adds -javaagent:/opt/opentelemetry-javaagent.jar (production).
ARG OTEL_AGENT_VERSION=2.31.1
ARG OTEL_AGENT_SHA1=1980f46fddc489e5c989d8369e655999455643ea
RUN curl -fsSL -o /opt/opentelemetry-javaagent.jar \
    "https://repo1.maven.org/maven2/io/opentelemetry/javaagent/opentelemetry-javaagent/${OTEL_AGENT_VERSION}/opentelemetry-javaagent-${OTEL_AGENT_VERSION}.jar" \
 && echo "${OTEL_AGENT_SHA1}  /opt/opentelemetry-javaagent.jar" | sha1sum -c -
COPY config.yml /opt/graphhopper/config.yml
COPY custom_models /opt/graphhopper/custom_models
WORKDIR /opt/graphhopper
# Not root: GraphHopper writes only below /data (graph, elevation cache);
# uid 1000 (the base image's «ubuntu») owns that volume, as for data-import.
USER 1000:1000
EXPOSE 8989 8990
# `server` imports the OSM file on first start when no graph exists yet.
ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /opt/graphhopper.jar server /opt/graphhopper/config.yml"]
