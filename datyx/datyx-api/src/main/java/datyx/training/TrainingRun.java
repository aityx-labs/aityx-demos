package datyx.training;

import java.time.Instant;
import java.util.List;
import java.util.Optional;

import datyx.datasource.DataSource;
import datyx.profile.Profile;
import io.quarkus.hibernate.orm.panache.PanacheEntity;
import io.quarkus.panache.common.Sort;
import jakarta.persistence.Basic;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;

/**
 * One training of a group of a source's table (table training_run): queued,
 * running, then succeeded or failed, with why it ran, what it measured
 * ({@code results}, the JSON of {@link XgbTrainer.Result}) and the trained
 * model (XGBoost's UBJSON). A source's runs are its profile's.
 */
@Entity
@Table(name = "training_run")
public class TrainingRun extends PanacheEntity {

    public enum Trigger {
        /** The group had never been trained. */
        INITIAL,
        /** Its table's timeSeriesRetrain said it was time. */
        SCHEDULE,
        /** Someone asked (POST .../training). */
        MANUAL
    }

    public enum Status {
        QUEUED, RUNNING, SUCCEEDED, FAILED;

        public boolean done() {
            return this == SUCCEEDED || this == FAILED;
        }
    }

    @ManyToOne(optional = false, fetch = FetchType.LAZY)
    @JoinColumn(name = "data_source_id")
    public DataSource dataSource;

    @Column(name = "table_fqn", nullable = false, length = 1000)
    public String tableFqn;

    @Column(name = "group_name", nullable = false, length = 64)
    public String groupName;

    @Column(nullable = false, length = 32)
    public String algorithm;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 16)
    public Trigger trigger;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 16)
    public Status status;

    @Column(name = "queued_at", nullable = false)
    public Instant queuedAt;

    @Column(name = "started_at")
    public Instant startedAt;

    @Column(name = "finished_at")
    public Instant finishedAt;

    @Column(length = 2000)
    public String error;

    /** What the run measured and found, as JSON: see XgbTrainer.Result. */
    @Column(columnDefinition = "text")
    public String results;

    /** The trained model, XGBoost's UBJSON; read only when needed. */
    @Basic(fetch = FetchType.LAZY)
    public byte[] model;

    /** A profile's latest runs, the newest first, at most {@code limit}. */
    public static List<TrainingRun> newest(Profile profile, int limit) {
        return find("dataSource.profile = ?1", Sort.descending("queuedAt", "id"), profile).page(0, limit).list();
    }

    /** A profile's run by id: empty when there is none, or it is another profile's. */
    public static Optional<TrainingRun> of(Profile profile, long id) {
        return find("id = ?1 and dataSource.profile = ?2", id, profile).firstResultOptional();
    }

    /** The latest run of a group of a source's table, whatever its status. */
    public static Optional<TrainingRun> latest(DataSource source, String tableFqn, String group) {
        return find("dataSource = ?1 and tableFqn = ?2 and groupName = ?3", Sort.descending("queuedAt", "id"),
            source, tableFqn, group).firstResultOptional();
    }

    /** The latest run of the group that succeeded. */
    public static Optional<TrainingRun> latestSucceeded(DataSource source, String tableFqn, String group) {
        return find("dataSource = ?1 and tableFqn = ?2 and groupName = ?3 and status = ?4", Sort.descending("queuedAt", "id"),
            source, tableFqn, group, Status.SUCCEEDED).firstResultOptional();
    }
}
