package datyx.training;

import java.sql.SQLException;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.stream.Collectors;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import datyx.catalog.Catalog;
import datyx.catalog.GroupEvent;
import datyx.catalog.Span;
import datyx.catalog.TimeSeries;
import datyx.crypto.Crypto;
import datyx.datasource.AccessCodec;
import datyx.datasource.DataSource;
import datyx.datasource.DataSource.DatabaseAccess;
import datyx.db.UniqueViolation;
import io.quarkus.narayana.jta.QuarkusTransaction;
import io.quarkus.runtime.StartupEvent;
import io.quarkus.scheduler.Scheduled;
import jakarta.annotation.PreDestroy;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Observes;
import jakarta.inject.Inject;
import jakarta.ws.rs.ProcessingException;
import jakarta.ws.rs.WebApplicationException;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.jboss.logging.Logger;

/**
 * The trainer, started with the API: it finds the groups tagged as time
 * series in each database source's catalogue (OpenMetadata) and trains
 * them, one at a time on a thread of its own, keeping each run
 * (TrainingRun), one per group and algorithm. Every minute
 * ({@code datyx.training.check-every}), the first time a few seconds after
 * start, each algorithm of a ready group is queued when it has never been
 * trained, or when its table's timeSeriesRetrain (1D when not set) has
 * passed since its latest run of that algorithm; after a failure, an hour
 * at most. never trains a group once. A run reads the group's table from
 * the source and trains it with the run's algorithm: XGBoost (Dataset,
 * XgbTrainer) or DeepAR (DeepArData, DeepArTrainer); what it can't do (the
 * catalogue or the source unreachable, a group no longer ready or no
 * longer tagged for the algorithm, too little data, a native library
 * missing) fails the run with the reason. Runs a stopped API left queued
 * or running are failed at start. Off with
 * {@code datyx.training.enabled=false} (tests).
 *
 * A group switched off (TimeSeries.Disabled, TimeSeries.acute.Disabled on
 * its table) isn't trained. Switching it on is the trigger: one ENABLED
 * run per algorithm of the group, each noting the change
 * ({@link #switched}). datyx learns of it from OpenMetadata's webhook
 * (datyx.catalog.CatalogEvents), from its own switch
 * (PUT .../timeseries/enabled), or, as a safety net, at its minute's
 * check: when the Disabled tag is gone and the trainer saw it at its last
 * look, or OpenMetadata's history of the table shows it removed after the
 * group's latest run. Each switch is kept (GroupEvent), and one switch on
 * queues its runs once, whichever path learns of it first.
 */
@ApplicationScoped
public class Training {

    private static final Logger LOG = Logger.getLogger(Training.class);

    static final Duration RETRY_AFTER_FAILURE = Duration.ofHours(1);

    private static final DateTimeFormatter UTC = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm 'UTC'").withZone(ZoneOffset.UTC);

    @Inject
    Catalog catalog;

    @Inject
    Crypto crypto;

    @Inject
    ObjectMapper json;

    @ConfigProperty(name = "datyx.training.enabled", defaultValue = "true")
    boolean enabled;

    /** The groups switched off at the trainer's last look, "sourceId|table|group", and since when it knows. */
    private final Map<String, Instant> seenDisabled = new ConcurrentHashMap<>();

    /**
     * Held while a run is decided and queued: the webhook, the switch and
     * the check can learn of one switch at once, and the decision (is a
     * run of this algorithm queued since?) and the run must be one step.
     */
    private final Object queueing = new Object();

    private final ExecutorService worker = Executors.newSingleThreadExecutor(r -> {
        Thread t = new Thread(r, "datyx-training");
        t.setDaemon(true);
        return t;
    });

    void onStart(@Observes StartupEvent event) {
        int interrupted = QuarkusTransaction.requiringNew().call(() -> TrainingRun.update(
            "status = ?1, finishedAt = ?2, error = ?3 where status in ?4", TrainingRun.Status.FAILED, Instant.now(),
            "interrupted: the API stopped before the run finished",
            List.of(TrainingRun.Status.QUEUED, TrainingRun.Status.RUNNING)));
        if (interrupted > 0) {
            LOG.infof("training: %d runs interrupted by a stop marked failed", interrupted);
        }
    }

    @PreDestroy
    void stop() {
        worker.shutdownNow();
    }

    /**
     * When a group's algorithm is next trained: now (Instant.EPOCH) when it
     * never was; empty while a run is queued or running, or after its run
     * when its table says never; else its latest run's time plus the
     * interval (an hour at most after a failure).
     */
    static Optional<Instant> nextAt(TrainingRun latest, String retrain) {
        if (latest == null) {
            return Optional.of(Instant.EPOCH);
        }
        if (!latest.status.done()) {
            return Optional.empty();
        }
        String every = retrain == null ? TimeSeries.DEFAULT_RETRAIN : retrain;
        if (TimeSeries.NEVER.equals(every)) {
            return Optional.empty();
        }
        Span span = Span.parse(every);
        if (span == null) {
            return Optional.empty();
        }
        Duration interval = span.duration();
        if (latest.status == TrainingRun.Status.FAILED && interval.compareTo(RETRY_AFTER_FAILURE) > 0) {
            interval = RETRY_AFTER_FAILURE;
        }
        return Optional.of(latest.queuedAt.plus(interval));
    }

    /** Whether a group can be trained, by schedule or on request: switched on, and ready (for each of its algorithms). */
    static boolean trainable(TimeSeries.Spec spec) {
        return spec.enabled() && spec.ready();
    }

    @Scheduled(every = "${datyx.training.check-every:60s}", delayed = "${datyx.training.first-check:5s}",
        concurrentExecution = Scheduled.ConcurrentExecution.SKIP)
    void check() {
        if (!enabled) {
            return;
        }
        List<Long> sources = QuarkusTransaction.requiringNew().call(() -> DataSource.<DataSource>list("type",
            DataSource.Type.DATABASE).stream().map(s -> s.id).toList());
        for (long sourceId : sources) {
            checkSource(sourceId);
        }
    }

    private static String key(long sourceId, String table, String group) {
        return sourceId + "|" + table + "|" + group;
    }

    /**
     * Notes that a group was just switched off, as if the trainer had seen
     * it: OpenMetadata merges one user's quick changes into one version, so
     * a switch off and on again within minutes may leave no trace in the
     * table's history, and the switch on would go unnoticed by the check.
     */
    public void switchedOff(long sourceId, String table, String group) {
        seenDisabled.putIfAbsent(key(sourceId, table, group), Instant.now());
    }

    /** One source's groups: switched-on groups queued, the rest when due. One look at a time. */
    synchronized void checkSource(long sourceId) {
        List<JsonNode> tables;
        try {
            tables = catalog.tables(sourceId);
        } catch (WebApplicationException | ProcessingException | IllegalStateException e) {
            LOG.debugf("training: the catalogue of data source %d can't be read: %s", sourceId, e.getMessage());
            return;
        }
        for (JsonNode table : tables) {
            for (TimeSeries.Spec spec : TimeSeries.specs(table)) {
                String key = key(sourceId, spec.table(), spec.group());
                if (!spec.enabled()) {
                    seenDisabled.putIfAbsent(key, Instant.now());
                    continue;
                }
                Instant offSince = seenDisabled.remove(key);
                try {
                    queueIfEnabled(sourceId, table, spec, offSince);
                } catch (WebApplicationException | ProcessingException | IllegalStateException e) {
                    LOG.debugf("training: the history of %s can't be read: %s", spec.table(), e.getMessage());
                }
                if (trainable(spec)) {
                    queueIfDue(sourceId, spec);
                }
            }
        }
    }

    /**
     * The check's safety net, for a switch on neither the webhook nor
     * datyx's switch told of: the trainer saw the group's Disabled tag at its
     * last look ({@code offSince}, when), or OpenMetadata's history of the
     * table shows the tag removed after the group's latest run or switch on
     * (or ever, when there is neither). Queues its runs as {@link #switched}
     * does, recorded as the check's only when it queues one.
     */
    private void queueIfEnabled(long sourceId, JsonNode table, TimeSeries.Spec spec, Instant offSince) {
        Instant since = QuarkusTransaction.requiringNew().call(() -> {
            DataSource source = DataSource.findById(sourceId);
            if (source == null) {
                return null;
            }
            Instant run = TrainingRun.latest(source, spec.table(), spec.group()).map(r -> r.queuedAt).orElse(Instant.EPOCH);
            Instant on = GroupEvent.latestOn(source, spec.table(), spec.group()).map(e -> e.receivedAt).orElse(Instant.EPOCH);
            return run.isAfter(on) ? run : on;
        });
        if (since == null || offSince != null && since.isAfter(offSince)) {
            // Its runs were queued, or its switch on recorded, since the trainer saw it off.
            return;
        }
        Optional<Catalog.Change> change = offSince != null ? Optional.of(Catalog.latestChange(table))
            : catalog.enabledAfter(table, spec.group(), since);
        if (change.isEmpty()) {
            return;
        }
        boolean merged = offSince != null && !change.get().at().isAfter(offSince);
        String note = TimeSeries.disabledFqn(spec.group()) + " removed in OpenMetadata ("
            + (!merged ? change.get().describe()
                : "seen by datyx at " + UTC.format(Instant.now()) + "; OpenMetadata merged it into table version "
                    + change.get().version() + ", as it does one user's changes within minutes")
            + ")";
        switched(new Switch(sourceId, spec.table(), spec.group(), true, GroupEvent.VIA_POLL, change.get().version(),
            change.get().by(), merged ? Instant.now() : change.get().at(), null), spec, offSince != null ? offSince : change.get().at(), note);
    }

    private void queueIfDue(long sourceId, TimeSeries.Spec spec) {
        for (String algorithm : algorithms(spec)) {
            queueIfDue(sourceId, spec, algorithm);
        }
    }

    /** The group's algorithms, by their tags: every one it is tagged for. */
    static List<String> algorithms(TimeSeries.Spec spec) {
        return spec.algorithms() != null ? spec.algorithms() : List.of(spec.algorithm());
    }

    private void queueIfDue(long sourceId, TimeSeries.Spec spec, String algorithm) {
        Long runId;
        synchronized (queueing) {
            runId = queue(() -> {
                DataSource source = DataSource.findById(sourceId);
                if (source == null) {
                    return null;
                }
                TrainingRun latest = TrainingRun.latest(source, spec.table(), spec.group(), algorithm).orElse(null);
                Optional<Instant> next = nextAt(latest, spec.retrain());
                if (next.isEmpty() || Instant.now().isBefore(next.get())) {
                    return null;
                }
                return create(source, spec, algorithm, latest == null ? TrainingRun.Trigger.INITIAL : TrainingRun.Trigger.SCHEDULE).id;
            });
        }
        if (runId != null) {
            submit(runId);
        }
    }

    /**
     * A group switched on or off, as datyx learned it: {@code via}
     * OpenMetadata's webhook, datyx's switch or the check; the table's
     * version after the change, who made it and when; OpenMetadata's id of
     * the change event, when it told.
     */
    public record Switch(long sourceId, String table, String group, boolean enabled, String via, String version, String by,
            Instant at, String omEventId) {
    }

    /** A switch kept: its GroupEvent's id and the runs it queued. */
    public record Recorded(long eventId, List<Long> runIds) {
    }

    /**
     * Keeps a switch (a GroupEvent), unless datyx knows it already, and,
     * for a switch on, queues one ENABLED run per algorithm of the group
     * ({@code spec}, read after the change), each noting {@code note}: one
     * per algorithm with no run queued at or after {@code since} (when the
     * group was switched on, or datyx knew it off: the trainer saw it off,
     * or kept a switch off after it), whether or not datyx has its trainer;
     * none while the group reads switched off again. Known already: the same
     * OpenMetadata change event; or the same switch (on or off, at the same
     * version of the table) kept since {@code since}: the webhook of datyx's
     * own switch, or the other way round (OpenMetadata may give a table a
     * version again, merging one user's quick changes, so an older one is
     * another switch). A switch off older than a switch on datyx kept since,
     * while {@code spec} reads the group on, is passed over: the switch on
     * came after it, its runs queued. The check's switch is kept only when it
     * queues a run. Empty when nothing is kept. One decision at a time, so
     * the webhook, the switch and the check never queue a switch's runs
     * twice. A switch off kept is noted as seen by the trainer.
     */
    public Optional<Recorded> switched(Switch s, TimeSeries.Spec spec, Instant since, String note) {
        String key = key(s.sourceId(), s.table(), s.group());
        Instant seenOff = seenDisabled.get(key);
        Optional<Recorded> recorded;
        synchronized (queueing) {
            recorded = Optional.ofNullable(queue(() -> record(s, spec, since, seenOff, note)));
        }
        if (recorded.isPresent()) {
            if (s.enabled()) {
                seenDisabled.remove(key);
            } else {
                seenDisabled.putIfAbsent(key, Instant.now());
            }
        }
        recorded.ifPresent(r -> {
            r.runIds().forEach(this::submit);
            LOG.infof("training: %s group %s switched %s (%s, table version %s, by %s): event %d, runs %s", s.table(), s.group(),
                s.enabled() ? "on" : "off", s.via(), s.version(), s.by(), r.eventId(), r.runIds());
        });
        return recorded;
    }

    private Recorded record(Switch s, TimeSeries.Spec spec, Instant since, Instant seenOff, String note) {
        DataSource source = DataSource.findById(s.sourceId());
        if (source == null || GroupEvent.recorded(s.omEventId())) {
            return null;
        }
        if (!s.enabled() && spec != null && spec.enabled() && s.at() != null && GroupEvent.latestOn(source, s.table(), s.group())
                .filter(on -> on.receivedAt.isAfter(s.at())).isPresent()) {
            // A switch off told late (the webhook's, after datyx's own switch on): the group is on now, and the
            // switch on datyx kept since came after it. Kept, it would make that switch on's runs look older.
            return null;
        }
        if (s.enabled()) {
            if (seenOff != null && seenOff.isAfter(since)) {
                // The trainer saw it off then: a run before belongs to an earlier switch on.
                since = seenOff;
            }
            GroupEvent latest = GroupEvent.latest(source, s.table(), s.group()).orElse(null);
            if (latest != null && !latest.enabled && latest.receivedAt.isAfter(since)) {
                // OpenMetadata merges one user's quick changes: an off and on again may carry the time of the version
                // before the off. The group was off when datyx kept the off; it was switched on after.
                since = latest.receivedAt;
            }
        }
        if (GroupEvent.keptSince(source, s.table(), s.group(), s.enabled(), s.version(), since)) {
            return null;
        }
        List<String> algorithms = new ArrayList<>();
        if (s.enabled() && spec != null && spec.enabled() && spec.algorithms() != null) {
            for (String algorithm : spec.algorithms()) {
                TrainingRun run = TrainingRun.latest(source, s.table(), s.group(), algorithm).orElse(null);
                if (run == null || run.status.done() && run.queuedAt.isBefore(since)) {
                    algorithms.add(algorithm);
                }
            }
        }
        if (GroupEvent.VIA_POLL.equals(s.via()) && algorithms.isEmpty()) {
            return null;
        }
        GroupEvent event = new GroupEvent();
        event.dataSource = source;
        event.tableFqn = s.table();
        event.groupName = s.group();
        event.enabled = s.enabled();
        event.via = s.via();
        event.omVersion = s.version();
        event.omEventId = s.omEventId();
        event.changedBy = s.by() == null || s.by().length() <= 320 ? s.by() : s.by().substring(0, 320);
        event.changedAt = s.at();
        event.receivedAt = Instant.now();
        event.persist();
        List<Long> runIds = new ArrayList<>();
        for (String algorithm : algorithms) {
            TrainingRun run = create(source, spec, algorithm, TrainingRun.Trigger.ENABLED);
            run.triggerNote = note == null || note.length() <= 500 ? note : note.substring(0, 500);
            run.eventId = event.id;
            runIds.add(run.id);
        }
        event.runIds = runIds.isEmpty() ? null : runIds.stream().map(String::valueOf).collect(Collectors.joining(","));
        return new Recorded(event.id, runIds);
    }

    /**
     * Runs {@code decide} in a transaction of its own, under the queueing
     * lock: null when the database refused a second active run of an
     * algorithm (its unique index), which the lock should already prevent.
     */
    private <T> T queue(java.util.concurrent.Callable<T> decide) {
        try {
            return QuarkusTransaction.requiringNew().call(decide);
        } catch (RuntimeException e) {
            if (UniqueViolation.in(e)) {
                LOG.infof("training: a run is queued already: %s", e.getMessage());
                return null;
            }
            throw e;
        }
    }

    /**
     * Queues a run of the group's algorithm someone asked for: empty when
     * one is queued or running already.
     */
    public Optional<Long> queueManual(long sourceId, TimeSeries.Spec spec, TimeSeries.Algorithm algorithm) {
        synchronized (queueing) {
            return Optional.ofNullable(queue(() -> {
                DataSource source = DataSource.findById(sourceId);
                TrainingRun latest = TrainingRun.latest(source, spec.table(), spec.group(), algorithm.tag).orElse(null);
                if (latest != null && !latest.status.done()) {
                    return null;
                }
                return create(source, spec, algorithm.tag, TrainingRun.Trigger.MANUAL).id;
            }));
        }
    }

    private static TrainingRun create(DataSource source, TimeSeries.Spec spec, String algorithm, TrainingRun.Trigger trigger) {
        TrainingRun run = new TrainingRun();
        run.dataSource = source;
        run.tableFqn = spec.table();
        run.groupName = spec.group();
        run.algorithm = algorithm;
        run.trigger = trigger;
        run.status = TrainingRun.Status.QUEUED;
        run.queuedAt = Instant.now();
        run.persist();
        LOG.infof("training: run %d queued (%s), %s group %s, %s", run.id, trigger.name().toLowerCase(), spec.table(), spec.group(),
            algorithm);
        return run;
    }

    /** Hands a queued run to the trainer's thread, once its transaction is committed. */
    public void submit(long runId) {
        worker.submit(() -> run(runId));
    }

    private record Job(String tableFqn, String group, String algorithm, DatabaseAccess access) {
    }

    /** Trains a queued run: reads the group's table, builds the dataset, trains and keeps what it found. */
    void run(long runId) {
        Job job = QuarkusTransaction.requiringNew().call(() -> {
            TrainingRun run = TrainingRun.findById(runId);
            if (run == null || run.status != TrainingRun.Status.QUEUED) {
                return null;
            }
            run.status = TrainingRun.Status.RUNNING;
            run.startedAt = Instant.now();
            DataSource source = run.dataSource;
            DatabaseAccess access = AccessCodec.unseal(crypto, json, source.profile.id, source.profile.keyWrapped,
                source.access).database();
            return new Job(run.tableFqn, run.groupName, run.algorithm, access);
        });
        if (job == null) {
            return;
        }
        try {
            TimeSeries.Spec spec = TimeSeries.spec(catalog.table(job.tableFqn()), job.group());
            if (!spec.enabled()) {
                throw new IllegalArgumentException("the group is switched off (" + TimeSeries.disabledFqn(job.group()) + ") now");
            }
            TimeSeries.Algorithm algorithm = TimeSeries.Algorithm.named(job.algorithm());
            if (algorithm == null || !spec.has(algorithm)) {
                throw new IllegalArgumentException("the group isn't tagged for " + job.algorithm() + " ("
                    + (algorithm == null ? job.algorithm() : algorithm.fqn(job.group())) + ") now");
            }
            if (!spec.ready()) {
                throw new IllegalArgumentException("the group isn't ready: " + String.join("; ", spec.problems()));
            }
            String results;
            byte[] model;
            XgbTrainer.Metrics test;
            int examples;
            if (algorithm == TimeSeries.Algorithm.XGBOOST) {
                Dataset.Builder builder = new Dataset.Builder(spec);
                TableReader.read(job.access(), spec, builder);
                XgbTrainer.Trained trained = XgbTrainer.train(builder.build());
                results = json.writeValueAsString(trained.result());
                model = trained.model();
                test = trained.result().test();
                examples = trained.result().dataset().examples();
            } else {
                DeepArData.Builder builder = new DeepArData.Builder(spec);
                TableReader.read(job.access(), spec, builder);
                DeepArTrainer.Trained trained = DeepArTrainer.train(builder.build());
                results = json.writeValueAsString(trained.result());
                model = trained.model();
                test = trained.result().test();
                examples = trained.result().dataset().examples();
            }
            QuarkusTransaction.requiringNew().run(() -> {
                TrainingRun run = TrainingRun.findById(runId);
                run.status = TrainingRun.Status.SUCCEEDED;
                run.finishedAt = Instant.now();
                run.results = results;
                run.model = model;
            });
            LOG.infof("training: run %d succeeded, %s group %s (%s): %d examples, test MAE %.3f (naive %.3f)", runId,
                job.tableFqn(), job.group(), job.algorithm(), examples, test.mae(), test.naiveMae());
        } catch (Throwable e) {
            String error = reason(e);
            LOG.warnf("training: run %d failed, %s group %s (%s): %s", runId, job.tableFqn(), job.group(), job.algorithm(), error);
            QuarkusTransaction.requiringNew().run(() -> {
                TrainingRun run = TrainingRun.findById(runId);
                run.status = TrainingRun.Status.FAILED;
                run.finishedAt = Instant.now();
                run.error = error.length() > 2000 ? error.substring(0, 2000) : error;
            });
        }
    }


    /** Why a run failed, in words. */
    static String reason(Throwable e) {
        if (e instanceof UnsatisfiedLinkError || e instanceof NoClassDefFoundError) {
            return "XGBoost's native library can't load (it needs an OpenMP runtime: libomp on macOS, libgomp on Linux; "
                + "and the JVM, not the native executable): " + e.getMessage();
        }
        if (e instanceof ai.djl.engine.EngineException) {
            return "DeepAR's engine, PyTorch (libtorch, through DJL), can't load (it needs the JVM, not the native "
                + "executable, and libtorch for this platform): " + e.getMessage();
        }
        if (e instanceof SQLException) {
            return "the data source can't be read: " + e.getMessage();
        }
        if (e instanceof WebApplicationException w) {
            return "OpenMetadata answered " + w.getResponse().getStatus();
        }
        if (e instanceof ProcessingException) {
            return "OpenMetadata can't be reached: " + e.getMessage();
        }
        String message = e.getMessage();
        if (e instanceof IllegalArgumentException && message != null) {
            return message;
        }
        List<String> parts = new ArrayList<>();
        parts.add(e.getClass().getSimpleName());
        if (message != null) {
            parts.add(message.strip().lines().findFirst().orElse(""));
        }
        return String.join(": ", parts);
    }
}
