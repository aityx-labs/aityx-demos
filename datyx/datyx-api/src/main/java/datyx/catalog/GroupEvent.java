package datyx.catalog;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

import datyx.datasource.DataSource;
import datyx.profile.Profile;
import io.quarkus.hibernate.orm.panache.PanacheEntity;
import io.quarkus.panache.common.Sort;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;

/**
 * A group of a source's table switched on (its Disabled tag removed) or
 * off (added), as datyx learned it (table group_event): {@code via}
 * OpenMetadata's webhook, datyx's own switch, or the trainer's check; the
 * table's version in OpenMetadata after the change, who made it and when;
 * and the runs a switch on queued, one per algorithm of the group. A
 * source's switches are its profile's.
 */
@Entity
@Table(name = "group_event")
public class GroupEvent extends PanacheEntity {

    /** OpenMetadata's webhook told datyx (POST /api/catalog/openmetadata-events). */
    public static final String VIA_WEBHOOK = "openmetadata-webhook";

    /** datyx switched it (PUT /api/datasources/{id}/timeseries/enabled). */
    public static final String VIA_API = "datyx-api";

    /** The trainer's minute check found it switched on, and queued its runs. */
    public static final String VIA_POLL = "poll";

    @ManyToOne(optional = false, fetch = FetchType.LAZY)
    @JoinColumn(name = "data_source_id")
    public DataSource dataSource;

    @Column(name = "table_fqn", nullable = false, length = 1000)
    public String tableFqn;

    @Column(name = "group_name", nullable = false, length = 64)
    public String groupName;

    @Column(nullable = false)
    public boolean enabled;

    @Column(nullable = false, length = 32)
    public String via;

    /** The table's version in OpenMetadata after the change. */
    @Column(name = "om_version", length = 32)
    public String omVersion;

    /** OpenMetadata's id of the change event and the group, when its webhook told datyx: a delivery again is the same switch. */
    @Column(name = "om_event_id", length = 128)
    public String omEventId;

    @Column(name = "changed_by", length = 320)
    public String changedBy;

    @Column(name = "changed_at")
    public Instant changedAt;

    @Column(name = "received_at", nullable = false)
    public Instant receivedAt;

    /** The runs it queued, their ids comma-separated; none for a switch off. */
    @Column(name = "run_ids", length = 1000)
    public String runIds;

    /** The ids of the runs it queued. */
    public List<Long> runIds() {
        List<Long> ids = new ArrayList<>();
        if (runIds != null) {
            for (String id : runIds.split(",")) {
                if (!id.isBlank()) {
                    ids.add(Long.parseLong(id.strip()));
                }
            }
        }
        return ids;
    }

    /** The latest switch of a group of a source's table. */
    public static Optional<GroupEvent> latest(DataSource source, String tableFqn, String group) {
        return find("dataSource = ?1 and tableFqn = ?2 and groupName = ?3", Sort.descending("receivedAt", "id"),
            source, tableFqn, group).firstResultOptional();
    }

    /** The latest switch on of a group of a source's table. */
    public static Optional<GroupEvent> latestOn(DataSource source, String tableFqn, String group) {
        return find("dataSource = ?1 and tableFqn = ?2 and groupName = ?3 and enabled = true", Sort.descending("receivedAt", "id"),
            source, tableFqn, group).firstResultOptional();
    }

    /**
     * Whether the same switch of a group (on or off, at the same version of
     * the table) was kept at or after {@code since}: told once already, by
     * another path. One kept before isn't it: OpenMetadata may give a table
     * a version again, merging one user's quick changes.
     */
    public static boolean keptSince(DataSource source, String tableFqn, String group, boolean enabled, String version,
            Instant since) {
        String query = "dataSource = ?1 and tableFqn = ?2 and groupName = ?3 and enabled = ?4 and receivedAt >= ?5 and omVersion ";
        return version == null
            ? count(query + "is null", source, tableFqn, group, enabled, since) > 0
            : count(query + "= ?6", source, tableFqn, group, enabled, since, version) > 0;
    }

    /** Whether OpenMetadata's change event is recorded already. */
    public static boolean recorded(String omEventId) {
        return omEventId != null && count("omEventId", omEventId) > 0;
    }

    /** A profile's latest switches, the newest first, at most {@code limit}. */
    public static List<GroupEvent> newest(Profile profile, int limit) {
        return find("dataSource.profile = ?1", Sort.descending("receivedAt", "id"), profile).page(0, limit).list();
    }
}
