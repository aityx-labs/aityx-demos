package datyx.training;

import java.time.Instant;
import java.util.List;

import datyx.datasource.DataSource;
import datyx.profile.Profile;
import io.quarkus.hibernate.orm.panache.PanacheEntity;
import io.quarkus.panache.common.Sort;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;

/**
 * One call to a trained model (table inference_call): who asked, which
 * model (its training run), how many series it was asked for and how many
 * it scored, how long it took, and whether it failed. A source's calls are
 * its profile's.
 */
@Entity
@Table(name = "inference_call")
public class InferenceCall extends PanacheEntity {

    public enum Status {
        OK, FAILED
    }

    @ManyToOne(optional = false, fetch = FetchType.LAZY)
    @JoinColumn(name = "data_source_id")
    public DataSource dataSource;

    @ManyToOne(optional = false, fetch = FetchType.LAZY)
    @JoinColumn(name = "training_run_id")
    public TrainingRun trainingRun;

    @Column(name = "table_fqn", nullable = false, length = 1000)
    public String tableFqn;

    @Column(name = "group_name", nullable = false, length = 64)
    public String groupName;

    @Column(name = "called_at", nullable = false)
    public Instant calledAt;

    @Column(nullable = false)
    public int millis;

    /** The series asked for; 0 for all those still observed. */
    @Column(nullable = false)
    public int requested;

    @Column(nullable = false)
    public int scored;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 16)
    public Status status;

    @Column(length = 2000)
    public String error;

    /** Who asked: the signed-in identity's email, else its subject; null while authentication is off. */
    @Column(length = 320)
    public String caller;

    /** A profile's calls since {@code since}, the newest first, at most {@code limit}. */
    public static List<InferenceCall> since(Profile profile, Instant since, int limit) {
        return find("dataSource.profile = ?1 and calledAt >= ?2", Sort.descending("calledAt", "id"), profile, since)
            .page(0, limit).list();
    }
}
