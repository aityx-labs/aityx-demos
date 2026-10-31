# Flink with what the admissions-hourly job needs, for the flink-*
# services of ../compose.yaml: the Kafka connector, the JDBC connector
# with its PostgreSQL dialect, and the PostgreSQL driver, from Maven
# Central, each pinned to its version and checked against its SHA-256;
# then the job's SQL and the script that submits it (submit.sh).
FROM flink:2.2.1-java21

ARG MAVEN=https://repo1.maven.org/maven2
ADD --chmod=644 --checksum=sha256:5605c691d11a501382c383fecba37a7a552467da5ab7ba904ef5d6f3d62c5616 \
    ${MAVEN}/org/apache/flink/flink-sql-connector-kafka/5.0.0-2.2/flink-sql-connector-kafka-5.0.0-2.2.jar /opt/flink/lib/
ADD --chmod=644 --checksum=sha256:f8357ab799095e6486315db4019edf63ced762bc8c2eaa63614c7b962755564b \
    ${MAVEN}/org/apache/flink/flink-connector-jdbc-core/4.1.0-2.2/flink-connector-jdbc-core-4.1.0-2.2.jar /opt/flink/lib/
ADD --chmod=644 --checksum=sha256:ae6da5769d932123606f1b9e03d90d57cde9c1d0144df6ffa64a9701afb86d6b \
    ${MAVEN}/org/apache/flink/flink-connector-jdbc-postgres/4.1.0-2.2/flink-connector-jdbc-postgres-4.1.0-2.2.jar /opt/flink/lib/
ADD --chmod=644 --checksum=sha256:73914527305a40cce504b0d3d90b23caf565136912d607ae8ae7c5895512332c \
    ${MAVEN}/org/postgresql/postgresql/42.7.14/postgresql-42.7.14.jar /opt/flink/lib/
# The JDBC connector reports the tables it writes to Flink's lineage
# through OpenLineage's JDBC helpers, and fails to plan without them.
ADD --chmod=644 --checksum=sha256:d575b68bf72996e34d59013c9e877c19c0eea876fcccd49e246287048d09a54b \
    ${MAVEN}/io/openlineage/openlineage-java/1.32.0/openlineage-java-1.32.0.jar /opt/flink/lib/

# Read-only to the flink user; submit.sh is executable in git.
COPY admissions-hourly.sql submit.sh /opt/flink/healthhub/
