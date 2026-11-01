package datyx.catalog;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Pattern;

import com.fasterxml.jackson.databind.JsonNode;
import io.quarkus.runtime.annotations.RegisterForReflection;

/**
 * datyx's vocabulary for time series, kept in OpenMetadata: what a column
 * is to a forecast, as a tag of the TimeSeries classification, and how
 * often a table's rows come and what a missing row means, as two custom
 * properties of the table. Whoever knows the data says it there (in
 * OpenMetadata's UI, or through PUT /api/datasources/{id}/timeseries);
 * the source itself never changes. The roles are the model's inputs in
 * general terms, so one tagging serves DeepAR or XGBoost (what each role
 * becomes to them is in its description).
 *
 * A table can hold more than one series, each a group of roles with a
 * name: TimeSeries.Target is the default group's Target,
 * TimeSeries.acute.Target the acute group's (a child tag of
 * TimeSeries.acute). Groups share the table's columns, frequency and
 * missing rows, and are read as datasets of their own, so one column can
 * be the Timestamp of every group and a Target in one of them only.
 *
 * Each group says which algorithm trains on it with a tag on the table:
 * TimeSeries.XGBoost for the default group, TimeSeries.acute.XGBoost for
 * acute; none is DeepAR, as before there were algorithms to choose. How
 * far ahead to predict is the table's timeSeriesHorizon, which its groups
 * share, required for XGBoost. What trains a group finds it by its
 * algorithm's tag.
 *
 * A group can be switched off, with TimeSeries.Disabled (the default
 * group's) or TimeSeries.acute.Disabled on the table: datyx doesn't train
 * it, and removing the tag, in OpenMetadata or through datyx, is what
 * trains it again (datyx.training.Training).
 */
public final class TimeSeries {

    public static final String CLASSIFICATION = "TimeSeries";

    public static final String CLASSIFICATION_DESCRIPTION = """
        What a column is to a time series forecast, such as DeepAR's. A table is a time series dataset \
        when one column is its Timestamp and one its Target; set the table's timeSeriesFrequency too. \
        For more than one dataset in a table, tag a group's columns with the roles under the group's own \
        tag (TimeSeries.acute.Target): each group is a dataset of its own. A tag on the table names the \
        algorithm that trains a group (TimeSeries.XGBoost, TimeSeries.acute.XGBoost; DeepAR when none), \
        and the table's timeSeriesHorizon how far ahead it predicts. TimeSeries.acute.Disabled on the \
        table switches the group off: datyx doesn't train it until the tag is removed, which trains it.""";

    /** The group of the roles tagged without one (TimeSeries.Target). */
    public static final String DEFAULT_GROUP = "default";

    private static final Pattern GROUP_PATTERN = Pattern.compile("[A-Za-z0-9_-]{1,64}");

    /** The table's custom property for how often rows come: a pandas offset such as 15min, 1h, 1D, 1W, 1MS. */
    public static final String FREQUENCY = "timeSeriesFrequency";

    /** The table's custom property for what a missing row means: zero (counts) or unknown (not observed). */
    public static final String MISSING = "timeSeriesMissing";

    public static final Set<String> MISSING_VALUES = Set.of("zero", "unknown");

    /** The table's custom property for how far ahead to predict, as a pandas offset such as 24h or 30D. */
    public static final String HORIZON = "timeSeriesHorizon";

    /**
     * The table's custom property for how often datyx trains its groups
     * again: a span such as 6h, 1D or 1W, or never (trained once).
     */
    public static final String RETRAIN = "timeSeriesRetrain";

    /** How often a group is trained again when its table doesn't say. */
    public static final String DEFAULT_RETRAIN = "1D";

    /** The value of {@link #RETRAIN} that trains a group once only. */
    public static final String NEVER = "never";

    /** The tag, under the classification or a group, that switches a group off. */
    public static final String DISABLED = "Disabled";

    public static final String DISABLED_DESCRIPTION = """
        This group of the table is switched off: datyx doesn't train it. Remove the tag (here, or with \
        the group's switch on datyx's dashboard) to switch it on: datyx then trains it at once with its \
        algorithm, a run whose trigger is 'enabled'.""";

    /** The tag on a table that switches a group off: TimeSeries.Disabled for the default group, TimeSeries.acute.Disabled for acute. */
    public static String disabledFqn(String group) {
        return DEFAULT_GROUP.equals(group) ? CLASSIFICATION + "." + DISABLED : CLASSIFICATION + "." + group + "." + DISABLED;
    }

    /** The group a table's tag FQN switches off, or null for a tag that isn't a TimeSeries Disabled tag. */
    static String disabledGroupOf(String fqn) {
        String[] parts = fqn.split("\\.", -1);
        if (parts.length < 2 || parts.length > 3 || !CLASSIFICATION.equals(parts[0]) || !DISABLED.equals(parts[parts.length - 1])) {
            return null;
        }
        if (parts.length == 2) {
            return DEFAULT_GROUP;
        }
        return GROUP_PATTERN.matcher(parts[1]).matches() && !isReserved(parts[1]) ? parts[1] : null;
    }

    private static final Pattern FREQUENCY_PATTERN = Pattern.compile("\\d*(s|min|h|D|B|W|W-[A-Z]{3}|MS|ME|M|QS|QE|Q|YS|YE|Y)");

    public enum Role {
        TIMESTAMP("Timestamp", "timestamp", """
            The time index: when each row's values were observed. One per table, a date or timestamp. \
            DeepAR: the series' start and the position of each value. XGBoost: the cutoffs a score is made \
            at, and the windows before and after them."""),
        TARGET("Target", "target", """
            The value to forecast. One per table, numeric. DeepAR: target. XGBoost: the label, its sum \
            over the horizon after a cutoff; its sums over windows before the cutoff are features."""),
        SERIES_KEY("SeriesKey", "seriesKey", """
            Says which series a row belongs to; together, the columns tagged so name one series. \
            None: the table is one series. DeepAR: item_id. XGBoost: whom a score is for, one row per \
            series and cutoff."""),
        STATIC_CATEGORICAL("StaticCategorical", "staticCategorical", """
            A category that holds for a whole series, such as its region or kind. DeepAR: feat_static_cat. \
            XGBoost: a categorical feature."""),
        STATIC_REAL("StaticReal", "staticReal", """
            A number that holds for a whole series, such as a size or capacity. DeepAR: feat_static_real. \
            XGBoost: a numeric feature."""),
        KNOWN_COVARIATE("KnownCovariate", "knownCovariates", """
            A number that changes over time and is known ahead, for the hours to forecast too, such as a \
            schedule, a holiday or a planned price. DeepAR: feat_dynamic_real. XGBoost: features of the \
            horizon ahead."""),
        PAST_COVARIATE("PastCovariate", "pastCovariates", """
            A number that changes over time and is only known once observed, such as a related count. \
            DeepAR: past_feat_dynamic_real, where the model supports it. XGBoost: its sums over windows \
            before the cutoff, as features.""");

        public final String tag;
        public final String field;
        public final String description;

        Role(String tag, String field, String description) {
            this.tag = tag;
            this.field = field;
            this.description = description;
        }

        public String fqn() {
            return CLASSIFICATION + "." + tag;
        }

        /** The role's tag in a group: TimeSeries.Target in the default group, TimeSeries.acute.Target in acute. */
        public String fqn(String group) {
            return DEFAULT_GROUP.equals(group) ? fqn() : CLASSIFICATION + "." + group + "." + tag;
        }

        static Role ofTag(String tag) {
            for (Role role : values()) {
                if (role.tag.equals(tag)) {
                    return role;
                }
            }
            return null;
        }
    }

    /**
     * What trains a group, as a tag on the table: TimeSeries.XGBoost for the
     * default group, TimeSeries.acute.XGBoost for acute. A group without one
     * is DeepAR's.
     */
    public enum Algorithm {
        DEEPAR("DeepAR", """
            DeepAR (GluonTS) trains on this group of the table: a probabilistic forecast of each series, step by \
            step over the horizon (prediction_length). A group without an algorithm tag is DeepAR's too."""),
        XGBOOST("XGBoost", """
            XGBoost trains on this group of the table: a score per series, the Target summed over the table's \
            timeSeriesHorizon after each cutoff (required), predicted from the series' static features, the \
            Target and PastCovariates summed over windows before the cutoff and the KnownCovariates ahead.""");

        public static final Algorithm DEFAULT = DEEPAR;

        public final String tag;
        public final String description;

        Algorithm(String tag, String description) {
            this.tag = tag;
            this.description = description;
        }

        /** The algorithm's tag for a group: TimeSeries.XGBoost in the default group, TimeSeries.acute.XGBoost in acute. */
        public String fqn(String group) {
            return DEFAULT_GROUP.equals(group) ? CLASSIFICATION + "." + tag : CLASSIFICATION + "." + group + "." + tag;
        }

        static Algorithm ofTag(String tag) {
            for (Algorithm algorithm : values()) {
                if (algorithm.tag.equals(tag)) {
                    return algorithm;
                }
            }
            return null;
        }

        /**
         * The algorithm a request names, in any case; null for none (the
         * group's tag removed: DeepAR). An IllegalArgumentException names the
         * algorithms there are.
         */
        public static Algorithm named(String name) {
            if (name == null || name.isBlank()) {
                return null;
            }
            for (Algorithm algorithm : values()) {
                if (algorithm.tag.equalsIgnoreCase(name.strip())) {
                    return algorithm;
                }
            }
            throw new IllegalArgumentException("the algorithm is DeepAR or XGBoost, not '" + name.strip() + "'");
        }
    }

    /** A group's algorithm, as a table's tag says it. */
    record Trained(String group, Algorithm algorithm) {
    }

    /** The group and algorithm a table's tag FQN names, or null for a tag that isn't a TimeSeries algorithm. */
    static Trained algorithmOf(String fqn) {
        String[] parts = fqn.split("\\.", -1);
        if (parts.length < 2 || parts.length > 3 || !CLASSIFICATION.equals(parts[0])) {
            return null;
        }
        Algorithm algorithm = Algorithm.ofTag(parts[parts.length - 1]);
        if (algorithm == null) {
            return null;
        }
        if (parts.length == 2) {
            return new Trained(DEFAULT_GROUP, algorithm);
        }
        return GROUP_PATTERN.matcher(parts[1]).matches() && !isReserved(parts[1]) ? new Trained(parts[1], algorithm) : null;
    }

    /** A role in a group, as a column's tag says it. */
    record Tagged(String group, Role role) {
    }

    /** The group and role a tag FQN names, or null for a tag that isn't a TimeSeries role. */
    static Tagged ofFqn(String fqn) {
        String[] parts = fqn.split("\\.", -1);
        if (parts.length < 2 || parts.length > 3 || !CLASSIFICATION.equals(parts[0])) {
            return null;
        }
        Role role = Role.ofTag(parts[parts.length - 1]);
        if (role == null) {
            return null;
        }
        if (parts.length == 2) {
            return new Tagged(DEFAULT_GROUP, role);
        }
        return GROUP_PATTERN.matcher(parts[1]).matches() && !isReserved(parts[1]) ? new Tagged(parts[1], role) : null;
    }

    /**
     * The group a request names: the default one when none, else the name as
     * given. An IllegalArgumentException says why a name can't be a group's.
     */
    public static String group(String name) {
        if (name == null || name.isBlank() || DEFAULT_GROUP.equals(name.strip())) {
            return DEFAULT_GROUP;
        }
        String group = name.strip();
        if (!GROUP_PATTERN.matcher(group).matches()) {
            throw new IllegalArgumentException("a group's name is letters, digits, _ and -, up to 64: not '" + group + "'");
        }
        if (isReserved(group)) {
            throw new IllegalArgumentException("'" + group + "' is a role, an algorithm or Disabled, so it can't name a group");
        }
        return group;
    }

    /** A role's or an algorithm's name, or Disabled, in any case: tags under the classification or a group, never a group. */
    private static boolean isReserved(String name) {
        if (DISABLED.equalsIgnoreCase(name)) {
            return true;
        }
        for (Role role : Role.values()) {
            if (role.tag.equalsIgnoreCase(name)) {
                return true;
            }
        }
        for (Algorithm algorithm : Algorithm.values()) {
            if (algorithm.tag.equalsIgnoreCase(name)) {
                return true;
            }
        }
        return false;
    }

    private TimeSeries() {
    }

    /**
     * A table read as a time series dataset: the algorithm that trains on
     * the group, whether it is switched on ({@code enabled}: the table has
     * no Disabled tag for it), the columns of each role, the frequency, the
     * horizon and the meaning of a missing row, and what keeps it from
     * being one ({@code problems}; ready when there are none).
     */
    @RegisterForReflection
    public record Spec(String table, String schema, String name, String group, String algorithm, boolean enabled, String timestamp, String target,
            List<String> seriesKey, List<String> staticCategorical, List<String> staticReal, List<String> knownCovariates,
            List<String> pastCovariates, String frequency, String horizon, String missing, String retrain, boolean ready,
            List<String> problems) {
    }

    /**
     * The groups OpenMetadata's table (with columns, their tags, and its
     * own tags) has a column tagged in, or an algorithm for, the default
     * first; none: no series.
     */
    public static List<String> groups(JsonNode table) {
        Set<String> groups = new LinkedHashSet<>();
        for (JsonNode column : table.path("columns")) {
            for (JsonNode tag : column.path("tags")) {
                Tagged tagged = ofFqn(tag.path("tagFQN").asText());
                if (tagged != null) {
                    groups.add(tagged.group());
                }
            }
        }
        for (JsonNode tag : table.path("tags")) {
            Trained trained = algorithmOf(tag.path("tagFQN").asText());
            if (trained != null) {
                groups.add(trained.group());
            }
        }
        List<String> ordered = new ArrayList<>(groups);
        if (ordered.remove(DEFAULT_GROUP)) {
            ordered.add(0, DEFAULT_GROUP);
        }
        return ordered;
    }

    /** OpenMetadata's table as the time series datasets it holds, one per group. */
    public static List<Spec> specs(JsonNode table) {
        return groups(table).stream().map(group -> spec(table, group)).toList();
    }

    /** OpenMetadata's table (with columns, their tags, its own tags and extension) as one group's time series dataset. */
    public static Spec spec(JsonNode table, String group) {
        Map<Role, List<String>> columns = new LinkedHashMap<>();
        for (Role role : Role.values()) {
            columns.put(role, new ArrayList<>());
        }
        Map<String, String> types = new LinkedHashMap<>();
        Map<String, Set<Role>> rolesOf = new LinkedHashMap<>();
        for (JsonNode column : table.path("columns")) {
            String name = column.path("name").asText();
            types.put(name, column.path("dataType").asText("UNKNOWN"));
            for (JsonNode tag : column.path("tags")) {
                Tagged tagged = ofFqn(tag.path("tagFQN").asText());
                if (tagged != null && tagged.group().equals(group)) {
                    columns.get(tagged.role()).add(name);
                    rolesOf.computeIfAbsent(name, n -> new LinkedHashSet<>()).add(tagged.role());
                }
            }
        }
        List<String> problems = new ArrayList<>();
        List<Algorithm> algorithms = new ArrayList<>();
        for (JsonNode tag : table.path("tags")) {
            Trained trained = algorithmOf(tag.path("tagFQN").asText());
            if (trained != null && trained.group().equals(group) && !algorithms.contains(trained.algorithm())) {
                algorithms.add(trained.algorithm());
            }
        }
        Algorithm algorithm = algorithms.isEmpty() ? Algorithm.DEFAULT : algorithms.get(0);
        boolean enabled = true;
        for (JsonNode tag : table.path("tags")) {
            if (group.equals(disabledGroupOf(tag.path("tagFQN").asText()))) {
                enabled = false;
            }
        }
        if (algorithms.size() > 1) {
            problems.add("the table is tagged " + String.join(" and ", algorithms.stream().map(a -> a.fqn(group)).toList())
                + "; one algorithm trains a group (tag another group for the other)");
        }
        String timestamp = single(columns.get(Role.TIMESTAMP), Role.TIMESTAMP.fqn(group), "the time index", problems);
        String target = single(columns.get(Role.TARGET), Role.TARGET.fqn(group), "the value to forecast", problems);
        if (timestamp != null && !ColumnTypes.TEMPORAL.contains(types.get(timestamp))) {
            problems.add("the Timestamp column " + timestamp + " is " + types.get(timestamp) + ", not a date or timestamp");
        }
        for (Role role : List.of(Role.TARGET, Role.STATIC_REAL, Role.KNOWN_COVARIATE, Role.PAST_COVARIATE)) {
            for (String column : columns.get(role)) {
                if (!ColumnTypes.NUMERIC.contains(types.get(column))) {
                    problems.add("the " + role.tag + " column " + column + " is " + types.get(column) + ", not a number");
                }
            }
        }
        rolesOf.forEach((column, roles) -> {
            for (Role only : List.of(Role.TIMESTAMP, Role.TARGET)) {
                if (roles.contains(only) && roles.size() > 1) {
                    problems.add(column + " is the " + only.tag + " and can't also be " + others(roles, only));
                }
            }
            if (roles.contains(Role.KNOWN_COVARIATE) && roles.contains(Role.PAST_COVARIATE)) {
                problems.add(column + " is tagged both KnownCovariate and PastCovariate; it is one or the other");
            }
        });
        JsonNode extension = table.path("extension");
        String frequency = text(extension.get(FREQUENCY));
        if (frequency == null) {
            problems.add("the table has no " + FREQUENCY + " (such as 1h, 1D or 1W)");
        } else if (!FREQUENCY_PATTERN.matcher(frequency).matches()) {
            problems.add(FREQUENCY + " '" + frequency + "' isn't a frequency such as 15min, 1h, 1D, 1W or 1MS");
        }
        String horizon = text(extension.get(HORIZON));
        if (horizon == null) {
            if (algorithm == Algorithm.XGBOOST) {
                problems.add("the table has no " + HORIZON + ", how far ahead XGBoost scores (such as 30D)");
            }
        } else if (!FREQUENCY_PATTERN.matcher(horizon).matches()) {
            problems.add(HORIZON + " '" + horizon + "' isn't a span such as 24h, 30D or 4W");
        }
        String retrain = text(extension.get(RETRAIN));
        if (retrain != null && !NEVER.equals(retrain) && Span.parse(retrain) == null) {
            problems.add(RETRAIN + " '" + retrain + "' is neither a span such as 6h, 1D or 1W nor never");
        }
        String missing = text(extension.get(MISSING));
        if (missing == null) {
            missing = "unknown";
        } else if (!MISSING_VALUES.contains(missing)) {
            problems.add(MISSING + " '" + missing + "' is neither zero (a missing row counts nothing) nor unknown");
        }
        return new Spec(table.path("fullyQualifiedName").asText(), table.path("databaseSchema").path("name").asText(null),
            table.path("name").asText(), group, algorithm.tag, enabled, timestamp, target, columns.get(Role.SERIES_KEY),
            columns.get(Role.STATIC_CATEGORICAL), columns.get(Role.STATIC_REAL), columns.get(Role.KNOWN_COVARIATE),
            columns.get(Role.PAST_COVARIATE), frequency, horizon, missing, retrain, problems.isEmpty(), problems);
    }

    private static String single(List<String> columns, String tag, String what, List<String> problems) {
        if (columns.size() == 1) {
            return columns.get(0);
        }
        if (columns.isEmpty()) {
            problems.add("no column is tagged " + tag + ", " + what);
        } else {
            problems.add(columns.size() + " columns are tagged " + tag + " (" + String.join(", ", columns)
                + "); one is " + what);
        }
        return null;
    }

    private static String others(Set<Role> roles, Role except) {
        List<String> tags = new ArrayList<>();
        for (Role role : roles) {
            if (role != except) {
                tags.add(role.tag);
            }
        }
        return String.join(" or ", tags);
    }

    private static String text(JsonNode node) {
        if (node == null || node.isNull()) {
            return null;
        }
        String value = node.isArray() && !node.isEmpty() ? node.get(0).asText() : node.asText();
        return value == null || value.isBlank() ? null : value.strip();
    }
}
