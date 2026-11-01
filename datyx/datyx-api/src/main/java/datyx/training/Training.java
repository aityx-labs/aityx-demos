package datyx.training;

import java.sql.SQLException;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
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
 */
@ApplicationScoped
public class Training {

    private static final Logger LOG = Logger.getLogger(Training.class);

    static final Duration RETRY_AFTER_FAILURE = Duration.ofHours(1);

    @Inject
    Catalog catalog;

    @Inject
    Crypto crypto;

    @Inject
    ObjectMapper json;

    @ConfigProperty(name = "datyx.training.enabled", defaultValue = "true")
    boolean enabled;

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

    /** Whether a group can be trained: tagged for XGBoost, and ready. */
    static boolean trainable(TimeSeries.Spec spec) {
        return TimeSeries.Algorithm.XGBOOST.tag.equals(spec.algorithm()) && spec.ready();
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
            List<JsonNode> tables;
            try {
                tables = catalog.tables(sourceId);
            } catch (WebApplicationException | ProcessingException | IllegalStateException e) {
                LOG.debugf("training: the catalogue of data source %d can't be read: %s", sourceId, e.getMessage());
                continue;
            }
            for (JsonNode table : tables) {
                for (TimeSeries.Spec spec : TimeSeries.specs(table)) {
                    if (trainable(spec)) {
                        queueIfDue(sourceId, spec);
                    }
                }
            }
        }
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
            if (!TimeSeries.Algorithm.XGBOOST.tag.equals(spec.algorithm())) {
                throw new IllegalArgumentException("the group is tagged for " + spec.algorithm() + ", not XGBoost, now");
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
