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

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import datyx.catalog.Catalog;
import datyx.catalog.Span;
import datyx.catalog.TimeSeries;
import datyx.crypto.Crypto;
import datyx.datasource.AccessCodec;
import datyx.datasource.DataSource;
import datyx.datasource.DataSource.DatabaseAccess;
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
 * The trainer, started with the API: it finds the groups tagged for
 * XGBoost in each database source's catalogue (OpenMetadata) and trains
 * them, one at a time on a thread of its own, keeping each run
 * (TrainingRun). Every minute ({@code datyx.training.check-every}), the
 * first time a few seconds after start, a ready group is queued when it
 * has never been trained, or when its table's timeSeriesRetrain (1D when
 * not set) has passed since its latest run; after a failure, an hour at
 * most. never trains a group once. A run reads the group's table from the
 * source, builds XGBoost's dataset (Dataset) and trains (XgbTrainer); what
 * it can't do (the catalogue or the source unreachable, a group no longer
 * ready, too little data, XGBoost's native library missing) fails the run
 * with the reason. Runs a stopped API left queued or running are failed
 * at start. Off with {@code datyx.training.enabled=false} (tests).
 *
 * A group switched off (TimeSeries.Disabled, TimeSeries.acute.Disabled on
 * its table) isn't trained. Switching it on is the trigger: when its
 * Disabled tag is gone, and the trainer saw it there at its last look, or
 * OpenMetadata's history of the table shows it removed after the group's
 * latest run, the group is queued at once, an ENABLED run, whatever its
 * algorithm, its note naming the change in OpenMetadata. A DeepAR group's
 * run fails: datyx has no DeepAR trainer yet.
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

    private final ExecutorService checker = Executors.newSingleThreadExecutor(r -> {
        Thread t = new Thread(r, "datyx-training-check");
        t.setDaemon(true);
        return t;
    });

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
        checker.shutdownNow();
        worker.shutdownNow();
    }

    /**
     * When a group is next trained: now (Instant.EPOCH) when it never was;
     * empty while a run is queued or running, or after its run when its
     * table says never; else its latest run's time plus the interval (an
     * hour at most after a failure).
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

    /** Whether a group can be trained, by schedule or on request: switched on, tagged for XGBoost, and ready. */
    static boolean trainable(TimeSeries.Spec spec) {
        return spec.enabled() && TimeSeries.Algorithm.XGBOOST.tag.equals(spec.algorithm()) && spec.ready();
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

    /**
     * Looks at the source's groups soon, on a thread of the trainer's own:
     * after a group is switched on through datyx, so its run doesn't wait
     * for the next minute's check.
     */
    public void checkSoon(long sourceId) {
        if (enabled) {
            checker.submit(() -> checkSource(sourceId));
        }
    }

    /**
     * Notes that a group was just switched off through datyx, as if the
     * trainer had seen it: OpenMetadata merges one user's quick changes into
     * one version, so a switch off and on again within minutes may leave no
     * trace in the table's history, and the switch on would go unnoticed.
     */
    public void switchedOff(long sourceId, TimeSeries.Spec spec) {
        seenDisabled.putIfAbsent(sourceId + "|" + spec.table() + "|" + spec.group(), Instant.now());
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
                String key = sourceId + "|" + spec.table() + "|" + spec.group();
                if (!spec.enabled()) {
                    seenDisabled.putIfAbsent(key, Instant.now());
                    continue;
                }
                Instant offSince = seenDisabled.remove(key);
                try {
                    if (queueIfEnabled(sourceId, table, spec, offSince)) {
                        continue;
                    }
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
     * Queues an ENABLED run of a group switched on since its latest run:
     * the trainer saw its Disabled tag at its last look ({@code offSince}, when),
     * or OpenMetadata's history of the table shows the tag removed after
     * that run (or ever, when it never ran). Whatever its algorithm. False
     * when it wasn't switched on, or a run of it is queued or running.
     */
    private boolean queueIfEnabled(long sourceId, JsonNode table, TimeSeries.Spec spec, Instant offSince) {
        Instant after = QuarkusTransaction.requiringNew().call(() -> {
            DataSource source = DataSource.findById(sourceId);
            TrainingRun latest = source == null ? null : TrainingRun.latest(source, spec.table(), spec.group()).orElse(null);
            return latest == null ? Instant.EPOCH : latest.queuedAt;
        });
        Optional<Catalog.Change> change = offSince != null ? Optional.of(Catalog.latestChange(table))
            : catalog.enabledAfter(table, spec.group(), after);
        if (change.isEmpty()) {
            return false;
        }
        String note = TimeSeries.disabledFqn(spec.group()) + " removed in OpenMetadata ("
            + (offSince == null || change.get().at().isAfter(offSince) ? change.get().describe()
                : "seen by datyx at " + UTC.format(Instant.now()) + "; OpenMetadata merged it into table version "
                    + change.get().version() + ", as it does one user's changes within minutes")
            + ")";
        Long runId = QuarkusTransaction.requiringNew().call(() -> {
            DataSource source = DataSource.findById(sourceId);
            if (source == null) {
                return null;
            }
            TrainingRun latest = TrainingRun.latest(source, spec.table(), spec.group()).orElse(null);
            if (latest != null && (!latest.status.done() || latest.queuedAt.isAfter(after))) {
                return null;
            }
            TrainingRun run = create(source, spec, TrainingRun.Trigger.ENABLED);
            run.triggerNote = note.length() > 500 ? note.substring(0, 500) : note;
            return run.id;
        });
        if (runId != null) {
            submit(runId);
        }
        return true;
    }

    private void queueIfDue(long sourceId, TimeSeries.Spec spec) {
        Long runId = QuarkusTransaction.requiringNew().call(() -> {
            DataSource source = DataSource.findById(sourceId);
            if (source == null) {
                return null;
            }
            TrainingRun latest = TrainingRun.latest(source, spec.table(), spec.group()).orElse(null);
            Optional<Instant> next = nextAt(latest, spec.retrain());
            if (next.isEmpty() || Instant.now().isBefore(next.get())) {
                return null;
            }
            return create(source, spec, latest == null ? TrainingRun.Trigger.INITIAL : TrainingRun.Trigger.SCHEDULE).id;
        });
        if (runId != null) {
            submit(runId);
        }
    }

    /**
     * Queues a run of the group someone asked for, in the caller's
     * transaction: empty when one is queued or running already.
     */
    public Optional<TrainingRun> queueManual(DataSource source, TimeSeries.Spec spec) {
        TrainingRun latest = TrainingRun.latest(source, spec.table(), spec.group()).orElse(null);
        if (latest != null && !latest.status.done()) {
            return Optional.empty();
        }
        return Optional.of(create(source, spec, TrainingRun.Trigger.MANUAL));
    }

    private static TrainingRun create(DataSource source, TimeSeries.Spec spec, TrainingRun.Trigger trigger) {
        TrainingRun run = new TrainingRun();
        run.dataSource = source;
        run.tableFqn = spec.table();
        run.groupName = spec.group();
        run.algorithm = spec.algorithm();
        run.trigger = trigger;
        run.status = TrainingRun.Status.QUEUED;
        run.queuedAt = Instant.now();
        run.persist();
        LOG.infof("training: run %d queued (%s), %s group %s", run.id, trigger.name().toLowerCase(), spec.table(), spec.group());
        return run;
    }

    /** Hands a queued run to the trainer's thread, once its transaction is committed. */
    public void submit(long runId) {
        worker.submit(() -> run(runId));
    }

    private record Job(String tableFqn, String group, DatabaseAccess access) {
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
            return new Job(run.tableFqn, run.groupName, access);
        });
        if (job == null) {
            return;
        }
        try {
            TimeSeries.Spec spec = TimeSeries.spec(catalog.table(job.tableFqn()), job.group());
            if (!spec.enabled()) {
                throw new IllegalArgumentException("the group is switched off (" + TimeSeries.disabledFqn(job.group()) + ") now");
            }
            if (!TimeSeries.Algorithm.XGBOOST.tag.equals(spec.algorithm())) {
                throw new IllegalArgumentException("datyx has no " + spec.algorithm()
                    + " trainer yet: only XGBoost groups train (tag the table " + TimeSeries.Algorithm.XGBOOST.fqn(job.group())
                    + " and set its timeSeriesHorizon to train this group with XGBoost)");
            }
            if (!spec.ready()) {
                throw new IllegalArgumentException("the group isn't ready: " + String.join("; ", spec.problems()));
            }
            Dataset.Builder builder = new Dataset.Builder(spec);
            TableReader.read(job.access(), spec, builder);
            XgbTrainer.Trained trained = XgbTrainer.train(builder.build());
            String results = json.writeValueAsString(trained.result());
            QuarkusTransaction.requiringNew().run(() -> {
                TrainingRun run = TrainingRun.findById(runId);
                run.status = TrainingRun.Status.SUCCEEDED;
                run.finishedAt = Instant.now();
                run.results = results;
                run.model = trained.model();
            });
            XgbTrainer.Metrics test = trained.result().test();
            LOG.infof("training: run %d succeeded, %s group %s: %d examples, test MAE %.3f (naive %.3f)", runId,
                job.tableFqn(), job.group(), trained.result().dataset().examples(), test.mae(), test.naiveMae());
        } catch (Throwable e) {
            String error = reason(e);
            LOG.warnf("training: run %d failed, %s group %s: %s", runId, job.tableFqn(), job.group(), error);
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
