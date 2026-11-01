package datyx.training;

import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import java.util.TreeSet;

import datyx.catalog.Span;
import datyx.catalog.TimeSeries;
import io.quarkus.runtime.annotations.RegisterForReflection;

/**
 * XGBoost's dataset made from a time series group (its TimeSeries tags),
 * whatever the table: one example per series and cutoff, its label the
 * Target summed over the horizon after the cutoff, its features what is
 * known at the cutoff.
 *
 * Rows are summed into steps of the frequency, per series (the SeriesKey's
 * values). A series runs from its first row to its end: with missing rows
 * as zero, the end of its cohort (the latest row of the series that share
 * its key but the last column: in HealthHub, the run's last day; with one
 * key column, the table's latest), so quiet steps at the end count as zero;
 * with missing rows unknown, its own last row. The features, per cutoff:
 * each StaticCategorical (categorical) and StaticReal; how many steps of
 * history the series has; the steps since the Target was last above zero;
 * the Target and each PastCovariate summed over the last 1, H, 3H and 12H
 * steps (H the horizon's steps); each KnownCovariate summed over the next
 * H. Cutoffs step back from each series' end every {@code stride} steps,
 * a quarter of the horizon, more when there would be over
 * {@link #MAX_EXAMPLES}. Examples are split by time: the latest 20% of
 * cutoffs test, the 15% before validation (early stopping), the rest
 * training, each label ending before the next part's first cutoff. The
 * series still observed (whose end is the latest) are scored at their end.
 */
public final class Dataset {

    public static final int MAX_EXAMPLES = 250_000;

    static final long MAX_STEPS = 50_000_000L;

    static final int MIN_TRAIN = 30;

    static final int MIN_TEST = 10;

    /** A row of the table: when, the series key's values, and the role columns' values (NaN for null). */
    public record Row(long epochSecond, List<String> key, String[] categories, double[] reals, double target,
            double[] past, double[] known) {
    }

    /** Examples as XGBoost takes them: a row-major matrix of features, labels, and the naive forecast of each. */
    public record Part(float[] features, float[] labels, double[] naive, int rows) {
    }

    /** A series scored at its end (a step): its key's values, its features, and its Target over the last horizon. */
    public record Scored(Map<String, String> series, float[] features, double last, long end) {
    }

    @RegisterForReflection
    public record Summary(int rows, int series, long steps, int examples, int train, int valid, int test, int stride,
            int features, String frequency, String horizon, String firstCutoff, String lastCutoff, String scoredAt,
            int scored) {
    }

    public final List<String> featureNames;
    public final String[] featureTypes;
    public final Part train;
    public final Part valid;
    public final Part test;
    public final List<Scored> scored;
    public final Summary summary;

    /** The group as it was read: what a model trained on it was trained with, and inference rebuilds. */
    public final TimeSeries.Spec spec;

    /** Each StaticCategorical column's codes, by value: kept with a model, so inference codes as training did. */
    public final Map<String, Map<String, Integer>> categories;

    private Dataset(TimeSeries.Spec spec, Map<String, Map<String, Integer>> categories, List<String> featureNames,
            String[] featureTypes, Part train, Part valid, Part test, List<Scored> scored, Summary summary) {
        this.spec = spec;
        this.categories = categories;
        this.featureNames = featureNames;
        this.featureTypes = featureTypes;
        this.train = train;
        this.valid = valid;
        this.test = test;
        this.scored = scored;
        this.summary = summary;
    }

    /** Adds rows one at a time, summing each series' steps, then {@link #build()}s the dataset. */
    public static final class Builder implements Rows {

        private final TimeSeries.Spec spec;
        private final Span frequency;
        private final Span horizonSpan;
        private final long step;
        private final int horizon;
        private final boolean zero;
        private final Map<List<String>, Series> series = new LinkedHashMap<>();
        private final Map<String, Map<String, Integer>> categories = new LinkedHashMap<>();
        private final boolean frozen;
        private final Map<List<String>, Long> observedUntil = new HashMap<>();
        private int rows;

        /** An IllegalArgumentException says why the frequency or horizon can't be trained on. */
        public Builder(TimeSeries.Spec spec) {
            this(spec, null);
        }

        /**
         * A builder that codes categories as {@code categories} says, as a
         * model was trained (a value it didn't see is missing), or by first
         * appearance when null.
         */
        public Builder(TimeSeries.Spec spec, Map<String, Map<String, Integer>> categories) {
            this.spec = spec;
            this.frozen = categories != null;
            for (String c : spec.staticCategorical()) {
                Map<String, Integer> known = categories == null ? null : categories.get(c);
                this.categories.put(c, known == null ? new LinkedHashMap<>() : new LinkedHashMap<>(known));
            }
            this.frequency = Span.parse(spec.frequency());
            if (frequency == null) {
                throw new IllegalArgumentException("the trainer steps by a fixed span (such as 15min, 1h, 1D or 1W), not "
                    + spec.frequency());
            }
            this.horizonSpan = Span.parse(spec.horizon());
            if (horizonSpan == null) {
                throw new IllegalArgumentException("the horizon is a fixed span (such as 24h, 30D or 4W), not " + spec.horizon());
            }
            this.step = frequency.duration().toSeconds();
            long ratio = horizonSpan.duration().toSeconds() / step;
            if (ratio < 1 || horizonSpan.duration().toSeconds() % step != 0 || ratio > 10_000) {
                throw new IllegalArgumentException("the horizon " + spec.horizon() + " isn't a whole number of steps of "
                    + spec.frequency());
            }
            this.horizon = (int) ratio;
            this.zero = "zero".equals(spec.missing());
        }

        public void add(Row row) {
            rows++;
            long bucket = Math.floorDiv(row.epochSecond(), step);
            Series s = series.computeIfAbsent(row.key(), k -> new Series(row.categories(), row.reals()));
            double[] values = new double[1 + row.past().length + row.known().length];
            values[0] = row.target();
            System.arraycopy(row.past(), 0, values, 1, row.past().length);
            System.arraycopy(row.known(), 0, values, 1 + row.past().length, row.known().length);
            s.steps.merge(bucket, values, Dataset::sum);
            s.fill(row.categories(), row.reals());
        }

        public int rows() {
            return rows;
        }

        /**
         * Says the cohort of a series (its key but the last column) was
         * observed until a time its rows read here may not reach: inference
         * reads only the series it scores, and a series ends with its cohort.
         */
        public void observedUntil(List<String> cohort, long epochSecond) {
            observedUntil.merge(cohort, Math.floorDiv(epochSecond, step), Math::max);
        }

        /** Each cohort's end: its series' latest step, or later when {@link #observedUntil} says so. */
        private Map<List<String>, Long> cohortEnds() {
            Map<List<String>, Long> ends = new HashMap<>(observedUntil);
            for (Map.Entry<List<String>, Series> e : series.entrySet()) {
                ends.merge(cohort(e.getKey()), e.getValue().steps.lastKey(), Math::max);
            }
            return ends;
        }

        private int[] windows() {
            return new TreeSet<>(List.of(1, horizon, 3 * horizon, 12 * horizon)).stream().mapToInt(Integer::intValue).toArray();
        }

        /** The static features of a series: its categories coded, then its numbers. */
        private float[] fixed(Series s) {
            float[] fixed = new float[spec.staticCategorical().size() + spec.staticReal().size()];
            for (int i = 0; i < spec.staticCategorical().size(); i++) {
                String v = s.categories[i];
                Map<String, Integer> m = categories.get(spec.staticCategorical().get(i));
                Integer code = v == null ? null : (frozen ? m.get(v) : m.computeIfAbsent(v, x -> m.size()));
                fixed[i] = code == null ? Float.NaN : code;
            }
            for (int i = 0; i < spec.staticReal().size(); i++) {
                fixed[spec.staticCategorical().size() + i] = (float) s.reals[i];
            }
            return fixed;
        }

        private Map<String, String> key(List<String> values) {
            Map<String, String> key = new LinkedHashMap<>();
            for (int k = 0; k < spec.seriesKey().size(); k++) {
                key.put(spec.seriesKey().get(k), values.get(k));
            }
            return key;
        }

        /**
         * Every series' features at its end (its cohort's, with missing rows
         * as zero), and its Target over the last horizon: what a model
         * scores. No minimum of data: a series of one row is scored too.
         */
        public List<Scored> atEnd() {
            Map<List<String>, Long> cohortEnds = cohortEnds();
            int[] windows = windows();
            int nPast = spec.pastCovariates().size();
            int nKnown = spec.knownCovariates().size();
            int nFeatures = featureCount(windows);
            List<Scored> scored = new ArrayList<>();
            for (Map.Entry<List<String>, Series> e : series.entrySet()) {
                Series s = e.getValue();
                long start = s.steps.firstKey();
                long end = zero ? cohortEnds.get(cohort(e.getKey())) : s.steps.lastKey();
                float[] fixed = fixed(s);
                Dense d = new Dense(e.getKey(), s, start, end);
                d.fill(zero, 1 + nPast + nKnown);
                int i = (int) (end - start);
                scored.add(new Scored(key(e.getKey()), features(d, i, fixed, windows, nPast, nKnown, nFeatures, false),
                    d.sum(0, i - horizon + 1, i), end));
            }
            return scored;
        }

        private int featureCount(int[] windows) {
            return spec.staticCategorical().size() + spec.staticReal().size() + 2
                + (1 + spec.pastCovariates().size()) * windows.length + spec.knownCovariates().size();
        }

        /** The dataset; an IllegalArgumentException says why there's too little to train on, or too much. */
        public Dataset build() {
            if (series.isEmpty()) {
                throw new IllegalArgumentException("the table has no rows to train on");
            }
            Map<List<String>, Long> cohortEnds = cohortEnds();
            long latest = Long.MIN_VALUE;
            long totalSteps = 0;
            List<Dense> dense = new ArrayList<>();
            for (Map.Entry<List<String>, Series> e : series.entrySet()) {
                Series s = e.getValue();
                long start = s.steps.firstKey();
                long end = zero ? cohortEnds.get(cohort(e.getKey())) : s.steps.lastKey();
                totalSteps += end - start + 1;
                if (totalSteps > MAX_STEPS) {
                    throw new IllegalArgumentException("the series hold over " + MAX_STEPS + " steps of " + frequency
                        + ": too many to train on in the API");
                }
                latest = Math.max(latest, end);
                dense.add(new Dense(e.getKey(), s, start, end));
            }
            int[] windows = windows();
            int nPast = spec.pastCovariates().size();
            int nKnown = spec.knownCovariates().size();

            List<String> names = new ArrayList<>();
            List<String> types = new ArrayList<>();
            for (String c : spec.staticCategorical()) {
                names.add(c);
                types.add("c");
            }
            for (String r : spec.staticReal()) {
                names.add(r);
                types.add("q");
            }
            names.add("steps of history");
            types.add("q");
            names.add("steps since " + spec.target() + " > 0");
            types.add("q");
            List<String> summed = new ArrayList<>();
            summed.add(spec.target());
            summed.addAll(spec.pastCovariates());
            for (String v : summed) {
                for (int w : windows) {
                    names.add(v + ", last " + new Span(frequency.count() * w, frequency.unit()));
                    types.add("q");
                }
            }
            for (String k : spec.knownCovariates()) {
                names.add(k + ", next " + horizonSpan);
                types.add("q");
            }
            int nFeatures = names.size();

            int stride = Math.max(1, horizon / 4);
            long count = 0;
            for (Dense d : dense) {
                count += cutoffs(d, stride);
            }
            if (count > MAX_EXAMPLES) {
                stride = (int) Math.ceil(stride * (double) count / MAX_EXAMPLES);
            }

            List<Example> examples = new ArrayList<>();
            List<Scored> scored = new ArrayList<>();
            for (Dense d : dense) {
                float[] fixed = fixed(d.series);
                d.fill(zero, 1 + nPast + nKnown);
                for (long c = d.end - horizon; c >= d.start; c -= stride) {
                    int i = (int) (c - d.start);
                    if (!zero && d.nan(0, i + 1, i + horizon) > 0) {
                        continue;
                    }
                    float[] f = features(d, i, fixed, windows, nPast, nKnown, nFeatures, true);
                    examples.add(new Example(c, f, d.sum(0, i + 1, i + horizon), d.sum(0, i - horizon + 1, i)));
                }
                if (d.end == latest) {
                    int i = (int) (d.end - d.start);
                    scored.add(new Scored(key(d.key), features(d, i, fixed, windows, nPast, nKnown, nFeatures, false),
                        d.sum(0, i - horizon + 1, i), d.end));
                }
            }

            long[] times = examples.stream().mapToLong(Example::cutoff).sorted().toArray();
            if (times.length == 0) {
                throw new IllegalArgumentException("no series is longer than the horizon (" + horizonSpan
                    + "): nothing to learn from");
            }
            long testFrom = times[(int) Math.floor(0.8 * (times.length - 1))];
            long validFrom = times[(int) Math.floor(0.65 * (times.length - 1))];
            List<Example> tr = new ArrayList<>();
            List<Example> va = new ArrayList<>();
            List<Example> te = new ArrayList<>();
            for (Example e : examples) {
                if (e.cutoff >= testFrom) {
                    te.add(e);
                } else if (e.cutoff >= validFrom && e.cutoff + horizon < testFrom) {
                    va.add(e);
                } else if (e.cutoff + horizon < validFrom) {
                    tr.add(e);
                }
            }
            if (tr.size() < MIN_TRAIN || te.size() < MIN_TEST) {
                throw new IllegalArgumentException("too few examples to train on: " + tr.size() + " for training and "
                    + te.size() + " for testing (at least " + MIN_TRAIN + " and " + MIN_TEST + "); the data needs to span "
                    + "more than a few horizons");
            }
            Summary summary = new Summary(rows, series.size(), totalSteps, examples.size(), tr.size(), va.size(), te.size(),
                stride, nFeatures, frequency.toString(), horizonSpan.toString(), time(times[0] + 1),
                time(times[times.length - 1] + 1), time(latest + 1), scored.size());
            Map<String, Map<String, Integer>> codes = new LinkedHashMap<>();
            categories.forEach((column, m) -> codes.put(column, Map.copyOf(m)));
            return new Dataset(spec, codes, List.copyOf(names), types.toArray(String[]::new), part(tr, nFeatures),
                part(va, nFeatures), part(te, nFeatures), scored, summary);
        }

        private long cutoffs(Dense d, int stride) {
            long span = d.end - horizon - d.start;
            return span < 0 ? 0 : span / stride + 1;
        }

        private float[] features(Dense d, int i, float[] fixed, int[] windows, int nPast, int nKnown, int nFeatures,
                boolean ahead) {
            float[] f = new float[nFeatures];
            int j = 0;
            for (float v : fixed) {
                f[j++] = v;
            }
            f[j++] = i + 1;
            f[j++] = d.lastAbove[i] < 0 ? Float.NaN : i - d.lastAbove[i];
            for (int v = 0; v <= nPast; v++) {
                for (int w : windows) {
                    f[j++] = (float) d.sum(v, i - w + 1, i);
                }
            }
            for (int k = 0; k < nKnown; k++) {
                f[j++] = ahead ? (float) d.sum(1 + nPast + k, i + 1, i + horizon) : Float.NaN;
            }
            return f;
        }

        /** The time a step starts, as a date and time: a cutoff at step c knows up to the start of step c + 1. */
        private String time(long bucket) {
            return LocalDateTime.ofInstant(Instant.ofEpochSecond(bucket * step), ZoneOffset.UTC).toString();
        }

        private static List<String> cohort(List<String> key) {
            return key.size() >= 2 ? key.subList(0, key.size() - 1) : List.of();
        }
    }

    private record Example(long cutoff, float[] features, double label, double naive) {
    }

    private static Part part(List<Example> examples, int nFeatures) {
        float[] x = new float[examples.size() * nFeatures];
        float[] y = new float[examples.size()];
        double[] naive = new double[examples.size()];
        for (int r = 0; r < examples.size(); r++) {
            Example e = examples.get(r);
            System.arraycopy(e.features(), 0, x, r * nFeatures, nFeatures);
            y[r] = (float) e.label();
            naive[r] = e.naive();
        }
        return new Part(x, y, naive, examples.size());
    }

    /** One series' rows, summed per step. */
    private static final class Series {
        final String[] categories;
        final double[] reals;
        final TreeMap<Long, double[]> steps = new TreeMap<>();

        Series(String[] categories, double[] reals) {
            this.categories = categories.clone();
            this.reals = reals.clone();
        }

        /** A static value a first row left empty, from a later one. */
        void fill(String[] categories, double[] reals) {
            for (int i = 0; i < categories.length; i++) {
                if (this.categories[i] == null) {
                    this.categories[i] = categories[i];
                }
            }
            for (int i = 0; i < reals.length; i++) {
                if (Double.isNaN(this.reals[i])) {
                    this.reals[i] = reals[i];
                }
            }
        }
    }

    /** A series laid out step by step from its start to its end, with running sums for its windows. */
    private static final class Dense {
        final List<String> key;
        final Series series;
        final long start;
        final long end;
        double[][] prefix;
        int[][] nans;
        int[] lastAbove;

        Dense(List<String> key, Series series, long start, long end) {
            this.key = key;
            this.series = series;
            this.start = start;
            this.end = end;
        }

        /** Lays the steps out: a step without rows is 0 with missing rows as zero, else unknown (NaN). */
        void fill(boolean zero, int width) {
            int length = (int) (end - start + 1);
            prefix = new double[width][length + 1];
            nans = new int[width][length + 1];
            lastAbove = new int[length];
            for (int i = 0; i < length; i++) {
                double[] v = series.steps.get(start + i);
                for (int c = 0; c < width; c++) {
                    double x = v == null ? (zero ? 0 : Double.NaN) : (Double.isNaN(v[c]) && zero ? 0 : v[c]);
                    prefix[c][i + 1] = prefix[c][i] + (Double.isNaN(x) ? 0 : x);
                    nans[c][i + 1] = nans[c][i] + (Double.isNaN(x) ? 1 : 0);
                }
                double target = prefix[0][i + 1] - prefix[0][i];
                lastAbove[i] = target > 0 ? i : (i == 0 ? -1 : lastAbove[i - 1]);
            }
            // The rows are in the running sums now.
            series.steps.clear();
        }

        /** The sum of column c over steps from..to (indexes in the series), clipped to the series. */
        double sum(int c, int from, int to) {
            int a = Math.max(0, from);
            int b = Math.min(prefix[c].length - 2, to);
            return b < a ? 0 : prefix[c][b + 1] - prefix[c][a];
        }

        int nan(int c, int from, int to) {
            int a = Math.max(0, from);
            int b = Math.min(nans[c].length - 2, to);
            return b < a ? 0 : nans[c][b + 1] - nans[c][a];
        }
    }

    static double[] sum(double[] a, double[] b) {
        double[] s = Arrays.copyOf(a, a.length);
        for (int i = 0; i < s.length; i++) {
            s[i] = Double.isNaN(s[i]) ? b[i] : (Double.isNaN(b[i]) ? s[i] : s[i] + b[i]);
        }
        return s;
    }
}
