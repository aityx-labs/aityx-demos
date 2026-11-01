package datyx.training;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import datyx.catalog.TimeSeries;
import io.quarkus.runtime.annotations.RegisterForReflection;
import ml.dmlc.xgboost4j.java.Booster;
import ml.dmlc.xgboost4j.java.DMatrix;
import ml.dmlc.xgboost4j.java.XGBoost;
import ml.dmlc.xgboost4j.java.XGBoostError;

/**
 * Trains XGBoost (XGBoost4J, the C++ library through JNI) on a
 * {@link Dataset}: gradient-boosted trees on the training examples, the
 * validation examples stopping it once their error stops falling, then
 * measured on the test examples against two baselines: the naive one (the
 * next horizon like the last) and the training labels' mean. A count-like
 * Target (never below zero) is fitted as a Poisson count, any other with
 * squared error. It answers what it measured, which features weighed most,
 * the scores of the series still
 * observed, and the model (UBJSON). A feature's weight is its share of the
 * mean absolute SHAP contribution over the test examples: how much it moved
 * the predictions, in the Target's own terms.
 */
public final class XgbTrainer {

    static final int ROUNDS = 400;

    static final int EARLY_STOPPING = 30;

    static final int TOP_SCORES = 25;

    static final int TOP_FEATURES = 12;

    @RegisterForReflection
    public record Metrics(int examples, double mae, double rmse, double naiveMae, double meanMae, double improvement,
            double meanLabel) {
    }

    @RegisterForReflection
    public record Importance(String feature, double share) {
    }

    @RegisterForReflection
    public record Score(Map<String, String> series, double predicted, double last) {
    }

    /**
     * What a run found, and what inference needs to use its model: the group
     * as it was trained ({@code spec}), the categories' codes, and the
     * features in order.
     */
    @RegisterForReflection
    public record Result(Dataset.Summary dataset, Map<String, Object> params, int bestIteration, Metrics test,
            List<Importance> importance, List<Score> scores, TimeSeries.Spec spec,
            Map<String, Map<String, Integer>> categories, List<String> features, List<String> featureTypes) {
    }

    /** What training answers: the result to keep, and the model. */
    public record Trained(Result result, byte[] model) {
    }

    private XgbTrainer() {
    }

    public static Trained train(Dataset data) throws XGBoostError {
        Map<String, Object> params = new LinkedHashMap<>();
        boolean counts = true;
        for (float y : data.train.labels()) {
            counts &= y >= 0;
        }
        params.put("objective", counts ? "count:poisson" : "reg:squarederror");
        params.put("eval_metric", "mae");
        params.put("tree_method", "hist");
        params.put("eta", 0.08);
        params.put("max_depth", 6);
        params.put("min_child_weight", 3);
        params.put("subsample", 0.8);
        params.put("colsample_bytree", 0.8);
        params.put("seed", 7);
        params.put("nthread", Math.max(1, Runtime.getRuntime().availableProcessors() / 2));

        DMatrix train = matrix(data, data.train);
        DMatrix valid = data.valid.rows() > 0 ? matrix(data, data.valid) : null;
        DMatrix test = matrix(data, data.test);
        try {
            Map<String, DMatrix> watches = new LinkedHashMap<>();
            watches.put("train", train);
            if (valid != null) {
                watches.put("valid", valid);
            }
            float[][] history = new float[watches.size()][ROUNDS];
            Booster booster = XGBoost.train(train, params, ROUNDS, watches, history, null, null,
                valid == null ? 0 : EARLY_STOPPING);
            String best = booster.getAttr("best_iteration");
            int bestIteration = best == null ? ROUNDS - 1 : Integer.parseInt(best);

            float[][] predicted = booster.predict(test);
            Metrics metrics = metrics(data, predicted);
            List<Importance> importance = importance(data, booster, test);
            List<Score> scores = scores(data, booster);
            byte[] model = booster.toByteArray("ubj");
            booster.dispose();
            return new Trained(new Result(data.summary, params, bestIteration, metrics, importance, scores, data.spec,
                data.categories, data.featureNames, List.of(data.featureTypes)), model);
        } finally {
            train.dispose();
            if (valid != null) {
                valid.dispose();
            }
            test.dispose();
        }
    }

    private static DMatrix matrix(Dataset data, Dataset.Part part) throws XGBoostError {
        DMatrix m = new DMatrix(part.features(), part.rows(), data.featureNames.size(), Float.NaN);
        m.setLabel(part.labels());
        m.setFeatureTypes(data.featureTypes);
        return m;
    }

    private static Metrics metrics(Dataset data, float[][] predicted) {
        double mean = 0;
        for (float y : data.train.labels()) {
            mean += y;
        }
        mean /= data.train.rows();
        double ae = 0;
        double se = 0;
        double naive = 0;
        double meanAe = 0;
        double labels = 0;
        float[] y = data.test.labels();
        for (int i = 0; i < y.length; i++) {
            double e = predicted[i][0] - y[i];
            ae += Math.abs(e);
            se += e * e;
            naive += Math.abs(data.test.naive()[i] - y[i]);
            meanAe += Math.abs(mean - y[i]);
            labels += y[i];
        }
        int n = y.length;
        double mae = ae / n;
        double naiveMae = naive / n;
        return new Metrics(n, round(mae), round(Math.sqrt(se / n)), round(naiveMae), round(meanAe / n),
            naiveMae == 0 ? 0 : round(1 - mae / naiveMae), round(labels / n));
    }

    /**
     * Each feature's share of the mean absolute SHAP contribution over the
     * test examples, the largest first. (XGBoost4J's gain scores go through a
     * model dump that refuses categorical splits.)
     */
    private static List<Importance> importance(Dataset data, Booster booster, DMatrix test) throws XGBoostError {
        int n = data.featureNames.size();
        float[][] contributions = booster.predictContrib(test, 0);
        double[] mean = new double[n];
        for (float[] row : contributions) {
            for (int i = 0; i < n; i++) {
                mean[i] += Math.abs(row[i]);
            }
        }
        double total = 0;
        for (double m : mean) {
            total += m;
        }
        List<Importance> list = new ArrayList<>();
        for (int i = 0; i < n && total > 0; i++) {
            if (mean[i] > 0) {
                list.add(new Importance(data.featureNames.get(i), round(mean[i] / total)));
            }
        }
        list.sort(Comparator.comparingDouble(Importance::share).reversed());
        return list.size() > TOP_FEATURES ? List.copyOf(list.subList(0, TOP_FEATURES)) : list;
    }

    /** The series still observed, scored at their end, the highest first. */
    private static List<Score> scores(Dataset data, Booster booster) throws XGBoostError {
        if (data.scored.isEmpty()) {
            return List.of();
        }
        int n = data.featureNames.size();
        float[] x = new float[data.scored.size() * n];
        for (int r = 0; r < data.scored.size(); r++) {
            System.arraycopy(data.scored.get(r).features(), 0, x, r * n, n);
        }
        DMatrix m = new DMatrix(x, data.scored.size(), n, Float.NaN);
        try {
            m.setFeatureTypes(data.featureTypes);
            float[][] p = booster.predict(m);
            List<Score> scores = new ArrayList<>();
            for (int r = 0; r < p.length; r++) {
                Dataset.Scored s = data.scored.get(r);
                scores.add(new Score(s.series(), round(p[r][0]), round(s.last())));
            }
            scores.sort(Comparator.comparingDouble(Score::predicted).reversed());
            return scores.size() > TOP_SCORES ? List.copyOf(scores.subList(0, TOP_SCORES)) : scores;
        } finally {
            m.dispose();
        }
    }

    private static double round(double v) {
        return Math.round(v * 1000) / 1000.0;
    }
}
