#!/usr/bin/env bash
# Keeps the admissions-hourly job running on the Flink cluster, as the
# flink-sql service of ../compose.yaml: every FLINK_SUBMIT_INTERVAL
# seconds (30) it asks the JobManager for its jobs and submits
# admissions-hourly.sql when none of that name is running (or starting,
# restarting...), once Kafka takes a connection. So a second
# `docker compose up`, or this container's restart, never doubles the job,
# and a JobManager that restarted, and lost its jobs, gets it back.
#
#   submit.sh          the loop
#   submit.sh check    exits 0 when the job is on the cluster (the
#                      container's health check)
set -uo pipefail

jobmanager="${FLINK_REST_URL:-http://flink-jobmanager:8081}"
interval="${FLINK_SUBMIT_INTERVAL:-30}"
name=healthhub-admissions-hourly
sql="$(dirname "$0")/admissions-hourly.sql"

# on_cluster: 0 when the JobManager lists the job in a state that isn't
# final, 1 when it doesn't, 2 when it doesn't answer. /jobs/overview
# answers {"jobs":[{"jid":...,"name":...,"state":...,"tasks":{...}},...]};
# each job is cut to one line (at its "jid"), its name and state in it.
on_cluster() {
    local overview
    overview="$(curl -fs --max-time 5 "$jobmanager/jobs/overview")" || return 2
    sed 's/{"jid"/\n{"jid"/g' <<<"$overview" \
        | grep -F "\"name\":\"$name\"" \
        | grep -qvE '"state":"(FINISHED|FAILED|CANCELED)"'
}

# kafka_up: 0 when Kafka takes a connection at the job's bootstrap address
# (the first, if several). Compose starts this service once Kafka is
# healthy; on Kubernetes nothing orders the two, and a job submitted before
# the broker answers has its source's admin client retry without a pause,
# thousands of log lines a second in the JobManager, until it does.
kafka_up() {
    local first="${HEALTHHUB_KAFKA_BOOTSTRAP:-kafka:19092}"
    first="${first%%,*}"
    timeout 5 bash -c 'exec 3<>"/dev/tcp/$1/$2"' _ "${first%:*}" "${first##*:}" 2>/dev/null
}

# submit: runs the SQL with the database password in place, through the
# SQL client, which returns once the job is submitted. The rendered file
# is private to this user and removed after. The client echoes every
# statement, the password's too, so only its verdicts are logged (the
# job's id, or the error), with the password masked should one quote it.
# Kafka's and the database's addresses are compose's (kafka:19092,
# postgres:5432) unless HEALTHHUB_KAFKA_BOOTSTRAP, HEALTHHUB_DB_HOST and
# HEALTHHUB_DB_PORT name others (on Kubernetes, k8s/).
submit() {
    local text password kafka db_host db_port rendered output status quote="'"
    text="$(<"$sql")"
    password="${HEALTHHUB_DB_PASSWORD:-healthhub}"
    kafka="${HEALTHHUB_KAFKA_BOOTSTRAP:-kafka:19092}"
    db_host="${HEALTHHUB_DB_HOST:-postgres}"
    db_port="${HEALTHHUB_DB_PORT:-5432}"
    # A quote doubles inside the SQL string; & is literal in the replacement.
    shopt -u patsub_replacement 2>/dev/null
    password="${password//$quote/$quote$quote}"
    kafka="${kafka//$quote/$quote$quote}"
    db_host="${db_host//$quote/$quote$quote}"
    db_port="${db_port//$quote/$quote$quote}"
    text="${text//@@HEALTHHUB_DB_PASSWORD@@/$password}"
    text="${text//@@HEALTHHUB_KAFKA_BOOTSTRAP@@/$kafka}"
    text="${text//@@HEALTHHUB_DB_HOST@@/$db_host}"
    text="${text//@@HEALTHHUB_DB_PORT@@/$db_port}"
    rendered="$(mktemp /tmp/admissions-hourly.XXXXXX.sql)"
    printf '%s\n' "$text" >"$rendered"
    output="$("$FLINK_HOME/bin/sql-client.sh" -f "$rendered" 2>&1)"
    status=$?
    rm -f "$rendered"
    output="${output//$password/***}"
    # The client colours its verdicts; the escapes go too.
    sed $'s/\e\\[[0-9;]*m//g' <<<"$output" \
        | grep -E 'Job ID|\[ERROR\]|Exception|Caused by|Reason' \
        | sed 's/^/flink-sql: /'
    # The client exits 0 even when a statement failed.
    [[ $status -eq 0 && "$output" != *"[ERROR]"* ]]
}

if [[ "${1:-}" == check ]]; then
    on_cluster
    exit
fi

trap 'exit 0' TERM INT
last=""
while true; do
    on_cluster
    case $? in
        0) state=running ;;
        2) state=unreachable ;;
        *) state=absent ;;
    esac
    # Logged when the state changes, not every round.
    if [[ "$state" != "$last" ]]; then
        case "$state" in
            running) echo "flink-sql: $name is on the cluster" ;;
            unreachable) echo "flink-sql: the JobManager at $jobmanager doesn't answer yet" ;;
        esac
    fi
    if [[ "$state" == absent ]] && ! kafka_up; then
        state=waiting
        [[ "$last" != waiting ]] && echo "flink-sql: Kafka doesn't answer yet; $name is submitted once it does"
    fi
    if [[ "$state" == absent ]]; then
        echo "flink-sql: $name isn't running; submitting it"
        if submit; then
            state=submitted
        else
            echo "flink-sql: submitting $name failed; trying again in ${interval} s" >&2
        fi
    fi
    last="$state"
    sleep "$interval" & wait $!
done
