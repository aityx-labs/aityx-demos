package datyx.training;

import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;

import datyx.catalog.Span;
import datyx.catalog.TimeSeries;

/**
 * DeepAR's data made from a time series group (its TimeSeries tags): each
 * series (the SeriesKey's values) as its Target step by step, from its
 * first row to its end, with its static categories coded. Rows are summed
 * into steps of the frequency. A series ends as in XGBoost's Dataset: with
 * missing rows as zero, at its cohort's end (the latest row of the series
 * that share its key but the last column), quiet steps counting 0; with
 * missing rows unknown, at its own last row, steps without rows unknown
 * (NaN, which DeepAR doesn't learn from). The horizon (prediction_length)
 * is the table's timeSeriesHorizon in steps, {@link #DEFAULT_HORIZON} steps
 * when it has none. KnownCovariates, PastCovariates and StaticReals aren't
 * used yet.
 */
public final class DeepArData {

    /** The steps forecast when the table has no timeSeriesHorizon. */
    public static final int DEFAULT_HORIZON = 24;

    /** One series, laid out: its key, its categories' codes, the step it starts at, and its Target per step. */
    public record Item(Map<String, String> series, int[] categories, long start, float[] target) {

        /** The step after its last: where its forecast starts. */
        public long end() {
            return start + target.length;
        }
    }

    public final TimeSeries.Spec spec;

    /** DJL's name for the frequency: H, 15min, D, W. */
    public final String freq;

    /** A step's length, in seconds. */
    public final long step;

    /** The steps forecast. */
    public final int horizon;

    /** Each StaticCategorical column's codes, by value: kept with a model, so inference codes as training did. */
    public final Map<String, Map<String, Integer>> categories;

    public final List<Item> items;

    /** The rows read. */
    public final int rows;

    private DeepArData(TimeSeries.Spec spec, String freq, long step, int horizon,
            Map<String, Map<String, Integer>> categories, List<Item> items, int rows) {
        this.spec = spec;
        this.freq = freq;
        this.step = step;
        this.horizon = horizon;
        this.categories = categories;
        this.items = items;
        this.rows = rows;
    }

    /**
     * The horizon DeepAR forecasts for a group: its table's, else
     * {@link #DEFAULT_HORIZON} steps of its frequency (1D for 1h); null when
     * the frequency isn't a fixed span.
     */
    public static String horizonOf(TimeSeries.Spec spec) {
        if (spec.horizon() != null) {
            return spec.horizon();
        }
        Span frequency = Span.parse(spec.frequency());
        return frequency == null ? null : Span.of(frequency.duration().multipliedBy(DEFAULT_HORIZON));
    }

    /** How many values each StaticCategorical column can take: its codes, and one for a value never seen. */
    public List<Integer> cardinality() {
        List<Integer> c = new ArrayList<>();
        for (String column : spec.staticCategorical()) {
            c.add(categories.get(column).size() + 1);
        }
        return c;
    }

    /** The time a step starts, as a date and time without a zone, as the table's timestamps are read. */
    public LocalDateTime time(long bucket) {
        return time(step, bucket);
    }

    static LocalDateTime time(long step, long bucket) {
        return LocalDateTime.ofInstant(Instant.ofEpochSecond(bucket * step), ZoneOffset.UTC);
    }

    /** All the steps the series hold. */
    public long steps() {
        return items.stream().mapToLong(i -> i.target().length).sum();
    }

    /** Adds rows one at a time, summing each series' steps, then {@link #build()}s the series. */
    public static final class Builder implements Rows {

        private final TimeSeries.Spec spec;
        private final String freq;
        private final long step;
        private final int horizon;
        private final boolean zero;
        private final boolean frozen;
        private final Map<String, Map<String, Integer>> categories = new LinkedHashMap<>();
        private final Map<List<String>, Series> series = new LinkedHashMap<>();
        private final Map<List<String>, Long> observedUntil = new HashMap<>();
        private int rows;

        /** An IllegalArgumentException says why the frequency or horizon can't be trained on. */
        public Builder(TimeSeries.Spec spec) {
            this(spec, null);
        }

        /**
         * A builder that codes categories as {@code categories} says, as a
         * model was trained (a value it didn't see is code 0, unknown), or by
         * first appearance when null.
         */
        public Builder(TimeSeries.Spec spec, Map<String, Map<String, Integer>> categories) {
            this.spec = spec;
            this.frozen = categories != null;
            for (String c : spec.staticCategorical()) {
                Map<String, Integer> known = categories == null ? null : categories.get(c);
                this.categories.put(c, known == null ? new LinkedHashMap<>() : new LinkedHashMap<>(known));
            }
            Span frequency = Span.parse(spec.frequency());
            if (frequency == null) {
                throw new IllegalArgumentException("DeepAR steps by a fixed span (such as 15min, 1h, 1D or 1W), not "
                    + spec.frequency());
            }
            this.step = frequency.duration().toSeconds();
            this.freq = (frequency.count() == 1 ? "" : String.valueOf(frequency.count())) + switch (frequency.unit()) {
                case "h" -> "H";
                case "min" -> "min";
                default -> frequency.unit();
            };
            if (spec.horizon() == null) {
                this.horizon = DEFAULT_HORIZON;
            } else {
                Span h = Span.parse(spec.horizon());
                if (h == null) {
                    throw new IllegalArgumentException("the horizon is a fixed span (such as 24h, 30D or 4W), not "
                        + spec.horizon());
                }
                long ratio = h.duration().toSeconds() / step;
                if (ratio < 1 || h.duration().toSeconds() % step != 0 || ratio > 1000) {
                    throw new IllegalArgumentException("the horizon " + spec.horizon() + " isn't a whole number of steps of "
                        + spec.frequency() + " (at most 1000)");
                }
                this.horizon = (int) ratio;
            }
            this.zero = "zero".equals(spec.missing());
        }

        @Override
        public void add(Dataset.Row row) {
            rows++;
            Series s = series.computeIfAbsent(row.key(), k -> new Series(row.categories()));
            s.steps.merge(Math.floorDiv(row.epochSecond(), step), row.target(),
                (a, b) -> Double.isNaN(a) ? b : (Double.isNaN(b) ? a : a + b));
            for (int i = 0; i < s.categories.length; i++) {
                if (s.categories[i] == null) {
                    s.categories[i] = row.categories()[i];
                }
            }
        }

        @Override
        public int rows() {
            return rows;
        }

        @Override
        public void observedUntil(List<String> cohort, long epochSecond) {
            observedUntil.merge(cohort, Math.floorDiv(epochSecond, step), Math::max);
        }

        /** The series, each laid out from its first step to its end; an IllegalArgumentException when there are none, or too many steps. */
        public DeepArData build() {
            if (series.isEmpty()) {
                throw new IllegalArgumentException("the table has no rows to train on");
            }
            Map<List<String>, Long> ends = new HashMap<>(observedUntil);
            for (Map.Entry<List<String>, Series> e : series.entrySet()) {
                ends.merge(cohort(e.getKey()), e.getValue().steps.lastKey(), Math::max);
            }
            List<Item> items = new ArrayList<>();
            long total = 0;
            for (Map.Entry<List<String>, Series> e : series.entrySet()) {
                Series s = e.getValue();
                long start = s.steps.firstKey();
                long end = zero ? ends.get(cohort(e.getKey())) : s.steps.lastKey();
                total += end - start + 1;
                if (total > Dataset.MAX_STEPS) {
                    throw new IllegalArgumentException("the series hold over " + Dataset.MAX_STEPS + " steps of "
                        + spec.frequency() + ": too many to train on in the API");
                }
                float[] target = new float[(int) (end - start + 1)];
                for (int i = 0; i < target.length; i++) {
                    Double v = s.steps.get(start + i);
                    target[i] = v == null || v.isNaN() ? (zero ? 0 : Float.NaN) : v.floatValue();
                }
                items.add(new Item(key(e.getKey()), codes(s), start, target));
            }
            Map<String, Map<String, Integer>> codes = new LinkedHashMap<>();
            categories.forEach((column, m) -> codes.put(column, Map.copyOf(m)));
            return new DeepArData(spec, freq, step, horizon, codes, items, rows);
        }

        /** A series' categories coded from 1, 0 for none or a value a frozen model never saw. */
        private int[] codes(Series s) {
            int[] c = new int[s.categories.length];
            for (int i = 0; i < c.length; i++) {
                String v = s.categories[i];
                Map<String, Integer> m = categories.get(spec.staticCategorical().get(i));
                Integer code = v == null ? null : (frozen ? m.get(v) : m.computeIfAbsent(v, x -> m.size() + 1));
                c[i] = code == null ? 0 : code;
            }
            return c;
        }

        private Map<String, String> key(List<String> values) {
            Map<String, String> key = new LinkedHashMap<>();
            for (int k = 0; k < spec.seriesKey().size(); k++) {
                key.put(spec.seriesKey().get(k), values.get(k));
            }
            return key;
        }

        private static List<String> cohort(List<String> key) {
            return key.size() >= 2 ? key.subList(0, key.size() - 1) : List.of();
        }
    }

    /** One series' rows, summed per step. */
    private static final class Series {
        final String[] categories;
        final TreeMap<Long, Double> steps = new TreeMap<>();

        Series(String[] categories) {
            this.categories = categories.clone();
        }
    }
}
