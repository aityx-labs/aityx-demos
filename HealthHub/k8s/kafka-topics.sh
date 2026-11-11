#!/bin/bash
# Kafka's readiness probe (kafka.yaml): ready once the broker answers a
# client and HealthHub's topics exist, as compose.yaml's health check. It
# makes the missing ones: healthhub.people.moves, healthhub.admissions,
# healthhub.alarms and healthhub.test, and healthhub.admissions.hourly, the
# Flink job's upserts, compacted as well as kept a day. Kafka's REST proxy
# answers 404 to a record for an unknown topic instead of letting the
# broker make it, so they must exist before the API publishes.
#
# It lists the topics (one JVM) and makes only those missing. Once they
# all exist it notes so in a file of the container's, and from then on
# checks only that the broker accepts connections: a client run is a JVM
# of its own, a second or two of CPU, too much for every probe. It reaches
# the broker on the pod's own listener, advertised as localhost:9092, as
# the Service routes nothing to the pod until this probe passes.
set -uo pipefail
export KAFKA_HEAP_OPTS=-Xmx64m
topics_sh=/opt/kafka/bin/kafka-topics.sh
bootstrap=localhost:9092
made=/tmp/healthhub-topics-made

if [[ -f "$made" ]]; then
  (exec 3<>/dev/tcp/127.0.0.1/9092) 2>/dev/null
  exit
fi
listed="$("$topics_sh" --bootstrap-server "$bootstrap" --list 2>/dev/null)" || exit 1
for topic in healthhub.people.moves healthhub.admissions healthhub.alarms healthhub.test; do
  grep -qxF "$topic" <<<"$listed" && continue
  "$topics_sh" --bootstrap-server "$bootstrap" --create --if-not-exists --topic "$topic" >/dev/null 2>&1 || exit 1
done
if ! grep -qxF healthhub.admissions.hourly <<<"$listed"; then
  "$topics_sh" --bootstrap-server "$bootstrap" --create --if-not-exists --topic healthhub.admissions.hourly \
    --config cleanup.policy=compact,delete >/dev/null 2>&1 || exit 1
fi
touch "$made"
