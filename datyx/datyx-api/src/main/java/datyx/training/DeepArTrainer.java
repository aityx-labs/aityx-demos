package datyx.training;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Random;

import ai.djl.MalformedModelException;
import ai.djl.Model;
import ai.djl.engine.Engine;
import ai.djl.inference.Predictor;
import ai.djl.metric.Metrics;
import ai.djl.ndarray.NDArray;
import ai.djl.ndarray.NDManager;
import ai.djl.ndarray.types.Shape;
import ai.djl.nn.Parameter;
import ai.djl.timeseries.Forecast;
import ai.djl.timeseries.TimeSeriesData;
import ai.djl.timeseries.dataset.FieldName;
import ai.djl.timeseries.dataset.TimeSeriesDataset;
import ai.djl.timeseries.distribution.DistributionLoss;
import ai.djl.timeseries.distribution.output.DistributionOutput;
import ai.djl.timeseries.model.deepar.DeepARNetwork;
import ai.djl.timeseries.timefeature.Lag;
import ai.djl.timeseries.timefeature.TimeFeature;
import ai.djl.timeseries.transform.InstanceSampler;
import ai.djl.timeseries.transform.TimeSeriesTransform;
import ai.djl.timeseries.transform.split.InstanceSplit;
import ai.djl.timeseries.translator.DeepARTranslator;
import ai.djl.training.DefaultTrainingConfig;
import ai.djl.training.EasyTrain;
import ai.djl.training.Trainer;
import ai.djl.training.dataset.Batch;
import ai.djl.training.initializer.XavierInitializer;
import ai.djl.training.listener.TrainingListener;
import ai.djl.training.optimizer.Optimizer;
import ai.djl.training.tracker.Tracker;
import ai.djl.translate.TranslateException;
import ai.djl.util.Progress;
import datyx.catalog.TimeSeries;
import io.quarkus.runtime.annotations.RegisterForReflection;

/**
 * Trains DeepAR (DJL's, on its PyTorch engine: libtorch through JNI) on a
 * group's series ({@link DeepArData}): an LSTM that reads each series' past
 * (its lags, the time of day, week and year, its age, its categories) and
 * gives, step by step over the horizon, a distribution of the next value:
 * a negative binomial for a count-like Target (never below zero, whole), a
 * Student's t for any other. Each series' last horizon is held out: the
 * network learns from random windows of the rest, a fixed number of
 * batches per epoch, then forecasts the held-out horizon of every series,
 * measured against two baselines: the naive one (the next horizon like the
 * last) and the training steps' mean, the absolute error of the forecast's
 * median (what minimizes it) and the squared error of its mean; and how
 * often the actual value falls between its 10th and 90th percentiles. It answers what it
 * measured, the forecasts of the series still observed (from their whole
 * history), and the network's parameters.
 */
public final class DeepArTrainer {

    static final String ENGINE = "PyTorch";

    static final int BATCH_SIZE = 32;

    static final int BATCHES_PER_EPOCH = 50;

    static final int EPOCHS = 30;

    /** Training stops after its epoch past this, however many epochs are left. */
    static final Duration TIME_LIMIT = Duration.ofMinutes(5);

    static final float LEARNING_RATE = 1e-3f;

    static final int TOP_SCORES = 25;

    /** The quantiles a forecast answers, besides its mean. */
    static final float LOW = 0.1f;

    static final float HIGH = 0.9f;

    @RegisterForReflection
    public record Summary(int rows, int series, long steps, int examples, int epochs, int test, String frequency,
            String horizon, int horizonSteps, int context, int history, String scoredAt, int scored) {
    }

    /** One step of a forecast: when it starts, the mean, and the 10th, 50th and 90th percentiles. */
    @RegisterForReflection
    public record Step(String at, double mean, double p10, double p50, double p90) {
    }

    /** A forecast, step by step: the mean and the 10th, 50th and 90th percentiles of its sample paths. */
    record Band(float[] mean, float[] p10, float[] p50, float[] p90) {
    }

    /** A series forecast from its end: the Target summed over the horizon ahead (the mean's), and over the last. */
    @RegisterForReflection
    public record Score(Map<String, String> series, double predicted, double last) {
    }

    /**
     * What a run found, and what inference needs to rebuild its network: the
     * group as it was trained, the categories' codes, the frequency, horizon
     * and context in steps, the categories' cardinality and the distribution.
     */
    @RegisterForReflection
    public record Result(Summary dataset, Map<String, Object> params, double trainLoss, XgbTrainer.Metrics test,
            double coverage, List<Score> scores, TimeSeries.Spec spec, Map<String, Map<String, Integer>> categories,
            String freq, long step, int horizon, int context, List<Integer> cardinality, String distribution) {
    }

    /** What training answers: the result to keep, and the network's parameters. */
    public record Trained(Result result, byte[] model) {
    }

    private DeepArTrainer() {
    }

    public static Trained train(DeepArData data) throws IOException, TranslateException, MalformedModelException {
        return train(data, EPOCHS, TIME_LIMIT, 42);
    }

    static Trained train(DeepArData data, int epochs, Duration limit, long seed)
            throws IOException, TranslateException, MalformedModelException {
        int h = data.horizon;
        int context = 2 * h;
        int history = context + Lag.getLagsForFreq(data.freq).stream().max(Integer::compare).orElse(1);
        List<DeepArData.Item> fit = new ArrayList<>();
        long examples = 0;
        for (DeepArData.Item item : data.items) {
            int n = item.target().length - h;
            if (n > h) {
                fit.add(item);
                examples += n - h;
            }
        }
        if (fit.isEmpty()) {
            throw new IllegalArgumentException("no series is longer than twice the horizon (" + h + " steps of "
                + data.spec.frequency() + "): nothing to learn from");
        }
        boolean counts = data.items.stream().allMatch(i -> isCount(i.target()));
        String distribution = counts ? "negative binomial" : "Student's t";
        List<Integer> cardinality = data.cardinality();

        Engine.getEngine(ENGINE).setRandomSeed((int) seed);
        Distributions.seed(seed);
        Map<String, Object> params = new LinkedHashMap<>();
        params.put("engine", ENGINE + " " + Engine.getEngine(ENGINE).getVersion());
        params.put("distribution", distribution);
        params.put("context", context);
        params.put("layers", 2);
        params.put("hidden", 40);
        params.put("dropout", 0.1);
        params.put("learningRate", LEARNING_RATE);
        params.put("batchSize", BATCH_SIZE);
        params.put("batchesPerEpoch", BATCHES_PER_EPOCH);

        byte[] model;
        int done = 0;
        double loss = Double.NaN;
        try (Model m = Model.newInstance("deepar", ENGINE)) {
            DeepARNetwork network = network(data.freq, h, context, cardinality, counts).buildTrainingNetwork();
            m.setBlock(network);
            NDManager manager = m.getNDManager();
            Windows windows = new Windows.Builder()
                .items(fit, data, history + h, h, new Random(seed))
                .setTransformation(trainingTransformation(network, manager, h))
                .setContextLength(context)
                .setSampling(BATCH_SIZE, true)
                .build();
            DefaultTrainingConfig config = new DefaultTrainingConfig(new DistributionLoss("Loss", output(counts)))
                .optOptimizer(Optimizer.adam().optLearningRateTracker(Tracker.fixed(LEARNING_RATE)).build())
                .optInitializer(new XavierInitializer(), Parameter.Type.WEIGHT)
                .addTrainingListeners(TrainingListener.Defaults.basic());
            try (Trainer trainer = m.newTrainer(config)) {
                trainer.setMetrics(new Metrics());
                int timeFeatures = TimeFeature.timeFeaturesFromFreqStr(data.freq).size() + 1;
                trainer.initialize(new Shape(1, Math.max(1, cardinality.size())), new Shape(1, 1),
                    new Shape(1, history, timeFeatures), new Shape(1, history), new Shape(1, history), new Shape(1, history),
                    new Shape(1, h, timeFeatures), new Shape(1, h), new Shape(1, h));
                long deadline = System.nanoTime() + limit.toNanos();
                for (int epoch = 0; epoch < epochs && System.nanoTime() < deadline; epoch++) {
                    for (Batch batch : trainer.iterateDataset(windows)) {
                        EasyTrain.trainBatch(trainer, batch);
                        trainer.step();
                        batch.close();
                    }
                    trainer.notifyListeners(listener -> listener.onEpoch(trainer));
                    done++;
                }
                loss = trainer.getTrainingResult().getTrainLoss();
            }
            ByteArrayOutputStream bytes = new ByteArrayOutputStream();
            try (DataOutputStream out = new DataOutputStream(bytes)) {
                network.saveParameters(out);
            }
            model = bytes.toByteArray();
        }
        params.put("epochs", done);

        Result partial = new Result(null, params, loss, null, Double.NaN, List.of(), data.spec, data.categories,
            data.freq, data.step, h, context, cardinality, distribution);
        try (Forecaster forecaster = new Forecaster(partial, model)) {
            // The held-out horizon of every series long enough, forecast from the steps before it.
            List<Band> held = forecaster.forecast(fit, h);
            double absolute = 0;
            double squared = 0;
            double naive = 0;
            double mean = 0;
            double actual = 0;
            int inside = 0;
            int n = 0;
            double trainMean = trainingMean(fit, h);
            for (int s = 0; s < fit.size(); s++) {
                float[] target = fit.get(s).target();
                float[] mu = held.get(s).mean();
                float[] median = held.get(s).p50();
                float[] low = held.get(s).p10();
                float[] high = held.get(s).p90();
                int from = target.length - h;
                for (int k = 0; k < h; k++) {
                    float y = target[from + k];
                    float last = target[from - h + k];
                    if (Float.isNaN(y) || Float.isNaN(last)) {
                        continue;
                    }
                    absolute += Math.abs(median[k] - y);
                    squared += (mu[k] - y) * (mu[k] - y);
                    naive += Math.abs(last - y);
                    mean += Math.abs(trainMean - y);
                    actual += y;
                    inside += y >= low[k] && y <= high[k] ? 1 : 0;
                    n++;
                }
            }
            if (n == 0) {
                throw new IllegalArgumentException("the held-out horizon of every series is unknown: nothing to test on");
            }
            double mae = absolute / n;
            double naiveMae = naive / n;
            XgbTrainer.Metrics test = new XgbTrainer.Metrics(n, round(mae), round(Math.sqrt(squared / n)), round(naiveMae),
                round(mean / n), naiveMae == 0 ? 0 : round(1 - mae / naiveMae), round(actual / n));

            // The series still observed, forecast from their whole history.
            long latest = data.items.stream().mapToLong(DeepArData.Item::end).max().orElse(0);
            List<DeepArData.Item> observed = data.items.stream().filter(i -> i.end() == latest).toList();
            List<Band> ahead = forecaster.forecast(observed, 0);
            List<Score> scores = new ArrayList<>();
            for (int s = 0; s < observed.size(); s++) {
                scores.add(new Score(observed.get(s).series(), round(sum(ahead.get(s).mean())),
                    round(lastSum(observed.get(s).target(), h))));
            }
            scores.sort(Comparator.comparingDouble(Score::predicted).reversed());
            Summary summary = new Summary(data.rows, data.items.size(), data.steps(),
                (int) Math.min(Integer.MAX_VALUE, (long) done * BATCHES_PER_EPOCH * BATCH_SIZE), done, fit.size(),
                data.spec.frequency(), horizonSpan(data), h, context, history, data.time(latest).toString(), observed.size());
            Result result = new Result(summary, params, round(loss), test, round((double) inside / n),
                List.copyOf(scores.subList(0, Math.min(TOP_SCORES, scores.size()))), data.spec, data.categories, data.freq,
                data.step, h, context, cardinality, distribution);
            return new Trained(result, model);
        }
    }

    /** The horizon as a span: the table's, or the default's steps of the frequency. */
    static String horizonSpan(DeepArData data) {
        return DeepArData.horizonOf(data.spec);
    }

    static DeepARNetwork.Builder network(String freq, int horizon, int context, List<Integer> cardinality, boolean counts) {
        return DeepARNetwork.builder()
            .setFreq(freq)
            .setPredictionLength(horizon)
            .optContextLength(context)
            .setCardinality(cardinality.isEmpty() ? List.of(1) : cardinality)
            .optUseFeatStaticCat(!cardinality.isEmpty())
            .optDistrOutput(output(counts));
    }

    private static DistributionOutput output(boolean counts) {
        return counts ? new Distributions.CountOutput() : new Distributions.RealOutput();
    }

    /** DeepAR's own transformation, its sampler of split points replaced: a window's split is where its future starts. */
    private static List<TimeSeriesTransform> trainingTransformation(DeepARNetwork network, NDManager manager, int horizon) {
        List<TimeSeriesTransform> transformation = new ArrayList<>(network.createTrainingTransformation(manager));
        for (int i = 0; i < transformation.size(); i++) {
            if (transformation.get(i) instanceof InstanceSplit) {
                transformation.set(i, new InstanceSplit(FieldName.TARGET, FieldName.IS_PAD, FieldName.START,
                    FieldName.FORECAST_START, new AtFuture(horizon), network.getHistoryLength(), horizon,
                    new FieldName[] {FieldName.FEAT_TIME, FieldName.OBSERVED_VALUES}, 0));
            }
        }
        return transformation;
    }

    private static boolean isCount(float[] target) {
        for (float v : target) {
            if (!Float.isNaN(v) && (v < 0 || v != Math.rint(v))) {
                return false;
            }
        }
        return true;
    }

    private static double trainingMean(List<DeepArData.Item> items, int h) {
        double sum = 0;
        long n = 0;
        for (DeepArData.Item item : items) {
            float[] t = item.target();
            for (int i = 0; i < t.length - h; i++) {
                if (!Float.isNaN(t[i])) {
                    sum += t[i];
                    n++;
                }
            }
        }
        return n == 0 ? 0 : sum / n;
    }

    static double sum(float[] values) {
        double s = 0;
        for (float v : values) {
            s += v;
        }
        return s;
    }

    /** The Target summed over the last {@code h} steps, unknown steps left out. */
    static double lastSum(float[] target, int h) {
        double s = 0;
        for (int i = Math.max(0, target.length - h); i < target.length; i++) {
            s += Float.isNaN(target[i]) ? 0 : target[i];
        }
        return s;
    }

    static double round(double v) {
        return Math.round(v * 1000) / 1000.0;
    }

    /** The split of a training window: where its last {@code horizon} steps, its future, start. */
    private static final class AtFuture extends InstanceSampler {

        AtFuture(int horizon) {
            super(-1, 0, horizon);
        }

        @Override
        public List<Integer> call(NDArray ts) {
            return List.of(getBounds(ts)[1]);
        }
    }

    /**
     * Random windows of the series, as many a epoch as its batches hold: a
     * series picked by how many split points it has, a split point at
     * random, and the window the steps before it that the network reads
     * (at most {@code length} - horizon) and the horizon after.
     */
    static final class Windows extends TimeSeriesDataset {

        private final List<DeepArData.Item> items;
        private final DeepArData data;
        private final long[] cumulative;
        private final int length;
        private final int horizon;
        private final Random random;

        private Windows(Builder builder) {
            super(builder);
            this.items = builder.items;
            this.data = builder.data;
            this.length = builder.length;
            this.horizon = builder.horizon;
            this.random = builder.random;
            this.cumulative = new long[items.size()];
            long total = 0;
            for (int i = 0; i < items.size(); i++) {
                total += items.get(i).target().length - 2L * horizon;
                cumulative[i] = total;
            }
        }

        @Override
        public TimeSeriesData getTimeSeriesData(NDManager manager, long index) {
            long r;
            synchronized (random) {
                r = Math.floorMod(random.nextLong(), cumulative[cumulative.length - 1]);
            }
            int i = Arrays.binarySearch(cumulative, r + 1);
            i = i >= 0 ? i : -i - 1;
            DeepArData.Item item = items.get(i);
            int split = (int) (r - (i == 0 ? 0 : cumulative[i - 1])) + 1;
            int from = Math.max(0, split + horizon - length);
            TimeSeriesData window = new TimeSeriesData(4);
            window.setStartTime(data.time(item.start() + from));
            window.setField(FieldName.TARGET, manager.create(Arrays.copyOfRange(item.target(), from, split + horizon)));
            if (item.categories().length > 0) {
                window.setField(FieldName.FEAT_STATIC_CAT, manager.create(item.categories()));
            }
            return window;
        }

        @Override
        protected long availableSize() {
            return (long) BATCHES_PER_EPOCH * BATCH_SIZE;
        }

        @Override
        public void prepare(Progress progress) {
        }

        static final class Builder extends TimeSeriesBuilder<Builder> {

            List<DeepArData.Item> items;
            DeepArData data;
            int length;
            int horizon;
            Random random;

            Builder items(List<DeepArData.Item> items, DeepArData data, int length, int horizon, Random random) {
                this.items = items;
                this.data = data;
                this.length = length;
                this.horizon = horizon;
                this.random = random;
                return this;
            }

            @Override
            protected Builder self() {
                return this;
            }

            Windows build() {
                return new Windows(this);
            }
        }
    }

    /**
     * A trained network, ready to forecast: the prediction network with the
     * run's parameters, and DJL's translator. Each forecast is 100 sample
     * paths; not thread-safe, so its callers take turns.
     */
    static final class Forecaster implements AutoCloseable {

        private final Result result;
        private final Model model;
        private final Predictor<TimeSeriesData, Forecast> predictor;
        private final int history;

        Forecaster(Result result, byte[] parameters) throws IOException, MalformedModelException {
            this.result = result;
            this.model = Model.newInstance("deepar", ENGINE);
            DeepARNetwork network = network(result.freq(), result.horizon(), result.context(), result.cardinality(),
                result.distribution().startsWith("negative")).buildPredictionNetwork();
            model.setBlock(network);
            try (DataInputStream in = new DataInputStream(new ByteArrayInputStream(parameters))) {
                network.loadParameters(model.getNDManager(), in);
            }
            Map<String, Object> arguments = new LinkedHashMap<>();
            arguments.put("prediction_length", result.horizon());
            arguments.put("context_length", result.context());
            arguments.put("freq", result.freq());
            arguments.put("use_feat_static_cat", !result.cardinality().isEmpty());
            this.predictor = model.newPredictor(DeepARTranslator.builder(arguments).build());
            this.history = result.context() + Lag.getLagsForFreq(result.freq()).stream().max(Integer::compare).orElse(1);
        }

        /**
         * Forecasts each series from its end, less its last {@code holdOut}
         * steps, from what the network reads (up to its history) to where
         * that starts: each step's mean and 10th, 50th and 90th percentiles of
         * the sample paths.
         */
        List<Band> forecast(List<DeepArData.Item> items, int holdOut) throws TranslateException {
            List<Band> bands = new ArrayList<>();
            for (int from = 0; from < items.size(); from += BATCH_SIZE) {
                try (NDManager manager = model.getNDManager().newSubManager()) {
                    List<TimeSeriesData> batch = new ArrayList<>();
                    for (DeepArData.Item item : items.subList(from, Math.min(items.size(), from + BATCH_SIZE))) {
                        int end = item.target().length - holdOut;
                        int start = Math.max(0, end - history);
                        TimeSeriesData input = new TimeSeriesData(4);
                        input.setStartTime(DeepArData.time(result.step(), item.start() + start));
                        input.setField(FieldName.TARGET, manager.create(Arrays.copyOfRange(item.target(), start, end)));
                        if (item.categories().length > 0) {
                            input.setField(FieldName.FEAT_STATIC_CAT, manager.create(item.categories()));
                        }
                        batch.add(input);
                    }
                    for (Forecast f : predictor.batchPredict(batch)) {
                        bands.add(new Band(f.mean().toFloatArray(), f.quantile(LOW).toFloatArray(),
                            f.quantile(0.5f).toFloatArray(), f.quantile(HIGH).toFloatArray()));
                    }
                }
            }
            return bands;
        }

        @Override
        public void close() {
            predictor.close();
            model.close();
        }
    }
}
